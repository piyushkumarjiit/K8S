# K8S

This script is not for Prod rather a 1-Click way to setup Kubernetes cluster along with its various components in homelab (or other non critical environments). Although it does support multiple stacked control planes and follows certain HA principles specified in Kubernetes documentation, I have not tested it extensively. Use it at your own risk.

I created this for my homelab and sharing in hope that it would enable others to set things up quicker. 
The script currently supports CentOS7 and CentOS 8 and I tested these 2 in my homelab. I was able to mix and match nodes without any issue.

While trying to setup my first cluster, I ran into lot of issues and hopefully this script would save you from all of those. I added resolutions to script with documentation to avoid future pain :) .

## Getting Started
Please set up public key based SSH access to all nodes (provisioned VMs) you are planning to use and connect to those nodes atleast ones via SSH. This would minimize the number of prompts (only 2 prompts) you would get during script execution.
Get block of available IP address from your local router. In case of DD-WRT based router, connect to the router via SSH and run <code> cat /var/lib/misc/dnsmasq.leases </code> to get a list of IP in use. As always I would recommend key based SSH for router as well.
Setup local DNS provider (in my case I use Pihole) to provide a local URL that would be used by various dashboard exposed by our MetalLB + Ingress controller combo.
Also make sure that raw/block drive is attached to worker nodes for Ceph to format and use.


### What all the script installs:
<li>KeepAlived</li>
<li>HAProxy</li>
<li>Docker + Containerd</li>
<li>Kubelet, Kubeadm, Kubectl</li>
<li>MetalLB</li>
<li>Nginx Ingress Controller</li>
<li>Rook + Ceph</li>
<li>Prometheus (using Kube-Prometheus)</li>
<li>AlertManager (using Kube-Prometheus)</li>
<li>Grafana with presets using mixins (using Kube-Prometheus)</li>
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


If something is not clear, I would recommend to download the script and take a look as I have added comments to make it easy for others to understand and customize.

## Prerequisites
The script is relatively self contained and fetches necessary files from github repos. To execute the script successfully we need:
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
Thus we only need to update variables in the main script (Setup_Kubernetes_V01.sh)


### Set up external Load Balancer (<code> setup_loadbalancer.sh </code>)
Before setting up Kubernetes nodes, we set up KeepAlived and HAProxy to provide virtual ip address for control plane (used by Kubernetes cluster later).
This script installs and configures all prerequisites needed by KeepAlived and HAProxy.
The script supports 3 modes:
<li>Create new instance: New VIP for new Kubernetes cluster</li>
<li>Update existing instance: New VIP for additional Kubernetes cluster</li>
<li>Setup as per user provided config: script uses user provided keepalived.conf and haproxy.cfg (should be present in $HOME) </li>
This script can be used to setup multiple virtual ip addresses that can be utilized by different Kubernetes clusters.

### Prepare Nodes (<code> prepare_node.sh </code>)
Main script calls <code>prepare_node.sh</code> to set up all prerequisites of nodes in a Kubernetes cluster.
DNS/IP based access to nodes, SELinux setting, Swap disable, Firewall, IP Forwarding, kernel mods, CRI-O/Containerd, Docker, Kuberadm, Kubelet, Kubectl and anything else required by a node in a Kubernetes cluster is setup by this script for all nodes (Master as well as workers).

### Setup the cluster
Once nodes are setup, script initializes the primary node ( with flags: --control-plane-endpoint, --pod-network-cidr  and --upload-certs) sets up networking (Calico and Weave supported via flags), adds other master nodes (defined in MASTER_NODE_NAMES) and adds worker nodes to the cluster (defined in WORKER_NODE_NAMES). Note: <code>kubectl get cs</code> would show error due to a known Kubernetes bug.

### Deploy MetalLB
Once the cluster is ready, the script deploys MetalLB to act as load balancer (External IP would populate for services utilizing LoadBalancer).
The script waits till MetalLB is ready before proceeding. MetalLB allocates IP addresses within IP range defined by START_IP_ADDRESS_RANGE and END_IP_ADDRESS_RANGE. 

### Deploy Nginx Ingress controller
Next the script deploys Nginx as ingress controller. Using MetalLB, the ingress controller gets external ip address and exposes services/dashboards.

### Prepare worker nodes and setup storage  (Rook + Ceph)
Based on flag (SETUP_ROOK_INSTALLED), script calls <code>setup_rook_ceph.sh</code> to:
<li>Setup prerequisites for Rook and Ceph</li>
<li>Ensures NTP/Chronyd is working on all nodes</li>
<li>Ensures Block/Raw drive is added on each worker node</li>
<li>Deploys Rook + Ceph</li>
<li>Sets up storage</li>
<li>Sets up Ceph dashboard with Ingress (could be configured to be available via MetalLB as well)</li>

### Deploy Kube-Prometheus  (Prometheus + AlertManager + Grafana + mixins)
Based on flag (SETUP_CLUSTER_MONITORING), script calls <code>setup_monitoring.sh</code> to:
<li>Installs Git, Go, JSONNET, JB and gojsonttoyaml</li>
<li>Downloads the latest jsonnet samples from kube-prometheus repo</li>
<li>Updates the samples for current config (storage class, ingress config, PVC etc.</li>
<li>Executes build to generate YAML files</li>
<li>Deploys the output to cluster</li>

The INGRESS_DOMAIN_NAME is used during config and all dashboards are accessible on the generated URL.

## Installation

After completing the prerequisite step defined above, connect to your server (terminal or SSH session), got your home directory and download the script using:
<code>wget https://raw.githubusercontent.com/piyushkumarjiit/K8S/master/Setup_Kubernetes_V01.sh</code>

Update the permissions on the downloaded file using:
<code>chmod 755 Setup_Kubernetes_V01.sh</code>

Update below mentioned variables in the script using an editor:
<li><code>START_IP_ADDRESS_RANGE</code></li>
<li><code>END_IP_ADDRESS_RANGE</code></li>
<li><code>LB_NODE_IPS</code></li>
<li><code>LB_NODE_NAMES</code></li>
<li><code>KUBE_VIP_1_IP</code></li>
<li><code>MASTER_NODE_IPS</code></li>
<li><code>MASTER_NODE_NAMES</code></li>
<li><code>WORKER_NODE_IPS</code></li>
<li><code>WORKER_NODE_NAMES</code></li>
<li><code>CEPH_DRIVE_NAME</code></li>
<li><code>ADMIN_USER</code></li>

Now run the script and follow prompts:
<code>sudo ./Setup_Kubernetes_V01.sh |& tee -a setup.log</code>


## Post Installation Steps
If everything went well so far, we would have a working HA Kubernetes cluster with external load balancer, storage, ingress and monitoring.
We would be able to login to Grafana dashboard (using admin/admin) from any computer in local network.
We can login into other dashboards (Rook, Prometheus and AlertManager) as well.

### To add a new node to cluster
We can add new nodes to the cluster without rerunning the script.
To add a node, copy the <code>prepare_node.sh</code> to the node to eb added, update the variables in <code>prepare_node.sh</code> to be only applicable to the specific node and execute <code>prepare_node.sh</code>.
Once it completes successfully, copy the applicable node on-boarding command from primary node (the node from where you ran the script). In the HOME folder there would be 2 files <code>add_worker.txt</code> and <code>add_master.txt</code> which contain respective commands. Execute these commands from your new node and it would be added to the cluster.

## Cleanup
I have also created set of scripts that would cleanup and bring your nodes to original state (almost).

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
You can update the script to add firewall rules in place of disabling Firewalld.
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
