## Install git
```
dnf install git -yy
```

## Install the operator (PREMADE)

```
git clone https://github.com/prometheus-operator/kube-prometheus
cd kube-prometheus/
kubectl apply --server-side -f manifests/setup
kubectl wait --for condition=Established --all CustomResourceDefinition --namespace=monitoring
kubectl apply -f manifests/
```


## Install Operator (Customized)

Cleanup:

```
kubectl delete --ignore-not-found=true -f manifests/ -f manifests/setup
```


```
go install -a github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest
go install github.com/brancz/gojsontoyaml@latest
go install github.com/google/go-jsonnet/cmd/jsonnet@latest
```

> You have to add the `jb` binary to your path. By default it's in `$HOME/go/bin`
> ```
> PATH=$PATH:$HOME/bin:$HOME/go/bin
> ```
{.is-info}


```
mkdir my-kube-prometheus; cd my-kube-prometheus
jb init
jb install github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@main
wget https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/example.jsonnet -O example.jsonnet
wget https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/build.sh -O build.sh
```



## Create Ingress Rules

```
kubectl --namespace monitoring create ingress grafana\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="grafana.k3s.lab/*=grafana:3000,tls"


kubectl --namespace monitoring create ingress alertmanager\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="alerts.k3s.lab/*=alertmanager-main:9093,tls"


kubectl --namespace monitoring create ingress blackbox\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="blackbox-exporter.k3s.lab/*=blackbox-exporter:9115"

kubectl --namespace monitoring create ingress prom-k8s\
  --annotation kubernetes.io/ingress.class=haproxy\
  --rule="prom-k8s.k3s.lab/*=prometheus-k8s:9090,tls"
```

> NOTE: the blackbox ingress is NOT https. It's meant to be used programatically to receive metrics about an endpoint and therefore a self signed cert can get in the way
{.is-info}

## Examining the Default Rules

There are multiple rules files that come with `kube-prometheus`. The best way to examin them is by cloning the git repo and `grepping` through the directory `kube-prometheus/manifests`.

```
grep "alert: " *  |awk '{print $4}' |sort |uniq
```

There appears to be 105 alerts in the directory.

OpenShift ships with more, approximately 175. These are the differences:

> NOTE: Items with an asterix `*` indicate OpenShift specific rules
{.is-info}


```
AlertmanagerReceiversNotConfigured
APIRemovedInNextEUSReleaseInUse
APIRemovedInNextReleaseInUse
AuditLogError
CannotRetrieveUpdates
CertifiedOperatorsCatalogError
CloudCredentialOperatorDeprovisioningFailed
CloudCredentialOperatorInsufficientCloudCreds
CloudCredentialOperatorProvisioningFailed
CloudCredentialOperatorStaleCredentials
CloudCredentialOperatorTargetNamespaceMissing
ClusterMonitoringOperatorReconciliationErrors
ClusterNotUpgradeable                  *
ClusterOperatorDegraded                *
ClusterOperatorDown                    *
ClusterOperatorFlapping                *
ClusterProxyApplySlow
ClusterVersionOperatorDown             *
CommunityOperatorsCatalogError         *
CoreDNSErrorsHigh                      *
CoreDNSHealthCheckSlow                 *
CoreDNSPanicking                       *
CsvAbnormalFailedOver2Min
CsvAbnormalOver30Min
etcdBackendQuotaLowSpace
etcdExcessiveDatabaseGrowth
etcdGRPCRequestsSlow
etcdHighCommitDurations
etcdHighFsyncDurations
etcdHighNumberOfFailedGRPCRequests
etcdHighNumberOfFailedProposals
etcdHighNumberOfLeaderChanges
etcdInsufficientMembers
etcdMemberCommunicationSlow
etcdMembersDown
etcdNoLeader
ExtremelyHighIndividualControlPlaneCPU
HAProxyDown
HAProxyReloadFail
HighOverallControlPlaneCPU
ImageRegistryStorageReconfigured       *
IngressControllerDegraded
IngressControllerUnavailable
InsightsDisabled                       *
InstallPlanStepAppliedWithWarnings
KubeJobCompletion
KubeletHealthState
MachineAPIOperatorMetricsCollectionFailing  *
MachineApproverMaxPendingCSRsReached        *
MachineHealthCheckUnterminatedShortCircuit  *
MachineNotYetDeleted
MachineWithNoRunningPhase
MachineWithoutValidNode
MasterNodesHighMemoryUsage
MCDDrainError
MCDPivotError
MCDRebootError
MultipleContainersOOMKilled
NodeProxyApplySlow
NodeProxyApplyStale
NodeWithoutSDNController
NodeWithoutSDNPod
NTODegraded
NTOPodsNotReady
PodDisruptionBudgetAtLimit
PodDisruptionBudgetLimit
RedhatMarketplaceCatalogError                *
RedhatOperatorsCatalogError                  *
SamplesDegraded                              *
SamplesImagestreamImportFailing              *
SamplesInvalidConfig                         *
SamplesMissingSecret                         *
SamplesMissingTBRCredential                  *
SamplesRetriesMissingOnImagestreamImportFailing    *
SamplesTBRInaccessibleOnBoot                 *
SchedulerLegacyPolicySet                     *
SDNPodNotReady
SimpleContentAccessNotAvailable
SystemMemoryExceedsReservation
TechPreviewNoUpgrade                           *
ThanosQueryGrpcClientErrorRate                 *
ThanosQueryGrpcServerErrorRate                 *
ThanosQueryHighDNSFailures                     *
ThanosQueryHttpRequestQueryErrorRateHigh       *
ThanosQueryHttpRequestQueryRangeErrorRateHigh  *
ThanosSidecarBucketOperationsFailed            *
ThanosSidecarNoConnectionToStartedPrometheus   *
UpdateAvailable                                *
```

