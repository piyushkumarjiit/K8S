#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@gmail.com)


if [[ $GRAYLOG_NAMESPACE == "" ]]
then
	echo "GRAYLOG_NAMESPACE not set. Using default value: graylog"
	GRAYLOG_NAMESPACE=graylog
else
	echo "GRAYLOG_NAMESPACE already set as $GRAYLOG_NAMESPACE. Proceeding."
fi

if [[ $RELEASE_NAME == "" ]]
then
	echo "RELEASE_NAME not set. Using default value: d2lsdev."
	RELEASE_NAME="d2lsdev"
else
	echo "RELEASE_NAME already set as $RELEASE_NAME. Proceeding."
fi

if [[ $INGRESS_HOST_NAME == "" ]]
then
	echo "INGRESS_HOST_NAME not set. Using default value: k8smagic.com."
	INGRESS_HOST_NAME="graylog.bifrost.com"
else
	echo "INGRESS_HOST_NAME already set as $INGRESS_HOST_NAME. Proceeding."
fi

if [[ $GRAYLOG_EXTERNAL_URL == "" ]]
then
	echo "GRAYLOG_EXTERNAL_URL not set. Using default value: http://graylog.bifrost.com:9000."
	#GRAYLOG_EXTERNAL_URL='http://192.168.2.191:9000'
	GRAYLOG_EXTERNAL_URL='http://graylog.bifrost.com:9000'
else
	echo "GRAYLOG_EXTERNAL_URL already set as $GRAYLOG_EXTERNAL_URL. Proceeding."
fi

if [[ $PERSISTENCE_STORAGECLASS == "" ]]
then
	echo "PERSISTENCE_STORAGECLASS not set. Using default value: rook-ceph-block."
	PERSISTENCE_STORAGECLASS="rook-ceph-block"
else
	echo "PERSISTENCE_STORAGECLASS already set. Proceeding."
fi

if [[ $PERSISTENCE_STORAGE_SIZE == "" ]]
then
	echo "PERSISTENCE_STORAGE_SIZE not set. Using default value: 5Gi."
	PERSISTENCE_STORAGE_SIZE=5Gi
else
	echo "PERSISTENCE_STORAGE_SIZE already set. Proceeding."
fi

if [[ $REPLICA_COUNT == "" ]]
then
	echo "REPLICA_COUNT not set. Using default value: 3."
	REPLICA_COUNT=3
else
	echo "REPLICA_COUNT already set. Proceeding."
fi

# Graylog YAML/Chart values
PERSISTENCE_ACCESS_MODE=ReadWriteOnce
MONGO_STORAGE_SIZE=$PERSISTENCE_STORAGE_SIZE
ELASTIC_DATA_STORAGE_SIZE=$PERSISTENCE_STORAGE_SIZE
ELASTIC_MASTERSTORAGE_SIZE=$PERSISTENCE_STORAGE_SIZE
GRAYLOG_STORAGE_SIZE=$PERSISTENCE_STORAGE_SIZE

REPLICA_COUNT=3
ELASTIC_CLIENT_REPLICAS=2
ELASTIC_DATA_REPLICAS=$REPLICA_COUNT
ELASTIC_MASTER_SET_REPLICAS=2
MONGO_MASTER_SET_REPLICAS=$REPLICA_COUNT
GRAYLOG_MASTER_SET_REPLICAS=2

#GRAYLOG_ADMIN="admin"
#Minimum 16 characters
#GRAYLOG_PASSWORD="ChangeMe123456789"


GRAYLOG_YAML="https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/graylog/graylog_template.yaml"

if [[ $GRAYLOG_PASSWORD == "ChangeMe123456789" ]]
then
	echo "Using default GRAYLOG_PASSWORD. Please update and rerun the script. Exiting."
	sleep 2
	exit 1
else
	echo "Not using default GRAYLOG_PASSWORD. Proceeding."
fi

#Create namesapce
echo "Creating namesapce"
kubectl create namespace $GRAYLOG_NAMESPACE

# Generate Base 64 encoded string for credentials
GRAYLOG_ADMIN_SECRET=$(echo -n "$GRAYLOG_ADMIN" | base64 | tr -dc '[:print:]')
GRAYLOG_PASSWORD_SECRET=$(echo -n "$GRAYLOG_PASSWORD" | base64 | tr -dc '[:print:]')
GRAYLOG_PASSWD_SHA=$(echo -n "$GRAYLOG_PASSWORD" | sha256sum | awk -F " " '{print $1}' | tr -dc '[:print:]'| base64 | tr -dc '[:print:]' )

cd ~
if [[ -f deploy_graylog_stack.yaml ]]
then
	echo "deploy_graylog_stack.yaml already present. Will use the file as is."
	# Wait for Graylog cluster to be ready
	kubectl apply -f deploy_graylog_stack.yaml -n $GRAYLOG_NAMESPACE
	CONTINUE_WAITING=$(kubectl get pods -n graylog | grep graylog-0 | grep Running | grep 1/1 > /dev/null 2>&1; echo $?)
	echo -n "Graylog cluster not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 10
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get pods -n graylog | grep graylog-0 | grep Running | grep 1/1 > /dev/null 2>&1; echo $?)
	done
	echo ""
	# Get Graylog SVC
	GRAYLOG_EXT_IP=$(kubectl get svc -n graylog | grep d2lsdev-graylog-web | awk -F " " '{print $4}')
	# Get Graylog admin password
	ADMIN_PASSWD=$(kubectl -n $GRAYLOG_NAMESPACE get secret "$RELEASE_NAME-graylog" -o jsonpath="{['data']['graylog-password-secret']}" | base64 --decode && echo)
	echo "Login to Graylog ($GRAYLOG_EXT_IP) using admin/$ADMIN_PASSWD"

else
	echo "Downloading deploy_graylog_stack.yaml"
	# Download Graylog Template file from github
	wget -q $GRAYLOG_YAML -O deploy_graylog_stack.yaml

	# Update Namespace
	sed -i "s*N@m3Sp@c3*$GRAYLOG_NAMESPACE*g" deploy_graylog_stack.yaml
	# Update Elastic Client Replica count
	sed -i "s*e1@st1cC1i3ntR3p1ic@*$ELASTIC_CLIENT_REPLICAS*g" deploy_graylog_stack.yaml
	# Update Elastic Data Replica count
	sed -i "s*e1@st1cD@t@R3p1ic@*$ELASTIC_DATA_REPLICAS*g" deploy_graylog_stack.yaml
	# Update ElasticSearch Master stateful Replica count
	sed -i "s*e1@st1cM@st3rR3p1ic@*$ELASTIC_MASTER_SET_REPLICAS*g" deploy_graylog_stack.yaml
	# Update MongoDB Master stateful Replica count
	sed -i "s*M0ng0M@st3rR3p1ic@*$MONGO_MASTER_SET_REPLICAS*g" deploy_graylog_stack.yaml
	# Update Graylog Master stateful Replica count
	sed -i "s*Gr@yL0gM@st3rR3p1ic@*$GRAYLOG_MASTER_SET_REPLICAS*g" deploy_graylog_stack.yaml
	# Update StorgeClass used for peristence
	sed -i "s*St0r3@g3C1@ss*$PERSISTENCE_STORAGECLASS*g" deploy_graylog_stack.yaml
	# Update ReleaseName
	sed -i "s*R31E@S3*$RELEASE_NAME*g" deploy_graylog_stack.yaml
	# Update Storage size for MongoDB
	sed -i "s*M0ng0DBSt0r@g3S1z3*$MONGO_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	# Update Storage size for Elastic Data node
	sed -i "s*E1@st1cD@t@St0r@g3*$ELASTIC_DATA_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	# Update Storage size for Elastic Master node
	sed -i "s*E1@st1cM@st3rSt0r@g3*$ELASTIC_MASTERSTORAGE_SIZE*g" deploy_graylog_stack.yaml
	# Update Storage size for Graylog
	sed -i "s*Gr@yL0gStor@g3*$GRAYLOG_STORAGE_SIZE*g" deploy_graylog_stack.yaml
	# Update External URL used by Graylog. Not used.
	#sed -i "s*Ingr3ssH0stN@m3*$INGRESS_HOST_NAME*g" deploy_graylog_stack.yaml
	# Update Graylog Admin user name. Default is admin
	sed -i "s*Gr@yL0gR00tUs3rN@m3*$GRAYLOG_ADMIN_SECRET*g" deploy_graylog_stack.yaml
	# Update Graylog Admin Password
	sed -i "s*Gr@yL0gP@ssw0rdS3cr3t*$GRAYLOG_PASSWORD_SECRET*g" deploy_graylog_stack.yaml
	# Update Graylog Admin Password SHA
	sed -i "s*Gr@yL0gP@ssw0rdSh@*$GRAYLOG_PASSWD_SHA*g" deploy_graylog_stack.yaml
	# Update External URL used by Graylog. Not used.
	sed -i "s*Gr@ylogExt3rn@lUR1*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml
	# Update External URL used by Graylog. Not used.
	sed -i "s*Gr@yL0gEmailWebInterfaceURl*$GRAYLOG_EXTERNAL_URL*g" deploy_graylog_stack.yaml

	echo "Completed updating the yaml file."

	# Wait for Graylog cluster to be ready
	kubectl apply -f deploy_graylog_stack.yaml -n $GRAYLOG_NAMESPACE
	CONTINUE_WAITING=$(kubectl get pods -n graylog | grep graylog-0 | grep Running | grep 1/1 > /dev/null 2>&1; echo $?)
	echo -n "Graylog cluster not ready. Waiting ."
	while [[ $CONTINUE_WAITING != 0 ]]
	do
		sleep 10
		echo -n "."
	 	CONTINUE_WAITING=$(kubectl get pods -n graylog | grep graylog-0 | grep Running | grep 1/1 > /dev/null 2>&1; echo $?)
	done
	echo ""
	# Get Graylog SVC
	GRAYLOG_EXT_IP=$(kubectl get svc -n graylog | grep d2lsdev-graylog-web | awk -F " " '{print $4}')
	# Get Graylog admin password
	ADMIN_PASSWD=$(kubectl -n $GRAYLOG_NAMESPACE get secret "$RELEASE_NAME-graylog" -o jsonpath="{['data']['graylog-password-secret']}" | base64 --decode && echo)

	echo "Login to Graylog ($GRAYLOG_EXT_IP) using admin/$ADMIN_PASSWD"
fi

echo "Install Graylog script Completed."