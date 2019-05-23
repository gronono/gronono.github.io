#!/bin/bash

# Set your proxy for APT if you have one or leave it empty
APT_PROXY="http://10.10.10.233:3142"


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
  "storage-driver": "overlay2"
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

install_cluster_tools() {
  local node=$1
  echo -e "${GREEN}Installing Flannel${NC}"
  lxc exec ${node} -- kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml
  echo -e "${GREEN}Installing Ingress${NC}"
  lxc exec ${node} -- kubectl apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/master/deployments/common/ns-and-sa.yaml
  lxc exec ${node} -- kubectl apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/master/deployments/common/default-server-secret.yaml
  lxc exec ${node} -- kubectl apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/master/deployments/common/nginx-config.yaml
  lxc exec ${node} -- kubectl apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/master/deployments/rbac/rbac.yaml
  lxc exec ${node} -- kubectl apply -f https://raw.githubusercontent.com/nginxinc/kubernetes-ingress/master/deployments/daemon-set/nginx-ingress.yaml
}

check_required_modules
create_lxc_profile
create_k8s_node kmaster
install_tools kmaster
init_kubernetes kmaster
create_k8s_node kworker1
install_tools kworker1
join_cluster kworker1 kmaster
install_cluster_tools kmaster

echo -e "${GREEN}Success${NC}"

