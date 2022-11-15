## K8S Setup
### Setup Tooling
After the VM has been installed and registered start by getting the CRIO repo:

```
export VERSION=1.21
systemctl enable --now cockpit.socket
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/CentOS_8/devel:kubic:libcontainers:stable:cri-o:$VERSION.repo
```

Next get the Kubernetes Repo so that you can install the tooling

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

Install the tooling, set SELinux to permissive and enable the kubelet and crio


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

Open the firewall.
> It's very important that the following shows "yes"
> ```
> [root@rhel8-k8s ~]# firewall-cmd --list-all |grep masq
>   masquerade: no
> ```
> If it does not (like above), external DNS resolution will fail
{.is-warning}


```
sudo firewall-cmd --zone=public --add-service=kube-apiserver --permanent
sudo firewall-cmd --zone=public --add-service=etcd-client --permanent
sudo firewall-cmd --zone=public --add-service=etcd-server --permanent
sudo firewall-cmd --zone=public --add-service=https --permanent
sudo firewall-cmd --zone=public --add-service=http --permanent

# Set the firewall basics
sudo firewall-cmd --zone=public --add-port=9100/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10249/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10250/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10251/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10252/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10257/tcp --permanent
sudo firewall-cmd --zone=public --add-port=10259/tcp --permanent
sudo firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent
sudo firewall-cmd --zone=public --add-port=6443/tcp --permanent
# this is for etcd metrics
sudo firewall-cmd --zone=public --add-port=2381/tcp --permanent


sudo firewall-cmd --add-masquerade --permanent
sudo firewall-cmd --reload
```

### Add Modules and Sysctls

Next create the modules and the sysctl settings that Kubernetes requires

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

#### kubeadmcfg.conf

```
---
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

controllerManager:
    extraArgs:
      bind-address: 0.0.0.0
scheduler:
    extraArgs:
      bind-address: 0.0.0.0
---
apiVersion: "kubeproxy.config.k8s.io/v1alpha1"
kind: KubeProxyConfiguration
metricsBindAddress: 0.0.0.0

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

If you are running a single node, you need to remove the `control-plane` taint so that pods can be scheduled on it...
```
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

### Install OVN

Install a CNI, in this case, we are using OVN
```
wget https://raw.githubusercontent.com/kubeovn/kube-ovn/release-1.10/dist/images/install.sh
mv install.sh ovn-install.sh
sh ovn-install.sh 
```

Finally setup the ingress controller. IN this case HAProxy
```
cat <<EOF | sudo tee ~/k8s_resources/haproxy-ingress-values.yaml
controller:
  hostNetwork: true
EOF

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
sh get_helm.sh
helm repo add haproxy-ingress https://haproxy-ingress.github.io/charts
helm repo update
helm install haproxy-ingress haproxy-ingress/haproxy-ingress  --create-namespace --namespace ingress-controller  --version 0.13.9  -f haproxy-ingress-values.yaml

```
