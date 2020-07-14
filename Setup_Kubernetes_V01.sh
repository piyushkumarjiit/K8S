#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#./Setup_Kubernetes_V01.sh > setup.log 2>&1
#./Setup_Kubernetes_V01.sh | tee setup.log
#./Setup_Kubernetes_V01.sh > >(tee setup.log) 2> >(tee setup.log >&2)
#./Setup_Kubernetes_V01.sh |& tee -a setup.log

#LB Details
export KUBE_VIP_1_HOSTNAME="VIP"
export KUBE_VIP_1_IP="192.168.2.6"
#Port where Control Plane API server would bind on Load Balancer
export API_PORT="6443"
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
export ADMIN_USER="ichigo"
export USER_HOME="/home/$ADMIN_USER"

#Do we want to setup Load Balancer
export EXTERNAL_LB_ENABLED="true"
#K8S network driver
networking_type="calico"

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

#Check if we can ping other nodes in cluster. If not, add IP Addresses and Hostnames in hosts file
# if [[ $ALL_NODES_ACCESSIBLE == "false" ]]
# then
# 		echo "Ping failed. Updating hosts file."
# 		#Take backup of old hosts file. In case we need to restore/cleanup
# 		cat /etc/hosts > hosts.txt
# 		#Add Master IP Addresses and Hostnames in hosts file
# 		NODES_IN_CLUSTER=$(cat <<- SETVAR
# 		$KUBE_VIP_1_IP  $KUBE_VIP_1_HOSTNAME
# 		$KUBE_MASTER_1_IP  $KUBE_MASTER_1_HOSTNAME
# 		$KUBE_MASTER_2_IP  $KUBE_MASTER_2_HOSTNAME
# 		$KUBE_MASTER_3_IP  $KUBE_MASTER_3_HOSTNAME
# 		$KUBE_WORKER_1_IP  $KUBE_WORKER_1_HOSTNAME
# 		$KUBE_WORKER_2_IP  $KUBE_WORKER_2_HOSTNAME
# 		$KUBE_WORKER_3_IP  $KUBE_WORKER_3_HOSTNAME
# 		$KUBE_LBNODE_1_IP $KUBE_LBNODE_1_HOSTNAME
# 		$KUBE_LBNODE_2_IP $KUBE_LBNODE_2_HOSTNAME
# 		SETVAR
# 		)
# 		echo -n "$NODES_IN_CLUSTER" | tee -a /etc/hosts
# 		echo "Hosts file updated."
# else
# 	echo "All nodes accessible. No change needed."
# fi

echo -n "$NODES_IN_CLUSTER" | sudo tee -a /etc/hosts

ssh-keygen -t rsa

for node in ${ALL_NODE_IPS[*]}
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

		# Script=$( cat <<- HERE
		# echo "Connected to $host"
		# cd ~
		# export KUBE_VIP="$KUBE_VIP_1_IP"
		# export UNICAST_PEER_IP=$FINAL_UNICAST_PEER_IP
		# export MASTER_PEER_IP=$MASTER_PEER_IP
		# wget "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/setup_loadbalancer.sh"
		# chmod 755 setup_loadbalancer.sh
		# sudo ./setup_loadbalancer.sh $PRIORITY $INTERFACE $AUTH_PASS $KUBE_MASTER_API_PORT $host
		# # rm setup_loadbalancer.sh
		# echo "Exiting."
		# exit
		# HERE
		# )
#ssh -t user@host ${Script}

	    #scp ~/setup_loadbalancer.sh "${USER}"@$host:
	    echo "SSH to target LB Node."
	    ssh "${USERNAME}"@$node <<- EOF
	    echo "Connected to $node"
	    cd ~
	    export KUBE_VIP="$KUBE_VIP_1_IP"
	    export UNICAST_PEER_IP=$FINAL_UNICAST_PEER_IP
		export MASTER_PEER_IP=$MASTER_PEER_IP
		export CALLING_NODE=$CURRENT_NODE_IP
	    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/setup_loadbalancer.sh"
	    chmod 755 setup_loadbalancer.sh
	    ./setup_loadbalancer.sh
	    #./setup_loadbalancer.sh $PRIORITY $INTERFACE $AUTH_PASS $API_PORT $node
	    rm setup_loadbalancer.sh
	    echo "Script (setup_loadbalancer) execution complete. Ending SSH session."
	    exit
		EOF
		echo "LB Config executed on $node"
	done
	echo "Load balancer setup complete."
else
	echo "Skipping load balancer setup."
fi

#Call Helper script to setup common elements
for node in ${KUBE_CLUSTER_NODE_NAMES[*]}
do
	if [[ " ${MASTER_NODE_NAMES[*]} " == *" $node "* ]]
    then
    	export NODE_TYPE="Master"
    	echo "For Master node $node NODE_TYPE set as :  $NODE_TYPE "
    else
    	export NODE_TYPE="Worker"
    	echo "For Worker node $node NODE_TYPE set as :  $NODE_TYPE "
    fi
	ssh "${USERNAME}"@$node <<- EOF
    echo "Connected to Kube node: $node"
    cd ~
    export NODE_TYPE=$NODE_TYPE
    export USERNAME="$ADMIN_USER"
    export TEMP_NODE_NAMES="${KUBE_CLUSTER_NODE_NAMES[*]}"
    export TEMP_NODE_IPS="${KUBE_CLUSTER_NODE_IPS[*]}"
    export CALLING_NODE_NAME=$CURRENT_NODE_NAME
    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/prepare_node.sh"
    chmod 755 prepare_node.sh
	./prepare_node.sh
	rm ./prepare_node.sh
	echo "Script (prepare_node) execution complete. Ending SSH session."
	exit
	EOF
	echo "Prep script completed on $node"
done

echo "All nodes prepared."
LB_CONNECTED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)

#read -p "Should we proceed to set up Primary node? (Yes/No): " user_reply

#Run below as sudo on Primary Master node
echo "******* Setting up Primary master node ********"

#Reset the cluster
sudo kubeadm reset -f
sudo rm -Rf/etc/cni/net.d /root/.kube ~/.kube
sudo systemctl daemon-reload
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sleep 10
echo "Reset complete."
#Save the old config
kubeadm config print init-defaults --component-configs KubeletConfiguration > config.yaml
echo "LB Details: "$KUBE_VIP_1_IP $API_PORT
echo "Status of LB flags, Connected is $LB_CONNECTED and Refused is $LB_REFUSED "
#Call init with endpoint and certificate parameters needed for Load Balanced Config
echo "Initializing control plane with: kubeadm init --control-plane-endpoint $KUBE_VIP_1_IP:$API_PORT "
sudo kubeadm init --control-plane-endpoint $KUBE_VIP_1_IP:$API_PORT --upload-certs | tee kubeadm_init_output.txt
echo "Done initializing control plane."
#Save the output from the previous command as you need it to add other nodes to cluster
#Extract command used to initialize other Master nodes
MASTER_JOIN_COMMAND=$(tail -n12 kubeadm_init_output.txt | head -n3 )
echo $MASTER_JOIN_COMMAND > add_master.txt
#Extract command used to initialize Worker nodes
WORKER_JOIN_COMMAND=$(tail -n2 kubeadm_init_output.txt)
echo $WORKER_JOIN_COMMAND > add_worker.txt
#Set permissions for prying eyes.
chown $(id -u):$(id -g) kubeadm_init_output.txt
chown $(id -u):$(id -g) add_master.txt
chown $(id -u):$(id -g) add_worker.txt

#Alternate way
# MYVAR=$(cat kubeadm_init_output.txt)
# # retain the part before "Please note that the certificate-key gives access to cluster sensitive data"
# MASTER_JOIN_COMMAND=${MYVAR%Please note that the certificate-key gives access to cluster sensitive data*}
# # retain the part after "You can now join any number of the control-plane node running the following command on each as root:"
# MASTER_JOIN_COMMAND=${MASTER_JOIN_COMMAND##*You can now join any number of the control-plane node running the following command on each as root:}
# echo $MASTER_JOIN_COMMAND

#If needed, regenerate join command from master
#sudo kubeadm token create --print-join-command

#Create Kube config Folder.
mkdir -p $USER_HOME/.kube
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $USER_HOME/.kube/config
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
echo "ChCommand: chown $(id $ADMIN_USER -u):$(id $ADMIN_USER -g) $USER_HOME/.kube/config"
sudo chown $(id $ADMIN_USER -u):$(id $ADMIN_USER -g) $USER_HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
echo "Kube config copied to Home."

kubectl get nodes # should show master as Not Ready as networking is missing
#Set up networking for Masternode. Networking probably is not needed after the Primary node
echo "Setting up network."
if [[ $networking_type == "calico" ]]
then
	#New YAML from K8s.io docs
	kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml
	echo "Calico set up."
else
	export kubever=$(kubectl version | base64 | tr -d '\n')
	kubectl apply -f https://cloud.weave.works/k8s/net?k8s-version=$kubever
	echo "Weave set up."
fi

#Takes some time for nodes to be ready
CONTINUE_WAITING=$(kubectl get nodes | grep Ready > /dev/null 2>&1; echo $?)
echo -n "Primary master node not ready. Waiting ."
while [[ $CONTINUE_WAITING != 0 ]]
do
	sleep 20
	echo -n "."
 	CONTINUE_WAITING=$(kubectl get nodes | grep Ready > /dev/null 2>&1; echo $?)
done
echo ""
echo "Primary master node ready."
kubectl get nodes

#Certificate Distribution to other Master nodes
echo "Trying to copy certificates to other nodes."

#If certificates are deleted, regenerate them using below command
#kubeadm init phase upload-certs --upload-certs
LOOP_COUNT=0
for TARGET_NODE_NAME in ${MASTER_NODE_NAMES[*]}
do
	if [[ "$TARGET_NODE_NAME" != "$CURRENT_NODE_NAME" ]]
	then
		((LOOP_COUNT++))
		echo "Connected to $TARGET_NODE_NAME"
		#Once Primary Node is setup, run below command to copy certificates to other nodes
	    scp /etc/kubernetes/pki/ca.crt "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR
	    scp /etc/kubernetes/pki/ca.key "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR
	    scp /etc/kubernetes/pki/sa.key "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR
	    scp /etc/kubernetes/pki/sa.pub "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR
	    scp /etc/kubernetes/pki/front-proxy-ca.crt "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR
	    scp /etc/kubernetes/pki/front-proxy-ca.key "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR
	    scp /etc/kubernetes/pki/etcd/ca.crt "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR/etcd-ca.crt
	    # Quote below line if you are using external etcd
	    scp /etc/kubernetes/pki/etcd/ca.key "$USERNAME"@$TARGET_NODE_NAME:$TARGET_DIR/etcd-ca.key
	else
		echo "Certificate already present."
	fi
done
if [[ LOOP_COUNT -gt 0 ]]
then 
	echo "Certificates copy step complete."
else
	echo "Certificate copy step failed."
fi

echo "Adding other Master nodes."
for node in ${MASTER_NODE_NAMES[*]}
do
	if [[ "$node" == "$CURRENT_NODE_NAME" ]]
	then
		echo "Source node already processed and added to cluster."
	else
		#Add other Master nodes
		echo "Trying to add $node"
		#SSH into other Master nodes
		ssh "$USERNAME"@$node <<- EOF
		cd ~
		export USERNAME=$USERNAME
		echo "Username set as: "$USERNAME

		#Reset the cluster. Only way I could get this to work seemlessly
		kubeadm reset -f
		rm -Rf/etc/cni/net.d /root/.kube ~/.kube
		systemctl daemon-reload		
		iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
		sleep 10

		#Before running kubadm join on non primary nodes, move certificates in respective locations
		echo "Trying to move certificates to their respective locations on $node"
		#Fetch the certificate_mover.sh from github
		wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/certificate_mover.sh"
		chmod 755 certificate_mover.sh
		bash -c "./certificate_mover.sh"
		bash -c "rm -f certificate_mover.sh"
		echo "Trying to add Master node to cluster."
		bash -c "$MASTER_JOIN_COMMAND"
	
		echo "Trying to copy '$HOME/admin.conf' over"
		mkdir -p \$HOME/.kube
		mkdir -p $USER_HOME/.kube
		echo "Command: /etc/kubernetes/admin.conf \$HOME/.kube/config"
		cp /etc/kubernetes/admin.conf \$HOME/.kube/config
		cp /etc/kubernetes/admin.conf $USER_HOME/.kube/config
		echo " ChCommand \$(id -u):\$(id -g) \$HOME/.kube/config"
		chown \$(id -u):\$(id -g) \$HOME/.kube/config
		chown \$(id $ADMIN_USER -u):\$(id $ADMIN_USER -g) $USER_HOME/.kube/config
		echo "Exiting."
		exit
		EOF
		echo "Master node: $node added."
	fi
done
echo "All Masters added."

#For security reasons cluster does not run pods on control-plane node. To override this use below command
#kubectl taint nodes --all node-role.kubernetes.io/master-

#Add Worker nodes to cluster
echo "Setting up worker nodes"
for node in ${WORKER_NODE_NAMES[*]}
do
	echo "Trying to add $node"
	#Try to SSH into each node
	ssh "$USERNAME"@$node <<- EOF
	echo "Trying to add Worker node:$node to cluster."
	kubeadm reset -f
	rm -Rf/etc/cni/net.d /root/.kube ~/.kube
	systemctl daemon-reload
	iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
	sleep 10
	bash -c "$WORKER_JOIN_COMMAND"
	echo "Exiting."
	exit
	EOF
	echo "Back from Worker: "$node
done
echo "All workers added."

sleep 30
#Check all nodes have joined the cluster. Only needed for Master.
kubectl get nodes

#Check all nodes have joined the cluster. Only needed for Master.
kubectl get pods

#Check Cluster info
kubectl cluster-info

#Check health of cluster
kubectl get cs

#Run a pod to check if everything works as expected
kubectl run nginx --image=nginx
