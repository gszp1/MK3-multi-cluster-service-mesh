# MK3-Multi-cluster-service-mesh

## Step-by-step
- Provision t3.medium EC2 using Terraform
- Install kind on instance
- Create 3 kind clusters with single node per cluster
- Install metallb on each cluster
- Generate CA certificate for clusters
- Install Istio base on each cluster
- Install Istio control plane on primary cluster
- Install Istio remote on remote-1 and remote-2 clusters
- Install East-West gateways and other components on clusters
- Deploy sample applications on remote-2 and remote-1 clusters so that they can communicate using service mesh (TODO)

## How to run
- Setup AWS credentials and region on your local machine
- execute run.sh script
- (optional) run example application using run_example.sh script from /example directory
- (optional) run cleanup.sh script to destroy the infrastructure created by this project

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
- edges only appear while traffic flows, so generate some load, e.g.:
```
watch -n1 'curl -s "http://<remote-1-node-ip>:30080/api?content=<your-message>"'
```