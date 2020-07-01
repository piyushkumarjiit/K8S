#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#Cluster related variables
# KUBE_VIP_1_HOSTNAME="VIP"
# KUBE_VIP_1_IP="192.168.2.6"
# KUBE_LBNODE_1_HOSTNAME="KubeLBNode1"
# KUBE_LBNODE_1_IP="192.168.2.205"
# KUBE_LBNODE_2_HOSTNAME="KubeLBNode2"
# KUBE_LBNODE_2_IP="192.168.2.111"
# KUBE_MASTER_1_HOSTNAME="KubeMasterCentOS8"
# KUBE_MASTER_1_IP="192.168.2.220"
# KUBE_MASTER_2_HOSTNAME="KubeMaster2CentOS8"
# KUBE_MASTER_2_IP="192.168.2.13"
# KUBE_MASTER_3_HOSTNAME="KubeMaster3CentOS8"
# KUBE_MASTER_3_IP="192.168.2.186"


# KUBE_VIP_1_IP="$KUBE_VIP_1_IP"
# KUBE_MASTER_1_IP="$KUBE_MASTER_1_IP"
# KUBE_MASTER_2_IP="$KUBE_MASTER_2_IP"
# KUBE_MASTER_3_IP="$KUBE_MASTER_3_IP"

#LB config related variables
PRIORITY=200
API_PORT=6443
INTERFACE=ens192
AUTH_PASS=K33p@Gu3ss1ng
#UNICAST_PEER_IP=$KUBE_LBNODE_2_IP
ROUTER_ID="RouterID1"

if [[ "$KUBE_VIP" == "" ]]
then
	echo "Virtual Address (KUBE_VIP) not set. Unable to proceed."
	exit 1
fi

if [[ "$UNICAST_PEER_IP" == "" ]]
then
	echo "List of keeplaived peers (UNICAST_PEER_IP) not passed. Unable to proceed."
	exit 1
fi	

if [[ $1 == "" ]]
then
	echo "PRIORITY not passed. Using default value: "$PRIORITY
else
	PRIORITY="$1"
	echo "Using passed PRIORITY: "$PRIORITY
fi

if [[ $2 == "" ]]
then
	echo "INTERFACE not passed. Using default value: "$INTERFACE
else
	INTERFACE="$2"
	echo "Using passed INTERFACE: "$INTERFACE
fi

if [[ $3 == "" ]]
then
	echo "AUTH_PASS not passed. Using default value: "$AUTH_PASS
else
	AUTH_PASS="$3"
	echo "Using passed AUTH_PASS: "$AUTH_PASS
fi

if [[ $4 == "" ]]
then
	echo "API_PORT not passed. Using default value: "$API_PORT
else
	API_PORT="$4"
	echo "Using passed API_PORT: "$API_PORT
fi

if [[ $5 == "" ]]
then
	UNICAST_SRC_IP="$(hostname -I | cut -d" " -f 1)"
	echo "UNICAST_SRC_IP not passed. Using default value: "$UNICAST_SRC_IP
else
	UNICAST_SRC_IP="$5"
	echo "Using passed PRIORITY: "$UNICAST_SRC_IP
fi

USERNAME="$(whoami)"
#Set the home directory in target server for scp
if [[ "$USERNAME" == "root" ]]
then
	TARGET_DIR="/root"
else
	TARGET_DIR="/home/$USERNAME"
fi

#Take backup of old hosts file. In case we need to restore/cleanup
cat /etc/hosts > hosts.txt
#Add IP Addresses and Hostnames in hosts file
if [[ ($NODES_IN_CLUSTER != "" ) && ("$CURRENT_NODE" != "$CALLING_NODE" ) ]]
then
	echo -n "$NODES_IN_CLUSTER" | tee -a /etc/hosts
	echo "Hosts file updated."
elif [[ "$CURRENT_NODE" == "$CALLING_NODE" ]]
then
	echo "Hosts file already update for Primary node by main script."
else
	#statements
	echo "NODES_IN_CLUSTER not set. Exiting."
	exit 1
fi

#Check the current status of Load balance config
LB_CONNECTED=$(nc -vz "$KUBE_VIP $API_PORT" |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz "$KUBE_VIP $API_PORT" |& grep refused > /dev/null 2>&1; echo $?)

if [[ $LB_CONNECTED == 0 || $LB_REFUSED == 0 ]]
then
	echo "Load balancer seems to be running on the sepcified VIP. Unable to proceed. Exiting."
	exit 1
fi

echo "Proceeding with LB config."
#Other Load Balancer nodes. Used in keepalived conf. Passed by main script and seprated by "%"
TEMP_PEER_IPS=$(echo $UNICAST_PEER_IP | sed 's#%#\n#g')
#All Master nodes part of the cluster. Used in haproxy.cfg. Passed by main script and seprated by "%"
TEMP_MASTER_IPS=$(echo $MASTER_PEER_IP | sed 's#%#\n#g')
#HAProxy.cfg server node params. This can be updated if needed.
LB_PARAMS="check port $API_PORT inter 5000 fall 5"

node=1
FINAL_SERVER_STRING=""
for SERVER in ${TEMP_MASTER_IPS[*]}
do
	if [[ "$FINAL_SERVER_STRING" == "" ]]
	then
						       #server node1 ###n0d31_1p_@ddr###:###AP1_P0RT### check port ###AP1_P0RT### inter 5000 fall 5
		FINAL_SERVER_STRING=$(echo "server SERVER$node $SERVER:$API_PORT $LB_PARAMS")
		FINAL_SERVER_STRING+=$'\n'
		echo "First Value added to FINAL_SERVER_STRING"
		node=$(($node + 1))
	else
		FINAL_SERVER_STRING+=$'\t'
		FINAL_SERVER_STRING+="$(echo -e "server SERVER$node $SERVER:$API_PORT $LB_PARAMS" )"
		FINAL_SERVER_STRING+=$'\n'
		echo "Value added to FINAL_SERVER_STRING"
		node="$(($node + 1))"
	fi
done
echo "All server entries ready."
echo "$FINAL_SERVER_STRING"

#Secondary
#PRIORITY="100"
#UNICAST_SRC_IP="$KUBE_LBNODE_2_IP"
#UNICAST_PEER_IP="KUBE_LBNODE_1_IP"


# Set SELinux in permissive mode (effectively disabling it). Needed for K8s as well as HAProxy
echo "Disabling SELINUX."
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
echo "Done."

#Check if non local bind is already allowed
NON_LOCAL_BIND_ALLOWED=$(cat /etc/sysctl.conf | grep net.ipv4.ip_nonlocal_bind=1 > /dev/null 2>&1; echo $?)
if [[ $NON_LOCAL_BIND_ALLOWED != 0 ]]
then	
	#To allow HAProxy to bind to non local ports
	echo "Updating to allow non local binding for HAProxy."
	bash -c 'cat <<- EOF >>/etc/sysctl.conf
	net.ipv4.ip_nonlocal_bind=1
	EOF'
	echo "Done."
	sysctl -q -p
else
	echo "Non local bind already setup in /etc/sysctl."
fi
#Reload settings from all system configuration files.
sysctl -q --system

cd ~
echo "Current Path:  $(pwd)"
if [[ ! -r $TARGET_DIR/keepalived.conf ]]
then
	echo "Downloading the template files from github."
	#Get the keepalived_template.conf and create a copy
	wget "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/keepalived_template.conf"
	cp keepalived_template.conf keepalived.conf
	echo "Updating the keepalived.conf."
	#Update the placeholders with value for primary
	sed -i "s*###r0ut3r_1d###*$ROUTER_ID*g" keepalived.conf
	sed -i "s*###1nt3rf@c3###*$INTERFACE*g" keepalived.conf
	sed -i "s*###pr10r1ty###*$PRIORITY*g" keepalived.conf
	sed -i "s*###un1c@st_src_1p###*$UNICAST_SRC_IP*g" keepalived.conf
	#sed -i "s*###un1c@st_p33r###*$UNICAST_PEER_IP*g" keepalived.conf
	sed -i "s*###@uth_p@ss###*$AUTH_PASS*g" keepalived.conf
	sed -i "s*###v1rtu@l_1p@ddr3ss###*$KUBE_VIP*g" keepalived.conf
	#Multiple nodes with newline thus had to use awk. Sed does not handle newline properly
	awk -i inplace -v srch="###un1c@st_p33r###" -v repl="$TEMP_PEER_IPS" '{ sub(srch,repl,$0); print $0 }' keepalived.conf
	echo "keepalived.conf updated."
else
	echo "Found keepalived.conf in current direcotry. Going to use it 'as is'."
fi

if [[ ! -r $TARGET_DIR/haproxy.cfg ]]
then
	echo "Downloading the template files from github."
	#Get the haproxy_template.cfg and create a copy
	wget "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/haproxy_template.cfg"
	cp haproxy_template.cfg haproxy.cfg
	echo "Updating the haproxy.cfg."
	#Update the placeholders with value for primary
	sed -i "s*###vip_@ddr3ss###*$KUBE_VIP*g" haproxy.cfg
	# sed -i "s*###n0d31_1p_@ddr###*$KUBE_MASTER_1_IP*g" haproxy.cfg
	# sed -i "s*###n0d32_1p_@ddr###*$KUBE_MASTER_2_IP*g" haproxy.cfg
	# sed -i "s*###n0d33_1p_@ddr###*$KUBE_MASTER_3_IP*g" haproxy.cfg
	sed -i "s*###AP1_P0RT###*$API_PORT*g" haproxy.cfg
	#Multiple nodes with newline thus had to use awk. Sed does not handle newline properly
	awk -i inplace -v srch="###S3rv3r###" -v repl="$FINAL_SERVER_STRING" '{ sub(srch,repl,$0); print $0 }' haproxy.cfg
	echo "haproxy.cfg updated."
else
	echo "Found haproxy.cfg in current direcotry. Going to use it 'as is'."
fi 


#Identify if it is Ubuntu or Centos/RHEL
distro=$(cat /etc/*-release | awk '/ID=/ { print }' | head -n 1 | awk -F "=" '{print $2}' | sed -e 's/^"//' -e 's/"$//')

if [[ $distro == "Ubuntu" ]]
then
	#Needs testing
	echo "Calling apt update."
	#Call update
	apt-get update

	#Disable UFW
	ufw disable

	#Install haproxy keepalived; 
	apt-get -y install haproxy keepalived

	#Update keepalived.conf
	mv $TARGET_DIR/keepalived.conf /etc/keepalived/keepalived.conf

	#Start keepalived service
	systemctl enable keepalived.service && systemctl start keepalived.service

	#Update HAProxy config (haproxy.cfg)
	mv $TARGET_DIR/haproxy.cfg /etc/haproxy/haproxy.cfg
	
	#Start HAProxy service
	systemctl start haproxy.service  && systemctl enable haproxy.service

	echo "Both the services should be up. Lets check."

elif [[ $distro == "centos" ]]
then
	echo "Calling yum update."
	#Update packages.
	sudo yum update -y

	#Disable and Stop firewalld. Unless firewalld is stopped, HAProxy would not work
	echo "Disabling firewalld."
	systemctl disable firewalld
	systemctl stop firewalld

	#Install haproxy keepalived; 
	echo "Installing haproxy and keepalived."
	dnf -y  install haproxy keepalived

	#Update keepalived.conf
	echo "Replacing the default keepalived.conf with our updated version."
	mv $TARGET_DIR/keepalived.conf /etc/keepalived/keepalived.conf

	#Start keepalived service
	systemctl enable keepalived.service && systemctl start keepalived.service

	#Update HAProxy config (haproxy.cfg)
	echo "Replacing the default haproxy.cfg with our updated version."
	echo "Expected path: $(pwd)/haproxy.cfg"
	mv $TARGET_DIR/haproxy.cfg /etc/haproxy/haproxy.cfg
	
	#Only for Non Primary node.
	#Run below command on Primary keepalived node to switch VIP to Secondary node. 
	#This ensures that VIP is available for HAProxy to bind to.
	#sudo systemctl stop keepalived
	
	#Start HAProxy service
	systemctl start haproxy.service  && systemctl enable haproxy.service

	#Run below command on Primary keepalived node to switch VIP back to Primary node.
	#sudo systemctl start keepalived
	echo "Both the services should be up. Lets check."
fi

nc -zv "$KUBE_VIP $API_PORT"
#Run Netcat and save the result in text file
#nc -vz "$KUBE_VIP $API_PORT" > file.txt 2>&1
#Check the 
LB_CONNECTED=$(nc -vz $KUBE_VIP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz $KUBE_VIP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)

if [[ ($LB_CONNECTED == 0 ) || ($LB_REFUSED == 0) ]]
then 
	echo "Route seems to be available."
else
	echo "No route found. Please check firewall config."
	nc -vz "$KUBE_VIP $API_PORT"
fi

echo "Script (setting_loadbalancer) completed."