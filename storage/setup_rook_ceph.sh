#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# ROOK Deployment script. Need to be executed from a host where we have:
#1. kubectl access
#2. hosts file or DNS based ssh access to all nodes
#3. key based ssh enabled for all nodes

#sudo ./cleanup_rook_ceph.sh | tee clean_storage.log
#sudo ./cleanup_rook_ceph.sh |& tee clean_storage.log

echo "----------- Preparing Storage Node: $(hostname) ------------"

# YAML/ Git variables
CEPH_COMMON_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/common.yaml
CEPH_OPERATOR_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/operator.yaml
CEPH_CLUSTER_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/cluster.yaml
CEPH_LB_DASHBOARD_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/dashboard-loadbalancer.yaml
CEPH_FILSYSTEM_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/filesystem.yaml
ROOK_STORAGE_CLASS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/storage/rook_storage_class.yaml
CEPH_TOOLBOX_YAML=https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/toolbox.yaml
#Hostname of the node from where we run the script
export CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
export CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"
#All Worker Nodes
export WORKER_NODE_IPS=("192.168.2.251" "192.168.2.137" "192.168.2.227")
export WORKER_NODE_NAMES=("KubeNode1CentOS8.bifrost" "KubeNode2CentOS8.bifrost" "KubeNode3CentOS8.bifrost")
#Username that we use to connect to remote machine via SSH
USERNAME="root"
# Flag for setting up Ceph tool container in K8S. Allowed values true/false
INSTALL_CEPH_TOOLS="true"
# Do we want Ceph dashboard to be accessible via Load Balancer/Metal LB or use via Ingress.Allowed values true/false
SETUP_FOR_LOADBALANCER="false"
#Make sure your K8S cluster is not using Pod security. If it is then you need to set 1 PodSecurityPolicy that allows privileged Pod execution

#To identify the empty storage drive run below command. The one with empty FSTYPE is one we can use
#lsblk -f

for node in ${WORKER_NODE_NAMES[*]}
do
	echo "Trying to connect to $node"
	#Try to SSH into each node
	ssh "$USERNAME"@$node <<- 'EOF'
	#Make sure chrony/ntp is running otherwise we would run in issue with Ceph
	CHRONY_WORKING=$(systemctl status chronyd | grep running > /dev/null 2>&1; echo $?)
	if [[ $CHRONY_WORKING -gt 0 ]]
	then
		echo "chronyd not running. Lets fix that."
		CHRONY_INSTALLED=$(dnf list | grep chrony > /dev/null 2>&1; echo $?)
		if [[ $CHRONY_INSTALLED == 0 ]]
		then
			systemctl start chronyd
			sleep 2
			CHRONY_WORKING=$(systemctl status chronyd | grep running > /dev/null 2>&1; echo $?)
			if [[ $CHRONY_WORKING == 0 ]]
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
			CHRONY_WORKING=$(systemctl status chronyd | grep running > /dev/null 2>&1; echo $?)
			if [[ $CHRONY_WORKING == 0 ]]
			then
				echo "chronyd installed and running."
			else
				echo "chronyd still not running. Might need human touch."
			fi
		fi
	else
		echo "chronyd working already. Proceeding"
	fi
	
	echo "Worker node processed. Exiting."
	sleep 2
	exit
	EOF
	echo "Back from Worker: "$node
done

# Get Common YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/common.yaml
wget -q $CEPH_COMMON_YAML
# Get Operator YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/operator.yaml
wget -q $CEPH_OPERATOR_YAML
# Deploy Rook
kubectl create -f common.yaml
kubectl create -f operator.yaml
# Download Cephs cluster YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/cluster.yaml
wget -q $CEPH_CLUSTER_YAML
# Create Cluster
kubectl create -f cluster.yaml

if [[ $SETUP_FOR_LOADBALANCER == "true" ]]
then
	#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/dashboard-loadbalancer.yaml
	wget -q $CEPH_LB_DASHBOARD_YAML
	#Update the file to make the name same as the one running in cluster and then apply
	sed -i "s/rook-ceph-mgr-dashboard-loadbalancer/rook-ceph-mgr-dashboard/" dashboard-loadbalancer.yaml
	kubectl apply -f dashboard-loadbalancer.yaml
else
	echo "Ceph dashboard would use Ingress."
fi

# Fetch the filesystem YAML
#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/filesystem.yaml
wget -q $CEPH_FILSYSTEM_YAML
kubectl apply -f filesystem.yaml
echo "Ceph Filesystem type storage created."
rm -f filesystem.yaml

#Fetch the StorageClass YAML
#wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/rook_storage_class.yaml
wget -q $ROOK_STORAGE_CLASS_YAML
kubectl apply -f rook_storage_class.yaml
echo "StorageClass config applied."
rm -f rook_storage_class.yaml

if [[ $INSTALL_CEPH_TOOLS == "true" ]]
then
	#wget -q https://raw.githubusercontent.com/rook/rook/release-1.3/cluster/examples/kubernetes/ceph/toolbox.yaml
	wget -q $CEPH_TOOLBOX_YAML
	kubectl apply -f toolbox.yaml
	echo "Created Ceph toolbox instance."
	rm -f toolbox.yaml
	#Connect to Ceph toolbox with below command
	#kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') bash
else
	echo "Skiiping Ceph toolbox setup."
fi

sleep 120
#Find the IP address allocated by your Load balancer using below command
ROOK_DASHBOARD_IP=$(kubectl  get service -A | grep rook-ceph-mgr-dashboard | awk -F " " '{print $5}')
if [[ $ROOK_DASHBOARD_IP != '<pending>' ]]
then
	echo "LB assigned external IP."
	echo 'Connect to Cephs Dashboard on https://'$ROOK_DASHBOARD_IP':8443'
	echo "Default login: admin and Password: $(kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo)"
else
	echo "LB failed to assign external IP."
fi

# Set this as default storage
# kubectl patch storageclass csi-cephfs -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
# kubectl patch storageclass csi-cephfs -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# To avoid csi-cephfs missing error
#kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') bash -c 'ceph fs subvolumegroup create myfs csi'
kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[0].metadata.name}') -- bash -c 'ceph fs subvolumegroup create myfs csi'
echo "CEPH FS Volume group created."
rm -f dashboard-loadbalancer.yaml cluster.yaml operator.yaml common.yaml

echo "Rook + Ceph setup completed."
