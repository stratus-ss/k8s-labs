## Install Kube-prometheus-stack

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Next create an override file to allow for etcd with the following content:

```
kubeEtcd:
  enabled: true
  service:
    enabled: true
    port: 2381
    targetPort: 2381
```

Pass this into the helm chart:

```
kubectl create ns prom
helm install   --namespace prom -f prom_custom_values.yaml   prom-stack prometheus-community/kube-prometheus-stack
```


## Create Ingress Rules

```
kubectl --namespace prom create ingress grafana\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="grafana.k3s.lab/*=prom-stack-grafana:80,tls"


kubectl --namespace prom create ingress alertmanager\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="alerts.k3s.lab/*=prom-stack-kube-prometheus-alertmanager:9093,tls"


kubectl --namespace prom create ingress prom-k8s\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="prom-k8s.k3s.lab/*=prom-stack-kube-prometheus-prometheus:9090,tls"
```


