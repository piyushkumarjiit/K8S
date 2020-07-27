#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
echo "========== Connected to $(hostname)) ============"
echo "Cleanup script initiated from node: $CALLING_NODE_NAME."

#Current Node IP
CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"
CURRENT_NODE_NAME="$(hostname)"
# kubectl/kubeadm might be installed but with missing config would return 1
KUBECTL_AVAILABLE=$(kubectl version > /dev/null 2>&1; echo $?)
KUBEADM_AVAILABLE=$(kubeadm version > /dev/null 2>&1; echo $?)
KUBELET_AVAILABLE=$(systemctl status kubelet > /dev/null 2>&1; echo $?)

if [[ $KUBEADM_AVAILABLE == 0 || $KUBEADM_AVAILABLE == 1 ]]
then
	echo "Kubeadm reset called."
	kubeadm reset -f
	yum -y -q remove kubeadm
	echo "kubeadm removed."
fi

if [[ $KUBECTL_AVAILABLE == 0 || $KUBECTL_AVAILABLE == 1 ]]
then
	kubectl drain $CURRENT_NODE_IP --delete-local-data --force --ignore-daemonsets
	kubectl delete node $CURRENT_NODE_IP
	echo "Kubectl delete node called."
	yum -y -q remove kubectl
	echo "kubectl removed."
fi

if [[ $KUBELET_AVAILABLE == 0 ]]
then
	echo "Kubelet reset called." 
	systemctl stop kubelet
	systemctl disable kubelet
	yum -y -q remove kubelet
	echo "kubelet removed."
fi

DOCKER_AVAILABLE=$(docker --version > /dev/null 2>&1; echo $?)
if [[ $DOCKER_AVAILABLE == 0 ]]
then
	echo "Pruning Docker"
	docker system prune -af
	systemctl stop docker
	systemctl disable docker
	echo "Removing Docker and CRI-O ."
	yum -y -q remove docker-ce
	echo "Docker removed."
	yum -y -q cri-o
	echo "cri-o removed."
fi

KEEPALIVED_AVAILABLE=$(systemctl status keepalived.service > /dev/null 2>&1; echo $?)
if [[ $KEEPALIVED_AVAILABLE == 0 ]]
then
	echo "Removing keepalived."
	systemctl stop keepalived.service
	systemctl disable keepalived.service
	yum -y -q keepalived
	echo "keepalived removed."
fi

HAPROXY_AVAILABLE=$(systemctl status haproxy.service > /dev/null 2>&1; echo $?)
if [[ $HAPROXY_AVAILABLE == 0 ]]
then
	echo "Removing haproxy."
	systemctl stop haproxy.service
	systemctl disable haproxy.service
	yum -y -q haproxy
	echo "haproxy removed."
fi

echo "Yum remove step completed."
yum -y -q autoremove

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

#Remove Directories
rm -Rf /etc/cni /var/lib/etcd /etc/kubernetes /usr/lib/systemd/system/kubelet.service.d
rm -Rf /root/.kube ~/.kube
rm -Rf /etc/docker /var/lib/docker /var/run/docker.sock ~/.docker /usr/bin/docker-compose
rm -Rf /var/lib/rook
echo "Docker and Kubernetes config directories deleted."
#groupdel docker
echo "Docker group removed."

#Enable and Start firewalld. Uncomment for real scenarios
#systemctl enable firewalld
#systemctl start firewalld
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
echo "firewalld enabled and started."


#Enable Swap manually. Uncomment for real scenarios
#sed -ir 's/.*-swap/#&/' /etc/fstab
echo "Swap enabled for restart."

#Enable SELinux. Uncomment for real scenarios
#setenforce 1
#sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config
echo "SELINUX enabled for restart."

#Restore the /etc/hosts file
if [[ -r hosts.txt && $CURRENT_NODE_NAME != $CALLING_NODE_NAME ]]
then
	cat hosts.txt > /etc/hosts
	echo "Hosts file overwritten."
	rm -f hosts.txt
else
	echo "Backup file does not exists."
fi

#Reset the IP Tables
iptables -F ; iptables -X ; iptables -t nat -F ; iptables -t nat -X; iptables -t mangle -F ; iptables -t mangle -X
echo "IPTables reset completed."
sysctl -q --system
systemctl daemon-reload

if [[ $CURRENT_NODE_NAME != $CALLING_NODE_NAME ]]
then
	echo "Cleanup done. Restarting the node to reset stuck handles."
	#shutdown -r
else
	echo "----------- $(hostname) cleanup completed ------------"
fi
