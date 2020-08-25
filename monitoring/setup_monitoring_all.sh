#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
# Monitoring setup script. Need to be executed from a host where we have:
#1. sudo + kubectl access
#2. Working kubernetes cluster
#3. Internet access to fetch files
#4. FQDN that can be used by ingress
#5. Storage already setup for use in PVC
#6. Value of storageclass to be used by PVC
#7. Size of PVC that should be requested

#sudo ./setup_monitoring_all.sh | tee setup_monitoring.log
#sudo ./setup_monitoring_all.sh |& tee setup_monitoring.log

echo "----------- Setting up Monitoring (Prometheus + Grafana + Alertmanager)  ------------"
KUBE_PROMETHEUS_REPO=https://github.com/coreos/kube-prometheus.git
#MONITORING_INGRESS_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/b55c2825f7fa4491c6018bd256ef5d7e0b62404c/examples/ingress.jsonnet
PROMETHEUS_PVC_JSONNET=https://raw.githubusercontent.com/coreos/kube-prometheus/master/examples/prometheus-pvc.jsonnet
KP_BUILD_SH=https://raw.githubusercontent.com/coreos/kube-prometheus/master/build.sh
MONITORING_INGRESS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ingress/monitoring-dashboard-ingress-http.yaml
GRAFANA_PVC_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/monitoring/grafana_pvc.yaml

if [[ $STORAGE_SIZE == "" ]]
then
	echo "STORAGE_SIZE not set. Setting default value of 2Gi."
	# Size of Prometheus PVC. Allowed value format "1Gi", "2Gi", "5Gi" etc
	STORAGE_SIZE="2Gi"
else
	echo "STORAGE_SIZE already set. Proceeding."
fi

if [[ $INGRESS_DOMAIN_NAME == "" ]]
then
	echo "INGRESS_DOMAIN_NAME not set. Setting a default value."
	# Domain name to be used by Ingress. Using this grafana URL would become: grafana.<domain>
	INGRESS_DOMAIN_NAME=bifrost.com
else
	echo "INGRESS_DOMAIN_NAME already set. Proceeding."
fi

if [[ $STORAGE_CLASS == "" ]]
then
	echo "STORAGE_CLASS is not set, trying to fetch from cluster."
	#Alternate option to fetch directly
	STORAGE_CLASS=$(kubectl get storageclass -n monitoring -o json | grep -w '"name":' | xargs | cat | sed "s/,//" | awk -F " " '{print $2}')
	if [[ $STORAGE_CLASS != "" ]]
	then
		echo "Storageclass value set."
	else
		echo "Unable to set storageclass: $STORAGE_CLASS. Setting the default value: csi-cephfs. "
		# Used in the PVC config for Prometheus. Set the value in Name column from the result of the command: kubectl get sc
		STORAGE_CLASS="csi-cephfs"
	fi
fi

# Run mode. Controls deployment of generated YAML files to cluster. Allowed values Deploy/DryRun
RUN_MODE=""

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
yum -y -q install go git
echo "Go and Git installed."
cd ~
# Install Jsonnet
JSONNET_INSTALLED=$(jsonnet -version >/dev/null 2>&1; echo $?)
if [[  $JSONNET_INSTALLED -gt 0 ]]
then
	echo "Installing jsonnet."
	go get github.com/google/go-jsonnet/cmd/jsonnet
	chmod 755 ~/go/bin/jsonnet
	cp ~/go/bin/jsonnet /usr/local/bin/jsonnet
	cp ~/go/bin/jsonnet /usr/bin/jsonnet
	JSONNET_INSTALLED=$(jsonnet -version >/dev/null 2>&1; echo $?)
	if [[  $JSONNET_INSTALLED == 0 ]]
	then
		echo "Jsonnet installed."
	else
		echo "Jsonnet installation failed."
	fi
else
	echo "JSONNET seems to be available: $JSONNET_INSTALLED "
fi
# Install Jsonnet Bundler
JB_INSTALLED=$(jb -h >/dev/null 2>&1; echo $?)
if [[  $JB_INSTALLED -gt 0 ]]
then
	echo "Installing jb."
	go get github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb
	chmod 755 ~/go/bin/jb
	cp ~/go/bin/jb /usr/local/bin/jb
	cp ~/go/bin/jb /usr/bin/jb	
	JB_INSTALLED=$(jb -h >/dev/null 2>&1; echo $?)
	if [[  $JB_INSTALLED == 0 ]]
	then
		echo "Jsonnet builder installed."
	else
		echo "Jsonnet builder installation failed."
	fi
else
	echo "JB seems to be available: $JB_INSTALLED"
fi

# Install gojsonttoyaml. Used to generate YAML files later
JSONTOYAML_INSTALLED=$(echo '{"test":"test \\nmultiple"}' | gojsontoyaml >/dev/null 2>&1; echo $?)
if [[  $JSONTOYAML_INSTALLED -gt 0 ]]
then
	echo "Installing gojsontoyaml."
	go get github.com/brancz/gojsontoyaml
	chmod 755 ~/go/bin/gojsontoyaml
	cp ~/go/bin/gojsontoyaml /usr/local/bin/gojsontoyaml
	cp ~/go/bin/gojsontoyaml /usr/bin/gojsontoyaml
	JSONTOYAML_INSTALLED=$(echo '{"test":"test \\nmultiple"}' | gojsontoyaml >/dev/null 2>&1; echo $?)
	if [[  $JSONTOYAML_INSTALLED == 0 ]]
	then
		echo "GoJsonToYaml installed."
	else
		echo "GoJsonToYaml installation failed."
	fi
else
	echo "JSONTOYAML seems to be available: $JSONTOYAML_INSTALLED"
fi

# Go HOME
cd ~
rm -Rf ~/my-kube-prometheus
# Go to my-kube-prometheus
mkdir -p my-kube-prometheus; cd my-kube-prometheus
jb init  # Creates the initial/empty "jsonnetfile.json"
# Installs all the kube-prometheus jb dependency
jb install github.com/coreos/kube-prometheus/jsonnet/kube-prometheus@release-0.5
echo "Kube-Prometheus cloned from repo."
# Update jb
jb update
echo "JB Update completed.."
# Fetch build.sh from github repo
wget -q $KP_BUILD_SH -O monitoring-build.sh
chmod +x monitoring-build.sh
echo "monitoring-build downloaded and permission updated."
# Fetch Prometheus PVC example from github repo
wget -q $PROMETHEUS_PVC_JSONNET -O monitoring-example.jsonnet
# To fix the temporary bug
sed -i "s/'{{ \$labels.device }}'/{{ \$labels.device }}/g" $HOME/my-kube-prometheus/vendor/github.com/prometheus/node_exporter/docs/node-mixin/alerts/alerts.libsonnet
# Update the Storage class in monitoring-example.jsonnet
sed -i "s/pvc.mixin.spec.withStorageClassName('ssd'),/pvc.mixin.spec.withStorageClassName('$STORAGE_CLASS'),/" monitoring-example.jsonnet
sed -i "s/pvc.mixin.spec.resources.withRequests({ storage: '100Gi' }/pvc.mixin.spec.resources.withRequests({ storage: '$STORAGE_SIZE' }/" monitoring-example.jsonnet
echo "PROMETHEUS_PVC_JSONNET downloaded and PVC config updated."

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
	
	echo "Setup ingress for monitoring dashboards."
	# Fetch the Ingress YAML from github repo
	wget -q $MONITORING_INGRESS_YAML
	# Update the template with your domain name
	sed -i "s/example.com/$INGRESS_DOMAIN_NAME/g" monitoring-dashboard-ingress-http.yaml
	# Apply the ingress YAML
	kubectl apply -f monitoring-dashboard-ingress-http.yaml
	echo "Ingress setup."
	sleep 2
	rm -f monitoring-dashboard-ingress-http.yaml
	rm -f monitoring-build.sh monitoring-example.jsonnet
	cd ~
	#rm -Rf go	
	CONTINUE_WAITING=$(kubectl get pods -n monitoring | grep grafana | grep Running > /dev/null 2>&1; echo $?)
	echo -n "Monitoring pods not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 20
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get pods -n monitoring | grep grafana | grep Running > /dev/null 2>&1; echo $?)
	done
	echo ""

	echo "You can try logging in to Grafana (grafana.$INGRESS_DOMAIN_NAME), Prometheus (prometheus.$INGRESS_DOMAIN_NAME) and Alertmanager (alertmanager.$INGRESS_DOMAIN_NAME)."
	# Default Grafana login admin/admin
else
	echo "Dry Run complete."
fi

#Delete binaries copied in /usr/bin or /usr/local/bin
rm -f /usr/bin/jsonnet
rm -f /usr/local/bin/jsonnet
rm -f /usr/bin/jb
rm -f /usr/local/bin/jb
rm -f /usr/bin/gojsontoyaml
rm -f /usr/local/bin/gojsontoyaml

echo "----------- Monitoring setup (Prometheus + Grafana + Alertmanager) complete  ------------ "
