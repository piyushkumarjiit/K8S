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

GRAYLOG_ADMIN="graylogadmin"
GRAYLOG_PASSWORD="Testing123"
GRAYLOG_PASSWORD_SHA="Testing123"






# Check if Helm is present
HELM_PRESENT=$(helm version > /dev/null 2>&1; echo $?)
if [[ $HELM_PRESENT == 0 ]]
then
	# Add Default Helm repo
	helm repo add stable https://kubernetes-charts.storage.googleapis.com/
	# Add Bitname Helm repo
	helm repo add bitnami https://charts.bitnami.com/bitnami
	# Add Elastic Helm repo
	#helm repo add elastic https://helm.elastic.co
	# Call helm update to sync charts
	helm repo update

	#Create namesapce
	kubectl create ns $MONGO_NAMESPACE
	# Create MongoDB secret
	apiVersion: v1
	kind: Secret
	metadata:
	  name: mongodb_secret_uri
	type: Opaque
	data:
		MONGODB_URI: mongodb://mongoadmin:Testing123@d2lsdev-mg-mongodb-0.d2lsdev-mg-mongodb-headless.logging.svc.cluster.local:27017/graylog


	
	# --set graylog.ingress.hosts=graylog.bifrost.com \
	# 	--set graylog.ingress.enabled=true \
	#--set graylog.ingress.hosts={'graylog.bifrost.com'} \
	# # Corret MongoDB URI shoule be: mongodb://{USERNAME}:{PASSWORD}@{HOSTNAME}:{PORT}/{DATABASE}
	# --set graylog.mongodb.uri=mongodb://mongodb-mongodb-replicaset-0.mongodb-mongodb-replicaset.graylog.svc.cluster.local:27017/graylog?replicaSet=rs0 \
	# Create graylog namespace
	kubectl create namespace $GRAYLOG_NAMESPACE
	# Install Graylog chart
	helm template "$RELEASE_NAME" stable/graylog --namespace $GRAYLOG_NAMESPACE \
	--set graylog.persistence.enabled=true \
	--set graylog.service.type="LoadBalancer" \
	--set graylog.persistence.storageClass=$PERSISTENCE_STORAGECLASS \
	--set graylog.persistence.accessMode=ReadWriteOnce \
	--set graylog.persistence.size=$PERSISTENCE_STORAGE_SIZE \
	--set graylog.metrics.enabled=$METRICS_ENABLED \
	--set graylog.ingress.enabled=true \
	--set graylog.ingress.hosts={$GRAYLOG_EXTERNAL_URL} \
	--set tags.install-mongodb=true \
	--set tags.install-elasticsearch=true > graylog.yaml


	# Download Graylog Template file from github
	wget -q "" -O deploy_graylog_stack.yaml

	sed -i "s*St0r3@g3C1@ss*$PERSISTENCE_STORAGECLASS*g" deploy_graylog_stack.yaml
	sed -i "s*R31E@S3*$RELEASE_NAME*g" deploy_graylog_stack.yaml
	sed -i "s*M0ng0DBSt0r@g3S1z3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	sed -i "s*E1@st1cD@t@St0r@g3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	sed -i "s*E1@st1cM@st3rSt0r@g3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	sed -i "s*Gr@yL0gStor@g3*$PERSISTENCE_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	sed -i "s*Ingr3ssH0stN@m3*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml
	sed -i "s*Gr@yL0gR00tUs3rN@m3*$GRAYLOG_ADMIN*g" deploy_graylog_stack.yaml
	sed -i "s*Gr@yL0gP@ssw0rdS3cr3t*$GRAYLOG_PASSWORD*g" deploy_graylog_stack.yaml
	sed -i "s*Gr@yL0gP@ssw0rdSh@*$GRAYLOG_PASSWORD_SHA*g" deploy_graylog_stack.yaml
	sed -i "s*Gr@ylogExt3rn@lUR1*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml
	sed -i "s*Gr@yL0gEmailWebInterfaceURl*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml







kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo
kubectl -n logging get secret d2lsdev-gl-graylog -o jsonpath="{['data']['graylog-password-secret']}" | base64 --decode && echo

# Get Graylog admin password
ADMIN_PASSWD=$(kubectl -n $GRAYLOG_NAMESPACE get secret "$RELEASE_NAME-graylog" -o jsonpath="{['data']['graylog-password-secret']}" | base64 --decode && echo)

echo "Login to Graylog using admin/$ADMIN_PASSWD"



else
	echo "Please install Helm before proceeding. Unable to proceed. Exiting."
	sleep 2
	exit 1
fi

# To check if everythign works
helm status "graylog"

# To delete everything
#helm delete --purge "graylog"
