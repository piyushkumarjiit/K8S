#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
echo "========== Connected to $(hostname)) ============"
echo "Cleanup script started."

#Below is newly added. Need to be tested against original ones.
CURRENT_NODE="$(hostname -I | cut -d" " -f 1)"
KUBECTL_AVAILABLE=$(kubectl version > /dev/null 2>&1; echo $?)
KUBEADM_AVAILABLE=$(kubeadm version > /dev/null 2>&1; echo $?)
if [[ $KUBECTL_AVAILABLE == 0 ]]
then
	kubectl drain $CURRENT_NODE --delete-local-data --force --ignore-daemonsets
	kubectl delete node $CURRENT_NODE
	echo "Kubectl delete node called."
fi
if [[ $KUBEADM_AVAILABLE == 0 ]]
then
	kubeadm reset
	echo "Kubeadm reset called."
fi

#Remove packages installed by yum
yum -y -q remove kubelet kubeadm kubectl
yum -y -q remove docker-ce docker-ce-cli containerd.io
yum -y -q haproxy keepalived
yum -y -q remove container-selinux
yum -y -q cri-o
echo "Yum remove step completed."
yum -y -q autoremove

#sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube*   
#sudo apt-get autoremove  

#Delete Repos we added
rm -f /etc/yum.repos.d/docker-ce.repo
rm -f /etc/yum.repos.d/kubernetes.repo
rm -f /etc/yum.repos.d/*rhcontainerbot:container-selinux.repo*
rm -f /etc/yum.repos.d/*devel:kubic:libcontainers*
echo "Repos deleted."

#Remove extra files created.
rm -f /etc/sysctl.d/k8s.conf
rm -f /etc/docker/daemon.json
rm -f ~/prepare*.*
rm -f ~/cleanup_node*.*
echo "Files created by setup script deleted."

#Remove folders
rm -Rf /etc/cni/net.d /root/.kube ~/.kube /var/lib/etcd /etc/kubernetes/pki 
rm -Rf /etc/docker /var/lib/docker /var/run/docker.sock ~/.docker /usr/bin/docker-compose
echo "Docker and Kubernetes config directories deleted."
groupdel docker

#Enable and Start firewalld.
#systemctl enable firewalld
#systemctl start firewalld
echo "firewalld enabled and started."

#Enable Swap manually
#sed -ir 's/.*-swap/#&/' /etc/fstab
echo "Swap enabled for restart."

#Enable SELinux
#setenforce 1
#sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config
echo "SELINUX enabled for restart."

#Restore the /etc/hosts file
if [[ -r hosts.txt && $CALLING_NODE != $CURRENT_NODE ]]
then
	cat hosts.txt > /etc/hosts
	echo "Hosts file overwritten."
else
	echo "Backup file does not exists."
fi

#Reset the IP Tables
iptables -F ; iptables -X ; iptables -t nat -F ; iptables -t nat -X; iptables -t mangle -F ; iptables -t mangle -X
echo "IPTables reset completed."
sysctl -q --system

echo "Cleanup script completed."

#Restart the node
#shutdown -r