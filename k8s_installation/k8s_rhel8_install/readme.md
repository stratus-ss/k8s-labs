# Intro

There are very few pieces of software that can be considered paradigm shifting. Microsoft's Windows Operating system completely shifted the desktop landscape. It provided a level of user friendless that home computers had been lacking. Fast forward to the late 1990s and the early 2000s, the Linux kernel and distributions provided an on ramp for businesses and individuals to adopt open source technologies in a way previously unseen. Jump forward again, VMWare, while not inventing virtual machines, popularized the mass adoption VMs at scale. In the same way, Docker in the early 2010s made container technology approachable and attractive for mass consumption. The industry saw an explosion of containerized applications over the next couple of years. With this new way to deploy software there came a need to orchestrate this disperate containers. While there have been many attempts at containers and orchestration, Kubernetes emerged as the undisputed leader for dealing with containers at scale.

In the time since vanilla Kubernetes (heretofor referred to as K8S) was first introduced into the broader community, there have been several distributions which have popped up to help smooth out some of the rough edges (OpenShift, Rancher and CloudFoundary just to name a few). While the process to get a K8S cluster up and running has become a lot easier, there are still a lot of manually steps required to get a cluster up and functioning. What follows here is a guide to installing K8S on a single node with CRIO, OVN, iptables and HAProxy as some of the fundamental enabling technologies.

## K8S Setup

The instructions below are for a Red Hat Enterprise Linux 8 host, but aside from package manager specific commands, this process should remain the same regardless of the distribution used.

### Setup Tooling
For the purposes of brevity, I am going to assume you know how to create a VM in your hypervisor and you know how to install RHEL 8. After the VM has been installed and registered start by getting the CRIO repo:

```
export VERSION=1.21
systemctl enable --now cockpit.socket
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
```

CRIO is the container engine that will ultimately run your containerized workload. While Docker can be used, CRIO will be used here as it is part the Cloud Native Computing Foundation and has been the choice of several popular enterprise K8S distributions.

We need to add the Kubernetes Repo so that you can install the tooling such as `kubeadm` and `kubectl` which will be used to interact with the cluster:

```
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF


cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF
```

As this is intended for learning we are going to set SELinux in permissive mode. You should **NEVER** disable SELinux. In a broader context, you should properly configure SELinux, especially for production-like functionality.  We need to install the tooling and ensure that the `kubelet` and `crio` are enabled and set to start their respective services.


```
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes cri-o iproute-tc 
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo systemctl enable --now kubelet
sudo systemctl enable --now crio
sudo systemctl start kubelet
sudo systemctl start crio
```

### Setup The Firewall

According to the [official documentation](https://kubernetes.io/docs/reference/ports-and-protocols/) the following ports need to be opened:

| Protocol | Direction| Port Range| Purpose|
|:----:|:-----:|:----:|:-----|
|TCP|Inbound|6443|K8S API|
|TCP|Inbound|2379-2380|ETCD API|
|TCP|Inbound|10250|Kubelet API|
|TCP|Inbound|10259|Kube Scheduler|
|TCP|Inbound|10257|Kube Controller Manager|
|TCP|Inbound|30000-32767|Node Ports|


RHEL 8 uses `firewall-cmd` to do this:

```
sudo firewall-cmd --zone=public --add-service=kube-apiserver --permanent
sudo firewall-cmd --zone=public --add-port=6443/tcp --permanent
sudo firewall-cmd --zone=public --add-service=etcd-client --permanent
sudo firewall-cmd --zone=public --add-service=etcd-server --permanent
sudo firewall-cmd --zone=public --add-port=10250/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10249/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10251/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10252/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10257/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10259/tcp --permanent
sudo firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent

sudo firewall-cmd --reload
```

### DNS - DNSMasq

For this lab, we will be using DNSMasq as it's easy to get setup and requires minimal configuration.

Install DNSMasq:

```
dnf install -y dnsmasq
```

After it is installed, you will want to make a small modification to your `/etc/resolv.conf`. Comment out and make note of the `nameserver` address that exists.

Replace it with your VMs IP address. In my case my `resolv.conf` looks like this:

```
search stratus.lab stratus.local k3s.local
#nameserver 192.168.99.7
nameserver 192.168.99.45
```

After this, you will want to create the file `/etc/dnsmasq.d/local_dns.conf` with the following contents:

```
# This is the server to forward dns querries to
server=<original nameserver>

# This is the wild card handling for your vm
address=/k3s.lab/<vm ip>
```

Restart DNSMasq:

```
systemctl restart dnsmasq
```

Finally, you need to open the firewall port for DNS to ensure that you can use DNSMasq outside of your vm (for instance from your laptop)

```
firewall-cmd --add-service=dns --permanent
firewall-cmd --reload
```

At this point your vm has been setup for wild card dns.

> **Note**
> You still need to configure your client (laptop) to make use of the vms dns. There are too many clients to document this process here. You will need to know how to set your own DNS settings.

<details>
<summary><b>ALTERNATIVE</b> PFSense Configuration</summary>

### Alternative DNS - PFSense

Kubernetes makes extensive use of DNS entries both forward and reverse lookups. In order to function properly the hosts have to be able to resolve their hostnames. This requires A records in your DNS system. In most systems, including PFSense, you can ensure this works with a Host Override:

![host_override.png](host_override.png)

If you are making a cluster that has more than 1 node, you will have to set up a load balancer (such as HAProxy) and adjust the DNS accordingly.

Additionally, it is a standard practice to have a wild card DNS entry for a specific sub-domain so that regardless of the service or the application you are using, it will always resolve. In PFSense, this can be done in the Custom Options section of the DNS Resolver:

![pfsense_custom_options.png](pfsense_custom_options.png)
</details>



> **Warning**
> **DO NOT** skip DNS resolution, both forward and reverse. It will cause you untold problems for a significant portion of the components in K8S




### Add Modules and Sysctls

What isn't called out as you are expected to know this as part of the administration of your distribution, is that you need to allow both overlays (network and filesystem) as well as IP Forwarding and bridging. To do this, create the modules and the sysctl settings that Kubernetes requires

```
# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF


# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
sudo sysctl --system
```

### Installing K8S

To install a basic cluster, you only need to run a simple command:

```
kubeadm init --pod-network-cidr=10.10.0.0/16
```

However, You can actually create a `kubeadmcfg.conf` file which will help you customize your deployment.

#### kubeadmcfg.conf

You can see what the default config will be if you just ran `kubeadm init` by running the following command:

```
kubeadm config print init-defaults
```

This is usefull to get an idea of how the file might be laid out. The [official documentation](https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/#basics) has an example YAML file with significantly more options to look at.

Below is the configuration that this lab used to successfully deploy a Kubernetes cluster.

> the `listen-metrics-urls` needed to be adjusted from the default in order to allow the Prometheus agents to scrape metrics. By default, **most** things are listening on `localhost` only.
{.is-success}


```
echo '---
apiVersion: "kubeadm.k8s.io/v1beta3"
kind: InitConfiguration
nodeRegistration:
    name: rhel8-k8s.stratus.lab
localAPIEndpoint:
    advertiseAddress: 192.168.99.45
---
apiVersion: "kubeadm.k8s.io/v1beta3"
kind: ClusterConfiguration
etcd:
  local:
    serverCertSANs:
    - "192.168.99.45"
    peerCertSANs:
    - "192.168.99.45"
    extraArgs:
      initial-cluster: rhel8-k8s.stratus.lab=https://192.168.99.45:2380
      initial-cluster-state: new
      name: rhel8-k8s.stratus.lab
      listen-peer-urls: https://192.168.99.45:2380
      listen-client-urls: https://192.168.99.45:2379
      advertise-client-urls: https://192.168.99.45:2379
      initial-advertise-peer-urls: https://192.168.99.45:2380
      metrics: extensive
      listen-metrics-urls: http://0.0.0.0:2381
apiServer:
   extraArgs:
     authorization-mode: Node,RBAC
   timeoutForControlPlane: 4m0s
networking:
   dnsDomain: cluster.local
   podSubnet: 10.16.0.0/16
   serviceSubnet: 10.96.0.0/12
' > kubeadmcfg.conf

```

#### Run the install command

You are finally able to do the base Kubernetes installation!

```
kubeadm init --config=/root/kubeadmcfg.conf
```

> Important: Don't forget to export the kubeconfig... add it to your `~/.bashrc`
> ```
> export KUBECONFIG=/etc/kubernetes/admin.conf
> ```
> While you are there you might as well add an alias for switching k8s contexts
> `alias kubecon='kubectl config set-context --current --namespace'`
{.is-warning}


### Install OVN

Install a CNI, in this case, we are using OVN. The [official installation documentation](https://github.com/kubeovn/kube-ovn/blob/master/docs/install.md) recommends using their script for installation. Normally it is not recommended to simply run a script from the internet, so in this case we are going to download and rename it so we know exactly what the script is for. This lab has ensured that it was installed with the expected values for POD_CIDR, SVC_CIDR and JOIN_CIDR. If you are planning to change any of these cider ranges, you will need to edit the variables inside the script in order to have a successful deployment of OVN.
```
wget https://raw.githubusercontent.com/kubeovn/kube-ovn/release-1.10/dist/images/install.sh
mv install.sh ovn-install.sh
sh ovn-install.sh 
```

Finally setup the ingress controller. IN this case HAProxy has a helm chart, which is essentially a cloud-native scripting language for Kubernetes compatible clusters. An understanding of Helm is outside the scope of this lab, but it does have the option to pass in a file as an option. This file can be used to add or override values that your cluster needs to run effectively. In this case we need to make sure that HAProxy is using the `hostNetwork`:
```
cat <<EOF | sudo tee ~/haproxy-ingress-values.yaml
controller:
  hostNetwork: true
EOF

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
sh get_helm.sh
helm repo add haproxy-ingress https://haproxy-ingress.github.io/charts
helm repo update
helm install haproxy-ingress haproxy-ingress/haproxy-ingress  --create-namespace --namespace ingress-controller  --version 0.13.9  -f haproxy-ingress-values.yaml

```

At this point if you have not encountered any errors and you have added the requesite lines to your `~/.bashrc` you should be able to see the pods running in your cluster:

```
[root@rhel8-k8s ~]# kubectl get pods -A
NAMESPACE            NAME                                            READY   STATUS    RESTARTS   AGE
ingress-controller   haproxy-ingress-84f5c464f7-9mcxv                1/1     Running   0          25s
kube-system          coredns-565d847f94-2dtg7                        1/1     Running   0          3m39s
kube-system          coredns-565d847f94-mkn68                        1/1     Running   0          3m34s
kube-system          etcd-rhel8-k8s.stratus.lab                      1/1     Running   1          5m43s
kube-system          kube-apiserver-rhel8-k8s.stratus.lab            1/1     Running   1          5m43s
kube-system          kube-controller-manager-rhel8-k8s.stratus.lab   1/1     Running   1          5m44s
kube-system          kube-ovn-cni-xhp4v                              1/1     Running   0          4m15s
kube-system          kube-ovn-controller-6c4574d875-d8fxq            1/1     Running   0          4m15s
kube-system          kube-ovn-monitor-867645b9d9-4tss4               1/1     Running   0          4m15s
kube-system          kube-ovn-pinger-6wrdz                           1/1     Running   0          3m27s
kube-system          kube-proxy-g4dh9                                1/1     Running   0          5m29s
kube-system          kube-scheduler-rhel8-k8s.stratus.lab            1/1     Running   1          5m42s
kube-system          ovn-central-546d6fd469-7dttd                    1/1     Running   0          4m32s
kube-system          ovs-ovn-f4cnq                                   1/1     Running   0          4m32s
```
