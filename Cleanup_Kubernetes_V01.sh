#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#./Setup_Kubernetes_V01.sh > setup.log 2>&1
#./Setup_Kubernetes_V01.sh | tee setup.log

export KUBE_VIP_1_HOSTNAME="VIP"
export KUBE_VIP_1_IP="192.168.2.6"
export KUBE_LBNODE_1_HOSTNAME="KubeLBNode1"
export KUBE_LBNODE_1_IP="192.168.2.205"
export KUBE_LBNODE_2_HOSTNAME="KubeLBNode2"
export KUBE_LBNODE_2_IP="192.168.2.111"
export KUBE_MASTER_1_HOSTNAME="KubeMasterCentOS8"
export KUBE_MASTER_1_IP="192.168.2.220"
export KUBE_MASTER_2_HOSTNAME="KubeMaster2CentOS8"
export KUBE_MASTER_2_IP="192.168.2.13"
export KUBE_MASTER_3_HOSTNAME="KubeMaster3CentOS8"
export KUBE_MASTER_3_IP="192.168.2.186"
export KUBE_WORKER_1_HOSTNAME="KubeNode1CentOS8"
export KUBE_WORKER_1_IP="192.168.2.251"
export KUBE_WORKER_2_HOSTNAME="KubeNode2CentOS8"
export KUBE_WORKER_2_IP="192.168.2.137"
export KUBE_WORKER_3_HOSTNAME="KubeNode3CentOS8"
export KUBE_WORKER_3_IP="192.168.2.227"
#Port where Control Plane API server would bind on Load Balancer
export KUBE_MASTER_API_PORT="6443"

export CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"


export MASTER_NODE_IPS=($KUBE_MASTER_1_IP $KUBE_MASTER_2_IP $KUBE_MASTER_3_IP)
export WORKER_NODE_IPS=($KUBE_WORKER_1_IP $KUBE_WORKER_2_IP $KUBE_WORKER_3_IP)
export KUBE_CLUSTER_NODES=(${MASTER_NODE_IPS[*]} ${WORKER_NODE_IPS[*]})
export LB_NODES_IP=($KUBE_LBNODE_1_IP $KUBE_LBNODE_2_IP)
export ALL_NODES=(${KUBE_CLUSTER_NODES[*]} ${LB_NODES_IP[*]})

export USERNAME="root"
export EXTERNAL_LB_ENABLED="false"

#USER_PASSWORD=$(cat passwd.txt)

networking_type="calico"

ALL_NODES_ACCESSIBLE="true"
for node in ${ALL_NODES[*]}
do
	if [[ $NODES_ACCESSIBLE != 0  &&  $NODES_IN_CLUSTER != "" ]]
	then
		echo "Node: $node inaccessible. Need to update hosts file."
		ALL_NODES_ACCESSIBLE="false"
	fi
done

#Check if we can ping other nodes in cluster. If not, add IP Addresses and Hostnames in hosts file
if [[ $ALL_NODES_ACCESSIBLE == "false" ]]
then
		echo "Ping failed. Updating hosts file."
		#Take backup of old hosts file. In case we need to restore/cleanup
		cat /etc/hosts > hosts.txt
		#Add Master IP Addresses and Hostnames in hosts file
		NODES_IN_CLUSTER=$(cat <<- SETVAR
		$KUBE_VIP_1_IP  $KUBE_VIP_1_HOSTNAME
		$KUBE_MASTER_1_IP  $KUBE_MASTER_1_HOSTNAME
		$KUBE_MASTER_2_IP  $KUBE_MASTER_2_HOSTNAME
		$KUBE_MASTER_3_IP  $KUBE_MASTER_3_HOSTNAME
		$KUBE_WORKER_1_IP  $KUBE_WORKER_1_HOSTNAME
		$KUBE_WORKER_2_IP  $KUBE_WORKER_2_HOSTNAME
		$KUBE_WORKER_3_IP  $KUBE_WORKER_3_HOSTNAME
		$KUBE_LBNODE_1_IP $KUBE_LBNODE_1_HOSTNAME
		$KUBE_LBNODE_2_IP $KUBE_LBNODE_2_HOSTNAME
		SETVAR
		)
		echo -n "$NODES_IN_CLUSTER" | tee -a /etc/hosts
		echo "Hosts file updated."
else
	echo "All nodes accessible. No change needed."
fi

echo -n "$NODES_IN_CLUSTER" | sudo tee -a /etc/hosts

ssh-keygen -t rsa

for node in ${ALL_NODES[*]}
do
	echo "Adding keys for $node"
	ssh-copy-id -i ~/.ssh/id_rsa.pub "$USERNAME"@$node
done
echo "Added keys for all nodes."

#From K8s Docs
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa #Assuming id_rsa is the name of the private key file

#Call helper script to setup LB (Keepalived + HAProxy)
if [[ $EXTERNAL_LB_ENABLED == "true" ]]
then
	PRIORITY=200
	UNICAST_PEER_IP=""
	#Iterate over all Addresses mentioned in LB_NODES_IP array
	for node in ${LB_NODES_IP[*]}
	do
		#Priority passed to LB subscript in decreasing order. Could be overridden if needed.
		PRIORITY="$(($PRIORITY - 1))"
		#Iterate over all Addresses mentioned in LB_NODES_IP array and set UNICAST_PEER_IP which is set in keepalived.conf
		for UNICAST_PEER_IP in ${LB_NODES_IP[*]}
		do
			if [[ "$UNICAST_PEER_IP" == "$node" ]]
			then
				echo "Ignoring node as it would be UNICAST_SRC_IP"
			else
				FINAL_UNICAST_PEER_IP="$UNICAST_PEER_IP%$FINAL_UNICAST_PEER_IP"
				#echo "Value added to UNICAST_SRC_IP"
			fi
		done
		#echo "FINAL_UNICAST_PEER_IP: $FINAL_UNICAST_PEER_IP"
		#Create 1 string by concatenating all Master nodes. Use % as separator to make it easy in util to separate
		MASTER_PEER_IP=$(echo ${MASTER_NODE_IPS[*]} | sed 's# #%#g')
	    echo "SSH to target LB Node."
	    ssh "${USERNAME}"@$node <<- EOF
	    echo "Connected to $node"
	    cd ~
	    export KUBE_VIP="$KUBE_VIP_1_IP"
	    export UNICAST_PEER_IP=$FINAL_UNICAST_PEER_IP
		export MASTER_PEER_IP=$MASTER_PEER_IP
		export CALLING_NODE=$CURRENT_NODE_IP
	    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/cleanup_loadbalancer.sh"
	    chmod 755 cleanup_loadbalancer.sh
	    ./cleanup_loadbalancer.sh
	    #./cleanup_loadbalancer.sh $PRIORITY $INTERFACE $AUTH_PASS $KUBE_MASTER_API_PORT $node
	    rm cleanup_loadbalancer.sh
	    echo "Exiting."
	    exit
		EOF
		echo "LB cleanup executed on $node"
	done
	echo "Load balancer cleanup complete."
else
	echo "Skipping load balancer cleanup."
fi

#Call Helper script to cleanup nodes
for node in ${KUBE_CLUSTER_NODES[*]}
do
	ssh -tt "${USERNAME}"@$node <<- EOF
    echo "Connected to $node"
    cd ~
    export NODES_IN_CLUSTER="$NODES_IN_CLUSTER"
    export CALLING_NODE=$CURRENT_NODE_IP
    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/cleanup_node.sh"
    chmod 755 cleanup_node.sh
	./cleanup_node.sh
	rm ./cleanup_node.sh
	echo "Exiting."
	exit
	EOF
echo "Cleanup script completed on $node"
done

echo "Nodes cleaned."
