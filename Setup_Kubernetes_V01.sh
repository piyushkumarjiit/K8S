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
export EXTERNAL_LB_ENABLED="true"

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
	    #./setup_loadbalancer.sh $PRIORITY $INTERFACE $AUTH_PASS $KUBE_MASTER_API_PORT $node
	    rm setup_loadbalancer.sh
	    echo "Exiting."
	    exit
		EOF
		echo "LB Config executed on $node"
	done
	echo "Load balancer setup complete."
else
	echo "Skipping load balancer setup."
fi

#Call Helper script to setup common elements
for node in ${KUBE_CLUSTER_NODES[*]}
do
	ssh -tt "${USERNAME}"@$node <<- EOF
    echo "Connected to $node"
    cd ~
    export NODES_IN_CLUSTER="$NODES_IN_CLUSTER"
    export CALLING_NODE=$CURRENT_NODE_IP
    wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/prepare_node.sh"
    chmod 755 prepare_node.sh
	./prepare_node.sh
	rm ./prepare_node.sh
	echo "Exiting."
	exit
	EOF
echo "Prep script completed on $node"
done

echo "Nodes prepared."
LB_CONNECTED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
LB_REFUSED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)
PROCESSING_NODE=0
for node in ${MASTER_NODE_IPS[*]}
do
	if [[ $PROCESSING_NODE == 0 ]] #Until first Master node is ready, we get refused from nc
	then
		PROCESSING_NODE+=1
		#Run below as sudo on Primary Master node
		echo "Setting up Primary master node."
		#Save the old config
		kubeadm config print init-defaults --component-configs KubeletConfiguration > config.yaml
		#Call init with endpoint and certificate parameters needed for Load Balanced Config
		sudo kubeadm init --control-plane-endpoint "$KUBE_VIP_1_IP:$API_PORT" --upload-certs | tee kubeadm_init_output.txt
		#Save the last line from the previous output as you need it to add other nodes to cluster
		#Extract command used to initialize other Master nodes
		MASTER_JOIN_COMMAND=$(tail -n12 kubeadm_init_output.txt | head -n3 )
		#Extract command used to initialize Worker nodes
		WORKER_JOIN_COMMAND=$(tail -n2 kubeadm_init_output.txt)
		#Set permissions for prying eyes.
		chown $(id -u):$(id -g) $HOME/kubeadm_init_output.txt

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
		mkdir -p $HOME/.kube
		sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
		sudo chown $(id -u):$(id -g) $HOME/.kube/config
		kubectl get nodes # should show master as Not Ready as networking is missing
		#Set up networking for Masternode. Networking probably is not needed after the Primary node
		if [[ $networking_type == "calico" ]]
		then
			#New YAML from K8s.io docs
			kubectl apply -f https://docs.projectcalico.org/v3.14/manifests/calico.yaml
			sleep 60

			#There is processing involved for Calico. Update these YAMLs for local use before proceeding
			#wget "https://docs.projectcalico.org/v3.5/getting-started/kubernetes/installation/hosted/etcd.yaml"
			#wget "https://docs.projectcalico.org/v3.5/getting-started/kubernetes/installation/hosted/calico.yaml"
			#Update params in the YAMLs
			#kubectl apply -f etcd.yaml
			#kubectl apply -f calico.yaml
			#Install the Tigera Calico operator. To be tested
			##kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
			#Install Calico. To be tested.
			###kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml

			echo "Calico set up."
		else
			export kubever=$(kubectl version | base64 | tr -d '\n')
			kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$kubever"
			echo "Weave set up."
		fi
		#Takes some time for nodes to be ready
		sleep 60

		kubectl get nodes | grep Ready # should show master as Ready
		if [[ $? == 0 ]]
		then
			echo "Primary master node ready."
		else
			echo "Primary master node not ready. Please check."
			exit 1
		fi

		#Set the home directory in target server for scp. $HOME does not work due to difference in users on src and tgt
		if [[ "$USERNAME" == "root" ]]
		then
			TARGET_DIR="/root"
		else
			TARGET_DIR="/home/$USERNAME"
		fi
		
		#Certificate Distribution to other Master nodes
		echo "Trying to copy certificates to other nodes."
		USER=$USERNAME # User we have setup ssh for

		#If certificates are deleted, regenerate them using below command
		#kubeadm init phase upload-certs --upload-certs

		for host in ${MASTER_NODE_IPS[*]}
		do
			if [[ "$host" != "$node" ]]
			then
				echo "Connected to $host"
				#Once Primary Node is setup, run below command to copy certificates to other nodes
			    scp /etc/kubernetes/pki/ca.crt "$USERNAME"@$host:$TARGET_DIR
			    scp /etc/kubernetes/pki/ca.key "$USERNAME"@$host:$TARGET_DIR
			    scp /etc/kubernetes/pki/sa.key "$USERNAME"@$host:$TARGET_DIR
			    scp /etc/kubernetes/pki/sa.pub "$USERNAME"@$host:$TARGET_DIR
			    scp /etc/kubernetes/pki/front-proxy-ca.crt "$USERNAME"@$host:$TARGET_DIR
			    scp /etc/kubernetes/pki/front-proxy-ca.key "$USERNAME"@$host:$TARGET_DIR
			    scp /etc/kubernetes/pki/etcd/ca.crt "$USERNAME"@$host:$TARGET_DIR/etcd-ca.crt
			    # Quote this line if you are using external etcd
			    scp /etc/kubernetes/pki/etcd/ca.key "$USERNAME"@$host:$TARGET_DIR/etcd-ca.key
			else
				echo "Certificate already present."
			fi
		done
		echo "Certificates copy step complete."
	else
		#Add other Master nodes
		echo "Adding other Master nodes. Trying to add $node"

		ssh "$USERNAME"@$node <<- EOF
		cd ~
		export USERNAME=$USERNAME
		#Before running kubadm join on non primary nodes, move certificates in respective locations
		echo "Trying to move certificates to their respective locations on $node"
		#Fetch the certificate_mover.sh from github
		wget "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/certificate_mover.sh"
		chmod 755 certificate_mover.sh
		bash -c "./certificate_mover.sh"
		echo "Trying to add Master node to cluster."
		bash -c "$MASTER_JOIN_COMMAND"
		echo "Trying to copy '$HOME/admin.conf' over"
		bash -c 'cp /etc/kubernetes/admin.conf $HOME/; chown $(id -u):$(id -g) $HOME/admin.conf ; export KUBECONFIG=$HOME/admin.conf'
		echo "Exiting."
		exit
		EOF
		echo "Master node: $node added."
	fi
done
echo "All Masters added."

#For security reasons cluster does not run pods on control-plane node. To override this use below command
#kubectl taint nodes --all node-role.kubernetes.io/master-

for node in ${WORKER_NODE_IPS[*]}
do
	#Add Pods to cluster
	echo "Setting up worker nodes"

	#Try to SSH into each node
	ssh "$USERNAME"@$node <<- EOF
	echo "Trying to add Worker node:$node to cluster."
	bash -c "$WORKER_JOIN_COMMAND"
	echo "Exiting."
	exit
	EOF
	echo "Back from Worker: "$node
done
echo "All workers added."

sleep 180
#Check all nodes have joined the cluster. Only needed for Master.
sudo kubectl get nodes

#Check all nodes have joined the cluster. Only needed for Master.
sudo kubectl get pods

#Check Cluster info
sudo kubectl cluster-info

#Check health of cluster
sudo kubectl get cs


