#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# if [[ $1 != "" ]]
# then
# 	CALLING_NODE=$1
# fi
CURRENT_NODE="$(hostname -I | cut -d" " -f 1)"
#Take backup of old hosts file. In case we need to restore/cleanup
cat /etc/hosts > hosts.txt
#Add IP Addresses and Hostnames in hosts file
if [[ ($NODES_IN_CLUSTER != "" ) && ("$CURRENT_NODE" != "$CALLING_NODE" ) ]]
then
	NODES_ADDED=$(ping -c 1 $CALLING_NODE  > /dev/null 2>&1; echo $?)
	if [[ $NODES_ADDED != "0" ]]
	then
		echo "Ping failed. Updating hosts file."
		echo -n "$NODES_IN_CLUSTER" | tee -a /etc/hosts
		echo "Hosts file updated."
	else
		echo "Nodes already present in hosts file."
	fi
elif [[ "$CURRENT_NODE" == "$CALLING_NODE" ]]
then
	echo "Hosts file already update for Primary node by main script."
else
	#statements
	echo "NODES_IN_CLUSTER not set. Exiting."
	exit 1
fi

# cat >> /etc/hosts<<EOF
# $KUBE_MASTER_1_IP  $KUBE_MASTER_1_HOSTNAME
# $KUBE_MASTER_2_IP  $KUBE_MASTER_2_HOSTNAME
# $KUBE_MASTER_3_IP  $KUBE_MASTER_3_HOSTNAME
# $KUBE_VIP_1_IP  $KUBE_VIP_1_HOSTNAME
# EOF

#Add IP Addresses and Hostnames in hosts file
#echo -n "$WORKERS_IN_HOSTS" | tee -a /etc/hosts
# cat >> /etc/hosts<<EOF
# $KUBE_WORKER_1_IP  $KUBE_WORKER_1_HOSTNAME
# $KUBE_WORKER_2_IP  $KUBE_WORKER_2_HOSTNAME
# $KUBE_WORKER_3_IP  $KUBE_WORKER_3_HOSTNAME
# EOF

# Set SELinux in permissive mode (effectively disabling it). Needed for K8s as well as HAProxy
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
echo "SELINUX updated."

#Setup IP tables for Bridged Traffic
bash -c 'cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF'

echo "IP tables updated."
sysctl -q --system

#Disable Swap
swapoff -a
#Disable Swap in fstab to ensure it does not get enabled on reboot
#We must also ensure that swap isn't re-enabled during a reboot on each server. Open up the /etc/fstab and comment out the swap entry like this:
#/dev/mapper/cl-swap     swap                    swap    defaults        0 0
#/dev/mapper/cl_kubemaster2centos8-swap swap                    swap    defaults        0 0
sed -ir 's/.*-swap/#&/' /etc/fstab
#Or
#sudo sed -i "s*/dev/mapper/cl*#/dev/mapper/cl*g" /etc/fstab
echo "Swap disabled."

#Disable and Stop firewalld. Unless firewalld is stopped, HAProxy would not work
systemctl disable firewalld
systemctl stop firewalld

echo "firewalld disabled."
#Add kubernetes repo
bash -c 'cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF'

echo "Kubernetes repo added."

#Add Docker repo
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

#Update packages.
yum update -y

#Install Docker on server
#nobest added for CentOS8
dnf -y  install docker-ce --nobest
usermod -aG docker $USER
#Enable Docker to start on start up
systemctl enable docker
#Start Docker
systemctl start docker

#Setup Cgroup drivers. Either run this as root or accept the bad alignment of script :(
bash -c 'cat <<- EOF > /etc/docker/daemon.json
{
"exec-opts": ["native.cgroupdriver=systemd"],
"log-driver": "json-file",
"log-opts": {"max-size": "100m"},
"storage-driver": "overlay2"
}
EOF'

echo "Cgroup drivers updated."
#On all nodes kubeadm and kubelet should be installed. kubectl is optional.
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

#Restart kublet
systemctl daemon-reload
systemctl enable kubelet && sudo systemctl start kubelet

echo "Script completed."


