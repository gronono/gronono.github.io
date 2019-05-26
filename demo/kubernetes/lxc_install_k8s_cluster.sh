#!/bin/bash

# Nb of worker nodes
NB_WORKERS=1

# Set your proxy for APT if you have one or leave it empty
APT_PROXY="http://$(ip route get 1 | head -n 1 | cut -d' ' -f7):3142"

# Proxy for Docker.
DOCKER_PROXY="http://$(ip route get 1 | head -n 1 | cut -d' ' -f7):3128"

# Ingress Service Ports
HTTP_PORT=30082
HTTPS_PORT=31817

LXC_NETWORK="$(lxc network list | grep OUI | cut -d'|' -f 2)"

REQUIRED_MODULES="br_netfilter xt_conntrack ip_tables ip6_tables netlink_diag nf_nat overlay rbd"
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

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
  local ip=$2
  echo -e "${GREEN}Creating container ${name}${NC}"
  lxc init images:debian/stretch "${name}"
  lxc profile apply "${name}" "k8s"
  lxc network attach "${LXC_NETWORK}" "${name}" eth0 eth0
  lxc config device set "${name}" eth0 ipv4.address "${ip}"
  lxc start "${name}"
  lxc exec "${name}" -- sh -c "while ! (ip addr | grep inet | grep eth0 2>/dev/null); do sleep 1; done"
  if [ ! -z "$APT_PROXY" ]
  then
    cat > /tmp/apt_proxy << EOF
Acquire::http { Proxy "${APT_PROXY}"; }
EOF
  lxc file push /tmp/apt_proxy "${name}"/etc/apt/apt.conf.d/proxy
  fi
  lxc exec "${name}" -- apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common iputils-ping wget nfs-common lvm2 dnsutils
}

install_k8s_tools() {
  local node=$1
  echo -e "${GREEN}Installing docker & kubernetes on ${node}${NC}"
  lxc file push /boot/config-"$(uname -r)" "${node}"/boot/config-"$(uname -r)"
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
  "storage-driver": "overlay2"
}
EOF
  lxc file push /tmp/docker-daemon.json "${node}"/etc/docker/daemon.json
  rm -rf /tmp/docker-daemon.json
  lxc exec "${node}" -- mkdir -p /etc/systemd/system/docker.service.d
  if [ ! -z "$DOCKER_PROXY" ]
  then
    cat > /tmp/docker-proxy << EOF
[Service]
Environment="HTTP_PROXY=${DOCKER_PROXY}"
Environment="HTTPS_PROXY=${DOCKER_PROXY}"
EOF
    lxc file push /tmp/docker-proxy "${node}"/etc/systemd/system/docker.service.d/http-proxy.conf
    rm -rf /tmp/docker-proxy
    curl "${DOCKER_PROXY}"/ca.crt > /tmp/ca.crt
    lxc file push /tmp/ca.crt "${node}"/usr/share/ca-certificates/docker_registry_proxy.crt
    lxc exec "${node}" -- sh -c "echo 'docker_registry_proxy.crt' >> /etc/ca-certificates.conf"
    lxc exec "${node}" -- update-ca-certificates --fresh
  fi
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
  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.11.0/Documentation/kube-flannel.yml
}

install_cluster_ingress() {
  local node=$1
  echo -e "${GREEN}Installing Ingress${NC}"
  lxc exec "${node}" -- kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.24.1/deploy/mandatory.yaml
  local gatewayIP
  gatewayIP=$(lxc exec gateway -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
  cat > /tmp/ingress-nginx.service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx
  namespace: kube-system
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
  sed -i 's/namespace: ingress-nginx/namespace: kube-system/g' /tmp/ingress-nginx.service.yaml 
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

install_haproxy() {
  echo -e "${GREEN}Installing HAProxy${NC}"
  local name=$1
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
}

install_nfs_server() {
  echo -e "${GREEN}Installing NFS Server${NC}"
  local name=$1
  lxc exec "${name}" -- apt install -y nfs-kernel-server
  lxc exec "${name}" -- mkdir -p /srv/nfs
  lxc exec "${name}" -- chown nobody:nogroup /srv/nfs
  local network
  network=$(lxc exec "${name}" -- ip addr sh | grep eth0 | grep inet | cut -d' ' -f 6)
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

waiting_for_pods() {
  echo -e "${GREEN}Waiting pods${NC}"
  while ( lxc exec "$1" -- kubectl get pod -A | grep -e ContainerCreating -e Init -e Pending > /dev/null)
  do
    sleep 1;
  done
}

# Requierements
check_required_modules
# Containers
create_lxc_profile
create_container "gateway" "10.223.181.199"
create_container "kmaster" "10.223.181.200"
for i in $(seq 1 ${NB_WORKERS})
do
  create_container "kworker$i" "10.223.181.20$i"
done
# Master
install_k8s_tools kmaster
init_kubernetes kmaster
# Worker
for i in $(seq 1 ${NB_WORKERS})
do
  install_k8s_tools "kworker$i"
  join_cluster "kworker$i" kmaster
done
rm -f /tmp/k8s_join.sh
# Gateway
install_haproxy gateway
install_nfs_server gateway
# Flannel
install_cluster_flannel kmaster
waiting_for_pods kmaster
# Ingress
install_cluster_ingress kmaster
waiting_for_pods kmaster
# Dashboard
install_cluster_dashboard kmaster
waiting_for_pods kmaster

lxc exec kmaster -- sh -c "kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')"
echo -e "Gateway IP : $(lxc exec gateway -- ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)"
echo -e "${GREEN}Success${NC}"
