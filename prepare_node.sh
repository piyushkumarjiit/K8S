#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

echo "----------- Preparing $(hostname) ------------"
#Hostname of the node from where we run the script
export CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
export CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"
#All node names passed by calling script that we are trying to setup
export ALL_NODE_NAMES=($TEMP_NODE_NAMES)
#All node IP addresses passed by calling script that we are trying to setup
export ALL_NODE_IPS=($TEMP_NODE_IPS)

if [[ ${ALL_NODE_NAMES[*]} == "" || ${ALL_NODE_IPS[*]} == "" ]]
then
	echo "ALL_NODE_NAMES or ALL_NODE_IPS not passed. Unable to proceed."
	exit 1
fi

echo "Value of passed ALL_NODE_NAMES ${ALL_NODE_NAMES[*]}"
echo "Value of passed ALL_NODE_IPS ${ALL_NODE_IPS[*]}"
#Check if we can ping other nodes in cluster. If not, add IP Addresses and Hostnames in hosts file
#Workaround for lack of DNS. Local node can ping itself but unable to SSH
HOST_PRESENT=$(cat /etc/hosts | grep $(hostname) > /dev/null 2>&1; echo $? )
if [[ $HOST_PRESENT != 0 ]]
then
	echo "$CURRENT_NODE_IP"	"$CURRENT_NODE_NAME" | tee -a /etc/hosts
fi
#Check connectivity to all nodes
index=0
for node in ${ALL_NODE_NAMES[*]}
do
	NODE_ACCESSIBLE=$(ping -q -c 1 -W 1 $node > /dev/null 2>&1; echo $?)
	NODE_ALREADY_PRESENT=$(cat /etc/hosts | grep -w $node > /dev/null 2>&1; echo $?)
	if [[ ($NODE_ACCESSIBLE != 0) && ($NODE_ALREADY_PRESENT != 0) ]]
	then
		echo "Node: $node inaccessible. Need to update hosts file."
		if [[ $index == 0 ]]
		then
			cat /etc/hosts > hosts.txt
			echo "Backed up /etc/hosts file."
		fi
		NODE_NAMES_LENGTH=${#ALL_NODE_NAMES[*]}
		NODE_IPS_LENGTH=${#ALL_NODE_NAMES[*]}
		if [[ $NODE_NAMES_LENGTH == $NODE_IPS_LENGTH ]]
		then			
			#Add Master IP Addresses and Hostnames in hosts file
			echo "${ALL_NODE_IPS[$index]}"	"$node" | tee -a /etc/hosts
			echo "Hosts file updated."
		else
			echo "Number of Host Names do not match with Host IPs provided. Unable to update /etc/hosts. Exiting."
			sleep 2
			exit 1
		fi
	else
		echo "Node $node is accessible."
	fi
	((index++))
done

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

IP4_FORWARDING_STATUS=$(cat /etc/sysctl.conf | grep -w 'net.ipv4.ip_forward=1' > /dev/null 2>&1; echo $?)
if [[ $IP4_FORWARDING_STATUS != 0 ]]
then	
	echo "Adding IPv4 forwarding rule."
	bash -c 'cat <<-EOF >>  /etc/sysctl.conf
	net.ipv4.ip_forward=1
	net.bridge.bridge-nf-call-iptables=1
	EOF'
	sysctl -p -q
	echo "Done."
else
	echo "IPV4 FORWARDING flag already set. No change needed."
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
		bash -c 'cat <<-EOF >>  /etc/sysctl.d/k8s.conf
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
	#/dev/mapper/cl-swap     swap                    swap    defaults        0 0
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
	# Setup your firewall settings
	#firewall-cmd --zone=public --add-port=10250/tcp --permanent        # Port used by kubelet
	#firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent  # range of ports used by NodePort
	#firewall-cmd --reload
	
	#Stop and disable firewalld. Quick fix when you dont want to set up firewall fules.
	systemctl stop firewalld
	systemctl disable firewalld
	#IP Tables need to be flushed. Would not be able to add nodes without this step.
	iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
	echo "Disabled firewalld. Please enable with direct rules."
	echo "Setting IPTable rules"
	## set default IPv6 policies to let everything in
	ip6tables --policy INPUT   ACCEPT;
	ip6tables --policy OUTPUT  ACCEPT;
	ip6tables --policy FORWARD ACCEPT;
	## start fresh
	ip6tables -Z; # zero counters
	ip6tables -F; # flush (delete) rules
	ip6tables -X; # delete all extra chains
	## set default IPv4 policies to let everything in
	iptables --policy INPUT   ACCEPT;
	iptables --policy OUTPUT  ACCEPT;
	iptables --policy FORWARD ACCEPT;
	## start fresh
	iptables -Z; # zero counters
	iptables -F; # flush (delete) rules
	iptables -X; # delete all extra chains
	echo "IPTables set afresh."
else
	echo "Firewalld seems to be disabled. Continuing."
fi

sysctl -q --system



echo "Add COPR and CRI-O repos."
#Add EPEL Repo. Not needed thus commented out.
#yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

#Enable the copr plugin and then rhcontainerbot/container-selinux repo for smooth Docker install
dnf -y -q install 'dnf-command(copr)'

#Below repo seems to be a dev one so use with caution
dnf -y -q copr enable rhcontainerbot/container-selinux
#Add CRI-O Repo.
#For CentOS8
#curl -s -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_8/devel:kubic:libcontainers:stable.repo
#sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.18.1/CentOS_8/devel:kubic:libcontainers:stable:cri-o:1.18.repo
#curl -s -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.1.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.18:/1.18.1/CentOS_8/devel:kubic:libcontainers:stable:cri-o:1.18:1.18.1.repo
#curl -s -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.repo https://provo-mirror.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.18:/1.18.3/CentOS_8/devel:kubic:libcontainers:stable:cri-o:1.18:1.18.3.repo

#For CentOS7
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_7/devel:kubic:libcontainers:stable.repo
#curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:1.18/CentOS_7/devel:kubic:libcontainers:stable:cri-o:1.18.repo
curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:1.18.1.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/1.18:/1.18.1/CentOS_7/devel:kubic:libcontainers:stable:cri-o:1.18:1.18.1.repo

echo "Added COPR and CRI-O repos."

#Update packages.
yum -y -q update

#containerd.io package is related to the runc conflicting with the runc package from the container-tools
echo "Install yum-utils"
yum -y -q install yum-utils
echo "Installed yum-utils"

#Check if Docker needs to be installed
DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
if [[ $DOCKER_INSTALLED -gt 0 ]]
then

	# Install Container-d
	#wget https://github.com/containerd/containerd/releases/download/v1.3.5/containerd-1.3.5-linux-amd64.tar.gz
	#tar xvf containerd-1.3.5-linux-amd64.tar.gz
	# dnf -y
	dnf -y install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.10-3.2.el7.x86_64.rpm
	echo "Installed Container-d"

	#install Containers common

	#Install CRI-O
	echo "Install CRI-O"
	yum -y -q install cri-o
	echo "Installed CRI-O"


	#Install Docker on server
	echo "Docker not available. Trying to install Docker."
	dnf -y -q config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
	dnf -y -q install docker-ce
	usermod -aG docker $USER
	usermod -aG docker "$USERNAME"
	RESTART_NEEDED=0
	#Enable Docker to start on start up
	systemctl enable docker
	#Start Docker
	systemctl start docker
	#Check again
	DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
	if [[ $DOCKER_INSTALLED == 0 ]]
	then
		echo "Docker seems to be working."
		echo "But you might need to disconnect and reconnect for usermod changes to reflect."
	else
		echo "Unable to install Docker. Trying the nobest option as last resort."
		sleep 2
		dnf -y -q config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
		dnf -y -q install docker-ce --nobest
		usermod -aG docker $USER
		usermod -aG docker "$USERNAME"
		#Enable Docker to start on start up
		systemctl enable docker
		#Start Docker
		systemctl start docker
		#Check again
		DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
		if [[ $DOCKER_INSTALLED != 0 ]]
		then
			echo "Unable to install Docker. Exiting."
			sleep 2
			exit 1
		else
			echo "Docker seems to be working but you may need to disconnect and reconnect for usermod changes to reflect."
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
	"storage-driver": "overlay2",
  	"storage-opts": [
    "overlay2.override_kernel_check=true"
  	]
	}
	EOF'
	echo "Cgroup drivers updated."
	# Restart Docker for changes to take effect
	systemctl daemon-reload
	systemctl restart docker
	echo "Docker restarted."
fi

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

echo "Installing kubelet, kubeadm and kubectl (optional)."
if [[  $NODE_TYPE == "Worker" ]]
then
	#On all nodes kubeadm and kubelet should be installed. kubectl is optional.
	yum -y -q install kubelet kubeadm --disableexcludes=kubernetes
	systemctl enable --now kubelet
	echo "Installed kubelet and kubeadm on Worker node."
else
	#On all nodes kubeadm and kubelet should be installed. kubectl is optional.
	yum -y -q install kubelet kubeadm kubectl --disableexcludes=kubernetes
	systemctl enable --now kubelet
	echo "Installed kubelet, kubeadm and kubectl on Master node."
fi

systemctl stop kubelet
echo "Setting IPTable rules"
## set default IPv6 policies to let everything in
ip6tables --policy INPUT   ACCEPT;
ip6tables --policy OUTPUT  ACCEPT;
ip6tables --policy FORWARD ACCEPT;
## start fresh
ip6tables -Z; # zero counters
ip6tables -F; # flush (delete) rules
ip6tables -X; # delete all extra chains
## set default IPv4 policies to let everything in
iptables --policy INPUT   ACCEPT;
iptables --policy OUTPUT  ACCEPT;
iptables --policy FORWARD ACCEPT;
## start fresh
iptables -Z; # zero counters
iptables -F; # flush (delete) rules
iptables -X; # delete all extra chains
echo "IPTables set afresh."
#Restart kublet
systemctl daemon-reload
systemctl enable kubelet 
systemctl start kubelet

if [[ $RESTART_NEEDED == 0 ]]
then
	echo "All done. Restarting the node for changes to take effect."
	#shutdown -r
else
	echo "Script completed."
	echo "----------- $(hostname) ready for next step ------------"
fi
