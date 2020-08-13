#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#sudo ./Setup_Kubernetes_V01.sh | tee setup.log
#sudo ./Setup_Kubernetes_V01.sh |& tee -a setup.log

# K8S Component related variables/Flags
# Do we want to setup Rook + Ceph. Allowed values true/false
SETUP_ROOK_INSTALLED="true"
# Do we want to setup Monitoring for Cluster (Prometheus + AlertManager+Grafana). Allowed values true/false
SETUP_CLUSTER_MONITORING="true"
# Flag to setup Metal LB. Allowed values true/false
SETUP_METAL_LB="true"
# Flag to indicate if there is a cloud provided LB available. Allowed values true/false
CLOUD_PROVIDED_LB="false"
# IP Address Pool for Metal LB
START_IP_ADDRESS_RANGE=192.168.2.190
END_IP_ADDRESS_RANGE=192.168.2.195
#Nginx Ingress setup flag. Allowed values true/false
SETUP_NGINX_INGRESS="true"
# Domain name to be used by Ingress. Using this grafana URL would become: grafana.<domain.com>
INGRESS_DOMAIN_NAME=bifrost.com
# Flag to setup Helm. Allowed values true/false
SETUP_HELM="true" 
# Flag to setup CERT_MANAGER. Allowed values true/false
SETUP_CERT_MANAGER="true"
#Do we want to setup HAPRoxy+KeepAlived Load Balancer. Allowed values true/false
EXTERNAL_LB_ENABLED="true"
# Disable firewall on each Kubernetes node or add rules. Allowed values true/false
KEEP_FIREWALL_ENABLED="false"
#All Nodes part of HAPRoxy+KeepAlived Load Balancer 
LB_NODE_IPS=("192.168.2.205" "192.168.2.111")
LB_NODE_NAMES=("KubeLBNode1.bifrost" "KubeLBNode2.bifrost")
# HAPRoxy+KeepAlived Load Balancer Details
KUBE_VIP_1_HOSTNAME="VIP"
KUBE_VIP_1_IP="192.168.2.6"
#Port where Control Plane API server would bind on Load Balancer
API_PORT="6443"
#Hostname of the node from where we run the script
CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"
#Do you want to set up new Primary Master nodes in this run. Allowed values true/false
SETUP_PRIMARY_MASTER="true"
#Do you want to add Master nodes in this run. Allowed values true/false
ADD_MASTER_NODES="true"
#All Master nodes
MASTER_NODE_IPS=("192.168.2.220" "192.168.2.13" "192.168.2.186" "192.168.2.175" "192.168.2.198" "192.168.2.140")
MASTER_NODE_NAMES=("KubeMasterCentOS8.bifrost" "KubeMaster2CentOS8.bifrost" "KubeMaster3CentOS8.bifrost" "K8SCentOS8Master1.bifrost" "K8SCentOS8Master2.bifrost" "K8SCentOS8Master3.bifrost")
#Do you want to add Worker nodes in this install. Allowed values true/false
ADD_WORKER_NODES="true"
#All Worker Nodes
WORKER_NODE_IPS=("192.168.2.251" "192.168.2.108" "192.168.2.109" "192.168.2.208" "192.168.2.95" "192.168.2.104")
WORKER_NODE_NAMES=("KubeNode1CentOS8.bifrost" "KubeNode2CentOS8.bifrost" "KubeNode3CentOS8.bifrost" "K8SCentOS8Node1.bifrost" "K8SCentOS8Node2.bifrost" "K8SCentOS8Node3.bifrost")
#All K8S nodes (Master + Worker)
KUBE_CLUSTER_NODE_IPS=(${MASTER_NODE_IPS[*]} ${WORKER_NODE_IPS[*]})
KUBE_CLUSTER_NODE_NAMES=(${MASTER_NODE_NAMES[*]} ${WORKER_NODE_NAMES[*]})
#All nodes we are trying to use. This is used for setting up seamless SSH and common binary install
ALL_NODE_IPS=($KUBE_VIP_1_IP ${KUBE_CLUSTER_NODE_IPS[*]} ${LB_NODE_IPS[*]})
ALL_NODE_NAMES=($KUBE_VIP_1_HOSTNAME ${KUBE_CLUSTER_NODE_NAMES[*]} ${LB_NODE_NAMES[*]})
#Should we use ClusterConfiguration yaml to set up master node or us kubeadm reset to set up cluster. Allowed values "yaml"/"endpoint"
SETUP_CLUSTER_VIA="endpoint"
#Do we want to manually copy the certificates. Allowed values true/false
MANUALLY_COPY_CERTIFICATES="false"
# Drive that is added block/raw for use by storage/Ceph. Valid values sdb, sdc etc.
CEPH_DRIVE_NAME="sdb"
# Used in the PVC config for Prometheus. Set the value in Name column from the result of the command: kubectl get sc
STORAGE_CLASS=""
# Size of Prometheus PVC. Allowed value format "1Gi", "2Gi", "5Gi" etc
STORAGE_SIZE="2Gi"
#Username that we use to connect to remote machine via SSH
USERNAME="root"
#User details for normal kubectl/kubeadm commands post install
ADMIN_USER="ichigo"
USER_HOME="/home/$ADMIN_USER"
# Container Runtime to be used. Allowed values containerd, cri-o and docker
CONTAINER_RUNTIME="docker"
# CRI-O version. Required only in case of cri-o.
CRI_O_VERSION=1.17
#K8S network (CNI) plugin. Allowed values calico/weave
NETWORKING_TYPE="calico"
POD_NETWORK_CIDR='10.244.0.0/16'
#Set below variables when running the script to add specific nodes to existing K8S cluster
MASTER_JOIN_COMMAND=""
WORKER_JOIN_COMMAND=""
#echo "All Node_NAMES: " ${ALL_NODE_NAMES[*]}

## YAML/Git variables
CALICO_YAML="https://docs.projectcalico.org/v3.14/manifests/calico.yaml"

METAL_LB_NAMESPACE=https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
METAL_LB_MANIFESTS=https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml
METAL_LB_CONFIGMAP=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/LB/metal_lb_configmap.yaml

NGINX_LB_DEPLOY_YAML=https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
NGINX_DEPLOY_YAML=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.34.1/deploy/static/provider/baremetal/deploy.yaml

HELM_INSTALL_SCRIPT=https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
CERT_MGR_DEPLOY=https://github.com/jetstack/cert-manager/releases/download/v0.16.0/cert-manager.yaml
SELF_SIGNED_CERT_TEMPLATE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ingress/cert_self_signed.yaml
CERTIFICATE_MOVER=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/certificate_mover.sh
SETUP_HA_KEEPALIVED_SCRIPT=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/LB/setup_loadbalancer.sh
PREPARE_NODE_SCRIPT="https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/prepare_node.sh"


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

#Workaround for lack of DNS. Local node can ping itself but unable to SSH
HOST_PRESENT=$(cat /etc/hosts | grep $(hostname) > /dev/null 2>&1; echo $?)
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

		#Create 1 string by concatenating all Master nodes. Use % as separator to make it easy in subscript to separate
		MASTER_PEER_IP=$(echo ${MASTER_NODE_IPS[*]} | sed 's# #%#g')
		#We can upload the file to target nodes or download from github.
	    #scp ~/setup_loadbalancer.sh "${USER}"@$host:
	    echo "SSH to target LB Node."
	    ssh "${USERNAME}"@$node <<- EOF
	    echo "Connected to $node"
	    cd ~
	    KUBE_VIP="$KUBE_VIP_1_IP"
	    UNICAST_PEER_IP=$FINAL_UNICAST_PEER_IP
		MASTER_PEER_IP=$MASTER_PEER_IP
		CALLING_NODE=$CURRENT_NODE_IP
	    # wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/setup_loadbalancer.sh"
	    wget -q $SETUP_HA_KEEPALIVED_SCRIPT
	    chmod 755 setup_loadbalancer.sh
	    . ./setup_loadbalancer.sh
	    #./setup_loadbalancer.sh $PRIORITY $INTERFACE $AUTH_PASS $API_PORT $node
	    rm -f setup_loadbalancer.sh
	    exit
		EOF
		echo "Load balancer config completed on $node"
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
    NODE_TYPE=$NODE_TYPE
    USERNAME="$ADMIN_USER"
    TEMP_NODE_NAMES="${ALL_NODE_NAMES[*]}"
    TEMP_NODE_IPS="${ALL_NODE_IPS[*]}"
    CALLING_NODE_NAME=$CURRENT_NODE_NAME
    CONTAINER_RUNTIME=$CONTAINER_RUNTIME
    CRI_O_VERSION=$CRI_O_VERSION
    KEEP_FIREWALL_ENABLED=$KEEP_FIREWALL_ENABLED
    yum -y -q install wget dnf
    #wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/prepare_node.sh"
    wget -q $PREPARE_NODE_SCRIPT
    chmod 755 prepare_node.sh
	. ./prepare_node.sh
	rm -f ./prepare_node.sh
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

#Set up the Primary Master node in the cluster.
if [[ $SETUP_PRIMARY_MASTER == "true" ]]
then
	echo "******* Setting up Primary master node ********"
	LB_CONNECTED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep Connected > /dev/null 2>&1; echo $?)
	LB_REFUSED=$(nc -vz $KUBE_VIP_1_IP $API_PORT |& grep refused > /dev/null 2>&1; echo $?)
	echo "LB Details: "$KUBE_VIP_1_IP $API_PORT
	echo "Status of LB flags, Connected is $LB_CONNECTED and Refused is $LB_REFUSED "

	#Run below as sudo on Primary Master node
	echo "Setting up primary node in cluster."
	if [[ $SETUP_CLUSTER_VIA == "yaml" ]]
	then
		echo "Setting up Via YAML."
		#Save the old config
		#kubeadm config print init-defaults --component-configs KubeletConfiguration > config.yaml
		#kubeadm config print join-defaults > join.yaml
		kubeadm config images pull --config kubeadm-config.yaml
		if [[ MANUALLY_COPY_CERTIFICATES == "true" ]]
		then
			#Call init with endpoint parameters needed for Load Balanced Config
			kubeadm init --config kubeadm-config.yaml | tee kubeadm_init_output.txt
		else
			#Call init with endpoint and certificate parameters needed for Load Balanced Config
			kubeadm init --config kubeadm-config.yaml --upload-certs | tee kubeadm_init_output.txt
		fi

	else
		echo "Setting up Via endpoint."
		#Save the old config
		#kubeadm config print init-defaults --component-configs KubeletConfiguration > config.yaml
		#Call init with endpoint and certificate parameters needed for Load Balanced Config
		echo "Initializing control plane with: kubeadm init --control-plane-endpoint $KUBE_VIP_1_IP:$API_PORT "
		if [[ MANUALLY_COPY_CERTIFICATES == "true" ]]
		then
			#Call init with endpoint parameters needed for Load Balanced Config
			kubeadm init --control-plane-endpoint "$KUBE_VIP_1_IP:$API_PORT" --pod-network-cidr=$POD_NETWORK_CIDR | tee kubeadm_init_output.txt
			#Save the output from the previous command as you would need it to add other nodes to cluster
		else
			#Call init with endpoint and certificate parameters needed for Load Balanced Config
			#kubeadm init --control-plane-endpoint "$KUBE_VIP_1_IP:$API_PORT" --upload-certs | tee kubeadm_init_output.txt
			kubeadm init --control-plane-endpoint "$KUBE_VIP_1_IP:$API_PORT" --pod-network-cidr=$POD_NETWORK_CIDR --upload-certs | tee kubeadm_init_output.txt
			#Save the output from the previous command as you would need it to add other nodes to cluster
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
	chmod 700 kubeadm_init_output.txt add_master.txt add_worker.txt

	#Create Kube config Folder.
	mkdir -p $USER_HOME/.kube
	mkdir -p $HOME/.kube
	cp /etc/kubernetes/admin.conf $USER_HOME/.kube/config
	cp /etc/kubernetes/admin.conf $HOME/.kube/config
	chown -R $(id $ADMIN_USER -u):$(id $ADMIN_USER -g) $USER_HOME/.kube/config
	chown -R $(id -u):$(id -g) $HOME/.kube/config
	echo "Kube config copied to Home."

	kubectl get nodes # should show master as Not Ready as networking is missing

	kubectl get pods -A # should show pods from all namespaces
	
	#Set up networking for Masternode. Networking probably is not needed after the Primary node
	echo "Setting up network."
	if [[ $NETWORKING_TYPE == "calico" ]]
	then
		#YAML from K8s.io docs
		kubectl apply -f $CALICO_YAML
		echo "Calico set up."
	else
		export kubever=$(kubectl version | base64 | tr -d '\n')
		kubectl apply -f https://cloud.weave.works/k8s/net?k8s-version=$kubever
		echo "Weave set up."
	fi
	kubectl get pods --all-namespaces -o wide
	#Takes some time for nodes to be ready
	CONTINUE_WAITING=$(kubectl get nodes | grep -w Ready > /dev/null 2>&1; echo $?)
	echo -n "Primary master node not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 10
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get nodes | grep -w Ready > /dev/null 2>&1; echo $?)
	done
	echo ""
	echo "Primary master node ready."
	kubectl get nodes

	if [[ $MANUALLY_COPY_CERTIFICATES == "true" ]]
	then
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
				echo "Certificates already present in Primary node."
			fi
		done
		if [[ $LOOP_COUNT -gt 0 ]]
		then 
			echo "Certificates copy step complete."
		else
			echo "Certificate copy step failed."
		fi
	else
		echo "Certificate copy not needed. Using --upload-certs flag."
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
			echo " =========== Trying to add $node =========== "
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
				#wget -q "https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/certificate_mover.sh"
				wget -q $CERTIFICATE_MOVER
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
			#echo " ChCommand \$(id -u):\$(id -g) \$HOME/.kube/config"
			chown \$(id -u):\$(id -g) \$HOME/.kube/config
			chown \$(id $ADMIN_USER -u):\$(id $ADMIN_USER -g) $USER_HOME/.kube/config
			
			echo "Master node added. Exiting."
			exit
			EOF
			echo " =========== Master node: $node added =========== "
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
			echo " =========== Trying to add $node =========== "
			#Try to SSH into each node
			ssh "$USERNAME"@$node <<- EOF
			echo "Trying to add Worker node:$node to cluster."
			bash -c "$WORKER_JOIN_COMMAND"
			echo "Worker node added. Exiting."
			exit
			EOF
			echo " =========== Back from Worker: $node  =========== "
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

sleep 60

#Check all nodes have joined the cluster. Only needed for Master.
kubectl get nodes

#Check all nodes have joined the cluster. Only needed for Master.
kubectl get pods

#Check Cluster info
kubectl cluster-info

#Check health of cluster. Due to LB config and known bug it would show controller-manager and scheduler as unhealthy
kubectl get cs

if [[ $SETUP_HELM == "true" ]]
then
	echo "Installing Helm"
	curl -fsSL -o get_helm.sh $HELM_INSTALL_SCRIPT
	chmod 755 get_helm.sh
	./get_helm.sh
	echo "Helm installed."
	rm -f get_helm.sh
else
	echo "Skipping Helm install."
fi

#To generate a secret
#kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey=$(openssl rand 128 | openssl enc -base64 -A) --dry-run=client -o yaml > secret.yaml

if [[ $SETUP_METAL_LB == "true" ]]
then
	echo "Proceeding with Metal LB setup."
	#Check that we are not using kube-proxy in IPVS mode.
	IPVS_FLAG=$(kubectl describe configmap -n kube-system kube-proxy | grep -w 'strictARP: false' > /dev/null 2>&1; echo $?)
	#If yes, then edit to add. Actually apply the changes, returns nonzero return code on errors only
	if [[ $IPVS_FLAG -gt 0 ]]
	then
		echo "Setting strictARP flag to true."
		kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | kubectl apply -f - -n kube-system
	else
		echo "strictARP flag already set. Continuing."
	fi

	#Apply below YAMLs
	kubectl apply -f $METAL_LB_NAMESPACE

	kubectl apply -f $METAL_LB_MANIFESTS
	# On first install only
	kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

	#Get the MetalLb config template from github
	wget -q $METAL_LB_CONFIGMAP
	#Update the template with provided address range
	sed -i "s*###st@rt_@ddr3ss###*$START_IP_ADDRESS_RANGE*g" metal_lb_configmap.yaml
	sed -i "s*###3nd_@ddr3ss###*$END_IP_ADDRESS_RANGE*g" metal_lb_configmap.yaml
	echo "MetalLB configmap yaml updated."
	#Apply MetalLB Config
	kubectl apply -f metal_lb_configmap.yaml
	rm -f metal_lb_configmap.yaml
	
	CONTINUE_WAITING=$(kubectl get pods -n metallb-system | grep controller | grep Running > /dev/null 2>&1; echo $?)
	echo -n "MetalLB controller pod not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 10
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get pods -n metallb-system | grep controller | grep Running > /dev/null 2>&1; echo $?)
	done
	echo ""
	#sleep 60
	echo " =========== Metal LB config complete. =========== "
	kubectl get pods -A
else
	echo "Skipping Metal LB setup."
fi

if [[ $SETUP_NGINX_INGRESS == "true" && $SETUP_METAL_LB == "true" && $CLOUD_PROVIDED_LB == "false" ]]
then
		echo "Setting up Nginx Ingress to work with MetalLB"
		#wget -q -O ingress_deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
		wget -q -O ingress_deploy.yaml $NGINX_LB_DEPLOY_YAML
		kubectl apply -f ingress_deploy.yaml
		echo "Nginx ingress deployed."
		rm -f ingress_deploy.yaml
elif [[ $SETUP_NGINX_INGRESS == "true" && $SETUP_METAL_LB == "false" && $CLOUD_PROVIDED_LB == "true" ]]
then
		echo "Skipping setting up Nginx Ingress for external cloud."
else
		echo "Setting up Nginx Ingress to work without a load balancer"
		#wget -q -O ingress_deploy.yaml https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.34.1/deploy/static/provider/baremetal/deploy.yaml
		wget -q -O ingress_deploy.yaml $NGINX_DEPLOY_YAML
		kubectl apply -f ingress_deploy.yaml
		CONTINUE_WAITING=$(kubectl get pods -n ingress-nginx | grep controller | grep Running > /dev/null 2>&1; echo $?)
		echo -n "Nginx controller pod not ready. Waiting ."
		while [[ $CONTINUE_WAITING != 0 ]]
		do
			sleep 10
			echo -n "."
		 	CONTINUE_WAITING=$(kubectl get pods -n ingress-nginx | grep controller | grep Running > /dev/null 2>&1; echo $?)
		done
		echo ""
		echo "Nginx ingress deployed."
		rm -f ingress_deploy.yaml
fi
echo " =========== Nginx ingress config complete. =========== "

# To generate SSL secret for
#openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ${KEY_FILE} -out ${CERT_FILE} -subj "/CN=${HOST}/O=${HOST}"


#Install Kustomize
#curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash

if [[ $SETUP_ROOK_INSTALLED == "true" ]]
then
	echo "Starting Ceph+Rook installation."
	export TEMP_NODE_NAMES="${WORKER_NODE_NAMES[*]}"
    export TEMP_NODE_IPS="${WORKER_NODE_IPS[*]}"
	wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/storage/setup_rook_ceph.sh
	chmod 755 setup_rook_ceph.sh
	. ./setup_rook_ceph.sh # source the script to use the variables already set above.
	echo "Storage setup complete."
	sleep 2
	rm -f setup_rook_ceph.sh
else
	echo "Skipping Ceph+Rook installation."
fi
echo " =========== Ceph+Rook installation complete. =========== "

if [[ $SETUP_CLUSTER_MONITORING == "true" ]]
then
	echo "Starting monitoring installation."
	wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/monitoring/setup_monitoring_all.sh
	chmod 755 setup_monitoring_all.sh
	. ./setup_monitoring_all.sh # source the script to use the variables already set above.
	echo "Monitoring setup complete."
	sleep 2
	rm -f setup_monitoring_all.sh
else
	echo "Skipping Monitoring installation."
fi
echo " =========== Monitoring installation complete. =========== "

# To install cert-manager
if [[ $SETUP_CERT_MANAGER == "true" ]]
	then
		echo "Setting up Cert Manager"
		#kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.16.0/cert-manager.yaml
		kubectl apply --validate=false -f $CERT_MGR_DEPLOY
		echo "Cert Manager deployed."
		wget -q $SELF_SIGNED_CERT_TEMPLATE
		echo -n "Cert Manager pod not ready. Waiting ."
		CONTINUE_WAITING=$(kubectl get pods -n cert-manager | grep cert-manager-webhook | grep Running > /dev/null 2>&1; echo $?)
		while [[ $CONTINUE_WAITING != 0 ]]
		do
			sleep 10
			echo -n "."
		 	CONTINUE_WAITING=$(kubectl get pods -n cert-manager | grep cert-manager-webhook | grep Running > /dev/null 2>&1; echo $?)
		done
		echo ""
		sleep 15
		kubectl apply -f cert_self_signed.yaml
		echo "Self Signed issuer setup."
		rm -f cert-manager.yaml cert_self_signed.yaml
else
	echo "Skipping setting up Cert Manager"
fi


