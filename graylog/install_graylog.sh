#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@gmail.com)

# Graylog Chart values
GRAYLOG_NAMESPACE=logging
RELEASE_NAME="d2lsdev"
GRAYLOG_EXTERNAL_URL='graylog.bifrost.com'
#PERSISTENCE_STORAGECLASS="csi-cephfs"
PERSISTENCE_STORAGECLASS="rook-ceph-block"
PERSISTENCE_STORAGE_SIZE=5Gi
PERSISTENCE_ACCESS_MODE=ReadWriteOnce
METRICS_ENABLED=true
REPLICA_COUNT=3

GRAYLOG_ADMIN="admin"
GRAYLOG_PASSWORD="ChangeMe123"
GRAYLOG_PASSWORD_SHA="$(echo -n $GRAYLOG_PASSWORD | sha256sum)"

GRAYLOG_YAML="https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/graylog/graylog_template.yaml"


if [[ $GRAYLOG_PASSWORD == "ChangeMe123" ]]
then
	echo "Using default GRAYLOG_PASSWORD. Please update and rerun the script. Exiting."
	sleep 2
	exit 1
else
	echo "Not using default GRAYLOG_PASSWORD. Proceeding."
fi

# Check if Helm is present
HELM_PRESENT=$(helm version > /dev/null 2>&1; echo $?)
if [[ $HELM_PRESENT == 0 ]]
then
	# Add Default Helm repo
	echo "Adding default repo"
	helm repo add stable https://kubernetes-charts.storage.googleapis.com/

	# Add Bitname Helm repo
	echo "Adding Bitnami repo"
	helm repo add bitnami https://charts.bitnami.com/bitnami
	# Add Elastic Helm repo
	#helm repo add elastic https://helm.elastic.co
	# Call helm update to sync charts
	echo "Calling help repo update."
	helm repo update

	#Create namesapce
	echo "Creating namesapce"
	kubectl create namespace $GRAYLOG_NAMESPACE
	# # Use Templating to generate YAML for Graylog stack. Or download directly from github.
	# helm template "$RELEASE_NAME" stable/graylog --namespace $GRAYLOG_NAMESPACE \
	# --set graylog.persistence.enabled=true \
	# --set graylog.service.type="LoadBalancer" \
	# --set graylog.persistence.storageClass=$PERSISTENCE_STORAGECLASS \
	# --set graylog.persistence.accessMode=ReadWriteOnce \
	# --set graylog.persistence.size=$PERSISTENCE_STORAGE_SIZE \
	# --set graylog.metrics.enabled=$METRICS_ENABLED \
	# --set graylog.ingress.enabled=true \
	# --set graylog.ingress.hosts={$GRAYLOG_EXTERNAL_URL} \
	# --set tags.install-mongodb=true \
	# --set tags.install-elasticsearch=true > graylog.yaml

	cd ~
	if [[ -f deploy_graylog_stack.yaml ]]
	then
		echo "deploy_graylog_stack.yaml already present. Will use the file as is."
	else
		echo "Downloading deploy_graylog_stack.yaml"
		# Download Graylog Template file from github
		wget -q $GRAYLOG_YAML -O deploy_graylog_stack.yaml
		# Update StorgeClass used for peristence
		sed -i "s*St0r3@g3C1@ss*$PERSISTENCE_STORAGECLASS*g" deploy_graylog_stack.yaml
		# Update ReleaseName
		sed -i "s*R31E@S3*$RELEASE_NAME*g" deploy_graylog_stack.yaml
		# Update Storage size for MongoDB
		sed -i "s*M0ng0DBSt0r@g3S1z3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
		# Update Storage size for Elastic Data node
		sed -i "s*E1@st1cD@t@St0r@g3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
		# Update Storage size for Elastic Master node
		sed -i "s*E1@st1cM@st3rSt0r@g3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
		# Update Storage size for Graylog
		sed -i "s*Gr@yL0gStor@g3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
		# Update External URL used by Graylog. Not used.
		sed -i "s*Ingr3ssH0stN@m3*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml
		# Update Graylog Admin user name. Default is admin
		sed -i "s*Gr@yL0gR00tUs3rN@m3*$GRAYLOG_ADMIN*g" deploy_graylog_stack.yaml
		# Update Graylog Admin Password
		sed -i "s*Gr@yL0gP@ssw0rdS3cr3t*$GRAYLOG_PASSWORD*g" deploy_graylog_stack.yaml
		# Update Graylog Admin Password SHA
		sed -i "s*Gr@yL0gP@ssw0rdSh@*$GRAYLOG_PASSWORD_SHA*g" deploy_graylog_stack.yaml
		# Update External URL used by Graylog. Not used.
		sed -i "s*Gr@ylogExt3rn@lUR1*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml
		# Update External URL used by Graylog. Not used.
		sed -i "s*Gr@yL0gEmailWebInterfaceURl*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml

		echo "Completed updating the yaml file."
	fi

	# Deploy Graylog
	kubectl apply -f deploy_graylog_stack.yaml
	CONTINUE_WAITING=$(kubectl get pods -n $GRAYLOG_NAMESPACE | grep web | grep Running > /dev/null 2>&1; echo $?)
	echo -n "Graylog cluster not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 10
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get pods -n $GRAYLOG_NAMESPACE | grep web | grep Running > /dev/null 2>&1; echo $?)
	done
	echo ""

	# Get Graylog admin password
	ADMIN_PASSWD=$(kubectl -n $GRAYLOG_NAMESPACE get secret "$RELEASE_NAME-graylog" -o jsonpath="{['data']['graylog-password-secret']}" | base64 --decode && echo)

	echo "Login to Graylog using admin/$ADMIN_PASSWD"

else
	echo "Please install Helm before proceeding. Unable to proceed. Exiting."
	sleep 2
	exit 1
fi

# To check if everythign works
#helm status "graylog"

# To delete everything
#helm delete --purge "graylog"