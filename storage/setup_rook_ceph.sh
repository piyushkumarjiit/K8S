#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# ROOK Deployment script. Need to be executed from a host where we have:
#1. sudo + kubectl and internet access
#2. Hosts file or DNS based ssh access to all nodes
#3. key based ssh enabled for all nodes
#4. Make sure Block/raw drive is attached to worker nodes before proceeding
#5. Make sure your K8S cluster is not using Pod security. If it is then you need to set 1 PodSecurityPolicy that allows privileged Pod execution

#sudo ./setup_rook_ceph.sh | tee setup_storage.log
#sudo ./setup_rook_ceph.sh |& tee setup_storage.log

echo "----------- Setting up Storage (Rook + Ceph) ------------"

# YAML/ Git variables
CEPH_COMMON_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/common.yaml
CEPH_OPERATOR_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/operator.yaml
CEPH_CLUSTER_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/cluster.yaml
CEPH_DASHBOARD_YAML=https://raw.githubusercontent.com/rook/rook/master/cluster/examples/kubernetes/ceph/dashboard-ingress-https.yaml
CEPH_LB_DASHBOARD_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/dashboard-loadbalancer.yaml
CEPH_FILSYSTEM_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/filesystem.yaml
ROOK_STORAGE_CLASS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/storage/rook_storage_class.yaml
CEPH_TOOLBOX_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/toolbox.yaml
#Hostname of the node from where we run the script
CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"

#All node names passed by calling script that we are trying to setup
# WORKER_NODE_NAMES=($TEMP_NODE_NAMES)
#All node IP addresses passed by calling script that we are trying to setup
# WORKER_NODE_IPS=($TEMP_NODE_IPS)

if [[ ${WORKER_NODE_NAMES[*]} == "" || ${WORKER_NODE_IPS[*]} == "" ]]
then
	echo "WORKER_NODE_NAMES or WORKER_NODE_IPS not passed. Trying to set."
	#All Worker Nodes
	WORKER_NODE_IPS=("192.168.2.208" "192.168.2.95" "192.168.2.104")
	WORKER_NODE_NAMES=("K8SCentOS8Node1.bifrost" "K8SCentOS8Node2.bifrost" "K8SCentOS8Node3.bifrost")
	exit 1
else
	echo "WORKER_NODE_NAMES already set. Proceeding."
fi

if [[ $CEPH_DRIVE_NAME == "" ]]
then
	echo "CEPH_DRIVE_NAME not set."
	# Drive that is added block/raw for use by Ceph. Valid values sdb, sdc etc.
	CEPH_DRIVE_NAME="sdb"
else
	echo "CEPH_DRIVE_NAME already set. Proceeding."
fi

if [[ $USERNAME == "" ]]
then
	echo "USERNAME not set. Setting as root."
	#Username that we use to connect to remote machine via SSH
	USERNAME="root"
else
	echo "USERNAME already set. Proceeding."
fi

if [[ $INGRESS_DOMAIN_NAME == "" ]]
then
	echo "INGRESS_DOMAIN_NAME not set. Setting as k8smagic.com."
	# Domain name to be used by Ingress. Using this ceph dashboard URL would become: rook.<domain.com>
	# INGRESS_DOMAIN_NAME=k8smagic.com
else
	echo "INGRESS_DOMAIN_NAME already set. Proceeding."
fi

# Flag for setting up Ceph tool container in K8S. Allowed values true/false
INSTALL_CEPH_TOOLS="true"
# Do we want Ceph dashboard to be accessible via Load Balancer/Metal LB or use via Ingress.Allowed values true/false
SETUP_FOR_LOADBALANCER="false"
# Flag for setting up Ceph as default storage in cluster. Allowed values true/false
SET_AS_DEFAULT_STORAGE="false"
#To identify the empty storage drive run below command. The one with empty FSTYPE is one we can use
#lsblk -a | grep sdb

for node in ${WORKER_NODE_NAMES[*]}
do
	echo "Trying to connect to $node"
	#Try to SSH into each node
	ssh "$USERNAME"@$node <<- EOF
	CEPH_DRIVE=$CEPH_DRIVE_NAME
	echo "CEPH DRIVE: \$CEPH_DRIVE"
	#Make sure chrony/ntp is running otherwise we would run in issue with Ceph
	CHRONY_WORKING=\$(systemctl status chronyd | grep running > /dev/null 2>&1; echo \$?)
	echo "Chrony Flag: \$(systemctl status chronyd | grep running)"
	if [[ \$CHRONY_WORKING -gt 0 ]]
	then
		echo "chronyd not running. Lets fix that."
		CHRONY_INSTALLED=\$(dnf list | grep chrony > /dev/null 2>&1; echo \$?)
		if [[ \$CHRONY_INSTALLED == 0 ]]
		then
			systemctl start chronyd
			sleep 2
			CHRONY_WORKING=\$(systemctl status chronyd | grep running > /dev/null 2>&1; echo \$?)
			if [[ \$CHRONY_WORKING == 0 ]]
			then
				echo "chronyd running now."
			else
				echo "chronyd still not running. Might need human touch."
			fi
		else
			echo "Installing chronyd"
			dnf -y -q install chrony
			echo "chronyd installed"
			systemctl enable chronyd
			systemctl start chronyd
			CHRONY_WORKING=\$(systemctl status chronyd | grep running > /dev/null 2>&1; echo \$?)
			if [[ \$CHRONY_WORKING == 0 ]]
			then
				echo "chronyd installed and running."
			else
				echo "chronyd still not running. Might need human touch."
			fi
		fi
	else
		echo "chronyd working already. Proceeding"
	fi
	CEPH_DRIVE_IS_PRESENT=\$(lsblk -f | grep \$CEPH_DRIVE | awk -F " " '{print \$1}')
	CEPH_DRIVE_IS_EMPTY=\$(lsblk -f | grep \$CEPH_DRIVE | awk -F " " '{print \$2}')
	echo "CEPH drive flag: \$CEPH_DRIVE_IS_PRESENT"
	if [[ \$CEPH_DRIVE_IS_PRESENT != \$CEPH_DRIVE ]]
	then
		echo "Please confirm that raw/block drive is mounted as \$CEPH_DRIVE. Unable to proceed."
		sleep 2
		exit 1
	else
		echo "Drive found. Proceeding."
	fi
	echo "Worker node processed. Exiting."
	sleep 2
	exit
	EOF
	echo "Back from Worker: "$node
done

# Get Common YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/common.yaml
wget -q $CEPH_COMMON_YAML -O rook-common.yaml
sleep 15
# Get Operator YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/operator.yaml
wget -q $CEPH_OPERATOR_YAML -O rook-operator.yaml

# Deploy Rook
kubectl create -f rook-common.yaml
sleep 15

kubectl create -f rook-operator.yaml
sleep 15
# Download Cephs cluster YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/cluster.yaml
wget -q $CEPH_CLUSTER_YAML -O rook-cluster.yaml
# Create Cluster
kubectl create -f rook-cluster.yaml

CONTINUE_WAITING=$(kubectl get pods -n rook-ceph | grep crashcollector | grep Running > /dev/null 2>&1; echo $?)
echo -n "Ceph cluster not ready. Waiting ."
while [[ $CONTINUE_WAITING != 0 ]]
do
	sleep 10
	echo -n "."
 	CONTINUE_WAITING=$(kubectl get pods -n rook-ceph | grep crashcollector | grep Running > /dev/null 2>&1; echo $?)
done
echo ""

if [[ $SETUP_FOR_LOADBALANCER == "true" ]]
then
	echo "Setting up rook.$INGRESS_DOMAIN_NAME to be used via a load balancer."
	wget -q $CEPH_LB_DASHBOARD_YAML -O rook-dashboard.yaml
	#Update the file to make the name same as the one running in cluster and then apply
	sed -i "s/rook-ceph-mgr-dashboard-loadbalancer/rook-ceph-mgr-dashboard/" rook-dashboard.yaml
	kubectl apply -f rook-dashboard.yaml
	echo "Done. rook.$INGRESS_DOMAIN_NAME dashboard would use load balancer."
else
	echo "Setting up rook.$INGRESS_DOMAIN_NAME to be used with ingress."
	wget -q $CEPH_LB_DASHBOARD_YAML -O rook-dashboard.yaml
	#Update the file to make the name same as the one running in cluster and then apply. Possible workaround as operator is not creating service
	#sed -i "s/rook-ceph-mgr-dashboard-loadbalancer/rook-ceph-mgr-dashboard/" rook-dashboard.yaml
	#sed -i "s/type: LoadBalancer/type: ClusterIP/" rook-dashboard.yaml
	#kubectl apply -f rook-dashboard.yaml
	#rm -f rook-dashboard.yaml
	wget -q $CEPH_DASHBOARD_YAML -O rook-dashboard.yaml
	sed -i "s/rook-ceph.example.com/rook\.$INGRESS_DOMAIN_NAME/g" rook-dashboard.yaml
	kubectl apply -f rook-dashboard.yaml
	echo " Done. rook.$INGRESS_DOMAIN_NAME dashboard would use Ingress."
	rm -f rook-dashboard.yaml
fi


# Fetch the filesystem YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/filesystem.yaml
wget -q $CEPH_FILSYSTEM_YAML -O rook-filesystem.yaml
kubectl apply -f rook-filesystem.yaml
sleep 15
echo "Ceph Filesystem type storage created."
rm -f rook-filesystem.yaml

#Fetch the StorageClass YAML
#wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/rook_storage_class.yaml
wget -q $ROOK_STORAGE_CLASS_YAML -O rook-storage_class.yaml
kubectl apply -f rook-storage_class.yaml
echo "StorageClass config applied."
rm -f rook-storage_class.yaml
sleep 15
if [[ $INSTALL_CEPH_TOOLS == "true" ]]
then
	#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/toolbox.yaml
	wget -q $CEPH_TOOLBOX_YAML -O ceph-toolbox.yaml
	kubectl apply -f ceph-toolbox.yaml
	echo "Created Ceph toolbox instance."
	rm -f ceph-toolbox.yaml
	#Connect to Ceph toolbox with below command
	#kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') bash
else
	echo "Skipping Ceph toolbox setup."
fi


CONTINUE_WAITING=$(($(kubectl get service -n rook-ceph rook-ceph-mgr-dashboard > /dev/null 2>&1; echo $?) \
+ $(kubectl -n rook-ceph get secret rook-ceph-dashboard-password > /dev/null 2>&1; echo $?)))
echo -n "Storage manager service not ready. Waiting ."
while [[ $CONTINUE_WAITING != 0 ]]
do
	sleep 20
	echo -n "."
 	CONTINUE_WAITING=$(($(kubectl get service -n rook-ceph rook-ceph-mgr-dashboard > /dev/null 2>&1; echo $?) \
+ $(kubectl -n rook-ceph get secret rook-ceph-dashboard-password > /dev/null 2>&1; echo $?)))
done
echo ""

#Find the IP address allocated by your Load balancer using below command
ROOK_DASHBOARD_IP=$(kubectl  get service -A | grep rook-ceph-mgr-dashboard | awk -F " " '{print $5}')
if [[ $ROOK_DASHBOARD_IP != '<pending>' && $SETUP_FOR_LOADBALANCER == "true" ]]
then
	echo "LB assigned external IP."
	echo 'Connect to Cephs Dashboard on https://'$ROOK_DASHBOARD_IP':8443'
	echo "Default login: admin and Password: $(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo)"
elif [[ $SETUP_FOR_LOADBALANCER != "true" ]]
then
	echo "Ingress configured for Rook Dashboard. Use: https://rook.$INGRESS_DOMAIN_NAME"
	echo "Default login: admin and Password: $(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo)"
else
	echo "No external IP assigned."
fi

if [[ $SET_AS_DEFAULT_STORAGE == "true" ]]
then
	echo "Setting as default storage in cluster."
	# Set this as default storage
	kubectl patch storageclass csi-cephfs -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
	# Unset this as default storage
	# kubectl patch storageclass csi-cephfs -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
else
	echo "Skipping setting as default storage in cluster."
fi

CONTINUE_WAITING=$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}' > /dev/null 2>&1; echo $?)
echo -n "CEPH tools pod not ready. Waiting ."
while [[ $CONTINUE_WAITING != 0 ]]
do
	sleep 20
	echo -n "."
 	CONTINUE_WAITING=$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}' > /dev/null 2>&1; echo $?)
done
echo ""
sleep 120
# To avoid csi-cephfs missing error
CSI_EXISTS=$(kubectl exec -i -n rook-ceph "$CEPH_TOOLS_POD" -- bash -c 'ceph fs subvolumegroup ls myfs | grep csi' > /dev/null 2>&1 ; echo $?)
if [[ $CSI_EXISTS != 0 ]]
then
	CEPH_TOOLS_POD=$(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}')
	echo "Fetch Ceph tools container name:" $CEPH_TOOLS_POD
	#kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') bash -c 'ceph fs subvolumegroup create myfs csi'
	kubectl exec -it -n rook-ceph "$CEPH_TOOLS_POD" -- bash -c 'ceph fs subvolumegroup create myfs csi'
	echo "CEPH FS Volume group created."
else
	echo "CSI already exists."
fi
rm -f rook-dashboard.yaml rook-operator.yaml rook-common.yaml rook-cluster.yaml 

echo "------------ Storage (Rook + Ceph) setup completed ------------"
