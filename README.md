# MK3-Multi-cluster-service-mesh

## How to run
- Setup AWS credentials and region on your local machine
- execute run.sh script
- create shell session with loaded kubeconfig - run use-kubeconfig.sh
- cleanup project directory and decommission EC2 instance - run clean.sh

## Running test application
- Test application is automatically deployed in configuration:
    - remote-1 -> sender (receives message from user and sends it to the responder - reads response from responder and returns to the user)
    - remote-2 -> responder (receives message from sender and returns response to sender)
    - communication goes like this: user -> sender(cluster: remote-1) -> responder(cluster: remote-2) -> sender -> user
- connect to EC2 instance - connect-vm.sh
- get IP for remote-1 node: 
```
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' remote-1-control-plane
````
- send message to sender: 
```
curl "http://<remote-1-node-ip>:30080/api?content=<your-message>"
```

## Observability (Kiali + Prometheus)
Cross-cluster traffic is observable in Kiali. Because Kiali queries a single
Prometheus, each cluster runs its own Prometheus and the primary federates the
two remotes (`prometheus/install.sh`). Istio adds `source_cluster` /
`destination_cluster` labels to its metrics, so the Kiali graph can box and
connect workloads across clusters.

Both `prometheus/install.sh` and `kiali/install-kiali.sh` are run automatically
by `run.sh`. To view the graph:
- port-forward Kiali: `./kiali/kiali-port-forward.sh` then open http://localhost:20002
- in **Traffic Graph**, select all namespaces and enable **Cluster boxing**
- edges only appear while traffic flows, so generate continuous load with the
  helper script. Run it **from your local machine** — it opens an SSH session to
  the EC2 instance and runs the request loop there (auto-detecting the remote-1
  node IP), so nothing needs to be copied or set up manually:
```
./generate-load.sh
```
  Options: `-i <interval>` `-m <message>` `-c <concurrency>` `-H <node-ip>`
  (e.g. `./generate-load.sh -i 0.5 -c 4`). Stop it with Ctrl-C.

## Adding KWOK clusters
As KWOK clusters are not meant to be used for application deployment, usage of these clusters is limited to deployment
and connecting to service mesh as additional remote clusters:
```
./kwok/add-cluster.sh 
```
This script will deploy KWOK cluster, install istio data plane (remote profile), east-west gateways and register it in 
service mesh. <br>
<br>
<br>
We can list all clusters in service mesh:
```
istioctl --context kind-primary remote-clusters
```
If status is seen as "synced" - cluster is correctly registered in service-mesh and is reachable for primary cluster
