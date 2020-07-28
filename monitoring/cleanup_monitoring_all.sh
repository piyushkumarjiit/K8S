#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# ROOK Deployment script. Need to be executed from a host where we have:
#1. kubectl access
#2. sudo level access
#3. internet access to fetch files
#4. FQDN that was used by ingress

#YAML and Git variables
KUBE_PROMETHEUS_REPO=https://github.com/coreos/kube-prometheus.git
#export MONITORING_INGRESS_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/b55c2825f7fa4491c6018bd256ef5d7e0b62404c/examples/ingress.jsonnet
PROMETHEUS_PVC_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/master/examples/prometheus-pvc.jsonnet
KP_BUILD_SH=https://raw.githubusercontent.com/coreos/kube-prometheus/master/build.sh
MONITORING_INGRESS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ingress/monitoring-dashboard-ingress-http.yaml
GRAFANA_PVC_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/monitoring/grafana_pvc.yaml
# Used in the PVC config for Prometheus. Set the value in Name column from the result of the command: kubectl get sc
STORAGE_CLASS="csi-cephfs"
# Size of Prometheus PVC. Allowed value format "1Gi", "2Gi", "5Gi" etc
STORAGE_SIZE="2Gi"
# Domain name to eb sued by Ingress. Using this grafana URL would become: grafana.<domain.com>
INGRESS_DOMAIN_NAME=bifrost.com
#github.com/coreos/kube-prometheus/jsonnet/kube-prometheus@release-0.4

if [[ -f monitoring-dashboard-ingress-http.yaml ]]
then
	echo "Monitoring ingress yaml present."
else
	echo "Fetching monitoring ingress yaml from git hub."
	# Fetch the Ingress YAML from github repo
	wget -q $MONITORING_INGRESS_YAML
	# Update the template with your domain name
	sed -i "s/example.com/$INGRESS_DOMAIN_NAME/g" monitoring-dashboard-ingress-http.yaml
fi

# Delete the ingress config YAML
kubectl delete -f monitoring-dashboard-ingress-http.yaml
sleep 2
rm -f monitoring-dashboard-ingress-http.yaml
sleep 2
cd ~
if [[ -d my-kube-prometheus ]]
then
	# Got to my-kube-prometheus directory
	cd my-kube-prometheus
	# Delete monitoring configs using YAML
	kubectl delete -f manifests/
	sleep 2
else
	echo "Old YAML files are deleted. Run setup in dry run mode to regenrate. Exiting."
	sleep 2
	exit.
fi

if [[ -f grafana_pvc.yaml ]]
then
	echo "Grafana PVC yaml present."
else
	echo "Fetching Grafana PVC yaml from github."
	# Fetch Grafana PVC YAML from github repo
	wget -q $GRAFANA_PVC_YAML
	# Delete PVC for Grafana
	kubectl delete -f grafana_pvc.yaml
fi

# Delete namespaces and CRDs using YAML
kubectl delete -f manifests/setup
sleep 2

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

# Delete binaries for jb, jsonnet and gojsontoyaml
sudo rm -f /usr/local/bin/jb
sudo rm -f /usr/local/bin/jsonnet
sudo rm -f /usr/local/bin/gojsontoyaml

cd ~
# Delete directories for Go and my-kube-prometheus
rm -Rf my-kube-prometheus go

echo "Script did not remove Go and Git. If required, please remove manually. Cleanup complete."
sleep 2
# Default Grafana login admin/admin

