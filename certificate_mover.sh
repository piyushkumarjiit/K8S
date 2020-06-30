#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
if [[ -z ${USERNAME} ]]
then
	#Set the home directory in target server for scp
	if [[ "$USERNAME" == "root" ]]
	then
		TARGET_DIR="/root"
	else
		TARGET_DIR="/home/$USERNAME"
	fi
	echo "Moving certificates from $HOME to respective locations."
	mkdir -p /etc/kubernetes/pki/etcd
	mv $TARGET_DIR/ca.crt /etc/kubernetes/pki/
	mv $TARGET_DIR/ca.key /etc/kubernetes/pki/
	mv $TARGET_DIR/sa.pub /etc/kubernetes/pki/
	mv $TARGET_DIR/sa.key /etc/kubernetes/pki/
	mv $TARGET_DIR/front-proxy-ca.crt /etc/kubernetes/pki/
	mv $TARGET_DIR/front-proxy-ca.key /etc/kubernetes/pki/
	mv $TARGET_DIR/etcd-ca.crt /etc/kubernetes/pki/etcd/ca.crt
	# Quote this line if you are using external etcd
	mv $TARGET_DIR/etcd-ca.key /etc/kubernetes/pki/etcd/ca.key
	echo "Certificates moved."
else
	echo "USERNAME not defined. Exiting."
	exit 1
fi