#!/bin/bash
# Author PiyushKumar.jiit@gmail.com

if [[ $LOGGING_NAMESPACE == "" ]]
then
	echo "LOGGING_NAMESPACE not set. Setting as kube-logging."
	LOGGING_NAMESPACE=kube-logging
else
	echo "LOGGING_NAMESPACE already set. Proceeding."
fi

if [[ $ELASTIC_SERVICE_NAME == "" ]]
then
	echo "ELASTIC_SERVICE_NAME not set. Setting as elasticsearch."
	ELASTIC_SERVICE_NAME=elasticsearch
else
	echo "ELASTIC_SERVICE_NAME already set. Proceeding."
fi

if [[ $ELASTIC_SERVICE_PORT == "" ]]
then
	echo "ELASTIC_SERVICE_PORT not set. Setting as 9200."
	ELASTIC_SERVICE_PORT=9200
else
	echo "ELASTIC_SERVICE_PORT already set. Proceeding."
fi

if [[ $STORAGE_CLASS_NAME == "" ]]
then
	echo "STORAGE_CLASS_NAME not set. Setting as rook-ceph-block."
	STORAGE_CLASS_NAME=rook-ceph-block
	STORAGE_CLASS=$(kubectl get storageclass -n monitoring -o json | grep -w '"name":' | xargs | cat | sed "s/,//" | awk -F " " '{print $2}')
	#Uncomment below line if you want the script to use default storage class
	#STORAGE_CLASS_NAME=$STORAGE_CLASS
else
	echo "STORAGE_CLASS_NAME already set. Proceeding."
fi

if [[ $STORAGE_SIZE == "" ]]
then
	echo "STORAGE_SIZE not set. Setting as 5Gi."
	STORAGE_SIZE=5Gi
else
	echo "STORAGE_SIZE already set. Proceeding."
fi

if [[ $KIBANA_SERVICE_NAME == "" ]]
then
	echo "KIBANA_SERVICE_NAME not set. Setting as kibana."
	KIBANA_SERVICE_NAME=kibana
else
	echo "KIBANA_SERVICE_NAME already set. Proceeding."
fi

if [[ $KIBANA_REPLICA_COUNT == "" ]]
then
	echo "KIBANA_REPLICA_COUNT not set. Setting as 1."
	KIBANA_REPLICA_COUNT=1
else
	echo "KIBANA_REPLICA_COUNT already set. Proceeding."
fi

if [[ $KIBANA_URL == "" ]]
then
	echo "KIBANA_URL not set. Setting as kibana.bifrost.com."
	KIBANA_URL=kibana.bifrost.com
else
	echo "KIBANA_URL already set. Proceeding."
fi

ELASTIC_SVC_ACC_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ElasticKibana/deploy_elastic_svc.yaml
ELASTIC_STATEFUL_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ElasticKibana/deploy_elastic_set.yaml
KIBANA_DEPLOY_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ElasticKibana/deploy_kibana.yaml
KIBANA_INGRESS_YAML=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/ElasticKibana/kibana-ingress-http.yaml

kubectl create namespace $LOGGING_NAMESPACE

# Download and update the YAMLs
wget -q $ELASTIC_SVC_ACC_YAML -O elastic_svc.yaml
sed -i "s*E1@st1cS3rv1c3N@m3*$ELASTIC_SERVICE_NAME*g" elastic_svc.yaml
sed -i "s*El@st1cP0rt*$ELASTIC_SERVICE_PORT*g" elastic_svc.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" elastic_svc.yaml

kubectl create -f elastic_svc.yaml -n $LOGGING_NAMESPACE
echo "Elastic service created."

wget -q $ELASTIC_STATEFUL_YAML -O elastic_statefulset.yaml
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" elastic_statefulset.yaml
sed -i "s*E1@st1cS3rv1c3N@m3*$ELASTIC_SERVICE_NAME*g" elastic_statefulset.yaml
sed -i "s*El@st1cP0rt*$ELASTIC_SERVICE_PORT*g" elastic_statefulset.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" elastic_statefulset.yaml
sed -i "s*St0r@g3C1@ssN@m3*$STORAGE_CLASS_NAME*g" elastic_statefulset.yaml
sed -i "s*St0r@g3S1z3*$STORAGE_SIZE*g" elastic_statefulset.yaml

kubectl create -f elastic_statefulset.yaml -n $LOGGING_NAMESPACE
echo "Elastic stateful set created."

# Wait for Elastic cluster to be ready before calling Kibana
CONTINUE_WAITING=$(kubectl get pods -n $LOGGING_NAMESPACE | grep es-cluster-0 | grep Running > /dev/null 2>&1; echo $?)
  while [[ $CONTINUE_WAITING != 0 ]]
  do
    sleep 10
    echo -n "."
    CONTINUE_WAITING=$(kubectl get pods -n $LOGGING_NAMESPACE | grep es-cluster-0 | grep Running > /dev/null 2>&1; echo $?)
  done
  echo ""
  sleep 15

wget -q $KIBANA_DEPLOY_YAML -O kibana_svc_deploy.yaml
sed -i "s*K1b@n@S3rv1c3*$KIBANA_SERVICE_NAME*g" kibana_svc_deploy.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" kibana_svc_deploy.yaml
sed -i "s*K1b@n@R3pl1c@s*$KIBANA_REPLICA_COUNT*g" kibana_svc_deploy.yaml
sed -i "s*E1@st1cS3rv1c3N@m3*$ELASTIC_SERVICE_NAME*g" kibana_svc_deploy.yaml
sed -i "s*El@st1cP0rt*$ELASTIC_SERVICE_PORT*g" kibana_svc_deploy.yaml

kubectl create -f kibana_svc_deploy.yaml -n $LOGGING_NAMESPACE
echo "Kibana deployed."

wget -q $KIBANA_INGRESS_YAML -O kibana_ingress.yaml 
sed -i "s*K1b@n@S3rv1c3*$KIBANA_SERVICE_NAME*g" kibana_ingress.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" kibana_ingress.yaml
sed -i "s*K1b@n@FQDN*$KIBANA_URL*g" kibana_ingress.yaml

kubectl create -f kibana_ingress.yaml -n $LOGGING_NAMESPACE
echo "Kibana ingress created."

#rm -f kibana_svc_deploy.yaml elastic_statefulset.yaml elastic_svc.yaml kibana_ingress.yaml

echo "Script to deploy Elasticsearch cluster with Kibana completed."