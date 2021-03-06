#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

# Node prepare script. Need to be executed from a host where we have:
#1. sudo and internet access
#2. Hosts file or DNS based ssh access to all nodes
#3. key based ssh enabled for all nodes

#sudo ./prepare_node.sh | tee prepare_node.log
#sudo ./prepare_node.sh |& tee prepare_node.log

echo "----------- Preparing $(hostname) ------------"
#Hostname of the node from where we run the script
CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"
#All node names passed by calling script that we are trying to setup
ALL_NODE_NAMES=($TEMP_NODE_NAMES)
#All node IP addresses passed by calling script that we are trying to setup
ALL_NODE_IPS=($TEMP_NODE_IPS)

if [[ ${ALL_NODE_NAMES[*]} == "" || ${ALL_NODE_IPS[*]} == "" ]]
then
	echo "ALL_NODE_NAMES or ALL_NODE_IPS not passed. Unable to proceed."
	exit 1
fi

if [[ $KEEP_FIREWALL_ENABLED == "" ]]
then
	echo "KEEP_FIREWALL_ENABLED not set. Defaulting to false. Will disbale the firewall."
	KEEP_FIREWALL_ENABLED="false"
else
	echo "KEEP_FIREWALL_ENABLED defined: $KEEP_FIREWALL_ENABLED"
fi

if [[ $CONTAINER_RUNTIME == "cri-o" && $CRI_O_VERSION == "" ]]
then
	echo "CRI_O_VERSION not set for $CONTAINER_RUNTIME. Defaulting to 1.17."
	CRI_O_VERSION=1.17
else
	echo "Passed CONTAINER_RUNTIME: $CONTAINER_RUNTIME and CRI_O_VERSION: $CRI_O_VERSION."
fi

echo "Value of passed ALL_NODE_NAMES ${ALL_NODE_NAMES[*]}"
echo "Value of passed ALL_NODE_IPS ${ALL_NODE_IPS[*]}"

DISTRO=$(cat /etc/*-release | awk '/ID=/ { print }' | head -n 1 | awk -F "=" '{print $2}' | sed -e 's/^"//' -e 's/"$//')
DISTRO_VERSION=$(cat /etc/*-release | awk '/VERSION_ID=/ { print }' | head -n 1 | awk -F "=" '{print $2}' | sed -e 's/^"//' -e 's/"$//')
OS_VERSION="$DISTRO$DISTRO_VERSION"


echo "Node OS Version: $OS_VERSION"
echo "CRI requested is $CONTAINER_RUNTIME"
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
	#sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
	echo "Done."
else
	echo "SELinux already set as permissive. No change needed."
fi

#Disable and Stop firewalld. Unless firewalld is stopped, HAProxy would not work
FIREWALLD_STATUS=$(sudo systemctl status firewalld | grep -w "Active: inactive" > /dev/null 2>&1; echo $?)
if [[ $FIREWALLD_STATUS -gt 0 && $KEEP_FIREWALL_ENABLED == "true" ]]
then
	# Setup your firewall settings. These need to be further refined. PVC was not working with firewall on
	firewall-cmd --get-active-zones
	firewall-cmd --zone=public --add-port=22/tcp --permanent 		# SSHD
	firewall-cmd --zone=public --add-port=25/tcp --permanent 		# Master
	firewall-cmd --zone=public --add-port=53/tcp --permanent 		# system-resolv

	firewall-cmd --zone=public --add-port=68/tcp --permanent 		# dhclient
	firewall-cmd --zone=public --add-port=179/tcp --permanent 		# Bird
	firewall-cmd --zone=public --add-port=323/tcp --permanent 		# Chronyd to sync time between nodes

	firewall-cmd --zone=public --add-port=2379/tcp --permanent 		# etcd
	firewall-cmd --zone=public --add-port=2380/tcp --permanent 		# etcd
	firewall-cmd --zone=public --add-port=2381/tcp --permanent 		# etcd
	firewall-cmd --zone=public --add-port=3300/tcp --permanent 		# Ceph monitor uses this port
	firewall-cmd --zone=public --add-port=5355/tcp --permanent 		# system-resolv

	firewall-cmd --zone=public --add-port=6443/tcp --permanent      # Port used by API Server
	firewall-cmd --zone=public --add-port=6789/tcp --permanent 		# Ceph monitor uses this port 
	firewall-cmd --zone=public --add-port=6800-7300/tcp --permanent	# Ceph Manager listens on the first available port on the public network beginning at port 6800
	
	firewall-cmd --zone=public --add-port=7946/tcp --permanent 		# MetalLB Speaker
	firewall-cmd --zone=public --add-port=7472/tcp --permanent 		# MetalLB Speaker
	#firewall-cmd --zone=public --add-port=8472/udp --permanent		# Need to check
	
	firewall-cmd --zone=public --add-port=9080/tcp --permanent 		# cephcsi
	firewall-cmd --zone=public --add-port=9081/tcp --permanent 		# cephcsi
	firewall-cmd --zone=public --add-port=9090/tcp --permanent 		# cephcsi
	firewall-cmd --zone=public --add-port=9091/tcp --permanent 		# cephcsi
	firewall-cmd --zone=public --add-port=9099/tcp --permanent 		# Calico-node
	firewall-cmd --zone=public --add-port=9100/tcp --permanent 		# Kube RBAC-p / node_exporter
	
	firewall-cmd --zone=public --add-port=10010/tcp --permanent 	# CRI-O’s so called stream_port 

	firewall-cmd --zone=public --add-port=10248/tcp --permanent     # Port used by kubelet
	firewall-cmd --zone=public --add-port=10249/tcp --permanent     # Port used by kube proxy
	firewall-cmd --zone=public --add-port=10250/tcp --permanent     # Port used by kubelet
	firewall-cmd --zone=public --add-port=10256/tcp --permanent 	# Port used by kube proxy
	firewall-cmd --zone=public --add-port=10257/tcp --permanent 	# Port used by kube controller
	firewall-cmd --zone=public --add-port=10259/tcp --permanent 	# Port used by kube scheduler
	firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent  # range of ports used by NodePort
	firewall-cmd --zone=public --add-port=36203/tcp --permanent 	# kubelet
	firewall-cmd --zone=public --add-port=38514/tcp --permanent     # Port used by kubelet
	firewall-cmd --zone=public --add-port=44167/tcp --permanent     # Port used by kubelet
	firewall-cmd --zone=public --add-masquerade --permanent		# Need to check

	firewall-cmd --reload
	systemctl restart firewalld
elif [[ $FIREWALLD_STATUS -gt 0 ]]
then
	#Stop and disable firewalld. Quick fix when you dont want to set up firewall fules.
	systemctl stop firewalld
	systemctl disable firewalld
	echo "Firewalld disabled. Continuing."
else
	echo "Firewalld seems to be disabled. Continuing."
fi

# Increase Max Virtual memory on nodes if running Elasticsearch
VM_MAX_MAP_STATUS=$(cat /etc/sysctl.conf | grep -w 'vm.max_map_count=262144' > /dev/null 2>&1; echo $?)
if [[ $VM_MAX_MAP_STATUS != 0 ]]
then	
	echo "Adding Virtual Memory value."
	bash -c 'cat <<-EOF >>  /etc/sysctl.conf
	vm.max_map_count=262144
	EOF'
	sysctl -p -q
	echo "Done."
else
	echo "Virtual Memory value already set. No change needed."
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

sysctl -q --system

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

#containerd.io package is related to the runc conflicting with the runc package from the container-tools
echo "Install yum-utils"
yum -y -q install yum-utils device-mapper-persistent-data lvm2
echo "Installed yum-utils"

#Add EPEL Repo. Not needed thus commented out.
yum -y -q install epel-re*
#yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
#yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

if [[ $CONTAINER_RUNTIME == "cri-o" ]]
then
	# Added below to fix the issue with IP4 forwarding. These are also required for CRI-O
	modprobe overlay
	modprobe br_netfilter
	if [[ -r /etc/sysctl.d/99-kubernetes-cri.conf ]]
	then
		echo "99-kubernetes-cri.conf exists. Using as is."
	else
		# Set up required sysctl params, these persist across reboots.
		cat <<- EOF > /etc/sysctl.d/99-kubernetes-cri.conf 
		net.bridge.bridge-nf-call-iptables  = 1
		net.ipv4.ip_forward                 = 1
		net.bridge.bridge-nf-call-ip6tables = 1
		EOF
		sysctl -q --system
		echo "99-kubernetes-cri.conf created and updated for CRI-O."
	fi

	echo "Add COPR and CRI-O repos."
	#Enable the copr plugin and then rhcontainerbot/container-selinux repo for smooth Docker install
	dnf -y -q install 'dnf-command(copr)'

	#Below repo seems to be a dev one so use with caution
	dnf -y -q copr enable rhcontainerbot/container-selinux
	#Add CRI-O Repo.

	if [[ $OS_VERSION == "centos8" ]]
	then
		#For CentOS8
		OS="CentOS_$DISTRO_VERSION"

		VERSION=$CRI_O_VERSION
		curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo
		curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
		echo "Added COPR and CRI-O repos for CentOS8."
	elif [[ $OS_VERSION == "centos7"  ]]
	then
		#For CentOS7
		OS="CentOS_$DISTRO_VERSION"
		VERSION=$CRI_O_VERSION
		curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/devel:kubic:libcontainers:stable.repo
		curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
		echo "Added COPR and CRI-O repos for CentOS7."
	else
		echo "Unable to install. Exiting."
		sleep 2
		exit 1
	fi
	#Update packages.
	yum -y -q update
	
	#install Containers common

	#Install CRI-O. Not working properly
	echo "Install CRI-O"
	# yum -y -q install https://cbs.centos.org/kojifiles/packages/cri-o/1.15.3/1.el7/x86_64/cri-o-1.15.3-1.el7.x86_64.rpm
	
	# Install Nix package manager
	#curl -L https://nixos.org/nix/install | sh
	# Download the CRI-O Nix package directly from latest commit in google bucket
	#curl -f https://storage.googleapis.com/k8s-conform-cri-o/artifacts/crio-$(git ls-remote https://github.com/cri-o/cri-o master | cut -c1-9).tar.gz -o crio.tar.gz
	yum -y -q install cri-o
	systemctl -q daemon-reload
	systemctl -q start crio
	echo "Installed CRI-O"
elif [[ $CONTAINER_RUNTIME == "containerd" ]]
then
	cat > /etc/modules-load.d/containerd.conf <<-EOF
	overlay
	br_netfilter
	EOF

	modprobe overlay
	modprobe br_netfilter

	# Setup required sysctl params, these persist across reboots.
	cat > /etc/sysctl.d/99-kubernetes-cri.conf <<-EOF
	net.bridge.bridge-nf-call-iptables  = 1
	net.ipv4.ip_forward                 = 1
	net.bridge.bridge-nf-call-ip6tables = 1
	EOF
	echo "99-kubernetes-cri.conf created and updated for containerd."
	sysctl -q --system

	# Add Docker repo as it is used by containerd and docker
	dnf -y -q config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
	#wget -O /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/centos/docker-ce.repo
	
	#Update packages.
	yum -y -q update
	
	# Install Container-d
	dnf -y -q install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.10-3.2.el7.x86_64.rpm
	yum update -y -q
	#yum install -y -q containerd.io
	## Configure containerd
	mkdir -p /etc/containerd
	containerd config default > /etc/containerd/config.toml
	# Enable Containerd to start on start up
	systemctl enable containerd
	echo "Installed Container-d"
	systemctl restart containerd
else
	#Check if Docker needs to be installed
	DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
	if [[ $DOCKER_INSTALLED -gt 0 ]]
	then

		# Add Docker repo as it is used by containerd and docker
		dnf -y -q config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
		#wget -O /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/centos/docker-ce.repo
		#Update packages.
		yum -y -q update
		#Install Docker on server
		echo "Docker not available. Trying to install Docker."
		if [[ $OS_VERSION == "centos8" ]]
		then
			# Install Container-d and Docker-CE
			dnf -y -q install https://download.docker.com/linux/centos/7/x86_64/stable/Packages/containerd.io-1.2.10-3.2.el7.x86_64.rpm
			dnf -y -q install docker-ce-19.03.11 docker-ce-cli-19.03.11
			echo "Docker installed in CentOS8."
		elif [[ $OS_VERSION == "centos7" ]]
		then
			#dnf -y -q install docker-ce
			dnf -y -q install containerd.io-1.2.13 docker-ce-19.03.11 docker-ce-cli-19.03.11
			echo "Docker installed in CentOS7."
		else
			echo "Unable to identify OSVersion. Exiting."
			sleep 2
			exit 1
		fi
		# Enable Containerd to start on start up
		systemctl enable containerd
		#Enable Docker to start on start up
		systemctl enable docker
		#Start Docker
		systemctl start docker
		#Check again
		DOCKER_INSTALLED=$(docker -v > /dev/null 2>&1; echo $?)
		if [[ $DOCKER_INSTALLED == 0 ]]
		then
			usermod -aG docker $USER
			usermod -aG docker "$USERNAME"
			echo "Docker seems to be working."
			#echo "But you might need to disconnect and reconnect for usermod changes to reflect."
		else
			echo "Unable to install Docker. Trying the nobest option as last resort."
			sleep 2
			#dnf -y -q config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
			dnf -y -q install docker-ce --nobest
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
				usermod -aG docker $USER
				usermod -aG docker "$USERNAME"
				RESTART_NEEDED=0
				echo "Docker seems to be working but you may need to disconnect and reconnect for usermod changes to reflect."
				sleep 5
				#exit 1
			fi
		fi

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
			mkdir -p /etc/systemd/system/docker.service.d
		fi

		# Restart Docker for changes to take effect
		systemctl daemon-reload
		systemctl restart docker
		echo "Docker restarted."

	else
		echo "Docker already installed."
	fi
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

if [[ $CONTAINER_RUNTIME == "cri-o" ]]
then
	systemctl stop kubelet
	# Set systemd as default cgroup driver
	
	#Check if the flag is defined in the file /var/lib/kubelet/config.yaml or kubelet.service
	CGROUPS_DEFINED=$(cat /var/lib/kubelet/config.yaml | grep cgroupDriver > /dev/null 2>&1; echo $?)
	if [[ $CGROUPS_DEFINED == 0 ]]
	then
		# Fetch existing KubeletConfiguration in the file /var/lib/kubelet/config.yaml or kubelet.service
		CURRENT_ARGS=$(cat /var/lib/kubelet/config.yaml)
		# Update the cgroups flag to systemd
		#sed -i 
	else
		# Fetch existing KubeletConfiguration in the file /var/lib/kubelet/config.yaml or kubelet.service
		CURRENT_ARGS=$(cat /var/lib/kubelet/config.yaml)
		#Add cgroups config to the file /var/lib/kubelet/config.yaml
		echo "Current Args: $CURRENT_ARGS"
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='cgroupDriver: systemd'
		echo "Updated Args: $CURRENT_ARGS"
		#Create a backup copy of /etc/kubernetes/kubelet.env
		cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.bak
		echo "Created a backup of exisitng kubelet.env. Appending the new ARGS"
		echo -e "$CURRENT_ARGS" > /var/lib/kubelet/config.yaml
		echo "Cgroups config updated in /var/lib/kubelet/config.yaml."
	fi

	# Add CRI-O related config
	# Fetch existing KUBELET_ARGS in the file or kubelet.service
	KUBELET_ARGS_DEFINED=$(cat /etc/kubernetes/kubelet.env | grep KUBELET_ARGS > /dev/null 2>&1; echo $?)
	if [[ $KUBELET_ARGS_DEFINED == 0 ]]
	then
		echo "KUBELET_ARGS present in /etc/kubernetes/kubelet.env. Updating existing config."
		# Fetch existing KubeletConfiguration in the file /var/lib/kubelet/config.yaml or kubelet.service
		CURRENT_ARGS=$(cat /etc/kubernetes/kubelet.env)
		#Add below to KUBELET_ARGS
		echo "Current Args: $CURRENT_ARGS"
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--container-runtime=remote' # Use remote runtime with provided socket.
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--container-runtime-endpoint=unix:///var/run/crio/crio.sock' #Socket for remote runtime
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--image-service-endpoint=unix:///run/crio/crio.sock'
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--runtime-request-timeout=10m' # Optional to allow for pulling large images that take long
		echo "Updated Args: $CURRENT_ARGS"
		#Create a backup copy of /etc/kubernetes/kubelet.env
		cp /etc/kubernetes/kubelet.env /etc/kubernetes/kubelet.env.bak
		echo "Created a backup of exisitng kubelet.env. Appending the new ARGS"
		echo -e "$CURRENT_ARGS" >> /etc/kubernetes/kubelet.env
		echo "kubelet.env updated. Restart of service is required."
	else
		echo "KUBELET_ARGS not defined in /etc/kubernetes/kubelet.env. Adding config."
		CURRENT_ARGS=$(cat /etc/kubernetes/kubelet.env)
		#Add below to KUBELET_ARGS
		echo "Current Args: $CURRENT_ARGS"
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--container-runtime=remote' # Use remote runtime with provided socket.
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--container-runtime-endpoint=unix:///var/run/crio/crio.sock' #Socket for remote runtime
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--image-service-endpoint=unix:///run/crio/crio.sock'
		CURRENT_ARGS+=$'\n'
		CURRENT_ARGS+='--runtime-request-timeout=10m' # Optional to allow for pulling large images that take long
		echo "Updated Args: $CURRENT_ARGS"
		#Create a backup copy of /etc/kubernetes/kubelet.env
		cp /etc/kubernetes/kubelet.env /etc/kubernetes/kubelet.env.bak
		echo "Created a backup of exisitng kubelet.env. Appending the new ARGS"
		echo -e "$CURRENT_ARGS" >> /etc/kubernetes/kubelet.env
		echo "kubelet.env updated. Restart of service is required."+
		#Restart kublet
		#echo 'Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=cgroupfs --runtime-cgroups=/systemd/system.slice --kubelet-cgroups=/systemd/system.slice"' \
		# >> /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
	fi

	#Check if the flag is defined in the file /var/lib/kubelet/config.yaml or kubelet.service
	EXTRA_ARGS_DEFINED=$(cat /etc/default/kubelet  > /dev/null 2>&1; echo $?)
	if [[ $EXTRA_ARGS_DEFINED == 0 ]]
	then
		# Fetch existing KubeletConfiguration in the file /var/lib/kubelet/config.yaml or kubelet.service
		echo "Adding extra args to /etc/default/kubelet"
		KUBELET_EXTRA_ARGS=$(cat /etc/default/kubelet)
		# Update the flag to systemd
		#sed -i 
	else
		# Fetch existing KubeletConfiguration in the file /var/lib/kubelet/config.yaml or kubelet.service
		KUBELET_EXTRA_ARGS=$(cat /etc/default/kubelet)
		#Add cgroups config to the file /var/lib/kubelet/config.yaml
		echo "Current Args: $KUBELET_EXTRA_ARGS"
		KUBELET_EXTRA_ARGS+=$'\n'
		KUBELET_EXTRA_ARGS+='--feature-gates="AllAlpha=false,RunAsGroup=true" --container-runtime=remote --cgroup-driver=systemd --container-runtime-endpoint="unix:///var/run/crio/crio.sock" --runtime-request-timeout=5m'
		echo "Updated Args: $KUBELET_EXTRA_ARGS"
		#Create a backup copy of /etc/kubernetes/kubelet.env
		cp /etc/default/kubelet /etc/default/kubelet.bak
		echo "Created a backup of exisitng kubelet.env. Appending the new ARGS"
		echo -e "$KUBELET_EXTRA_ARGS" > /etc/default/kubelet
		echo "Cgroups config updated in /etc/default/kubelet."
	fi

	systemctl daemon-reload
	systemctl enable kubelet 
	systemctl start kubelet
else
	echo "No extra CRI-O related config required."
fi

if [[ $RESTART_NEEDED == 0 ]]
then
	echo "All done. Restarting the node for changes to take effect."
	#shutdown -r
else
	echo "Script completed."
	echo "----------- $(hostname) ready for next step ------------"
fi
