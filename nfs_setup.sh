#!/bin/bash
#Author: Piyush Kumar (piyushkumar.jiit@.com)

if [[ $1 == "" ]]
then 
	SHARE_DIRECTORY="docbase1"
	echo "Passed param 1 is null. Setting default value for SHARE_DIRECTORY $SHARE_DIRECTORY"
else
	SHARE_DIRECTORY="$1"
	echo "Using passed value for SHARE_DIRECTORY $SHARE_DIRECTORY"
fi

if [[ $2 == "" ]]
then 
	CLINET_IP='*'
	echo "Passed param 2 is null. Setting default value for CLINET_IP $CLINET_IP"
else
	CLINET_IP="$2"
	echo "Using passed value for CLINET_IP $CLINET_IP"
fi


if [[ $3 == "" ]]
then 
	BASE_NFS_DIRECTORY="/mnt/nfs_share"
	echo "Passed param 3 is null. Setting default value for BASE_NFS_DIRECTORY $BASE_NFS_DIRECTORY"
else
	SHARE_DIRECTORY="$3"
	echo "Using passed value for BASE_NFS_DIRECTORY $BASE_NFS_DIRECTORY"
fi

NFS_WORKING=$(systemctl status nfs-server.service > /dev/null 2>&1; echo $?)
if [[ $NFS_WORKING != 0 ]]
then
	echo "Installing nfs nfs-utils"
	#Install nfs utils
	dnf install nfs-utils -y
	#Enable the service
	systemctl enable nfs-server.service
	#Start the service
	systemctl start nfs-server.service
	#Test the status of the service
else
	echo "nfs already installed."
fi


#Create the directory to sahre over nfs
mkdir -p $BASE_NFS_DIRECTORY/$SHARE_DIRECTORY
#Update the permissions on the directory
chown -R nobody: $BASE_NFS_DIRECTORY/$SHARE_DIRECTORY
SHARE_PRESENT=$(cat /etc/exports | grep $SHARE_DIRECTORY > /dev/null 2>&1; echo $?)
if [[ $SHARE_PRESENT -gt 0 ]]
then
	echo "Share already seems to be present in exports file. Skipping adding."
else	
	#Update /etc/exports to include the directory to be exported
	#$BASE_NFS_DIRECTORY/$SHARE_DIRECTORY	*(rw,no_root_squash)
	cat <<- EOF > /etc/exports
	$BASE_NFS_DIRECTORY/$SHARE_DIRECTORY	$CLINET_IP(rw,no_root_squash)
	EOF
	echo "/etc/exports File updated."
	#Modification to /etc/exports require
	exportfs -a
	#Restart the service
	systemctl restart nfs-utils.service
fi

#Add firewall exception rule and reload
firewall-cmd --permanent --add-service mountd
firewall-cmd --permanent --add-service nfs
firewall-cmd --reload


#Client Node setup
#dnf install nfs-utils nfs4-acl-tools -y
#CURRENT_NODE="$(hostname -I | cut -d" " -f 1)"
#Mount on client machine
#echo "mount -o nfsvers=4 $CURRENT_NODE:$BASE_NFS_DIRECTORY/$SHARE_DIRECTORY /mnt/$SHARE_DIRECTORY"

echo "Script complete."
