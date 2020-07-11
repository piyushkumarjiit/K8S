#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

CURRENT_NODE="$(hostname -I | cut -d" " -f 1)"
echo "----------- Preparing $(hostname) ------------"

if [[ (${ALL_NODE_NAMES[*]} == "") || (${ALL_NODE_IPS[*]} == "") ]]
then
	echo "ALL_NODE_NAMES or ALL_NODE_IPS not passed. Unable to proceed."
	echo "${ALL_NODE_NAMES[*]} and ${ALL_NODE_IPS[*]} "
	exit 1
fi

#Check if we can ping other nodes in cluster. If not, add IP Addresses and Hostnames in hosts file
index=0
for node in ${ALL_NODE_NAMES[*]}
do
	NODE_ACCESSIBLE=$(ping -q -c 1 -W 1 $node > /dev/null 2>&1; echo $?)
	if [[ $NODE_ACCESSIBLE != 0 ]]
	then
		echo "Node: $node inaccessible. Need to update hosts file."
		if [[ $index == 0 ]]
		then
			cat /etc/hosts > hosts.txt
			echo "Backed up /etc/hosts file."
		fi
		#Add Master IP Addresses and Hostnames in hosts file
		echo "${ALL_NODE_IPS[$index]}"	"$node" | tee -a /etc/hosts
		# NODES_IN_CLUSTER=$(cat <<- SETVAR
		# ${ALL_NODE_IPS[$index]}	$node
		# SETVAR
		# )
		# echo "$NODES_IN_CLUSTER" | tee -a /etc/hosts
		#echo -n "$NODES_IN_CLUSTER" | tee -a /etc/hosts
		echo "Node added to /etc/hosts file."
		NODES_IN_CLUSTER=""
	else
		echo "Node accessible. No need to update /etc/hosts file"
	fi
	index+=1
done


# NODES_ADDED=$(ping -c 1 $CALLING_NODE  > /dev/null 2>&1; echo $?)
# if [[ $NODES_ADDED != 0  &&  $NODES_IN_CLUSTER != "" ]]
# then
# 		echo "Ping failed. Updating hosts file."
# 		#Take backup of old hosts file. In case we need to restore/cleanup
# 		cat /etc/hosts > hosts.txt
# 		echo -n "$NODES_IN_CLUSTER" | tee -a /etc/hosts
# 		echo "Hosts file updated."
# elif [[ $NODES_IN_CLUSTER != "" ]]
# then
# 	echo "NODES_IN_CLUSTER not set. Exiting."
# 	exit 1
# else
# 	echo "Hosts file already updated for Primary node by main script."
# fi

#Check the status of SELinux and disable if needed.
SELINUX_STATUS=$(cat /etc/selinux/config | grep 'SELINUX=enforcing' > /dev/null 2>&1; echo $?)
if [[ $SELINUX_STATUS == 0 ]]
then	
	# Set SELinux in permissive mode (effectively disabling it). Needed for K8s as well as HAProxy
	echo "Disabling SELINUX."
	setenforce 0
	sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
	echo "Done."
else
	echo "SELinux already set as permissive. No change needed."
fi

#Check if IP tables contain K8s config

if [[ -r /etc/sysctl.d/k8s.conf ]]
then
	BRIDGED_MODE=$(cat /etc/sysctl.d/k8s.conf | grep -w 'net.bridge.bridge-nf-call-iptables = 1' > /dev/null 2>&1; echo $?)
	if [[ BRIDGED_MODE == 0 ]]
	then 
		"K8s.conf already exists and contains IP tables rules."
	else
		echo "Adding IP tables rules to existing K8s file."
		#Setup IP tables for Bridged Traffic
		bash -c 'cat <<-EOF >  /etc/sysctl.d/k8s.conf
		net.bridge.bridge-nf-call-ip6tables = 1
		net.bridge.bridge-nf-call-iptables = 1
		EOF'
		echo "File (k8s.conf) updated."
	fi
else
		echo "Creating k8s.conf and adding IP tables rules."
		#Setup IP tables for Bridged Traffic
		bash -c 'cat <<-EOF >  /etc/sysctl.d/k8s.conf
		net.bridge.bridge-nf-call-ip6tables = 1
		net.bridge.bridge-nf-call-iptables = 1
		EOF'
		echo "IP tables updated."
fi

#Check if swap is already commented out in fstab
SWAP_FSTAB=$(cat /etc/fstab | grep '^#.*-swap' > /dev/null 2>&1; echo $?)
if [[ $SWAP_FSTAB == 0 ]]
then
	echo "Swap already disabled in fstab. No change needed."
else
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
	RESTART_NEEDED=0
fi

#Disable and Stop firewalld. Unless firewalld is stopped, HAProxy would not work
FIREWALLD_STATUS=$(sudo systemctl status firewalld | grep -w "Active: inactive" > /dev/null 2>&1; echo $?)
if [[ FIREWALLD_STATUS -gt 0 ]]
then
	#Stop and disable firewalld
	sudo systemctl stop firewalld
	sudo systemctl disable firewalld
	echo "Disabled firewalld. Please enable with direct rules."
else
	echo "Firewalld seems to be disabled. Continuing."
fi

sysctl -q --system

if [[ -r /etc/yum.repos.d/kubernetes.repo ]]
then
	echo "Kubernetes repo already present."
else
	#Add kubernetes repo
	cat <<-'EOF' > /etc/yum.repos.d/kubernetes.repo
	[kubernetes]
	name=Kubernetes
	baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-$basearch
	enabled=1
	gpgcheck=1
	repo_gpgcheck=1
	gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
	exclude=kubelet kubeadm kubectl
	EOF
echo "Kubernetes repo added."
fi

#Update packages.
yum update -y

#Manually install containerd.io
#yum install -y https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.6-3.3.el7.x86_64.rpm

#containerd.io package is related to the runc conflicting with the runc package from the container-tools
yum install -y yum-utils
yum install -y container-selinux
yum module -y disable container-tools

#Check if Docker needs to be installed
DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
if [[ $DOCKER_INSTALLED -gt 0 ]]
then
	#Install Docker on server
	echo "Docker does not seem to be available. Trying to install Docker."
	curl -fsSL https://get.docker.com -o get-docker.sh
	sudo sh get-docker.sh
	sudo usermod -aG docker $USER
	RESTART_NEEDED=0
	#Enable Docker to start on start up
	sudo systemctl enable docker
	#Start Docker
	sudo systemctl start docker
	#Remove temp file.
	rm get-docker.sh
	#Check again
	DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
	if [[ $DOCKER_INSTALLED == 0 ]]
	then
		echo "Docker seems to be working."
		#echo "But you might need to disconnect and reconnect for usermod changes to reflect."
		#echo "Reconnect and rerun the script. Exiting."
		#sleep 10
		#exit 1
	else
		echo "Unable to install Docker. Trying the nobest option as last resort."
		sleep 2
		sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
		sudo dnf -y  install docker-ce --nobest
		sudo usermod -aG docker $USER
		#Enable Docker to start on start up
		sudo systemctl enable docker
		#Start Docker
		sudo systemctl start docker
		#Check again
		DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
		if [[ $DOCKER_INSTALLED != 0 ]]
		then
			echo "Unable to install Docker. Exiting."
			sleep 2
			exit 1
		else
			echo "Docker seems to be working but you need to disconnect and reconnect for usermod changes to reflect."
			sleep 5
			exit 1
		fi
	fi		
else
	echo "Docker already installed."
fi

#Setup Cgroup drivers. Either run this as root or accept the bad alignment of script :(
if [[ -f /etc/docker/daemon.json ]]
then
	echo "daemon.json is already present. Keeping it as is."
else
	bash -c 'cat <<- EOF > /etc/docker/daemon.json
	{
	"exec-opts": ["native.cgroupdriver=systemd"],
	"log-driver": "json-file",
	"log-opts": {"max-size": "100m"},
	"storage-driver": "overlay2"
	}
	EOF'
	echo "Cgroup drivers updated."
fi

#On all nodes kubeadm and kubelet should be installed. kubectl is optional.
yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
#systemctl enable --now kubelet
#Restart kublet
systemctl daemon-reload
systemctl enable kubelet && sudo systemctl start kubelet

if [[ $RESTART_NEEDED == 0 ]]
then
	echo "All done. Restarting the node for changes to take effect."
	shutdown -r
else
	echo "Script completed."
	echo "----------- $(hostname) ready for next step ------------"
fi



