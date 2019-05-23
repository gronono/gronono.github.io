#!/bin/bash

# Nb of worker nodes
NB_WORKERS=1

EMAIL="arnaud.brunet@gmail.com"

# Set your proxy for APT if you have one or leave it empty
#APT_PROXY="http://10.10.10.233:3142"
APT_PROXY="http://192.168.1.101:3142"
# Proxies for Docker Registry
DOCKER_PROXY="\"http://192.168.1.101:5000\", \"http://192.168.1.101:5001\""

REQUIRED_MODULES="br_netfilter xt_conntrack ip_tables ip6_tables netlink_diag nf_nat overlay"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

set -e

check_required_modules() {
  echo -e "${GREEN}Checking required modules:${NC}"
  for module in ${REQUIRED_MODULES}; do
    if ! lsmod | cut -d' ' -f1 | grep $module > /dev/null
    then
      echo -e "${RED}module ${module} not found${NC}"
      exit 1
    fi
  done
}

create_lxc_profile() {
  echo -e "${GREEN}Creating LXC 'k8s' profile${NC}"
  lxc profile copy default k8s
  lxc profile set k8s linux.kernel_modules xt_conntrack,ip_tables,ip6_tables,netlink_diag,nf_nat,overlay
  echo -en 'lxc.apparmor.profile=unconfined\nlxc.cap.drop= \nlxc.cgroup.devices.allow=a\nlxc.mount.auto=proc:rw sys:rw' | lxc profile set k8s raw.lxc -
  lxc profile set k8s security.privileged "true"
  lxc profile set k8s security.nesting "true"
  
}

create_k8s_node() {
  local node=$1
  echo -e "${GREEN}Creating ${node} node${NC}"
  lxc init images:debian/stretch ${node}
  lxc profile apply ${node} k8s
  lxc start ${node}
  lxc file push /boot/config-$(uname -r) ${node}/boot/config-$(uname -r)
  echo -e "${GREEN}Waiting while ${node} is ready${NC}"
  lxc exec ${node} -- sh -c "while ! (ip addr | grep inet | grep eth0 2>/dev/null); do sleep 1; done"
}

install_tools() {
  local node=$1
  echo -e "${GREEN}Installing docker & kubernetes on ${node}${NC}"
  if [ ! -z "$APT_PROXY" ]
  then
    cat > /tmp/apt_proxy << EOF
Acquire::http { Proxy "${APT_PROXY}"; }
EOF
    lxc file push /tmp/apt_proxy ${node}/etc/apt/apt.conf.d/proxy
  fi
  lxc exec ${node} -- apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common iputils-ping
  lxc exec ${node} -- sh -c "curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -"
  lxc exec ${node} -- sh -c "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -"
  lxc exec ${node} -- add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian stretch stable"
  lxc exec ${node} -- add-apt-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
  lxc exec ${node} -- apt update
  lxc exec ${node} -- apt install -y docker-ce kubelet kubeadm kubectl
  cat > /tmp/docker-daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": [ ${DOCKER_PROXY} ]
}
EOF
  lxc file push /tmp/docker-daemon.json ${node}/etc/docker/daemon.json
  rm -rf /tmp/docker-daemon.json
  lxc exec ${node} -- mkdir -p /etc/systemd/system/docker.service.d
  lxc exec ${node} -- sh -c "echo 'Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false"' >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
  lxc exec ${node} -- systemctl daemon-reload
  lxc exec ${node} -- systemctl restart docker
  lxc exec ${node} -- systemctl restart kubelet
}

init_kubernetes() {
  local node=$1
  echo -e "${GREEN}Kubernetes init on ${node}${NC}"
  lxc exec ${node} -- kubeadm init --ignore-preflight-errors=FileContent--proc-sys-net-bridge-bridge-nf-call-iptables,Swap --pod-network-cidr=10.244.0.0/16
  lxc exec ${node} -- mkdir -p /root/.kube
  lxc exec ${node} -- cp -i /etc/kubernetes/admin.conf /root/.kube/config
  mkdir -p ${HOME}/.kube
  lxc file pull ${node}/etc/kubernetes/admin.conf ${HOME}/.kube/config
  local cmd=$(lxc exec ${node} -- kubeadm token create --print-join-command)
  echo "${cmd} --ignore-preflight-errors=FileContent--proc-sys-net-bridge-bridge-nf-call-iptables,Swap" > /tmp/k8s_join.sh
}

join_cluster() {
  local node=$1
  echo -e "${GREEN}Join cluster for node ${node}${NC}"
  lxc file push /tmp/k8s_join.sh ${node}/root/k8s_join.sh
  lxc exec ${node} -- sh /root/k8s_join.sh
}

install_cluster_flannel() {
  local node=$1
  echo -e "${GREEN}Installing Flannel${NC}"
  lxc exec ${node} -- kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
}

install_cluster_ingress() {
  local node=$1
  echo -e "${GREEN}Installing Ingress${NC}"
  lxc exec $[node] -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
  cat > /tmp/ingress-nginx.service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: NodePort
  ports:
    - name: http
      port: 80
      targetPort: 80
      nodePort: 31080
      protocol: TCP
    - name: https
      port: 443
      targetPort: 443
      nodePort: 31443
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
EOF
  lxc file push /tmp/ingress-nginx.service.yaml ${node}/root/ingress-nginx.service.yaml
  rm -f /tmp/ingress-nginx.service.yaml
  lxc exec ${node} -- kubectl apply -f /root/ingress-nginx.service.yaml
  cat > /tmp/ingress-nginx.configmap.yaml << EOF
kind: ConfigMap
apiVersion: v1
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
data:
  use-proxy-protocol: "true"
EOF
  lxc file push /tmp/ingress-nginx.configmap.yaml ${node}/root/ingress-nginx.configmap.yaml
  rm -f /tmp/ingress-nginx.configmap.yaml
  lxc exec ${node} -- kubectl apply -f /root/ingress-nginx.configmap.yaml
}

install_cluster_dashboard() {
  local node=$1
  echo -e "${GRREEN}Installing Dashboard${NC}"
  lxc exec ${node} -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
  cat > /tmp/admin-user.yaml << EOF 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF
  lxc file push /tmp/admin-user.yaml ${node}/root/admin-user.yaml
  rm -f /tmp/admin-user.yaml
  lxc exec ${node} -- kubectl apply -f /root/admin-user.yaml
  cat > /tmp/admin-role.yaml << EOF
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: admin-user
    namespace: kube-system
EOF
  lxc file push /tmp/admin-role.yaml ${node}/root/admin-role.yaml
  rm -f /tmp/admin-role.yaml
  lxc exec ${node} -- kubectl apply -f /root/admin-role.yaml 
}

install_cluster_certmanager() {
  local node=$1
  lxc exec ${note} -- kubectl create namespace cert-manager
  lxc exec ${note} -- kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
  lxc exec ${note} -- kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v0.8.0/cert-manager.yaml
  cat > /tmp/letsencrypt-staging.clusterissuer.yaml << EOF
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    email: ${EMAIL}
    http01: {}
    privateKeySecretRef:
      key: "letsencrypt-staging"
      name: letsencrypt-staging
    server: https://acme-staging-v02.api.letsencrypt.org/directory
EOF
  lxc file push /tmp/letsencrypt-staging.clusterissuer.yaml ${node}/root/letsencrypt-staging.clusterissuer.yaml
  rm -f /tmp/letsencrypt-staging.clusterissuer.yaml
  lxc exec ${node} -- kubectl apply -f /root/letsencrypt-staging.clusterissuer.yaml
  cat > /tmp/letsencrypt-prod.clusterissuer.yaml << EOF
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: ${EMAIL}
    http01: {}
    privateKeySecretRef:
      key: ""
      name: letsencrypt-prod
    server: https://acme-v02.api.letsencrypt.org/directory
EOF
  lxc file push /tmp/letsencrypt-prod.clusterissuer.yaml ${node}/root/letsencrypt-prod.clusterissuer.yaml
  rm -f /tmp/letsencrypt-prod.clusterissuer.yaml
  lxc exec ${node} -- kubectl apply -f /root/letsencrypt-prod.clusterissuer.yaml
}

check_required_modules
create_lxc_profile
create_k8s_node kmaster
install_tools kmaster
init_kubernetes kmaster
for i in $(seq 1 ${NB_WORKERS});
do
  create_k8s_node kworker$i
  install_tools kworker$i
  join_cluster kworker$i kmaster
done
rm -f /tmp/k8s_join.sh
install_cluster_flannel kmaster
install_cluster_ingress kmaster
install_cluster_dashboard kmaster
install_cluster_certmanager kmaster

lxc exec kmaster -- sh -c "kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')"
echo -e "${GREEN}Success${NC}"
echo -e "Admin token: ${adm_token}"

