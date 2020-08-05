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

if [[ $KUBEADM_AVAILABLE == 0  ]]
then
	echo "Kubeadm reset called."
	kubeadm reset -f
	yum -y -q remove kubeadm
	echo "kubeadm removed."
fi

if [[ $KUBECTL_AVAILABLE == 0  ]]
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

DOCKER_AVAILABLE=$(docker -v > /dev/null 2>&1; echo $?)
if [[ $DOCKER_AVAILABLE == 0 ]]
then
	echo "Pruning Docker"
	docker system prune -af
	systemctl stop docker
	systemctl disable docker
	echo "Removing Docker and CRI-O ."
	yum -y -q remove docker-ce docker-ce-cli
	echo "Docker removed."
	yum -y -q remove cri-o
	echo "cri-o removed."
else
	echo "Docker is not installed."
	sleep 1
fi

KEEPALIVED_AVAILABLE=$(systemctl status keepalived.service > /dev/null 2>&1; echo $?)
if [[ $KEEPALIVED_AVAILABLE == 0 ]]
then
	echo "Removing keepalived."
	systemctl stop keepalived.service
	systemctl disable keepalived.service
	yum -y -q remove keepalived
	echo "keepalived removed."
else
	echo "KEEPALIVED is not installed."
	sleep 1
fi

HAPROXY_AVAILABLE=$(systemctl status haproxy.service > /dev/null 2>&1; echo $?)
if [[ $HAPROXY_AVAILABLE == 0 ]]
then
	echo "Removing haproxy."
	systemctl stop haproxy.service
	systemctl disable haproxy.service
	yum -y -q remove haproxy
	echo "haproxy removed."
else
	echo "HAPROXY is not installed."
	sleep 1
fi

#yum -y -q remove kube.*
yum -y -q remove kubelet kubeadm kubectl containerd.io
yum -y -q autoremove
yum -y -q clean all
yum -y -q history sync
echo "Yum remove step completed."


CEPH_DRIVE_PRESENT=$(lsblk -f -o NAME,FSTYPE | grep ceph > /dev/null 2>&1; echo $? )
if [[ $CEPH_DRIVE_PRESENT == 0 ]]
then
	echo "Cleaning Rook and Ceph related config and zapping drive."
	yum -y -q install sgdisk
	CEPH_DRIVE=('/dev/sdb')
	#DISK='/dev/sdb'
	for DISK in ${CEPH_DRIVE[*]}
	do
		# Zap the disk to a fresh, usable state (zap-all is important, b/c MBR has to be clean)
		# You will have to run this step for all disks.
		sgdisk --zap-all $DISK
		dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync
		# These steps only have to be run once on each node
		# If rook sets up osds using ceph-volume, teardown leaves some devices mapped that lock the disks.
		DMREMOVE_STATUS=$(ls /dev/mapper/ceph-* | xargs -I% -- dmsetup remove % > /dev/null 2>&1; echo $? )
		if [[ $DMREMOVE_STATUS -gt 0 ]]
		then
			rm -f /dev/mapper/ceph-*
			echo "Manually deleted /dev/mapper/ceph "
		else
			echo "DMREMOVE_STATUS completed successfully."
		fi
		# ceph-volume setup can leave ceph-<UUID> directories in /dev (unnecessary clutter)
		rm -rf /dev/ceph-*
		rm -Rf /var/lib/rook
	done
	yum -y -q remove sgdisk
else
	echo "No processing needed for Rook/Ceph."
fi

if [[ -f /var/lib/rook ]]
then
	echo "Removing /var/lib/rook"
	rm -Rf /var/lib/rook
else
	echo "Directory /var/lib/rook not found."
fi

if [[ -f /var/lib/cni ]]
then
	echo "Removing /var/lib/cni"
	rm -Rf /var/lib/cni
	rm -Rf /etc/coredns/Corefile
else
	echo "Directory /var/lib/cni not found."
fi

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
rm -Rf /etc/cni /var/lib/etcd /etc/kubernetes /var/lib/kubelet /usr/lib/systemd/system/kubelet.service.d
rm -Rf /opt/cni /var/lib/cni /var/lib/calico /var/lib/weave
rm -Rf /root/.kube ~/.kube
rm -Rf /etc/docker /var/lib/docker /var/run/docker.sock ~/.docker /usr/bin/docker-compose /etc/systemd/system/docker.service.d
rm -Rf /opt/containerd /var/lib/containerd /var/lib/containers /var/lib/docker-engine  /var/lib/dockershim
rm -Rf /usr/lib/systemd/system/kubelet.service.d



echo "Docker and Kubernetes config directories deleted."
#groupdel docker
echo "Docker group deleted."

#Enable and Start firewalld. Uncomment for real scenarios
#systemctl enable firewalld
#systemctl start firewalld
iptables -F ; iptables -t nat -F ; iptables -t mangle -F ; iptables -X ;  iptables -t nat -X;  iptables -t mangle -X
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
echo "Resetting the IPtables."
## start fresh
iptables -Z; # zero counters
iptables -F; # flush (delete) rules
iptables -X; # delete all extra chains
iptables -t nat -F ; 
iptables -t nat -X; 
iptables -t mangle -F ; 
iptables -t mangle -X
## start fresh
ip6tables -Z; # zero counters
ip6tables -F; # flush (delete) rules
ip6tables -X; # delete all extra chains

echo "IPTables reset completed."
sysctl -q --system
systemctl daemon-reload

if [[ $CURRENT_NODE_NAME != $CALLING_NODE_NAME ]]
then
	echo "Cleanup done. Restarting the node to reset stuck handles."
	shutdown -r
else
	echo "----------- $(hostname) cleanup completed ------------"
fi