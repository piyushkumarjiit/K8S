#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#Cluster related variables
KUBE_VIP_1_HOSTNAME="VIP"
KUBE_VIP_1_IP="192.168.2.6"
KUBE_LBNODE_1_HOSTNAME="KubeLBNode1"
KUBE_LBNODE_1_IP="192.168.2.205"
KUBE_LBNODE_2_HOSTNAME="KubeLBNode2"
KUBE_LBNODE_2_IP="192.168.2.111"
KUBE_MASTER_1_HOSTNAME="KubeMasterCentOS8"
KUBE_MASTER_1_IP="192.168.2.220"
KUBE_MASTER_2_HOSTNAME="KubeMaster2CentOS8"
KUBE_MASTER_2_IP="192.168.2.13"
KUBE_MASTER_3_HOSTNAME="KubeMaster3CentOS8"
KUBE_MASTER_3_IP="192.168.2.186"

#LB config related variables
PRIORITY=200
API_PORT=6443
INTERFACE=ens192
AUTH_PASS=K33p@Gu3ss1ng
UNICAST_PEER_IP=$KUBE_LBNODE_2_IP

if [[ $1 == "" ]]
then
	echo "KUBE_VIP_1_IP not passed. Unable to proceed."
	exit 1
else
	UNICAST_PEER_IP="$1"
	echo "Using passed UNICAST_PEER_IP: "$UNICAST_PEER_IP
fi

if [[ $2 == "" ]]
then
	echo "UNICAST_PEER_IP not passed. Unable to proceed."
	exit 1
else
	UNICAST_PEER_IP="$2"
	echo "Using passed UNICAST_PEER_IP: "$UNICAST_PEER_IP
fi	

UNICAST_SRC_IP="$(hostname -I | cut -d" " -f 1)"
echo "Using localhost IP Address as UNICAST_SRC_IP: " $UNICAST_SRC_IP

if [[ $3 == "" ]]
then
	echo "PRIORITY not passed. Using default value: "$PRIORITY
else
	PRIORITY="$3"
	echo "Using passed PRIORITY: "$PRIORITY
fi

if [[ $4 == "" ]]
then
	echo "INTERFACE not passed. Using default value: "$INTERFACE
else
	INTERFACE="$4"
	echo "Using passed INTERFACE: "$INTERFACE
fi

if [[ $5 == "" ]]
then
	echo "AUTH_PASS not passed. Using default value: "$AUTH_PASS
else
	AUTH_PASS="$5"
	echo "Using passed AUTH_PASS: "$AUTH_PASS
fi

if [[ $6 == "" ]]
then
	echo "API_PORT not passed. Using default value: "$API_PORT
else
	API_PORT="$6"
	echo "Using passed API_PORT: "$API_PORT
fi


#Secondary
#PRIORITY="100"
#UNICAST_SRC_IP="$KUBE_LBNODE_2_IP"
#UNICAST_PEER_IP="KUBE_LBNODE_1_IP"


# Set SELinux in permissive mode (effectively disabling it). Needed for K8s as well as HAProxy
echo "Disabling SELINUX."
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
echo "Done."

#To allow HAProxy to bind to non local ports
echo "Updating to allow non local binding for HAProxy."
bash -c 'cat <<- EOF >>/etc/sysctl.conf
net.ipv4.ip_nonlocal_bind=1
EOF'
echo "Done."

sysctl -p
sysctl --system

cd ~
echo "Downloading the template files from github."
#Get the keepalived_template.conf and create a copy
#Get the haproxy_template.cfg and create a copy

echo "Updating the keepalived template."
cp keepalived_template.conf keepalived.conf
#Update the placeholders with value for primary
sed -i "s*###1nt3rf@c3###*$INTERFACE*g" keepalived.conf
sed -i "s*###pr10r1ty###*$PRIORITY*g" keepalived.conf
sed -i "s*###un1c@st_src_1p###*$UNICAST_SRC_IP*g" keepalived.conf
sed -i "s*###un1c@st_p33r###*$UNICAST_PEER_IP*g" keepalived.conf
sed -i "s*###@uth_p@ss###*$UNICAST_PEER_IP*g" keepalived.conf
sed -i "s*###v1rtu@l_1p@ddr3ss###*$KUBE_VIP_1_IP*g" keepalived.conf
echo "Done."

echo "Updating the haproxy template."
cp haproxy_template.cfg haproxy.cfg
#Update the placeholders with value for primary
sed -i "s*###vip_@ddr3ss###*$KUBE_VIP_1_IP*g" haproxy.cfg
sed -i "s*###n0d31_1p_@ddr###*$KUBE_MASTER_1_IP*g" haproxy.cfg
sed -i "s*###n0d32_1p_@ddr###*$KUBE_MASTER_2_IP*g" haproxy.cfg
sed -i "s*###n0d33_1p_@ddr###*$KUBE_MASTER_3_IP*g" haproxy.cfg
echo "Done."

#Identify if it is Ubuntu or Centos/RHEL
distro=$(cat /etc/*-release | awk '/ID=/ { print }' | head -n 1 | awk -F "=" '{print $2}' | sed -e 's/^"//' -e 's/"$//')

if [[ $distro == "Ubuntu" ]]
then
	#Needs testing
	echo "Calling apt update."
	#Call update
	sudo apt-get update

	#Disable UFW
	sudo ufw disable

	#Install haproxy keepalived; 
	sudo apt-get -y install haproxy keepalived

	#Update keepalived.conf
	sudo mv keepalived.conf /etc/keepalived/keepalived.conf

	#Start keepalived service
	sudo systemctl enable keepalived.service && systemctl start keepalived.service

	#Update HAProxy config (haproxy.cfg)
	sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg
	
	#Start HAProxy service
	sudo systemctl start haproxy.service  && systemctl enable haproxy.service

	echo "Both the services should be up. Lets check."

elif [[ $distro == "centos" ]]
then
	echo "Calling yum update."
	#Update packages.
	sudo yum update -y

	#Disable and Stop firewalld. Unless firewalld is stopped, HAProxy would not work
	echo "Disabling firewalld."
	sudo systemctl disable firewalld
	sudo systemctl stop firewalld

	#Install haproxy keepalived; 
	echo "Installing haproxy and keepalived."
	sudo dnf -y  install haproxy keepalived

	#Update keepalived.conf
	echo "Replacing the default keepalived.conf with our updated version."
	sudo mv keepalived.conf /etc/keepalived/keepalived.conf

	#Start keepalived service
	sudo systemctl enable keepalived.service && systemctl start keepalived.service

	#Update HAProxy config (haproxy.cfg)
	echo "Replacing the default haproxy.cfg with our updated version."
	sudo mv haproxy.cfg /etc/haproxy/haproxy.cfg
	
	#Only for Non Primary node.
	#Run below command on Primary keepalived node to switch VIP to Secondary node. 
	#This ensures that VIP is available for HAProxy to bind to.
	#sudo systemctl stop keepalived
	
	#Start HAProxy service
	sudo systemctl start haproxy.service  && systemctl enable haproxy.service

	#Run below command on Primary keepalived node to switch VIP back to Primary node.
	#sudo systemctl start keepalived
	echo "Both the services should be up. Lets check."
fi

nc -zv $KUBE_VIP_1_IP $API_PORT
#Run Netcat and save the result in text file
nc -vz $KUBE_VIP_1_IP $API_PORT > file.txt 2>&1
#Check the 

if [[ $(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?) == 0 || $(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep refused > /dev/null 2>&1; echo $?) ]]
then 
	echo "Route seems to be available."
else
	echo "No route found. Please check firewall config."
	nc -vz $KUBE_VIP_1_IP $API_PORT
fi

echo "Script (setting_loadbalancer) completed."
