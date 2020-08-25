#!/bin/bash
# Author PiyushKumar.jiit@gmail.com
# This script adds fluent-bit config to a cluster.
# Elasticsearch and Kibana should be available and their details should be set in corresponding variables.

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
	echo "ELASTIC_SERVICE_PORT not set. Setting as 9200"
	ELASTIC_SERVICE_PORT=9200
else
	echo "ELASTIC_SERVICE_PORT already set. Proceeding."
fi

if [[ $LOGSTASH_PREFIX == "" ]]
then
	echo "LOGSTASH_PREFIX not set. Setting as fluent-logs."
	LOGSTASH_PREFIX='fluent-logs'
else
	echo "LOGSTASH_PREFIX already set. Proceeding."
fi

if [[ $FLUENT_SVC_ACCOUNT_NAME == "" ]]
then
	echo "FLUENT_SVC_ACCOUNT_NAME not set. Setting as fluent-bit."
	FLUENT_SVC_ACCOUNT_NAME=fluent-bit
else
	echo "FLUENT_SVC_ACCOUNT_NAME already set. Proceeding."
fi

if [[ $KIBANA_SERVICE_NAME == "" ]]
then
	echo "KIBANA_SERVICE_NAME not set. Setting as kibana."
	KIBANA_SERVICE_NAME=kibana
else
	echo "KIBANA_SERVICE_NAME already set. Proceeding."
fi

if [[ $KIBANA_URL == "" ]]
then
	echo "KIBANA_URL not set. Setting as kibana.bifrost.com."
	KIBANA_URL=kibana.bifrost.com
else
	echo "KIBANA_URL already set. Proceeding."
fi

FLUENTBIT_ACC_ROLE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentbit/fluentbit_acc_role.yaml
FLUENTBIT_CONFIG_MAP=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentbit/fluentbit_config_map.yaml
FLUENTBIT_DAEMON_SET=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentbit/fluentbit_ds.yaml

#Create the namespace
kubectl create namespace $LOGGING_NAMESPACE

wget -q $FLUENTBIT_ACC_ROLE -O fb-acc-role.yaml
# Update variables in template
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" fb-acc-role.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-acc-role.yaml
kubectl create -f fb-acc-role.yaml -n $LOGGING_NAMESPACE
echo "Service account and role created."

wget -q $FLUENTBIT_CONFIG_MAP -O fb-configmap.yaml
# Update variables in template
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-configmap.yaml
sed -i "s:L0gSt@shPr3f1x:$LOGSTASH_PREFIX:g" fb-configmap.yaml
kubectl create -f fb-configmap.yaml -n $LOGGING_NAMESPACE
echo "Config map created."

wget -q $FLUENTBIT_DAEMON_SET -O fb-ds.yaml
# Update variables in template
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" fb-ds.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-ds.yaml
sed -i "s*E1@st1cS3@rch*$ELASTIC_SERVICE_NAME*g" fb-ds.yaml
sed -i "s*El@st1cP0rt*$ELASTIC_SERVICE_PORT*g" fb-ds.yaml
kubectl create -f fb-ds.yaml -n $LOGGING_NAMESPACE
sleep 5
kubectl rollout status daemonset/fluent-bit -n $LOGGING_NAMESPACE
echo "Fluent-bit daemonset deployed."
#Clean yaml files downloaded for deployment
rm -f fb-ds.yaml fb-configmap.yaml fb-acc-role.yaml
echo "Template yaml files removed."
echo "Trying to add pattern to index-pattern in Kibana."

# Get Kibana Cluster IP
KIBANA_CLUSTER_IP=$(kubectl get svc -n $LOGGING_NAMESPACE -o wide | grep $KIBANA_SERVICE_NAME | awk -F " " '{print $3}')
echo "Kibana cluster IP: $KIBANA_CLUSTER_IP"
LOGSTASH_PREFIX='fluent-logs*'
echo -n "Kibana Service not ready. Waiting ."
CONTINUE_WAITING=$(curl -s $KIBANA_CLUSTER_IP:5601/api/saved_objects/index-pattern/my-pattern | grep -w "Saved object \[index-pattern\/my-pattern\] not found" > /dev/null 2>&1; echo $? )
#CONTINUE_WAITING=$(kubectl get pods -n cert-manager | grep cert-manager-webhook | grep Running > /dev/null 2>&1; echo $?)
while [[ $CONTINUE_WAITING != 0 ]]
do
	sleep 10
	echo -n "."
 	CONTINUE_WAITING=$(curl -s $KIBANA_CLUSTER_IP:5601/api/saved_objects/index-pattern/my-pattern | grep -w "Saved object \[index-pattern\/my-pattern\] not found" > /dev/null 2>&1; echo $? )
done
echo ""

curl -X POST $KIBANA_CLUSTER_IP:5601/api/saved_objects/index-pattern/my-pattern  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -d "
{
    \"attributes\": {
    \"title\": \"$LOGSTASH_PREFIX\"
  }
}"

echo "fluent bit deployment script complete."

