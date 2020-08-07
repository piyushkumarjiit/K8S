# K8S

This script is not for Prod rather a streamlined way to setup Kubernetes cluster in homelab (or other non critical environments). Although it does support multiple stacked control planes and follows certain HA principles specified in Kubernetes documentation, use it at your own risk.
When I started learning Kubernetes setting up the cluster was a task in itself. So I created this for my homelab and sharing in hope that it would enable others to set things up quicker.
The script currently supports CentOS7 and CentOS 8 and I tested these 2 in my homelab. I was able to mix and match nodes without any issue.

## Getting Started
Please set up public key based SSH access to all nodes (provisioned VMs) we are planning to use and connect to those nodes atleast ones via SSH. This would minimize the number of prompts (only 2 prompts) you would get during script execution.
Get block of available IP address from your local router. In case of DD-WRT based router, connect to the router via SSH and run <code> cat /var/lib/misc/dnsmasq.leases </code> to get a list of IP in use. As always I would recommend key based SSH for router as well.
Also make sure that raw/block drive is attached to worker nodes for Ceph to format and use.


### What all the script installs:
<li>KeepAlived</li>
<li>HAProxy</li>
<li></li>
<li>Docker + Containerd</li>
<li>Kubelet, Kubeadm, Kubectl</li>
<li>MetalLB</li>
<li>Nginx Ingress Controller</li>
<li>Rook + Ceph</li>
<li>Prometheus</li>
<li>AlertManager</li>
<li>Grafana with presets using mixins</li>
<li>CertManager</li>

### What all the script does:
<li>Takes care of all dependencies for all components involved (modprobes, firewalld, selinux, swap, DNS, IP Forwarding, CRI-O, Docker etc.)</li>
<li>Install and sets up KeepAlived + HAProxy for use by control plane</li>
<li>Install things that are needed by cluster (kubelet, kubeadm, kubectl)</li>
<li>Sets up Primary control plane and initializes the cluster</li>
<li>Adds all masters to the cluster</li>
<li>Adds all workers to the cluster</li>
<li>Deploys MetalLB to act as external load balancer</li>
<li>Deploys Nginx Ingress controller</li>
<li>Prepare worker nodes for Rook+ Ceph setup (NTP/Chronyd, detect presence of block/raw drive etc.)</li>
<li>Deploys Rook + Ceph for storage</li>
<li>Sets up Rook dashboard for storage monitoring</li>
<li>Installs Go, Git, jsonnet, jb and gojsontoyaml for use by Kube-Prometheus</li>
<li>Uses Kube-Prometheus to configure and deploy Prometheus + AlertManager + Grafana </li>
<li>Sets up Dashboards for Prometheus + AlertManager + Grafana </li>


If something is not clear on this ReadMe, I would recommend to download the script and take a look as I have added comments to make it easy for others to understand and customize as needed.



## Prerequisites
The script is relatively self contained and fetches necessary files from github repo. To execute the script successfully we need:

<li>Access to Internet</li>
<li>Provisioned VMs that would serve as Nodes</li>
<li>Names and IPs of Load balancer nodes (to be used by KeepAlived and HAProxy)</li>
<li>Names and IPs of Master and Worker nodes</li>
<li>Running Linux server</li>
<li>SSH, SUDO access to your server</li>
<li>Public key based SSH access to all nodes (if not available, script would set this up but you would get a lot of prompts to enter root password)</li>
<li>List of available Local IP addresses that can be used by MetalLB</li>
<li>Domain name to be used by Ingress (LAN/internal would do.) </li>
<li>Block/raw drive attached to all worker nodes (to be used by Ceph for storage)</li>

## How the script works?
To keep it as streamlined as possible, I have defined variables in main script that can be updated to align with local environment.
All other scripts (setting up storage, setting up monitoring etc.) are sourced in main script.
Thus we only need to update variables in main script (Setup_Kubernetes_V01.sh)



### Prepare Nodes (prepare_node.sh)

### Set up external Load Balancer (KeepAlived + HA Proxy)

### Setup the cluster

### Deploy MetalLB  

### Deploy Nginx Ingress controller 

### Prepare worker nodes and setup storage  (Rook + Ceph)

### Deploy Kube-Prometheus  (Prometheus + AlertManager + Grafana + mixins)



## Installation

After completing the prerequisite step defined above, connect to your server (terminal or SSH session), got your home directory and download the script using:
<code>wget https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/Setup_Kubernetes_V01.sh</code>

Update the permissions on the downloaded file using:
<code>chmod 755 Setup_Kubernetes_V01.sh</code>

Update below mentioned variables in the script using an editor:
<code>START_IP_ADDRESS_RANGE</code>
<code>END_IP_ADDRESS_RANGE</code>
<code>LB_NODE_IPS</code>
<code>LB_NODE_NAMES</code>
<code>KUBE_VIP_1_IP</code>
<code>MASTER_NODE_IPS</code>
<code>MASTER_NODE_NAMES</code>
<code>WORKER_NODE_IPS</code>
<code>WORKER_NODE_NAMES</code>
<code>CEPH_DRIVE_NAME</code>
<code>ADMIN_USER</code>

Now run below script and follow prompts:
<code>sudo ./Setup_Kubernetes_V01.sh |& tee -a setup.log</code>


## Post Installation Steps
If everything went well so far, we would have a working HA Kubernetes cluster with external load balancer, storage, ingress and monitoring.
We would be able to login to Grafana dashboard (using admin/admin) from any computer in local network.
We can login into other dashboards (Rook, Prometheus and AlertManager) as well.

## Cleanup
As I had to iterate multiple times, I have also created set of scripts that would cleanup and bring your nodes to original state (almost).

Connect to your server (terminal or SSH session), got your home directory and download the script using:
<code>wget https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/Cleanup_Kubernetes_V01.sh</code>

Update the permissions on the downloaded file using:
<code>chmod 755 Cleanup_Kubernetes_V01.sh</code>

Update the variables(mentioned in Installation section above) updated for Setup_Kubernetes_V01.sh using an editor.

Now run below script and follow prompts:
<code>sudo ./Cleanup_Kubernetes_V01.sh |& tee -a cleanup.log</code>

## Whats Next
This is just a start and the script(s) could be further improved.
NFS could be added to Ceph/storage via automated shell scripts.
We can update the script to add firewall rules in place of disabling Firewalld.
I am planning to add Ubuntu and Raspberry pi support down the line (if people find it useful).


## Authors
**Piyush Kumar** - (https://github.com/piyushkumarjiit)

## License
This project is licensed under the Apache License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments
Thanks to below URLs for providing me the necessary understanding and material to come up with this script.
<li>https://kubernetes.io/docs/home/ </li>
<li>https://www.keepalived.org/manpage.html</li>
<li>http://cbonte.github.io/haproxy-dconv/2.2/configuration.html</li>
<li>https://www.Stackoverflow.com</li>
<li>https://www.Google.com</li>
<li>https://rook.github.io/docs/rook/v1.3/</li>
<li>https://github.com/prometheus-operator/kube-prometheus</li>


