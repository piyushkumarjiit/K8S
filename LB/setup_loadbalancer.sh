#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#YAML/GIt variables
KEEP_ALIVED_CONF_TEMPLATE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/LB/keepalived_template.conf
HA_PROXY_CONF_TEMPLATE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/LB/haproxy_template.cfg

#LB config related default values for variables
PRIORITY=200
API_PORT=6443
INTERFACE=ens192
AUTH_PASS=K33p@Gu3ss1ng
ROUTER_ID="RouterID1"
STATE=MASTER
BALANCER="roundrobin"
#INSTANCE_COUNT=$((2 + RANDOM % 20))
INSTANCE_COUNT=$(($(cat /etc/haproxy/haproxy.cfg | grep KubeAPIServerName | sed 's/[^0-9]*//g' ) + 1))
KubeAPIServerName="KubeAPIServerName$INSTANCE_COUNT"
KubeClusterName="KubeClusterName$INSTANCE_COUNT"
VIRTUAL_ROUTER_ID=$(($(cat /etc/keepalived/keepalived.conf | grep virtual_router_id | awk -F " " '{print $2}') + 1))
VRRP_INSTANCE=$(($(cat /etc/keepalived/keepalived.conf | grep vrrp_instance | awk -F " " '{print $2}') + 1))
echo "----------- Setting up Load Balancing in $(hostname) ------------"

if [[ "$KUBE_VIP" == "" ]]
then
	echo "Virtual Address (KUBE_VIP) not set. Unable to proceed."
	exit 1
fi

if [[ "$UNICAST_PEER_IP" == "" ]]
then
	echo "List of keepalived peers (UNICAST_PEER_IP) not passed. Unable to proceed."
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

KEEPALIVED_AVAILABLE=$(systemctl status keepalived.service > /dev/null 2>&1; echo $?)
HAPROXY_AVAILABLE=$(systemctl status haproxy.service > /dev/null 2>&1; echo $?)
if [[ ($KEEPALIVED_AVAILABLE == 0) && ($HAPROXY_AVAILABLE == 0) ]]
then
	#Check the current status of Load balance config
	echo "Try: nc -vz $KUBE_VIP $API_PORT"
	LB_CONNECTED=$(nc -vz $KUBE_VIP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
	LB_REFUSED=$(nc -vz $KUBE_VIP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)
	echo "Results of Con: $LB_CONNECTED and Ref: $LB_REFUSED"
	if [[ $LB_CONNECTED == 0 || $LB_REFUSED == 0 ]]
	then
		echo "Load balancer seems to be running on the specified VIP. Unable to proceed. Exiting."
		exit 1
	fi
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
if [[ ! -r $HOME/keepalived.conf && $KEEPALIVED_AVAILABLE != 0 ]]
then
	echo "Downloading the template files from github."
	#Get the keepalived_template.conf and create a copy
	#wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/keepalived_template.conf"
	wget -q $KEEP_ALIVED_CONF_TEMPLATE
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
elif [[ -r /etc/keepalived/keepalived.conf  ]]
then
	echo "Found keepalived.conf in /etc/keepalived/ direcotry. Updating it with new VIP config."

	echo "Creating the section to be added to existing keepalived.conf"
	#Get the keepalived_template.conf and create a copy
	echo "Updating the keepalived.conf."

	VRRP_VARIABLE=$(echo "vrrp_instance $VRRP_INSTANCE")
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "{" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "state $STATE" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "interface $INTERFACE" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "virtual_router_id $VIRTUAL_ROUTER_ID" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "priority $PRIORITY" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "advert_int 1" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "unicast_src_ip $UNICAST_SRC_IP" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "unicast_peer" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "{" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "$TEMP_PEER_IPS" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "}" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "authentication" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "{" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "auth_type PASS" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "auth_pass $AUTH_PASS" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "}" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "virtual_ipaddress" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "{" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "$KUBE_VIP" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "}" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "}" )"
	VRRP_VARIABLE+=$'\n'

	echo "keepalived.conf updated."
	#Create a backup copy of keepalived
	cp /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.bak
	echo "Created a backup of exisitng keepalived conf. Appending the new VRRP section"
	echo -e "$VRRP_VARIABLE" >> /etc/keepalived/keepalived.conf
	echo "keepalived.conf updated. Restart of service is required."

else
	echo "Found keepalived.conf in current direcotry. Going to use it 'as is'."
fi

if [[ ! -r $HOME/haproxy.cfg && $HAPROXY_AVAILABLE != 0 ]]
then
	echo "Downloading the template files from github."
	#Get the haproxy_template.cfg and create a copy
	#wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/haproxy_template.cfg"
	wget -q $HA_PROXY_CONF_TEMPLATE
	cp haproxy_template.cfg haproxy.cfg
	rm haproxy_template.cfg
	echo "Updating the haproxy.cfg."
	#Update the placeholders with value for primary
	sed -i "s*###vip_@ddr3ss###*$KUBE_VIP*g" haproxy.cfg
	# sed -i "s*###n0d31_1p_@ddr###*$KUBE_MASTER_1_IP*g" haproxy.cfg
	sed -i "s*###AP1_P0RT###*$API_PORT*g" haproxy.cfg
	#Multiple nodes with newline thus had to use awk. Sed does not handle newline properly
	awk -i inplace -v srch="###S3rv3r###" -v repl="$FINAL_SERVER_STRING" '{ sub(srch,repl,$0); print $0 }' haproxy.cfg
	echo "haproxy.cfg updated."
elif [[ -r /etc/haproxy/haproxy.cfg ]]
then
	echo "Found haproxy.cfg in /etc/haproxy direcotry."

	echo "Creating the section to be added to existing haproxy.cfg"
	VRRP_VARIABLE=""
	VRRP_VARIABLE=$(echo "frontend $KubeAPIServerName")
	VRRP_VARIABLE+=$'\n\t'
	VRRP_VARIABLE+="$(echo -e "bind $KUBE_VIP:$API_PORT" )"
	VRRP_VARIABLE+=$'\n\t'
	VRRP_VARIABLE+="$(echo -e "mode tcp" )"
	VRRP_VARIABLE+=$'\n\t'
	VRRP_VARIABLE+="$(echo -e "default_backend $KubeClusterName" )"
	VRRP_VARIABLE+=$'\n'
	VRRP_VARIABLE+="$(echo -e "backend $KubeClusterName" )"
	VRRP_VARIABLE+=$'\n\t'
	VRRP_VARIABLE+="$(echo -e "mode tcp" )"
	VRRP_VARIABLE+=$'\n\t'
	VRRP_VARIABLE+="$(echo -e "balance $BALANCER" )"
	VRRP_VARIABLE+=$'\n\t'
	VRRP_VARIABLE+="$(echo -e "$FINAL_SERVER_STRING" )"
	VRRP_VARIABLE+=$'\n'

	echo "haproxy.cfg updated."
	#Create a backup copy of keepalived
	cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.bak
	echo "Created a backup of exisitng haproxy.cfg. Appending the new section"
	echo -e "$VRRP_VARIABLE" >> /etc/haproxy/haproxy.cfg

else
	echo "Found haproxy.cfg in current direcotry. Going to use it 'as is'."
fi

IP4_FORWARDING_STATUS=$(cat /etc/sysctl.conf | grep -w 'net.ipv4.ip_forward=1' > /dev/null 2>&1; echo $?)
if [[ $IP4_FORWARDING_STATUS != 0 ]]
then
	# Set SELinux in permissive mode (effectively disabling it). Needed for K8s as well as HAProxy
	echo "Adding IPv4 forwarding rule."
	bash -c 'cat <<-EOF >>  /etc/sysctl.conf
	net.ipv4.ip_forward=1
	net.bridge.bridge-nf-call-iptables=1
	EOF'
	sysctl -p -q
	echo "IPV4 forwarding set."
else
	echo "IPV4 FORWARDING flag already set. No change needed."
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

	if [[ ($KEEPALIVED_AVAILABLE != 0) && ($HAPROXY_AVAILABLE != 0) ]]
	then
		echo "Calling yum update."
		#Update packages.
		sudo yum update -y -q
		#Install haproxy keepalived; 
		echo "Installing haproxy and keepalived."
		dnf -y -q  install haproxy keepalived
		#Update keepalived.conf
		echo "Replacing the default keepalived.conf with our updated version."
		mv $HOME/keepalived.conf /etc/keepalived/keepalived.conf
		#Start keepalived service
		systemctl enable keepalived.service
		systemctl start keepalived.service
		#Update HAProxy config (haproxy.cfg)
		echo "Replacing the default haproxy.cfg with our updated version."
		echo "Expected path: $(pwd)/haproxy.cfg"
		mv $HOME/haproxy.cfg /etc/haproxy/haproxy.cfg
		#Only for Non Primary node when remote binding is not enabled/available
		#Run below command on Primary keepalived node to switch VIP to Secondary node. 
		#This ensures that VIP is available for HAProxy to bind to.
		#sudo systemctl stop keepalived
		#Start HAProxy service
		systemctl enable haproxy.service
		systemctl start haproxy.service
		#Run below command on Primary keepalived node to switch VIP back to Primary node.
		#sudo systemctl start keepalived
	else
		echo "keepalived and HAProxy already installed. Restarting to reflect lastest config."
		systemctl restart keepalived.service
		systemctl restart haproxy.service
		echo "Done."
	fi

	echo "Both the services should be up. Lets check."
fi
sleep 20
#nc -zv $KUBE_VIP $API_PORT

#Check LB status
LB_CONNECTED=$(nc -vz $KUBE_VIP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz $KUBE_VIP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)

if [[ ($LB_CONNECTED == 0 ) || ($LB_REFUSED == 0) ]]
then 
	echo "Route seems to be available."
	echo "----------- Load Balancing set up complete in $(hostname) ------------"
	sleep 2
else
	echo "No route found. Please check firewall config."
	nc -vz $KUBE_VIP $API_PORT
	echo "----------- Load Balancing set up Failed in $(hostname) ------------"
	sleep 2
fi
