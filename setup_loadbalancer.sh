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

echo "----------- Setting up Load Balancing in $(hostname) ------------"

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
	echo "Using passed UNICAST_SRC_IP: "$UNICAST_SRC_IP
fi

# USERNAME="$(whoami)"
# #Set the home directory in target server for scp
# if [[ "$USERNAME" == "root" ]]
# then
# 	TARGET_DIR="/root"
# else
# 	TARGET_DIR="/home/$USERNAME"
# fi

#Check if we can ping other nodes in cluster. If not, add IP Addresses and Hostnames in hosts file
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

#Check the current status of Load balance config
echo "Try: nc -vz $KUBE_VIP $API_PORT"
LB_CONNECTED=$(nc -vz $KUBE_VIP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz $KUBE_VIP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)
echo "Results of Con: $LB_CONNECTED and Ref: $LB_REFUSED"
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
if [[ ! -r $HOME/keepalived.conf ]]
then
	echo "Downloading the template files from github."
	#Get the keepalived_template.conf and create a copy
	wget "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/keepalived_template.conf"
	cp keepalived_template.conf keepalived.conf
	rm keepalived_template.conf
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

if [[ ! -r $HOME/haproxy.cfg ]]
then
	echo "Downloading the template files from github."
	#Get the haproxy_template.cfg and create a copy
	wget "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/haproxy_template.cfg"
	cp haproxy_template.cfg haproxy.cfg
	rm haproxy_template.cfg
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
	mv $HOME/keepalived.conf /etc/keepalived/keepalived.conf
	#Start keepalived service
	systemctl enable keepalived.service && systemctl start keepalived.service
	#Update HAProxy config (haproxy.cfg)
	mv $HOME/haproxy.cfg /etc/haproxy/haproxy.cfg	
	#Start HAProxy service
	systemctl start haproxy.service  && systemctl enable haproxy.service

	echo "Both the services should be up. Let's check."

elif [[ $distro == "centos" ]]
then
	echo "Calling yum update."
	#Update packages.
	sudo yum update -y

	#Disable and Stop firewalld. firewalld blocks HAProxy and needs exception rules or be disabled.
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

	#Install haproxy keepalived; 
	echo "Installing haproxy and keepalived."
	dnf -y  install haproxy keepalived

	#Update keepalived.conf
	echo "Replacing the default keepalived.conf with our updated version."
	mv $HOME/keepalived.conf /etc/keepalived/keepalived.conf

	#Start keepalived service
	systemctl enable keepalived.service && systemctl start keepalived.service

	#Update HAProxy config (haproxy.cfg)
	echo "Replacing the default haproxy.cfg with our updated version."
	echo "Expected path: $(pwd)/haproxy.cfg"
	mv $HOME/haproxy.cfg /etc/haproxy/haproxy.cfg
	
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
sleep 20
nc -zv $KUBE_VIP $API_PORT
#Run Netcat and save the result in text file
#nc -vz "$KUBE_VIP $API_PORT" > file.txt 2>&1
#Check the 
LB_CONNECTED=$(nc -vz $KUBE_VIP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz $KUBE_VIP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)

if [[ ($LB_CONNECTED == 0 ) || ($LB_REFUSED == 0) ]]
then 
	echo "Route seems to be available."
	echo "----------- Load Balancing set up complete in $(hostname) ------------"
else
	echo "No route found. Please check firewall config."
	nc -vz $KUBE_VIP $API_PORT
	echo "----------- Load Balancing set up Failed in $(hostname) ------------"
fi

#echo "Script (setting_loadbalancer) completed."