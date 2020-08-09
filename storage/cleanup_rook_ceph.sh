#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
#ROOK + Ceph Cleanup script. Need to eb executed from a host where we have:
#1. key based ssh enabled for all nodes
#2. hosts file or DNS based ssh access to all nodes
#3. sudo + kubectl access
#4. Internet access to fetch files

#sudo ./setup_rook_ceph.sh |& tee -a setup_storage.log

echo "----------- Cleaning Rook + Ceph  ------------"

# YAML/ Git variables
CEPH_COMMON_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/common.yaml
CEPH_OPERATOR_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/operator.yaml
CEPH_CLUSTER_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/cluster.yaml
CEPH_DASHBOARD_YAML=https://raw.githubusercontent.com/rook/rook/master/cluster/examples/kubernetes/ceph/dashboard-ingress-https.yaml
CEPH_LB_DASHBOARD_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/dashboard-loadbalancer.yaml
CEPH_FILSYSTEM_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/filesystem.yaml
ROOK_STORAGE_CLASS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/storage/rook_storage_class.yaml
CEPH_TOOLBOX_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/toolbox.yaml

# Flag for setting up Ceph tool container in K8S. Allowed values true/false
INSTALL_CEPH_TOOLS="true"
# Do we want Ceph dashboard to be accessible via Load Balancer/Metal LB or use via Ingress.Allowed values true/false
SETUP_FOR_LOADBALANCER="false"

if [[ ${WORKER_NODE_NAMES[*]} == "" || ${WORKER_NODE_IPS[*]} == "" ]]
then
	echo "WORKER_NODE_NAMES or WORKER_NODE_IPS not passed. Unable to proceed."
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

# Check if Kubectl is available or not
KUBECTL_AVAILABLE=$(kubectl version > /dev/null 2>&1; echo $?)

if [[ -f rook-storage_class.yaml ]]
then
	echo "rook-storage_class.yaml already present. Proceeding."
else
	echo "Downloading rook-storage_class.yaml"
	#Fetch the StorageClass YAML
	wget -q $ROOK_STORAGE_CLASS_YAML -O rook-storage_class.yaml
fi

if [[ -f rook-filesystem.yaml ]]
then
	echo "rook-filesystem.yaml already present. Proceeding."
else
	echo "Downloading rook-filesystem.yaml"
	# Fetch the filesystem YAML
	wget -q $CEPH_FILSYSTEM_YAML -O rook-filesystem.yaml
fi

if [[ -f rook-dashboard.yaml ]]
then
	echo "rook-dashboard.yaml already present. Proceeding."
else
	echo "Downloading rook-dashboard.yaml"
	if [[ $SETUP_FOR_LOADBALANCER == "true" ]]
	then
		# Download Cephs cluster YAML
		wget -q $CEPH_LB_DASHBOARD_YAML -O rook-dashboard.yaml
		sed -i "s/rook-ceph-mgr-dashboard-loadbalancer/rook-ceph-mgr-dashboard/" rook-dashboard.yaml
	else
		wget -q $CEPH_DASHBOARD_YAML -O rook-dashboard.yaml
	fi
fi

if [[ -f rook-cluster.yaml ]]
then
	echo "rook-cluster.yaml already present. Proceeding."
else
	echo "Downloading rook-cluster.yaml"
	# Download Cephs cluster YAML
	wget -q $CEPH_CLUSTER_YAML -O rook-cluster.yaml
fi
if [[ -f rook-operator.yaml ]]
then
	echo "rook-operator.yaml already present. Proceeding."
else
	echo "Downloading rook-operator.yaml"
	# Get Operator YAML
	wget -q $CEPH_OPERATOR_YAML -O rook-operator.yaml
fi
if [[ -f rook-common.yaml ]]
then
	echo "rook-common.yaml already present. Proceeding."
else
	echo "Downloading rook-common.yaml"
	# Get Common YAML
	wget -q $CEPH_COMMON_YAML -O rook-common.yaml
fi
if [[ -f ceph-toolbox.yaml ]]
then
	echo "ceph-toolbox.yaml already present. Proceeding."
	#Connect to Ceph toolbox with below command
	#kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') bash
else
	echo "Downloading ceph-toolbox.yaml."
	wget -q $CEPH_TOOLBOX_YAML -O ceph-toolbox.yaml
fi

if [[ $KUBECTL_AVAILABLE == 0  ]]
then
	# Make sure it is not set as default storage
	kubectl patch storageclass csi-cephfs -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
	# Delete rook_storage_class using YAML 
	kubectl delete -f rook-storage_class.yaml
	echo "Rook StorageClass config deleted."
	# Delete Filesystem using YAML 
	kubectl delete -f rook-filesystem.yaml
	echo "Rook Filesystem config deleted."
	# Delete dashboard config using YAML 
	kubectl delete -f rook-dashboard.yaml
	echo "Rook dashboard config deleted."

	# Delete Cluster using YAML 
	kubectl delete -f rook-cluster.yaml
	echo "Rook cluster config deleted."
	# Delete Ceph cluster as per Rook documentation
	#kubectl -n rook-ceph delete cephcluster rook-ceph
	#Wait for Ceph cluster to be deleted.
	ROOK_CLUSTER_DELETED=$(kubectl -n rook-ceph get cephcluster)
	while [[ $ROOK_CLUSTER_DELETED == 0 ]]
	do
		echo "Wait for cluster to be deleted."
		sleep 30
		ROOK_CLUSTER_DELETED=$(kubectl -n rook-ceph get cephcluster)
	done
	echo "proceeding with rest of the cleanup."
	# Delete Ceph toolbox
	kubectl delete -f ceph-toolbox.yaml
	echo "Ceph toolbox instance deleted."
	# Delete Operator
	kubectl delete -f rook-operator.yaml
	echo "Rook operator config deleted."
	# Delete Common
	kubectl delete -f rook-common.yaml
	echo "Rook common config deleted."
else
	echo "Kubectl unavailable. Unable to delete storage components."
fi

rm -f rook-storage_class.yaml rook-filesystem.yaml rook-cluster.yaml 
rm -f rook-operator.yaml rook-common.yaml rook-dashboard.yaml ceph-toolbox.yaml


#Count the number of lines returned as more than 1 would mean filesystem is assigned.
FS_ROW_COUNT=$(lsblk -f | grep $CEPH_DRIVE_NAME.* | awk -F " " '{print $2}' | wc -l)
# Find the filesystem on drive specified
FS_TYPE=$(lsblk -f | grep $CEPH_DRIVE_NAME.* | awk -F " " '{print $2}')
if [[ $FS_ROW_COUNT == 0 && $FS_TYPE != "" ]]
then
	#Connect to each node and zap Ceph Drives
	echo "Cleaning Ceph drives on worker nodes"
	for node in ${WORKER_NODE_NAMES[*]}
	do
		echo "Trying to connect to $node"
		#Try to SSH into each node
		ssh "$USERNAME"@$node <<- EOF
		echo "Trying to clean Ceph drive on node:\$node."
		#CEPH_DRIVE=('/dev/sdb')
		CEPH_DRIVE=$CEPH_DRIVE_NAME
		CEPH_DRIVE_PRESENT=\$(lsblk -f -o NAME,FSTYPE | grep ceph > /dev/null 2>&1; echo \$? )
		echo "Ceph drive present flag: \$CEPH_DRIVE_PRESENT"
		if [[ \$CEPH_DRIVE_PRESENT == 0 ]]
		then
			echo "Cleaning Rook and Ceph related config and zapping drive."
			for DISK in \${CEPH_DRIVE[*]}
			do
				echo "Begin zapping process."
				sgdisk --zap-all \$DISK
				dd if=/dev/zero of="\$DISK" bs=1M count=100 oflag=direct,dsync
				DMREMOVE_STATUS=\$(ls /dev/mapper/ceph-* | xargs -I% -- dmsetup remove % > /dev/null 2>&1; echo \$? )
				if [[ \$DMREMOVE_STATUS -gt 0 ]]
				then
					rm -f /dev/mapper/ceph-*
					echo "Manually deleted /dev/mapper/ceph "
				else
					echo "DMREMOVE_STATUS completed successfully."
				fi
				rm -rf /dev/ceph-*
				rm -Rf /var/lib/rook
			done
		else
			rm -Rf /dev/ceph-*
			rm -Rf /var/lib/rook
			echo "No processing needed for Rook/Ceph."
		fi
		echo "Worker node processed. Exiting."
		sleep 2
		exit
		EOF
		echo "Back from Worker: "$node
	done
else
	echo "Filesystem for specified drive seems to be already flushed."
fi

echo "----------- Rook removed. Drives used by Ceph zapped -----------"
