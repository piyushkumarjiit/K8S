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
#Do we want to setup Load Balancer
export EXTERNAL_LB_ENABLED="true"
#All Nodes running Load Balancer
export LB_NODE_IPS=("192.168.2.205" "192.168.2.111")
export LB_NODE_NAMES=("KubeLBNode1.bifrost" "KubeLBNode2.bifrost")
#Do you want to set up new Primary Master nodes in this run. Allowed true/false
export SETUP_PRIMARY_MASTER="true"
#Do you want to add Master nodes in this run. Allowed true/false
export ADD_MASTER_NODES="true"
#All Master nodes
export MASTER_NODE_IPS=("192.168.2.220" "192.168.2.13" "192.168.2.186")
export MASTER_NODE_NAMES=("KubeMasterCentOS8.bifrost" "KubeMaster2CentOS8.bifrost" "KubeMaster3CentOS8.bifrost")
#Do you want to add Worker nodes in this install. Allowed true/false
export ADD_WORKER_NODES="true"
#All Worker Nodes
export WORKER_NODE_IPS=("192.168.2.251" "192.168.2.137" "192.168.2.227")
export WORKER_NODE_NAMES=("KubeNode1CentOS8.bifrost" "KubeNode2CentOS8.bifrost" "KubeNode3CentOS8.bifrost")
#All K8S nodes (Master + Worker)
export KUBE_CLUSTER_NODE_IPS=(${MASTER_NODE_IPS[*]} ${WORKER_NODE_IPS[*]})
export KUBE_CLUSTER_NODE_NAMES=(${MASTER_NODE_NAMES[*]} ${WORKER_NODE_NAMES[*]})
#All nodes we are trying to use
export ALL_NODE_IPS=($KUBE_VIP_1_IP ${KUBE_CLUSTER_NODE_IPS[*]} ${LB_NODE_IPS[*]})
export ALL_NODE_NAMES=($KUBE_VIP_1_HOSTNAME ${KUBE_CLUSTER_NODE_NAMES[*]} ${LB_NODE_NAMES[*]})
#Should we use ClusterConfiguration yaml to set up master node or us kubeadm reset to set up cluster. Allowed values "yaml"/"endpoint"
export SETUP_CLUSTER_VIA="endpoint"
#Do we want to manually copy the certificates
MANUALLY_COPY_CERTIFICATES="false"

#Username that we use to connect to remote machine via SSH
USERNAME="root"
#Username that we would use for normal kubectl/kubeadm commands post install
ADMIN_USER="ichigo"
USER_HOME="/home/$ADMIN_USER"

#Set below variables when running the script to add specific nodes to existing K8S cluster
MASTER_JOIN_COMMAND=""
WORKER_JOIN_COMMAND=""

echo "All Node_NAMES: " ${ALL_NODE_NAMES[*]}

#K8S network type. Allowed values calico/flannel
networking_type="calico"

if [[ $SETUP_PRIMARY_MASTER != "true" ]]
then
	if [[ ($ADD_MASTER_NODES == "true") ]]
	then
		if [[ (($MASTER_JOIN_COMMAND == "") || (${MASTER_NODE_IPS[*]} == "")) ]]
		then		
			echo "Unable to add new Master node to cluster without MASTER_JOIN_COMMAND. Exiting."
			sleep 2
			exit 1
		else
			echo "Proceeding to add new Master node(s)."
		fi
	fi

	if [[ $ADD_WORKER_NODES == "true" ]]
	then
		if [[ ${WORKER_NODE_NAMES[*]} == "" ]] 
		then
			echo "Unable to add new Worker node to cluster without WORKER_NODE_NAMES. Exiting."
			sleep 2
			exit 1
		elif [[ $WORKER_JOIN_COMMAND == "" ]]
		then
			echo "WORKER_JOIN_COMMAND is undefined. Trying to generate token."
			#Try to generate a new token
			#kubeadm token create --print-join-command
			WORKER_JOIN_COMMAND=$(kubeadm token create --print-join-command)
			if [[ $WORKER_JOIN_COMMAND == "" ]]
			then
				echo "Token generation failed. Unable to add new Worker node to cluster without WORKER_JOIN_COMMAND. Exiting."
				sleep 2
				exit 1
			fi
		else
			echo "Proceeding to add new Worker node(s)."
		fi
	fi
fi

#read -n 1 -p "Press any key to continue:"

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

#Setup key based SSH connection to all nodes
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

#Setup Load Balancer (Keepalived + HAProxy)
if [[ $EXTERNAL_LB_ENABLED == "true" ]]
then
	PRIORITY=200
	UNICAST_PEER_IP=""
	#Iterate over all Addresses mentioned in LB_NODE_IPS array
	for node in ${LB_NODE_IPS[*]}
	do
		#Priority passed to LB subscript in decreasing order. Could be overridden if needed.
		PRIORITY="$(($PRIORITY - 1))"
		#Iterate over all Addresses mentioned in LB_NODE_IPS array and set UNICAST_PEER_IP which is set in keepalived.conf
		for UNICAST_PEER_IP in ${LB_NODE_IPS[*]}
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
		#Create 1 string by concatenating all Master nodes. Use % as separator to make it easy in subscript to separate
		MASTER_PEER_IP=$(echo ${MASTER_NODE_IPS[*]} | sed 's# #%#g')

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

#Call Helper script to setup K8S common elements
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
    export TEMP_NODE_NAMES="${ALL_NODE_NAMES[*]}"
    export TEMP_NODE_IPS="${ALL_NODE_IPS[*]}"
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
echo "All K8S nodes prepared."

#ClusterConfig yaml Template
# cat > kubeadm-config.yaml <<-'EOF'
# apiVersion: kubeadm.k8s.io/v1beta2
# kind: ClusterConfiguration
# kubernetesVersion: v1.18.0
# controlPlaneEndpoint: 192.168.2.6:6443
# networking:
#     podSubnet: 10.244.0.0/16
# EOF

#To migrate old config file to new version
#kubeadm config migrate --old-config old.yaml --new-config new.yaml

#Set up the Primary Master node in the cluster.
if [[ $SETUP_PRIMARY_MASTER == "true" ]]
then
	echo "Setting up primary node in cluster."
	LB_CONNECTED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
	LB_REFUSED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)
	echo "LB Details: "$KUBE_VIP_1_IP $API_PORT
	echo "Status of LB flags, Connected is $LB_CONNECTED and Refused is $LB_REFUSED "

	#Run below as sudo on Primary Master node
	echo "******* Setting up Primary master node ********"
	if [[ $SETUP_CLUSTER_VIA == "yaml" ]]
	then
		echo "Setting up Via YAML."
		#Save the old config
		kubeadm config print init-defaults --component-configs KubeletConfiguration > config.yaml
		kubeadm config print join-defaults > join.yaml
		kubeadm config images pull --config kubeadm-config.yaml
		if [[ MANUALLY_COPY_CERTIFICATES == "true" ]]
		then
			#Call init with endpoint parameters needed for Load Balanced Config
			sudo kubeadm init --config kubeadm-config.yaml | tee kubeadm_init_output.txt
		else
			#Call init with endpoint and certificate parameters needed for Load Balanced Config
			sudo kubeadm init --config kubeadm-config.yaml --upload-certs | tee kubeadm_init_output.txt
		fi

	else
		echo "Setting up Via endpoint."
		#Save the old config
		kubeadm config print init-defaults --component-configs KubeletConfiguration > config.yaml
		#Call init with endpoint and certificate parameters needed for Load Balanced Config
		echo "Initializing control plane with: kubeadm init --control-plane-endpoint $KUBE_VIP_1_IP:$API_PORT "
		if [[ MANUALLY_COPY_CERTIFICATES == "true" ]]
		then
			#Call init with endpoint parameters needed for Load Balanced Config
			sudo kubeadm init --control-plane-endpoint "$KUBE_VIP_1_IP:$API_PORT" | tee kubeadm_init_output.txt
			#Save the output from the previous command as you need it to add other nodes to cluster
		else
			#Call init with endpoint and certificate parameters needed for Load Balanced Config
			sudo kubeadm init --control-plane-endpoint "$KUBE_VIP_1_IP:$API_PORT" --upload-certs | tee kubeadm_init_output.txt
			#Save the output from the previous command as you need it to add other nodes to cluster
		fi
	fi

	echo "Done initializing control plane."
	
	#Extract command used to initialize other Master nodes
	MASTER_JOIN_COMMAND=$(tail -n12 kubeadm_init_output.txt | head -n3 )
	echo $MASTER_JOIN_COMMAND > add_master.txt
	#Extract command used to initialize Worker nodes
	WORKER_JOIN_COMMAND=$(tail -n2 kubeadm_init_output.txt)
	echo $WORKER_JOIN_COMMAND > add_worker.txt
	#Set permissions to stop prying eyes.
	chown $(id -u):$(id -g) kubeadm_init_output.txt
	chown $(id -u):$(id -g) add_master.txt
	chown $(id -u):$(id -g) add_worker.txt

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
	kubectl get pods --all-namespaces -o wide
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
	CONTINUE_WAITING=$(kubectl get nodes | grep -w Ready > /dev/null 2>&1; echo $?)
	echo -n "Primary master node not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 20
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get nodes | grep -w Ready > /dev/null 2>&1; echo $?)
	done
	echo ""
	echo "Primary master node ready."
	kubectl get nodes

	#Certificate Distribution to other Master nodes
	echo "Trying to copy certificates to other nodes."

	if [[ MANUALLY_COPY_CERTIFICATES == "true" ]]
	then
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
				echo "Certificates already present in Primary node."
			fi
		done
		if [[ LOOP_COUNT -gt 0 ]]
		then 
			echo "Certificates copy step complete."
		else
			echo "Certificate copy step failed."
		fi
	else
		echo "Certificate copy not needed when using --upload-certs flag."
	fi
fi
	
if [[ $ADD_MASTER_NODES == "true" ]]
then
	echo "Adding other Master nodes."
	for node in ${MASTER_NODE_NAMES[*]}
	do
		if [[ "$node" == "$CURRENT_NODE_NAME" ]]
		then
			echo "Source node already processed and added to cluster."

		elif [[ -n "$MASTER_JOIN_COMMAND" ]]
		then
			#Add other Master nodes
			echo "Trying to add $node"
			#SSH into other Master nodes
			ssh "$USERNAME"@$node <<- EOF
			cd ~
			export USERNAME=$USERNAME
			echo "Username set as: "$USERNAME
			
			if [[ $MANUALLY_COPY_CERTIFICATES == "true" ]]
			then
				#Before running kubadm join on non primary nodes, move certificates in respective locations
				echo "Trying to move certificates to their respective locations on $node"
				#Fetch the certificate_mover.sh from github
				wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/certificate_mover.sh"
				chmod 755 certificate_mover.sh
				bash -c "./certificate_mover.sh"
				bash -c "rm -f certificate_mover.sh"
			fi
			
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
		else
			echo "MASTER_JOIN_COMMAND is undefined. Exiting."
			sleep 2
			exit 1
		fi
	done
	echo "All Masters added."
else
	echo "Not adding Master node."
fi

#For security reasons cluster does not run pods on control-plane node. To override this use below command
#kubectl taint nodes --all node-role.kubernetes.io/master-

if [[ $ADD_WORKER_NODES == "true" ]]
then
	if [[ -n "$WORKER_JOIN_COMMAND" ]]
	then		
		#Add Worker nodes to cluster
		echo "Setting up worker nodes"
		for node in ${WORKER_NODE_NAMES[*]}
		do
			echo "Trying to add $node"
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
		sleep 10
	else
		echo "WORKER_JOIN_COMMAND is undefined. Exiting."
		sleep 2
		exit 1
	fi
else
	echo "Skipping adding workers."
fi

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
