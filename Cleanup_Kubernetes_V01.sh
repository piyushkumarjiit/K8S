#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#./Setup_Kubernetes_V01.sh |& tee -a cleanup.log
#./Cleanup_Kubernetes_V01.sh | tee cleanup.log

echo "------------ Cleanup script started --------------"

#LB Details
export KUBE_VIP_1_HOSTNAME="VIP"
export KUBE_VIP_1_IP="192.168.2.6"
#Port where Control Plane API server would bind on Load Balancer
export KUBE_MASTER_API_PORT="6443"
#Hostname of the node from where we run the script
export CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
export CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"

#All Nodes running Load Balancer
export LB_NODES_IP=("192.168.2.205" "192.168.2.111")
export LB_NODES_NAMES=("KubeLBNode1.bifrost" "KubeLBNode2.bifrost")
#All Master nodes
export MASTER_NODE_IPS=("192.168.2.220" "192.168.2.13" "192.168.2.186")
export MASTER_NODE_NAMES=("KubeMasterCentOS8.bifrost" "KubeMaster2CentOS8.bifrost" "KubeMaster3CentOS8.bifrost")
#All Worker Nodes
export WORKER_NODE_IPS=("192.168.2.251" "192.168.2.137" "192.168.2.227")
export WORKER_NODE_NAMES=("KubeNode1CentOS8.bifrost" "KubeNode2CentOS8.bifrost" "KubeNode3CentOS8.bifrost")
#All K8S nodes (Master + Worker)
export KUBE_CLUSTER_NODE_IPS=(${MASTER_NODE_IPS[*]} ${WORKER_NODE_IPS[*]})
export KUBE_CLUSTER_NODE_NAMES=(${MASTER_NODE_NAMES[*]} ${WORKER_NODE_NAMES[*]})
#All nodes we are trying to use
export ALL_NODE_IPS=($KUBE_VIP_1_IP ${KUBE_CLUSTER_NODE_IPS[*]} ${LB_NODES_IP[*]})
export ALL_NODE_NAMES=($KUBE_VIP_1_HOSTNAME ${KUBE_CLUSTER_NODE_NAMES[*]} ${LB_NODES_NAMES[*]})
#Username that we use to connect to remote machine via SSH
export USERNAME="root"
#Flag to identify if LB nodes also should be cleaned
export EXTERNAL_LB_ENABLED="true"
#Workaround for lack of DNS. Local node can ping itself but unable to SSH
echo "$CURRENT_NODE_IP"	"$CURRENT_NODE_NAME" | tee -a /etc/hosts


echo "Deleting all pods."
kubectl delete --all pods

#Check connectivity to all nodes
index=0
for node in ${ALL_NODE_NAMES[*]}
do
	NODE_ACCESSIBLE=$(ping -q -c 1 -W 1 $node > /dev/null 2>&1; echo $?)
	NODE_ALREADY_PRESENT=$(cat /etc/hosts | grep -w $node > /dev/null 2>&1; echo $?)
	if [[ $NODE_ACCESSIBLE != 0 ]]
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

#Call Helper script to cleanup K8S nodes
for node in ${KUBE_CLUSTER_NODE_NAMES[*]}
do
	ssh "${USERNAME}"@$node <<- EOF
    export CALLING_NODE_NAME=$CURRENT_NODE_NAME
    cd ~
    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/cleanup_node.sh"
    chmod 755 cleanup_node.sh
	./cleanup_node.sh
	sleep 1
	rm -f ./cleanup_node.sh
	echo "Exiting."
	exit
	EOF
	echo "K8S cleanup script completed on $node"
done
echo "K8S cleanup script completed."

#Call helper script to cleanup Load Balancer (Keepalived + HAProxy)
if [[ $EXTERNAL_LB_ENABLED == "true" ]]
then
	#Iterate over all Addresses mentioned in LB_NODES_IP array
	for node in ${LB_NODES_IP[*]}
	do
	    echo "SSH to target LB Node."
	    ssh "${USERNAME}"@$node <<- EOF
	    export CALLING_NODE_NAME=$CURRENT_NODE_NAME
	    cd ~
	    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/cleanup_node.sh"
	    chmod 755 cleanup_node.sh
		./cleanup_node.sh
		sleep 1
		rm -f ./cleanup_node.sh
		echo "Exiting."
		exit
		EOF
		echo "LB cleanup executed on $node"
	done
	echo "Load balancer cleanup complete."
else
	echo "Skipping load balancer cleanup."
fi

#Restore the /etc/hosts file
if [[ -r hosts.txt ]]
then
	cat hosts.txt > /etc/hosts
	echo "Hosts file overwritten."
	rm -f hosts.txt
else
	echo "Backup file does not exists."
fi

echo "------------ All Nodes cleaned --------------"

echo "Restarting the node. Connect again."
#shutdown -r
