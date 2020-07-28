#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# ROOK Deployment script. Need to be executed from a host where we have:
#1. kubectl access
#2. sudo level access
#3. internet access to fetch files
#4. FQDN that can be used by ingress

export KUBE_PROMETHEUS_REPO=https://github.com/coreos/kube-prometheus.git
#export MONITORING_INGRESS_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/b55c2825f7fa4491c6018bd256ef5d7e0b62404c/examples/ingress.jsonnet
export PROMETHEUS_PVC_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/master/examples/prometheus-pvc.jsonnet
export KP_BUILD_SH=https://raw.githubusercontent.com/coreos/kube-prometheus/master/build.sh
export MONITORING_INGRESS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ingress/monitoring-dashboard-ingress-http.yaml
export GRAFANA_PVC_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/monitoring/grafana_pvc.yaml
# Used in the PVC config for Prometheus. Set the value in Name column from the result of the command: kubectl get sc
STORAGE_CLASS=""
# Size of Prometheus PVC. Allowed value format "1Gi", "2Gi", "5Gi" etc
STORAGE_SIZE="2Gi"
# Domain name to be used by Ingress. Using this grafana URL would become: grafana.<domain.com>
INGRESS_DOMAIN_NAME=bifrost.com
# Run mode. Allowed values Deploy/DryRun
RUN_MODE=""
if [[ $STORAGE_CLASS == "" ]]
then
	echo "STORAGE_CLASS is not set, trying to fetch from cluster."
	#Alternate option to fetch directly
	STORAGE_CLASS=$(kubectl get storageclass -n monitoring -o json | grep -w '"name":' | xargs | cat | sed "s/,//" | awk -F " " '{print $2}')
	if [[ $STORAGE_CLASS != "" ]]
	then
		echo "Storageclass value set."
	else
		echo "Unable to set storageclass: $STORAGE_CLASS. Please set manually and rerun. exiting."
		sleep 2.
		exit 1
	fi
fi

if [[ $RUN_MODE == "" ]]
then
	echo "RUN_MODE not set. Defaulting to Deploy."
	RUN_MODE=Deploy
fi

# Install Git
GIT_INSTALLED=$(git version >/dev/null 2>&1; echo $?)
if [[  $GIT_INSTALLED -gt 0 ]]
then
	echo "Installing git."
	yum -y -q install git
fi
# Install Go
GO_INSTALLED=$(go version >/dev/null 2>&1; echo $?)
if [[  $GO_INSTALLED -gt 0 ]]
then
	echo "Installing go."
	yum -y -q install go
fi
sudo yum -y -q install go git
echo "Go and Git installed."
cd ~
# Install Jsonnet
JSONNET_INSTALLED=$(jsonnet -version >/dev/null 2>&1; echo $?)
if [[  $JSONNET_INSTALLED -gt 0 ]]
then
	echo "Installing jsonnet."
	go get github.com/google/go-jsonnet/cmd/jsonnet
	chmod 755 ~/go/bin/jsonnet
	sudo cp ~/go/bin/jsonnet /usr/local/bin/jsonnet
	sudo cp ~/go/bin/jsonnet /usr/bin/jsonnet
	echo "jsonnet installed."
	jsonnet -version
fi
# Install Jsonnet Bundler
JB_INSTALLED=$(jb -h >/dev/null 2>&1; echo $?)
if [[  $JB_INSTALLED -gt 0 ]]
then
	echo "Installing jb."
	go get github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
	chmod 755 ~/go/bin/jb
	sudo cp ~/go/bin/jb /usr/local/bin/jb
	sudo cp ~/go/bin/jb /usr/bin/jb
	echo "Jsonnet builder installed."
	jb -h
fi

# Install gojsonttoyaml. Used to generate files later
JSONTOYAML_INSTALLED=$(echo '{"test":"test \\nmultiple"}' | gojsontoyaml >/dev/null 2>&1; echo $?)
if [[  $JSONTOYAML_INSTALLED -gt 0 ]]
then
	echo "Installing gojsontoyaml."
	go get github.com/brancz/gojsontoyaml
	chmod 755 ~/go/bin/gojsontoyaml
	sudo cp ~/go/bin/gojsontoyaml /usr/local/bin/gojsontoyaml
	sudo cp ~/go/bin/gojsontoyaml /usr/bin/gojsontoyaml
	echo "GoJsonToYaml installed."
fi

# Go HOME
cd ~
rm -Rf ~/my-kube-prometheus
# CD to my-kube-prometheus
mkdir -p my-kube-prometheus; cd my-kube-prometheus
jb init  # Creates the initial/empty "jsonnetfile.json"
# Installs all the kube-prometheus jb dependency
jb install github.com/coreos/kube-prometheus/jsonnet/kube-prometheus@release-0.5
# Update jb
jb update
# Fetch build.sh from github repo
wget -q $KP_BUILD_SH -O monitoring-build.sh
chmod +x monitoring-build.sh
# Fetch Prometheus PVC example from github repo
wget -q $PROMETHEUS_PVC_JSONNET -O monitoring-example.jsonnet
# Update the Storage class in monitoring-example.jsonnet
sed -i "s/pvc.mixin.spec.withStorageClassName('ssd'),/pvc.mixin.spec.withStorageClassName('$STORAGE_CLASS'),/" monitoring-example.jsonnet
sed -i "s/pvc.mixin.spec.resources.withRequests({ storage: '100Gi' }/pvc.mixin.spec.resources.withRequests({ storage: '$STORAGE_SIZE' }/" monitoring-example.jsonnet

# Update Jsonnet to include extra namespaces in the cluster. Probably not needed.
# Fetch namespace jsonnet
#wget -q https://raw.githubusercontent.com/coreos/kube-prometheus/b55c2825f7fa4491c6018bd256ef5d7e0b62404c/examples/additional-namespaces.jsonnet
#wget -q https://raw.githubusercontent.com/coreos/kube-prometheus/b55c2825f7fa4491c6018bd256ef5d7e0b62404c/examples/additional-namespaces-servicemonitor.jsonnet
# Update Ingress for Prometheus, Grafana and Alertmanager. Easier to do through YAML
#wget -q $MONITORING_INGRESS_JSONNET

# Execute monitoring-build.sh
./monitoring-build.sh monitoring-example.jsonnet

# Actual deployment in cluster
if [[ $RUN_MODE == "Deploy" ]]
then
	# Create namespaces and CRDs 
	kubectl create -f manifests/setup
	# Documentation asks to wait for monitors to come up but they do not until we deploy the pods
	kubectl get servicemonitors --all-namespaces
	sleep 30
	# Updated the grafana yaml to use PVC. Not ideal way to achieve but jsonnet was too much pain.
	sed -Ez 's/emptyDir: \{\}/persistentVolumeClaim:\n          claimName: grafana-pvc/' ~/my-kube-prometheus/manifests/grafana-deployment.yaml > ~/my-kube-prometheus/manifests/grafana_deployment_updated.yaml
	rm -f ~/my-kube-prometheus/manifests/grafana-deployment.yaml
	
	# Get PVC template for Grafana from github repo and create the PVC
	wget -q $GRAFANA_PVC_YAML
	kubectl apply -f grafana_pvc.yaml

	# Apply rest of the YAMLs
	kubectl create -f manifests/

	# Fetch the Ingress YAML from github repo
	wget -q $MONITORING_INGRESS_YAML
	# Update the template with your domain name
	sed -i "s/example.com/$INGRESS_DOMAIN_NAME/g" monitoring-dashboard-ingress-http.yaml


	# Apply the ingress YAML
	kubectl apply -f monitoring-dashboard-ingress-http.yaml
	sleep 2
	rm -f monitoring-dashboard-ingress-http.yaml
	rm -f monitoring-build.sh monitoring-example.jsonnet
	cd ~
	rm -Rf go	

	echo "You can try logging in to Grafana (grafana.$INGRESS_DOMAIN_NAME), Prometheus (prometheus.$INGRESS_DOMAIN_NAME) and Alertmanager (alertmanager.$INGRESS_DOMAIN_NAME)."
	# Default Grafana login admin/admin
else
	echo "Dry Run complete."
fi

#Delete binaries copied in /usr/bin
rm -f /usr/bin/jsonnet
rm -f /usr/bin/jb
rm -f /usr/bin/gojsontoyaml

echo "All done."

