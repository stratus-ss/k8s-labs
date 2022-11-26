# scratch notes

Keycloak install from here: https://fabianlee.org/2022/09/10/kubernetes-keycloak-iam-deployed-into-kubernetes-cluster-for-oauth2-oidc/

SSL San info from here: https://stackoverflow.com/questions/64814173/how-do-i-use-sans-with-openssl-instead-of-common-name

User Kubeconfig hints here: https://medium.com/@int128/kubectl-with-openid-connect-43120b451672

# Introduction

Once Kubernetes is setup and has some basic configuration, one of the first steps that administrators take is to secure the platform. As part of this, some form of centralized authentication is desireable. There are a lot of options to accomplish this. In this lab we are going to look at Keycloak which says that 

> Keycloak provides user federation, strong authentication, user management, fine-grained authorization, and more. 

Most companies don't use Keycloak's built in user management, but instead plug in to some for of LDAP backend.

> **Note**
> I have derived sections of this lab from Fabian Lee's [blog post on Keycloak](https://fabianlee.org/2022/09/10/kubernetes-keycloak-iam-deployed-into-kubernetes-cluster-for-oauth2-oidc/)

## Setup SSL Certs 

Keycloak functions best when it has its own certificates. While you can use the certificates that ship with K8S, it is recommended that you use SSL certs that are specific to Keycloak which is the most likely production setup.

You need to generate some SSL certs for Keycloak. Here is a short script which will create a script to generate the SSL certs for you

```
cat << EOL > selfsigned_openssl.sh
#!/bin/bash

FQDN="\$1"
[ -n "\$FQDN" ] || { echo "ERROR provide FQDN for self-signed cert"; exit 3; }

echo -------------------
echo FQDN is \$FQDN
echo -------------------

openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
-keyout /tmp/\$FQDN.key -out /tmp/\$FQDN.pem \
-subj "/C=US/ST=CA/L=SFO/O=myorg/CN=\$FQDN" \
-addext "subjectAltName = DNS:\$FQDN"

openssl x509 -in /tmp/\$FQDN.pem -text -noout | grep -E "Subject:|Not After :|DNS:|Issuer:"

echo ""
echo "public cert and private key are located in /tmp directory"

EOL
```

You can run the script and pass in your FQDN to have it create the certs

```
chmod +x selfsigned_openssl.sh
prefix=keycloak.k3s.lab
./selfsigned_openssl.sh $prefix
```

In order for Linux tooling to trust the self-signed certicates, you have to add them into the system trust store. The default Kubernetes certificates are not trusted by default. So on top of the self signed cert we just generated we are going to add the K8S certs to the trust store as well. 
Add the certs into the ca-trust store:

```
cp /tmp/$prefix.{pem,key} /etc/pki/tls/certs/
cp /etc/kubernetes/pki/ca.crt /etc/pki/tls/certs/
update-ca-trust
```

In order for applications inside of Kubernetes to make use of the certificates, we are going to create a secret to hold both the key and certificate. Use the following command to create the secret:

```
kubectl create -n default secret tls tls-credential --key=/tmp/$prefix.key --cert=/tmp/$prefix.pem
```

## Updating The KubeAPI

We have laid the foundation for Keycloak authentication. However, in order to allow us to login to Kubernetes with the user that will be created in Keycloak, we have to update the kubeapi. While we could potentially have done this during the installation, adding Open ID Connect (oidc) information does not require a re-installation, instead it can be added directly into the YAML file.

You can update the `kube-apiserver.yaml` file to include the OIDC information manually, or you can use the snippet below to do it for you. The required edits goes bleow the `--tls` options in the `kube-apiserver.yaml` file.

```
cat << EOL > temp_oidc_settings.txt
    - --oidc-issuer-url=https://keycloak.k3s.lab/realms/myrealm
    - --oidc-client-id=myclient
    - --oidc-username-claim=name
    - --oidc-groups-claim=groups
    - --oidc-ca-file=/etc/pki/tls/certs/keycloak.k3s.lab.pem
EOL


sed -i '/    - --tls-private-key-file=\/etc\/kubernetes\/pki\/apiserver.key/rtemp_oidc_settings.txt' /etc/kubernetes/manifests/kube-apiserver.yaml
```

Both CRIO and the Kubelet need to be restarted in order to make use of the changes:
```
systemctl restart crio && systemctl restart kubelet
```

## Allowing Traffic Into Keycloak

We need to create an ingress route to be able to access Keycloak. Unlike the previous ingress definitions we have used, there is more involved to create this ingress. See if you can figure out how to construct an ingress YAML file. Name the file `keycloak-ingress.yaml`. You will need to have the following in the file

- an annotation in the `metadata` section for the HAProxy
- a label in the `metadata` section of `app: keycloak`
- a `name` in the `metadata` section with the value of `keycloak`
- a `rule` in the `spec` section as well as the following
    - a host of `keycloak.k3s.lab`
    - the `pathType` should have a value of `Prefix`
    - a `backend` pointing to the keycloak service
- a `tls` section that
    - has a host of `keycloak.k3s.lab`
    - a `secretName` with the value of the secret you created earlier

<details>
  <summary><b>Hints and Spoilers</b></summary>
  <details>
    <summary><b>HINT: Ingress Skeleton</b></summary>
    Below you can see a skeleton of an ingress definition. There are things missing

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
  labels:
spec:
  rules:
  - host: 
    http:
      paths:
      - pathType: 
        path: "/"
        backend:
          service:
            
  tls:
  - hosts:
    - 
    secretName: 
```
    
  </details>
  <details>
    <summary><b>SPOILER: Completed Ingress</b></summary>

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: haproxy
  labels:
    app: keycloak
  name: keycloak
spec:
  rules:
  - host: keycloak.k3s.lab
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: keycloak
            port:
              number: 8080
  tls:
  - hosts:
    - keycloak.k3s.lab
    secretName: tls-credential
```    
  </details>
  </details>
  </details>
  

After you have figured out the ingress YAML, create the ingress object in Kubernetes:

```
kubectl create -f keycloak-ingress.yaml
```


Get the poststart script and the json files (replace the urls in the post file)

```
curl -s https://raw.githubusercontent.com/fabianlee/blogcode/master/keycloak/myclient.exported.json |sed "s/keycloak\.kubeadm\.local/$prefix/g" > myclient.exported.json

wget https://raw.githubusercontent.com/fabianlee/blogcode/master/keycloak/poststart.sh

kubectl create configmap keycloak-configmap --from-file=poststart.sh --from-file=myclient.exported.json
```

While we have, so far, been creating individual YAML files for each object we have been creating, you can combine them into one file. The below file defintes a `service` and a `deployment` in the same file. The deployment section has a lifecycle hook to create users the first time container is created:

```
cat << EOL > keycloak.yaml
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  labels:
    app: keycloak
spec:
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  selector:
    app: keycloak
  type: ClusterIP
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  labels:
    app: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        lifecycle:
          postStart:
            exec:
              # lifecycle hook called right after container created, bash script has built-in delay
              command: ["/bin/bash","-c","cd /opt/keycloak/bin; ./poststart.sh > /tmp/poststart.log"]
        image: quay.io/keycloak/keycloak:20.0.1
        args: ["start-dev"]
        env:
        - name: KEYCLOAK_ADMIN
          value: "admin"
        - name: KEYCLOAK_ADMIN_PASSWORD
          value: "admin"
        - name: KC_PROXY
          value: "edge"
        ports:
        - name: http
          containerPort: 8080
        readinessProbe:
          httpGet:
            path: /realms/master
            port: 8080
        volumeMounts:
          - mountPath: /opt/keycloak/bin/poststart.sh
            subPath: poststart.sh
            name: keycloak-hookvolume
          - mountPath: /tmp/myclient.exported.json
            subPath: myclient.exported.json
            name: keycloak-hookvolume
      volumes:
      - name: keycloak-hookvolume
        configMap:
          name: keycloak-configmap
          defaultMode: 0755

EOL
```


> **Note**
> You can use some shell magic to define the resources and create them at the same time. However, it is considered good practice to have the artifacts used to create resources. This way you can refer back to them, store them in source control or simply back them up for later.

With the YAML file created, create the objects in Kubernetes

```
kubectl create -f keycloak.yaml

sleep 100

kubectl exec -it deployment/keycloak -n default -c keycloak -- cat /tmp/keycloak.properties
kubectl exec -it deployment/keycloak -n default -c keycloak -- cat /tmp/keycloak.properties |grep secret |awk -F "=" '{print $2}' > /tmp/client_secret
```


## Setting Up A Regular User

For this next section, we'll want to create a new user (or change to an existing one). This is just so that we don't use the same kubeconfig as another user. This can cause weird problems over time. For the remaining part of this lab, I assume you have created an unprivileged user. I called my `k8s`.

We need to bootstrap a kubeconfig with some cluster and context information. The reason is that while we could attempt to figure out all of the flags to pass into `kubectl`, however in this case we can derive this information from the default kubeconfig. Create the `~.kube` directory and the user kubeconfig:

```
mkdir ~/.kube

cat << EOL > ~/.kube/config
apiVersion: v1
clusters:
- cluster:
    server: https://192.168.99.45:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: myuser
kind: Config
users:
- name: myuser
  user:

EOL
```

Kubernetes has a lot of plugins that are available for the `kubectl` command. Most of the time the defaults will serve all of your needs. However, in this case, the `oidc-login` plugin will help us finish configuring the user's configuration. One of the most popular plugin managers is called `krew`. We're going to download it, add it to our path with the following commands:

```
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

export CLIENT_SECRET=$(cat /tmp/client_secret)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

kubectl krew install oidc-login
kubectl krew install whoami
```

Now that it is installed, we need get some tokens from Keycloak before we proceed. Remember the `keycloak.properties` we examined way back at the start of the lab? It has a client secret in it that we need. You should be able to find a copy of this client secret in `/tmp/client_secret`. 

> **Warning**
> If you are using a distribution (like RHEL8) which uses bash 4.x there is some problem with the client secret when attempting to use it from a shell variable. Therefore, you will need to copy and paste the client_secret from the file into the commands below.

```
# for Bash 4.x you need to manually put in the secret value as variable expansion does not work correctly
ID_TOKEN=$(curl -k -d "grant_type=password" -d "scope=openid" -d "client_id=myclient" -d "client_secret=<insert client_secret>" -d "username=myuser" -d "password=Password1!" https://keycloak.k3s.lab/realms/myrealm/protocol/openid-connect/token |jq .id_token)

REFRESH_TOKEN=$(curl -k -d "grant_type=password" -d "scope=openid" -d "client_id=myclient" -d "client_secret=<insert client_secret>" -d "username=myuser" -d "password=Password1!" https://keycloak.k3s.lab/realms/myrealm/protocol/openid-connect/token |jq .refresh_token)
```

Finally, with the tokens captured, we can finish out kubeconfig:

```
kubectl config set-credentials myuser "--auth-provider=oidc" \
"--auth-provider-arg=idp-issuer-url=https://keycloak.k3s.lab/realms/myrealm" \
"--auth-provider-arg=client-id=myclient" \
"--auth-provider-arg=client-secret=${CLIENT_SECRET}" \
"--auth-provider-arg=refresh-token=$(sed -e 's/^"//' -e 's/"$//' <<<$REFRESH_TOKEN)" \
"--auth-provider-arg=id-token=$(sed -e 's/^"//' -e 's/"$//' <<<$ID_TOKEN)"
```

You can now run some commands against the cluster:

```
kubectl auth can-i create pods --all-namespaces
kubectl auth can-i list deployments --all-namespaces
kubectl auth can-i list nodes
```

Verify your identity via the plugin we installed earlier:

```
kubectl whoami
```

You should see the following output:

```
https://keycloak.k3s.lab/realms/myrealm#first last
```

## A Look At Permissions

You should now be running commands as the user from keycloak. However, you need to actually allow the user to perform actions against the cluster. To do so, create the Role Based Acceess Controls (RBAC) and make the user cluster-admin

```
cat << EOL > cluster-admin.yaml
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: oidc-admin-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: "https://keycloak.k3s.lab/realms/myrealm#first last"

EOL

kubectl create -f cluster-admin.yaml
```

> If you try a kubectl command without the above you will get output similar to the following:
>```
>Error from server (Forbidden): pods is forbidden: User "https://keycloak.k3s.lab/realms/myrealm#first last" cannot list resource "pods" in API group "" in the namespace "default"
>```
{.is-info}

If you want to see which cluster role bindings have access to the `cluster-admin` role you can run the following command:

```
kubectl get clusterrolebindings | grep "cluster-admin"
```

You should see 2 entries:

```
cluster-admin                                          ClusterRole/cluster-admin                                                          3h8m
oidc-admin-binding                                     ClusterRole/cluster-admin                                                          8m
```

If you examin the `oidc-admin-binding` you will see which user it is:

```
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  creationTimestamp: "2022-11-26T20:02:02Z"
  name: oidc-admin-binding
  resourceVersion: "19390"
  uid: 53f94b3c-5091-43cd-9de8-fd1950fbaf22
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: https://keycloak.k3s.lab/realms/myrealm#first last
```

This mirrors what we created before. This also demonstrates how important the naming of objects in Kubernetes really is. You can see we called this `oidc-admin-binding` but we had to open it up to know which users were in there. This might be what you want, you could have multiple users in this file, all being authenticated via Keycloak. On the other hand, since this is a test cluster, it might be worth considering a name which describes the user, such as `first-last-from-keycloak`. It's something that can make a big difference for the ongoing understanding of your clusters as they grow.
