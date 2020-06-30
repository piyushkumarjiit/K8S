#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)
if [[ -z ${USER} ]]
then
	echo "Moving certificates from $HOME to respective locations."
	mkdir -p /etc/kubernetes/pki/etcd
	mv /home/${USER}/ca.crt /etc/kubernetes/pki/
	mv /home/${USER}/ca.key /etc/kubernetes/pki/
	mv /home/${USER}/sa.pub /etc/kubernetes/pki/
	mv /home/${USER}/sa.key /etc/kubernetes/pki/
	mv /home/${USER}/front-proxy-ca.crt /etc/kubernetes/pki/
	mv /home/${USER}/front-proxy-ca.key /etc/kubernetes/pki/
	mv /home/${USER}/etcd-ca.crt /etc/kubernetes/pki/etcd/ca.crt
	# Quote this line if you are using external etcd
	mv /home/${USER}/etcd-ca.key /etc/kubernetes/pki/etcd/ca.key
	echo "Certificates moved."
else
	echo "USER not defined. Exiting."
	exit 1
fi