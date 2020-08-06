#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# ROOK Deployment script. Need to be executed from a host where we have:
#1. kubectl access
#2. sudo level access
#3. internet access to fetch files
#4. FQDN that was used by ingress

#sudo ./cleanup_monitoring_all.sh | tee cleanup_monitoring.log
#sudo ./cleanup_monitoring_all.sh |& tee cleanup_monitoring.log

echo "----------- Cleaning Prometheus + Grafana + Alertmanager  ------------"
#YAML and Git variables
KUBE_PROMETHEUS_REPO=https://github.com/coreos/kube-prometheus.git
#export MONITORING_INGRESS_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/b55c2825f7fa4491c6018bd256ef5d7e0b62404c/examples/ingress.jsonnet
PROMETHEUS_PVC_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/master/examples/prometheus-pvc.jsonnet
KP_BUILD_SH=https://raw.githubusercontent.com/coreos/kube-prometheus/master/build.sh
MONITORING_INGRESS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ingress/monitoring-dashboard-ingress-http.yaml
GRAFANA_PVC_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/monitoring/grafana_pvc.yaml

if [[ $STORAGE_CLASS == "" ]]
then
	echo "STORAGE_CLASS is not set, trying to fetch from cluster."
	#Alternate option to fetch directly
	STORAGE_CLASS=$(kubectl get storageclass -n monitoring -o json | grep -w '"name":' | xargs | cat | sed "s/,//" | awk -F " " '{print $2}')
	if [[ $STORAGE_CLASS != "" ]]
	then
		echo "Storageclass value set."
	else
		echo "Unable to set storageclass: $STORAGE_CLASS. Please set manually and rerun. "
		# Used in the PVC config for Prometheus. Set the value in Name column from the result of the command: kubectl get sc
		STORAGE_CLASS=""
		sleep 2.
		exit 1
	fi
fi

if [[ $STORAGE_SIZE == "" ]]
then
	echo "STORAGE_SIZE not set. Setting default value of 2Gi."
	# Size of Prometheus PVC. Allowed value format "1Gi", "2Gi", "5Gi" etc
	STORAGE_SIZE="2Gi"
else
	echo "STORAGE_SIZE already set. Proceeding."
fi

#github.com/coreos/kube-prometheus/jsonnet/kube-prometheus@release-0.4
KUBECTL_AVAILABLE=$(kubectl version > /dev/null 2>&1; echo $?)

cd ~
if [[ -f monitoring-dashboard-ingress-http.yaml ]]
then
	echo "Monitoring ingress yaml present."
else
	echo "Fetching monitoring ingress yaml from git hub."
	# Fetch the Ingress YAML from github repo
	wget -q $MONITORING_INGRESS_YAML -O monitoring-dashboard-ingress-http.yaml
	# Update the template with your domain name
	sed -i "s/example.com/$INGRESS_DOMAIN_NAME/g" monitoring-dashboard-ingress-http.yaml
fi

if [[ -f grafana_pvc.yaml ]]
then
	echo "Grafana PVC yaml present."
else
	echo "Fetching Grafana PVC yaml from github."
	# Fetch Grafana PVC YAML from github repo
	wget -q $GRAFANA_PVC_YAML -O monitoring-grafana_pvc.yaml
fi

if [[ $KUBECTL_AVAILABLE == 0  ]]
then
	# Delete the ingress config YAML
	kubectl delete -f monitoring-dashboard-ingress-http.yaml
	echo "Ingress deleted using YAML."
	sleep 2
	# Delete PVC for Grafana
	echo "Trying to delete Grafana PVC"
	#kubectl patch pvc -n monitoring grafana-pvc -p '{"metadata":{"finalizers":null}}'
	kubectl delete -f monitoring-grafana_pvc.yaml &
	PVC_DELETE_STUCK=$(kubectl get pvc -n monitoring grafana-pvc | grep Terminating > /dev/null 2>&1; echo $? )
	sleep 10
	if [[ $PVC_DELETE_STUCK == 0 ]]
	then
		kubectl patch pvc -n monitoring grafana-pvc -p '{"metadata":{"finalizers":null}}'
		echo "Had to use patching to fix PVC delete."
	else
		echo "PVC for Grafana deleted using YAML."
	fi
	#Go to HOME
	cd ~
	if [[ -d my-kube-prometheus ]]
	then
		echo "Deleting using existing YAML files present in my-kube-prometheus folder."
		# Got to my-kube-prometheus directory
		cd my-kube-prometheus
		# Delete monitoring configs using YAML
		kubectl delete -f manifests/
		sleep 2
		# Delete namespaces and CRDs using YAML
		kubectl delete -f manifests/setup
		echo "Done."
		sleep 2
		rm -f monitoring-build.sh monitoring-example.jsonnet
	else
		echo "Old YAML files are deleted. Run setup in dry run mode to regenrate. Exiting."
		sleep 2
		#exit
	fi
	# Fetch count of PVC used by monitoring
	TOTAL_PVC=$(kubectl get pvc -n monitoring -o json | grep -w '"name":' | wc -l)
	echo "Total PVC in use: "$TOTAL_PVC
	# Loop to get all their names
	count=0
	while [ $count -lt $TOTAL_PVC ]
	do
		PVC_NAME=$(kubectl get pvc -n monitoring -o json | grep -w '"name":' | xargs | cat | awk -F "," '{print $count}')
		kubectl delete -n monitoring pvc $PVC_NAME
		echo "Deleted PVC: $PVC_NAME"
		((count++))
	done
	echo "All PVCs deleted."
	sleep 2

else
	echo "Kubectl unavailable. Unable to delete config using monitoring-dashboard-ingress-http.yaml"
fi

# Delete binaries for jb, jsonnet and gojsontoyaml
sudo rm -f /usr/local/bin/jb
sudo rm -f /usr/local/bin/jsonnet
sudo rm -f /usr/local/bin/gojsontoyaml

cd ~
# Delete directories for Go and my-kube-prometheus
rm -Rf my-kube-prometheus go
rm -f monitoring-dashboard-ingress-http.yaml monitoring-grafana_pvc.yaml

echo "Script did not remove Go and Git. If required, please remove manually. Cleanup complete."
sleep 2
echo "----------- Cleanup complete  ------------"
# Default Grafana login admin/admin


