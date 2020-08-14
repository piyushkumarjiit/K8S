#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

#sudo ./Cleanup_Kubernetes_V01.sh | tee cleanup.log
#sudo ./Cleanup_Kubernetes_V01.sh |& tee -a cleanup.log

echo "------------ Cleanup script started --------------"

#LB Details
KUBE_VIP_1_HOSTNAME="VIP"
KUBE_VIP_1_IP="192.168.2.6"
#Port where Control Plane API server would bind on Load Balancer
KUBE_MASTER_API_PORT="6443"
#Hostname of the node from where we run the script
CURRENT_NODE_NAME="$(hostname)"
#IP of the node from where we run the script
CURRENT_NODE_IP="$(hostname -I | cut -d" " -f 1)"

#All Nodes running Load Balancer
LB_NODES_IP=("192.168.2.205" "192.168.2.111")
LB_NODES_NAMES=("KubeLBNode1.bifrost" "KubeLBNode2.bifrost")
#All Master nodes
MASTER_NODE_IPS=("192.168.2.220" "192.168.2.13" "192.168.2.186" "192.168.2.175" "192.168.2.198" "192.168.2.140")
MASTER_NODE_NAMES=("KubeMasterCentOS8.bifrost" "KubeMaster2CentOS8.bifrost" "KubeMaster3CentOS8.bifrost" "K8SCentOS8Master1.bifrost" "K8SCentOS8Master2.bifrost" "K8SCentOS8Master3.bifrost")
#All Worker Nodes
WORKER_NODE_IPS=("192.168.2.251" "192.168.2.108" "192.168.2.109" "192.168.2.208" "192.168.2.95" "192.168.2.104")
WORKER_NODE_NAMES=("KubeNode1CentOS8.bifrost" "KubeNode2CentOS8.bifrost" "KubeNode3CentOS8.bifrost" "K8SCentOS8Node1.bifrost" "K8SCentOS8Node2.bifrost" "K8SCentOS8Node3.bifrost")
#All K8S nodes (Worker + Master)
KUBE_CLUSTER_NODE_IPS=(${WORKER_NODE_IPS[*]} ${MASTER_NODE_IPS[*]})
KUBE_CLUSTER_NODE_NAMES=(${WORKER_NODE_NAMES[*]} ${MASTER_NODE_NAMES[*]})
#All nodes we are trying to use
ALL_NODE_IPS=($KUBE_VIP_1_IP ${KUBE_CLUSTER_NODE_IPS[*]} ${LB_NODES_IP[*]})
ALL_NODE_NAMES=($KUBE_VIP_1_HOSTNAME ${KUBE_CLUSTER_NODE_NAMES[*]} ${LB_NODES_NAMES[*]})
#Flag to identify if LB nodes should also be cleaned
EXTERNAL_LB_ENABLED="true"
#Workaround for lack of DNS. Local node can ping itself but unable to SSH
echo "$CURRENT_NODE_IP"	"$CURRENT_NODE_NAME" | tee -a /etc/hosts
# Do we want to setup Rook + Ceph. Allowed values true/false
SETUP_ROOK_INSTALLED="true"
# Do we want to setup Monitoring for Cluster (Prometheus + AlertManager+Grafana). Allowed values true/false
SETUP_CLUSTER_MONITORING="true"
#Nginx Ingress setup flag. Allowed values true/false
SETUP_NGINX_INGRESS="true"
# Flag to setup Metal LB. Allowed values true/false
SETUP_METAL_LB="true" 
# Drive that is added block/raw for use by storage/Ceph. Valid values sdb, sdc etc.
CEPH_DRIVE_NAME="sdb"
# Used in the PVC config for Prometheus. Set the value in Name column from the result of the command: kubectl get sc
STORAGE_CLASS="csi-cephfs"
# Size of Prometheus PVC. Allowed value format "1Gi", "2Gi", "5Gi" etc
STORAGE_SIZE="2Gi"
#Username that we use to connect to remote machine via SSH
USERNAME="root"

#YAML/Git variables
METAL_LB_NAMESPACE=https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
METAL_LB_MANIFESTS=https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml
NGINX_LB_DEPLOY_YAML=https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/cloud/deploy.yaml
NGINX_DEPLOY_YAML=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.34.1/deploy/static/provider/baremetal/deploy.yaml
CERT_MGR_DEPLOY=https://github.com/jetstack/cert-manager/releases/download/v0.16.0/cert-manager.yaml
SELF_SIGNED_CERT_TEMPLATE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ingress/cert_self_signed.yaml
CALICO_YAML="https://docs.projectcalico.org/v3.14/manifests/calico.yaml"

KUBECTL_AVAILABLE=$(kubectl version > /dev/null 2>&1; echo $?)
MONITORING_PODS_PRESENT=$(kubectl get pods -n monitoring > /dev/null 2>&1; echo $?)
STORAGE_PODS_PRESENT=$(kubectl get pods -n rook-ceph > /dev/null 2>&1; echo $?)
if [[ $SETUP_CLUSTER_MONITORING == "true" && $MONITORING_PODS_PRESENT == 0 ]]
then
	echo "Starting monitoring components cleanup."
	wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/monitoring/cleanup_monitoring_all.sh
	chmod +x cleanup_monitoring_all.sh
	. ./cleanup_monitoring_all.sh # source the script to use the variables already set above.
	echo "Monitoring cleanup complete."
	rm -f cleanup_monitoring_all.sh
else
	echo "Skipping monitoring cleanup."
fi

if [[ $SETUP_ROOK_INSTALLED == "true" && $STORAGE_PODS_PRESENT == 0 ]]
then
	echo "Starting storage components cleanup."
	wget -q https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/storage/cleanup_rook_ceph.sh
	chmod +x cleanup_rook_ceph.sh
	. ./cleanup_rook_ceph.sh # source the script to use the variables already set above.
	echo "Storage cleanup complete."
	rm -f cleanup_rook_ceph.sh
else
	echo "Skipping Ceph+Rook cleanup."
fi

# To cleanup cert-manager
if [[ $SETUP_CERT_MANAGER == "true" && $KUBECTL_AVAILABLE == 0 ]]
	then
		if [[ -f cert_self_signed.yaml ]]
		then
			kubectl delete -f cert_self_signed.yaml
			echo "Self Signed issuer deleted."
			rm -f cert_self_signed.yaml
		else
			echo "Deleting cert_self_signed.yaml"
			wget -q $SELF_SIGNED_CERT_TEMPLATE
			kubectl delete -f cert_self_signed.yaml
			echo "Self Signed issuer deleted."
			rm -f cert_self_signed.yaml
		fi
		if [[ -f cert-manager.yaml ]]
		then
			echo "Deleting Cert Manager"	
			kubectl delete -f $CERT_MGR_DEPLOY
			echo "Cert Manager deleted."
			rm -f cert-manager.yaml
		else
			echo "Deleting cert-manager.yaml"
			kubectl delete -f $CERT_MGR_DEPLOY
			echo "Cert Manager deleted."
			rm -f cert-manager.yaml
		fi
else
	echo "Cert Manager not identified for removal."
fi

if [[ $SETUP_NGINX_INGRESS == "true" && $KUBECTL_AVAILABLE == 0 ]]
then
	if [[ -f ingress_deploy.yaml ]]
	then
		echo "Removing Nginx Ingress"
		kubectl delete -f ingress_deploy.yaml
		echo "Nginx ingress removed."
		rm -f ingress_deploy.yaml
	else
		echo "Downloading ingress_deploy.yaml"
		if [[ $SETUP_METAL_LB == "true" && $CLOUD_PROVIDED_LB == "false" ]]
		then
			echo "Downloading Nginx Ingress YAML that works with MetalLB"
			wget -q -O ingress_deploy.yaml $NGINX_LB_DEPLOY_YAML
		elif [[ $SETUP_METAL_LB == "false" && $CLOUD_PROVIDED_LB == "true" ]]
		then
			echo "Skipping cleaning up Nginx Ingress for external cloud."
		else
			echo "Cleaning Nginx Ingress YAML that works without Loadbalancer."
			wget -q -O ingress_deploy.yaml $NGINX_DEPLOY_YAML
		fi
		kubectl delete -f ingress_deploy.yaml
		echo "Nginx ingress removed."
		rm -f ingress_deploy.yaml
	fi
else
	echo "Nginx Ingress not identified for removal."
fi

if [[ $SETUP_METAL_LB == "true" && $KUBECTL_AVAILABLE == 0 ]]
then
		echo "Deleting MetalLB config via manifests."
		kubectl delete -f $METAL_LB_MANIFESTS
		echo "Deleting MetalLB namespace."
		kubectl delete -f $METAL_LB_NAMESPACE
else
	echo "MetalLB not marked for removal."
fi

if [[ $KUBECTL_AVAILABLE == 0 ]]
then
	echo "Deleting all pods."
	kubectl delete --all pods
else
	echo "Kubectl not present."
fi

#Check connectivity to all nodes
HOST_PRESENT=$(cat /etc/hosts | grep $(hostname) > /dev/null 2>&1; echo $? )
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
shutdown -r
