#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
echo "Cleanup script started."

#Below is newly added. Need to be tested against original ones.
CURRENT_NODE="$(hostname -I | cut -d" " -f 1)"
kubectl drain $CURRENT_NODE --delete-local-data --force --ignore-daemonsets
kubectl delete node $CURRENT_NODE
kubeadm reset

#Remove packages installed by yum
yum -y remove docker-ce kubelet kubeadm kubectl haproxy keepalived

#sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube*   
#sudo apt-get autoremove  

#Delete Repos
rm -f "/etc/yum.repos.d/docker-ce.repo"
rm -f "/etc/yum.repos.d/kubernetes.repo"

#Remove extra files created.
rm -f "/etc/sysctl.d/k8s.conf"
rm -f "/etc/docker/daemon.json"

#Remove folders
rm -Rf /etc/cni/net.d /root/.kube ~/.kube /var/lib/etcd

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
if [[ -r hosts.txt ]]
then
	cat hosts.txt > /etc/hosts
	echo "Hosts file overwritten."
else
	echo "Backup file does not exists."
fi

#Reset the IP Tables
iptables -F ; iptables -X ; iptables -t nat -F ; iptables -t nat -X; iptables -t mangle -F ; iptables -t mangle -X

sysctl -q --system

echo "Cleanup script completed."

#Restart the node
#shutdown -r