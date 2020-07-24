#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
#ROOK + Ceph Cleanup script. Need to eb executed from a host where we have:
#1. key based ssh enabled for all nodes
#2. hosts file or DNS based ssh access to all nodes
echo "----------- Cleaning Rook + Ceph  ------------"

#All Worker Nodes
export WORKER_NODE_IPS=("192.168.2.251" "192.168.2.137" "192.168.2.227")
export WORKER_NODE_NAMES=("KubeNode1CentOS8.bifrost" "KubeNode2CentOS8.bifrost" "KubeNode3CentOS8.bifrost")
#Username that we use to connect to remote machine via SSH
USERNAME="root"

# Make sure it is not set as default storage
kubectl patch storageclass csi-cephfs -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

if [[ -f rook_storage_class.yaml ]]
then
	echo "rook_storage_class.yaml already present. Proceeding."
else
	echo "Downloading rook_storage_class.yaml"
	#Fetch the StorageClass YAML
	wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/rook_storage_class.yaml
fi

if [[ -f filesystem.yaml ]]
then
	echo "filesystem.yaml already present. Proceeding."
else
	echo "Downloading filesystem.yaml"
	# Fetch the filesystem YAML
	wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/filesystem.yaml
fi

if [[ -f cluster.yaml ]]
then
	echo "Cluster.yaml already present. Proceeding."
else
	echo "Downloading cluster.yaml"
	# Download Cephs cluster YAML
	wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/cluster.yaml
fi
if [[ -f operator.yaml ]]
then
	echo "Operator.yaml already present. Proceeding."
else
	echo "Downloading Operator.yaml"
	# Get Operator YAML
	wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/operator.yaml
fi
if [[ -f common.yaml ]]
then
	echo "Common.yaml already present. Proceeding."
else
	echo "Downloading Common.yaml"
	# Get Common YAML
	wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/common.yaml
fi
if [[ -f toolbox.yaml ]]
then
	echo "Ceph toolbox.yaml already present. Proceeding."
	#Connect to Ceph toolbox with below command
	#kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') bash
else
	echo "Skiiping Ceph toolbox setup."
	wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/toolbox.yaml

fi

# Delete rook_storage_class using YAML 
kubectl delete -f rook_storage_class.yaml
echo "StorageClass config deleted."
# Delete Filesystem using YAML 
kubectl delete -f filesystem.yaml
echo "Ceph Filesystem config deleted."
# Delete Cluster using YAML 
kubectl delete -f cluster.yaml
echo "Ceph cluster config deleted."
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

# Delete Operator
kubectl delete -f operator.yaml
echo "Ceph operator config deleted."
# Delete Common
kubectl delete -f common.yaml
echo "Ceph common config deleted."

# Delete Ceph toolbox
kubectl delete -f toolbox.yaml
echo "Ceph toolbox instance deleted."

#Connect to each node and zap Ceph Drives
echo "Cleaning Ceph drives on worker nodes"
for node in ${WORKER_NODE_NAMES[*]}
do
	echo "Trying to connect to $node"
	#CEPH_DRIVE=('/dev/sdb')
	#Try to SSH into each node
	ssh "$USERNAME"@$node <<- 'EOF'
	echo "Trying to clean Ceph drive on node:$node."
	CEPH_DRIVE=('/dev/sdb')
	CEPH_DRIVE_PRESENT=$(lsblk -f -o NAME,FSTYPE | grep ceph > /dev/null 2>&1; echo $? )
	echo $CEPH_DRIVE_PRESENT
	if [[ $CEPH_DRIVE_PRESENT == 0 ]]
	then
		echo "Cleaning Rook and Ceph related config and zapping drive."
		for DISK in ${CEPH_DRIVE[*]}
		do
			echo "Begin zapping process."
			sgdisk --zap-all $DISK
			dd if=/dev/zero of="$DISK" bs=1M count=100 oflag=direct,dsync
			DMREMOVE_STATUS=$(ls /dev/mapper/ceph-* | xargs -I% -- dmsetup remove % > /dev/null 2>&1; echo $? )
			if [[ $DMREMOVE_STATUS -gt 0 ]]
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
		rm -rf /dev/ceph-*
		rm -Rf /var/lib/rook
		echo "No processing needed for Rook/Ceph."
	fi
	echo "Worker node processed. Exiting."
	sleep 2
	exit
	EOF
	echo "Back from Worker: "$node
done

rm -f rook_storage_class.yaml filesystem.yaml cluster.yaml operator.yaml common.yaml toolbox.yaml

echo "Rook removed. Drives used by Ceph zapped."
