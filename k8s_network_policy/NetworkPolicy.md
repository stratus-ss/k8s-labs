## App Setup

### Create the namespace

```
kubectl create namespace bouvier
kubectl create namespace simpson
```


### Create the app

```
kubectl create deployment patty --image=quay.io/openshift-examples/simple-http-server:micro --port=8080 -n bouvier
kubectl create deployment selma --image=quay.io/openshift-examples/simple-http-server:micro --port=8080 -n bouvier
```

```
kubectl create deployment homer --image=quay.io/openshift-examples/simple-http-server:micro --port=8080 -n simpson
kubectl create deployment marge --image=quay.io/openshift-examples/simple-http-server:micro --port=8080 -n simpson
```

### Create the service

```
kubectl expose deployment patty --type=ClusterIP --port=8080 --target-port=8080 -n bouvier
kubectl expose deployment selma --type=ClusterIP --port=8080 --target-port=8080 -n bouvier
kubectl expose deployment homer --type=ClusterIP --port=8080 --target-port=8080 -n simpson
kubectl expose deployment marge --type=ClusterIP --port=8080 --target-port=8080 -n simpson

```


## Create an Ingress route

```
# Sample
kubectl --namespace <namespace> create ingress <ingress friendly name>\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="<route URL>/*=<service name>:8080,tls"
#### End Sample  
  
kubectl --namespace bouvier create ingress patty\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="patty-bouvier.k3s.lab/*=patty:8080,tls"

kubectl --namespace bouvier create ingress selma\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="selma-bouvier.k3s.lab/*=selma:8080,tls"


kubectl --namespace simpson create ingress marge\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="marge-simpson.k3s.lab/*=marge:8080,tls"


kubectl --namespace simpson create ingress homer\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="homer-simpson.k3s.lab/*=homer:8080,tls"

```

## Get The TMUX script and run it in a new shell

```
wget https://examples.openshift.pub/networking/network-policy/network-policy-demo/run-tmux.sh
```

You need to know what your wildcard dns entry is to run this script

```
sh run-tmux.sh k3s.lab
```


## Setup the Network Policy 



```
wget https://examples.openshift.pub/networking/network-policy/network-policy-demo/01_default-deny-simpson.yaml
kubectl apply -f 01_default-deny-simpson.yaml

wget https://examples.openshift.pub/networking/network-policy/network-policy-demo/02_allow-from-openshift-ingress-simpson.yaml
kubectl apply -f 02_allow-from-openshift-ingress-simpson.yaml

wget https://examples.openshift.pub/networking/network-policy/network-policy-demo/03_allow-same-namespace-simpson.yaml
kubectl apply -f 03_allow-same-namespace-simpson.yaml

wget https://examples.openshift.pub/networking/network-policy/network-policy-demo/04_allow-from-bouviers-to-marge-simpson.yaml
sed -i  's/deployment/app/g'  04_allow-from-bouviers-to-marge-simpson.yaml
kubectl apply -f 04_allow-from-bouviers-to-marge-simpson.yaml
```

