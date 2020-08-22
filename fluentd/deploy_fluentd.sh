#!/bin/bash
# Author PiyushKumar.jiit@gmail.com
LOGGING_NAMESPACE=kube-logging
FLUENT_SVC_ACCOUNT_NAME=fluent-bit
LOGSTASH_PREFIX=fluent-logs
FLUENT_ELASTICSEARCH_HOST=elasticsearch
FLUENT_ELASTICSEARCH_PORT=9200

#FLUENTBIT_SVC_ACCOUNT=https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-service-account.yaml
#FLUENTBIT_ROLE=https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role.yaml
#FLUENTBIT_ROLE_BINDING=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_role_binding.yaml

FLUENTBIT_ACC_ROLE=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_acc_role.yaml
FLUENTBIT_CONFIG_MAP=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_config_map.yaml
FLUENTBIT_DAEMON_SET=https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/fluentd/fluentd_ds.yaml

#Create the namespace, SVC account, Role and Cluster role binding
kubectl create namespace $LOGGING_NAMESPACE
wget -q $FLUENTBIT_ACC_ROLE -O fb-acc-role.yaml
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" fb-acc-role.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-acc-role.yaml
kubectl create -f fb-acc-role.yaml

# wget -q $FLUENTBIT_SVC_ACCOUNT -o fb-svc-account.yaml
# # Change Namespace. Changing name would cause issue in role binding with OOTB yaml
# sed -i "s*name: fluent-bit*name: $FLUENT_SVC_ACCOUNT_NAME*g" fb-svc-account.yaml
# sed -i "s*namespace: logging*namespace: $LOGGING_NAMESPACE*g" fb-svc-account.yaml
# kubectl create -f fb-svc-account.yaml

# wget -q $FLUENTBIT_ROLE -o fb-role.yaml
# kubectl create -f fb-role.yaml

# wget -q $FLUENTBIT_ROLE_BINDING -o fb-role-binding.yaml
# # Change Namespace
# #sed -i "s*name: fluent-bit*name: $FLUENT_SVC_ACCOUNT_NAME*g" fb-svc-account.yaml
# sed -i "s*namespace: logging*namespace: $LOGGING_NAMESPACE*g" fb-role-binding.yaml
# kubectl create -f fb-role-binding.yaml

wget -q $FLUENTBIT_CONFIG_MAP -O fb-configmap.yaml
# Change Namespace
#sed -i "s*name: fluent-bit*name: $FLUENT_SVC_ACCOUNT_NAME*g" fb-configmap.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-configmap.yaml
sed -i "s*L0gSt@shPr3f1x*$LOGSTASH_PREFIX*g" fb-configmap.yaml
kubectl create -f fb-configmap.yaml


wget -q $FLUENTBIT_DAEMON_SET -O fb-ds.yaml
# Change Namespace
sed -i "s*SVC_@cc0unt_N@m3*$FLUENT_SVC_ACCOUNT_NAME*g" fb-ds.yaml
sed -i "s*N@m3Sp@c3*$LOGGING_NAMESPACE*g" fb-ds.yaml
sed -i "s*E1@st1cS3@rch*$FLUENT_ELASTICSEARCH_HOST*g" fb-ds.yaml
sed -i "s*El@st1cP0rt*$FLUENT_ELASTICSEARCH_PORT*g" fb-ds.yaml
kubectl create -f fb-ds.yaml
sleep 5
kubectl rollout status daemonset/fluent-bit -n kube-logging

#Clean yaml files downloaded for deployment
rm -f fb-ds.yaml fb-configmap.yaml fb-acc-role.yaml