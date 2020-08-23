#!/bin/bash
# Author PiyushKumar.jiit@gmail.com


if [[ $LOGGING_NAMESPACE == "" ]]
then
	echo "LOGGING_NAMESPACE not set. Setting as kube-logging."
	LOGGING_NAMESPACE=kube-logging
else
	echo "LOGGING_NAMESPACE already set. Proceeding."
fi

if [[ $FLUENT_ELASTICSEARCH_HOST == "" ]]
then
	echo "FLUENT_ELASTICSEARCH_HOST not set. Setting as elasticsearch."
	FLUENT_ELASTICSEARCH_HOST=elasticsearch
else
	echo "FLUENT_ELASTICSEARCH_HOST already set. Proceeding."
fi

if [[ $FLUENT_ELASTICSEARCH_PORT == "" ]]
then
	echo "FLUENT_ELASTICSEARCH_PORT not set. Setting as 9200"
	FLUENT_ELASTICSEARCH_PORT=9200
else
	echo "FLUENT_ELASTICSEARCH_PORT already set. Proceeding."
fi

if [[ $LOGSTASH_PREFIX == "" ]]
then
	echo "LOGSTASH_PREFIX not set. Setting as fluent-logs."
	LOGSTASH_PREFIX=fluent-logs
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

if [[ $KIBANA_URL == "" ]]
then
	echo "KIBANA_URL not set. Setting as kibana.bifrost.com."
	KIBANA_URL=kibana.bifrost.com
else
	echo "KIBANA_URL already set. Proceeding."
fi

FLUENTBIT_ACC_ROLE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_acc_role.yaml
FLUENTBIT_CONFIG_MAP=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_config_map.yaml
FLUENTBIT_DAEMON_SET=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_ds.yaml

#Create the namespace
kubectl create namespace $LOGGING_NAMESPACE

wget -q $FLUENTBIT_ACC_ROLE -O fb-acc-role.yaml
# Update variables in template
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" fb-acc-role.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-acc-role.yaml
kubectl create -f fb-acc-role.yaml -n $LOGGING_NAMESPACE

wget -q $FLUENTBIT_CONFIG_MAP -O fb-configmap.yaml
# Update variables in template
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-configmap.yaml
sed -i "s*L0gSt@shPr3f1x*$LOGSTASH_PREFIX*g" fb-configmap.yaml
kubectl create -f fb-configmap.yaml -n $LOGGING_NAMESPACE

wget -q $FLUENTBIT_DAEMON_SET -O fb-ds.yaml
# Update variables in template
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" fb-ds.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-ds.yaml
sed -i "s*E1@st1cS3@rch*$FLUENT_ELASTICSEARCH_HOST*g" fb-ds.yaml
sed -i "s*El@st1cP0rt*$FLUENT_ELASTICSEARCH_PORT*g" fb-ds.yaml
kubectl create -f fb-ds.yaml -n $LOGGING_NAMESPACE
sleep 5
kubectl rollout status daemonset/fluent-bit -n $LOGGING_NAMESPACE

#Clean yaml files downloaded for deployment
rm -f fb-ds.yaml fb-configmap.yaml fb-acc-role.yaml


echo "Trying to add pattern to index-pattern in Kibana."

echo "Curling:"
echo '
{
  "attributes": {
    "title": "$LOGSTASH_PREFIX"
  }
}'

# curl -X POST $KIBANA_URL:5601/api/saved_objects/index-pattern/my-pattern  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' -d '
# {
#   "attributes": {
#     "title": "$LOGSTASH_PREFIX"
#   }
# }'


echo "fluent bit deployment script complete."