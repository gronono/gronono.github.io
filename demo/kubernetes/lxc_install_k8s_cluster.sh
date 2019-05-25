#!/bin/bash

# Nb of worker nodes
NB_WORKERS=1
# Email address for Let's encrypt issuers
EMAIL="arnaud.brunet@gmail.com"

# Set your proxy for APT if you have one or leave it empty
#APT_PROXY="http://10.10.10.233:3142"
APT_PROXY="http://$(ip route get 1 | head -n 1 | cut -d' ' -f7):3142"
# Proxies for Docker Registry
#DOCKER_PROXY="\"http://192.168.1.101:5000\", \"http://192.168.1.101:5001\""

REQUIRED_MODULES="br_netfilter xt_conntrack ip_tables ip6_tables netlink_diag nf_nat overlay"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

HTTP_PORT=30082
HTTPS_PORT=31817

set -e

check_required_modules() {
  echo -e "${GREEN}Checking required modules${NC}"
  for module in ${REQUIRED_MODULES}; do
    if ! lsmod | cut -d' ' -f1 | grep "${module}" > /dev/null
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

create_container() {
  local name=$1
  local profil=$2
  echo -e "${GREEN}Creating container ${name}${NC}"
  lxc init images:debian/stretch "${name}"
  if [ ! -z "$profil" ]
  then
    lxc profile apply "${name}" "${profil}"
  fi
  lxc start "${name}"
  lxc exec "${name}" -- sh -c "while ! (ip addr | grep inet | grep eth0 2>/dev/null); do sleep 1; done"
  if [ ! -z "$APT_PROXY" ]
  then
    cat > /tmp/apt_proxy << EOF
Acquire::http { Proxy "${APT_PROXY}"; }
EOF
  lxc file push /tmp/apt_proxy "${name}"/etc/apt/apt.conf.d/proxy
  fi
  lxc exec "${name}" -- apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common iputils-ping wget nfs-common
}

create_k8s_node() {
  local node=$1
  create_container "${node}" k8s
  lxc file push /boot/config-"$(uname -r)" "${node}"/boot/config-"$(uname -r)"
}

install_tools() {
  local node=$1
  echo -e "${GREEN}Installing docker & kubernetes on ${node}${NC}"
  lxc exec "${node}" -- sh -c "curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -"
  lxc exec "${node}" -- sh -c "curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -"
  lxc exec "${node}" -- add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian stretch stable"
  lxc exec "${node}" -- add-apt-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
  lxc exec "${node}" -- apt update
  lxc exec "${node}" -- apt install -y docker-ce kubelet kubeadm kubectl
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
  lxc file push /tmp/docker-daemon.json "${node}"/etc/docker/daemon.json
  rm -rf /tmp/docker-daemon.json
  lxc exec "${node}" -- mkdir -p /etc/systemd/system/docker.service.d
  lxc exec "${node}" -- sh -c "echo 'Environment="KUBELET_EXTRA_ARGS=--fail-swap-on=false"' >> /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"
  lxc exec "${node}" -- systemctl daemon-reload
  lxc exec "${node}" -- systemctl restart docker
  lxc exec "${node}" -- systemctl restart kubelet
}

init_kubernetes() {
  local node=$1
  echo -e "${GREEN}Kubernetes init on ${node}${NC}"
  lxc exec "${node}" -- kubeadm init --ignore-preflight-errors=FileContent--proc-sys-net-bridge-bridge-nf-call-iptables,Swap --pod-network-cidr=10.244.0.0/16
  lxc exec "${node}" -- mkdir -p /root/.kube
  lxc exec "${node}" -- cp -i /etc/kubernetes/admin.conf /root/.kube/config
  mkdir -p "${HOME}"/.kube
  lxc file pull "${node}"/etc/kubernetes/admin.conf "${HOME}"/.kube/config
  local cmd
  cmd=$(lxc exec "${node}" -- kubeadm token create --print-join-command)
  echo "${cmd} --ignore-preflight-errors=FileContent--proc-sys-net-bridge-bridge-nf-call-iptables,Swap" > /tmp/k8s_join.sh
}

join_cluster() {
  local node=$1
  echo -e "${GREEN}Join cluster for node ${node}${NC}"
  lxc file push /tmp/k8s_join.sh "${node}"/root/k8s_join.sh
  lxc exec "${node}" -- sh /root/k8s_join.sh
}

install_cluster_flannel() {
  local node=$1
  echo -e "${GREEN}Installing Flannel${NC}"
  lxc exec "${node}" -- kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
}

install_cluster_ingress() {
  local node=$1
  echo -e "${GREEN}Installing Ingress${NC}"
  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
#  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
#  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/baremetal/service-nodeport.yaml
  local gatewayIP
  gatewayIP=$(lxc exec gateway -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
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
  externalIPs:
    - ${gatewayIP}
  ports:
    - name: http
      nodePort: ${HTTP_PORT}
      port: 80
      targetPort: 80
      protocol: TCP
    - name: https
      nodePort: ${HTTPS_PORT}
      port: 443
      targetPort: 443
      protocol: TCP
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
EOF
  lxc file push /tmp/ingress-nginx.service.yaml "${node}"/root/ingress-nginx.service.yaml
  rm -f /tmp/ingress-nginx.service.yaml
  lxc exec "${node}" -- kubectl apply -f /root/ingress-nginx.service.yaml
}

install_cluster_dashboard() {
  local node=$1
  echo -e "${GREEN}Installing Dashboard${NC}"
  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml
  cat > /tmp/admin-user.yaml << EOF 
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
EOF
  lxc file push /tmp/admin-user.yaml "${node}"/root/admin-user.yaml
  rm -f /tmp/admin-user.yaml
  lxc exec "${node}" -- kubectl apply -f /root/admin-user.yaml
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
  lxc file push /tmp/admin-role.yaml "${node}"/root/admin-role.yaml
  rm -f /tmp/admin-role.yaml
  lxc exec "${node}" -- kubectl apply -f /root/admin-role.yaml 
  cat > /tmp/kube-admin.ingress.yaml << EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: kube-admin-ingress
  namespace: kube-system
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  tls:
  - hosts:
    - kube-admin
  rules:
  - host: kube-admin
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 443
EOF
  lxc file push /tmp/kube-admin.ingress.yaml "${node}"/root/kube-admin.ingress.yaml
  rm -f /tmp/kube-admin.ingress.yaml
  lxc exec "${node}" -- kubectl apply -f /root/kube-admin.ingress.yaml
}

install_cluster_certmanager() {
  local node=$1
  lxc exec "${node}" -- kubectl create namespace cert-manager
  lxc exec "${node}" -- kubectl label namespace cert-manager certmanager.k8s.io/disable-validation=true
  lxc exec "${node}" -- kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v0.8.0/cert-manager.yaml
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
  lxc file push /tmp/letsencrypt-staging.clusterissuer.yaml "${node}"/root/letsencrypt-staging.clusterissuer.yaml
  rm -f /tmp/letsencrypt-staging.clusterissuer.yaml
  lxc exec "${node}" -- kubectl apply -f /root/letsencrypt-staging.clusterissuer.yaml
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
      key: "letsencrypt-prod"
      name: letsencrypt-prod
    server: https://acme-v02.api.letsencrypt.org/directory
EOF
  lxc file push /tmp/letsencrypt-prod.clusterissuer.yaml "${node}"/root/letsencrypt-prod.clusterissuer.yaml
  rm -f /tmp/letsencrypt-prod.clusterissuer.yaml
  lxc exec "${node}" -- kubectl apply -f /root/letsencrypt-prod.clusterissuer.yaml
}

create_gateway_node() {
  local name=$1
  create_container "${name}" "k8s"
  lxc exec "${name}" -- apt install -y haproxy
  cat > /tmp/haproxy.cfg << EOF
global
	log /dev/log	local0
	log /dev/log	local1 notice
	chroot /var/lib/haproxy
	stats socket /run/haproxy/admin.sock mode 660 level admin
	stats timeout 30s
	user haproxy
	group haproxy
	daemon
	ca-base /etc/ssl/certs
	crt-base /etc/ssl/private
	ssl-default-bind-ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
	ssl-default-bind-options no-sslv3

defaults
	log	global
	mode	http
	option	httplog
	option	dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000
	errorfile 400 /etc/haproxy/errors/400.http
	errorfile 403 /etc/haproxy/errors/403.http
	errorfile 408 /etc/haproxy/errors/408.http
	errorfile 500 /etc/haproxy/errors/500.http
	errorfile 502 /etc/haproxy/errors/502.http
	errorfile 503 /etc/haproxy/errors/503.http
	errorfile 504 /etc/haproxy/errors/504.http

frontend kube-https
  bind *:443
  mode tcp
  option tcplog
  timeout client 1m
  default_backend https-backend

frontend kube-http
  bind *:80
  mode tcp
  option tcplog
  timeout client 1m
  default_backend http-backend

backend https-backend
  mode tcp
  balance roundrobin
EOF
  local directive
  directive=$(generate_haproxy_directive "${HTTPS_PORT}")
  printf "${directive}" >> /tmp/haproxy.cfg
  cat >> /tmp/haproxy.cfg << EOF

backend http-backend
  mode tcp
  balance roundrobin
EOF
  directive=$(generate_haproxy_directive "${HTTP_PORT}")
  printf "${directive}" >> /tmp/haproxy.cfg
  lxc file push /tmp/haproxy.cfg "${name}"/etc/haproxy/haproxy.cfg
  rm -f /tmp/haproxy.cfg
  lxc exec "${name}" -- systemctl restart haproxy.service
  lxc exec "${name}" -- apt install -y nfs-kernel-server
  lxc exec "${name}" -- mkdir -p /srv/nfs
  lxc exec "${name}" -- chown nobody:nogroup /srv/nfs
  local network
  network=$(lxc exec gateway -- ip addr sh | grep eth0 | grep inet | cut -d' ' -f 6)
  cat > /tmp/exports << EOF
/srv/nfs ${network}(rw,sync,no_root_squash,no_subtree_check)
EOF
  lxc file push /tmp/exports "${name}"/etc/exports
  rm -f /tmp/exports
  lxc exec "${name}" -- systemctl restart nfs-server
  
}

generate_haproxy_directive() {
  local port=$1
  local directive
  for i in $(seq 1 ${NB_WORKERS});
  do
    local ip
    ip=$(lxc exec "kworker$i" -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    directive="${directive}  server node1 ${ip}:${port}\n"
  done
  echo -n "${directive}"
}

install_cluster_metallb() {
  local node=$1
  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/google/metallb/v0.7.3/manifests/metallb.yaml
  local gatewayIP
  gatewayIP=$(lxc exec gateway -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
  cat > /tmp/metallb.config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${EXTERNAL_IP}-${EXTERNAL_IP}
EOF
  lxc file push /tmp/metallb.config.yaml "${node}"/root/metallb.config.yaml
  rm -f /tmp/metallb.config.yaml
  lxc exec "${node}" -- kubectl apply -f /root/metallb.config.yaml
}

install_cluster_nfs() {
  local node=$1
  local gatewayIP
  gatewayIP=$(lxc exec gateway -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
  cat > /tmp/nfs.pv.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
  labels:
    type: local
spec:
  storageClassName: manual
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: ${gatewayIP}
    path: "/srv/nfs"
EOF
  lxc file push /tmp/nfs.pv.yaml "${node}"/root/nfs.pv.yaml
  rm -f /tmp/nfs.pv.yaml
  lxc exec "${node}" -- kubectl apply -f /root/nfs.pv.yaml
  cat > /tmp/nfs.pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
EOF
  lxc file push /tmp/nfs.pvc.yaml "${node}"/root/nfs.pvc.yaml
  rm -f /tmp/nfs.pvc.yaml
  lxc exec "${node}" -- kubectl apply -f /root/nfs.pvc.yaml
}

waiting_for_pods() {
  echo -e "${GREEN}Waiting pods${NC}"
  while ( lxc exec "$1" -- kubectl get pod -A | grep -e ContainerCreating -e Init -e Pending > /dev/null)
  do
    sleep 1;
  done
}

check_required_modules
create_lxc_profile
create_k8s_node kmaster
install_tools kmaster
init_kubernetes kmaster
for i in $(seq 1 ${NB_WORKERS})
do
  create_k8s_node "kworker$i"
  install_tools "kworker$i"
  join_cluster "kworker$i" kmaster
done
rm -f /tmp/k8s_join.sh
create_gateway_node gateway
install_cluster_flannel kmaster
waiting_for_pods kmaster
#install_cluster_metallb kmaster
install_cluster_ingress kmaster
waiting_for_pods kmaster
# install_cluster_certmanager kmaster
install_cluster_dashboard kmaster
install_cluster_nfs kmaster
waiting_for_pods kmaster

lxc exec kmaster -- sh -c "kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')"
echo -e "Gateway IP : $(lxc exec gateway -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)"
echo -e "${GREEN}Success${NC}"
