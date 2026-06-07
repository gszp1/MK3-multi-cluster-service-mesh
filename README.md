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