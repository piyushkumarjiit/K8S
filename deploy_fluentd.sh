#!/bin/bash
# Author PiyushKumar.jiit@gmail.com
LOGGING_NAMESPACE=kube-logging
SVC_ACCOUNT_NAME=fluent-bit

FLUENTBIT_SVC_ACCOUNT=https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-service-account.yaml
FLUENTBIT_ROLE=https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role.yaml
FLUENTBIT_ROLE_BINDING=https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role-binding.yaml
FLUENTBIT_CONFIG_MAP=https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-configmap.yaml

kubectl create namespace logging

wget -q $FLUENTBIT_SVC_ACCOUNT -o fb-svc-account.yaml
# Change Namespace. Changing name would cause issue in role binding with OOTB yaml
#sed -i "s*name: fluent-bit*name: $SVC_ACCOUNT_NAME*g" fb-svc-account.yaml
sed -i "s*namespace: logging*namespace: $LOGGING_NAMESPACE*g" fb-svc-account.yaml
kubectl create -f fb-svc-account.yaml

wget -q $FLUENTBIT_ROLE -o fb-role.yaml
kubectl create -f fb-role.yaml

wget -q $FLUENTBIT_ROLE_BINDING -o fb-role-binding.yaml
# Change Namespace
#sed -i "s*name: fluent-bit*name: $SVC_ACCOUNT_NAME*g" fb-svc-account.yaml
sed -i "s*namespace: logging*namespace: $LOGGING_NAMESPACE*g" fb-role-binding.yaml
kubectl create -f fb-role-binding.yaml

wget -q $FLUENTBIT_CONFIG_MAP -o fb-configmap.yaml
# Change Namespace
#sed -i "s*name: fluent-bit*name: $SVC_ACCOUNT_NAME*g" fb-configmap.yaml
sed -i "s*namespace: logging*namespace: $LOGGING_NAMESPACE*g" fb-configmap.yaml
kubectl create -f fb-configmap.yaml

