# EKS + ECR + Helm Deployment

This repository contains Terraform code to provision an EKS (Kubernetes) cluster and an ECR repository inside a dedicated VPC on AWS. It also includes a Helm chart to deploy a Django application onto the cluster.

The application image is built from the `app/` directory and pushed to ECR. The Helm chart deploys a Deployment, Service (LoadBalancer), ConfigMap, Secret, a Horizontal Pod Autoscaler, and an in-cluster PostgreSQL StatefulSet.

## Project structure

```text
lesson-7/
│
├── main.tf                    # Wires the modules together
├── backend.tf                 # State backend configuration (S3 + DynamoDB)
├── provider.tf                # AWS provider + default tags
├── versions.tf                # Terraform / provider version constraints
├── variables.tf               # Root input variables
├── locals.tf                  # AZs, state bucket name, cluster name
├── outputs.tf                 # Aggregated outputs from all modules
├── Makefile                   # `make help` for all common commands
│
├── modules/
│   ├── s3-backend/            # S3 bucket + DynamoDB table for state
│   ├── vpc/                   # VPC, public/private subnets, IGW, NAT, routing
│   ├── ecr/                   # ECR repository for the application image
│   └── eks/                   # EKS cluster, managed node group, IAM, add-ons
│
├── app/                       # Application code + Dockerfile
│   ├── Dockerfile
│   ├── manage.py
│   ├── requirements.txt
│   ├── config/
│   └── core/
│
├── charts/
│   └── django-app/            # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── configmap.yaml
│           ├── secret.yaml
│           ├── hpa.yaml
│           ├── postgres.yaml
│           ├── ingress.yaml
│           ├── serviceaccount.yaml
│           ├── _helpers.tpl
│           └── NOTES.txt
│
└── scripts/
    └── push-to-ecr.sh         # Builds app/ and pushes it to ECR
```

## Architecture

- **VPC** — `10.0.0.0/16` with 3 public and 3 private subnets across three AZs, an Internet Gateway, and a single NAT Gateway. Subnets are tagged for EKS auto-discovery.
- **EKS** — control plane spanning all 6 subnets, a managed node group in the private subnets, plus necessary add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`). The node role carries the required AWS managed policies.
- **ECR** — repository with scan-on-push, a lifecycle policy to keep the 10 most recent images, and an access policy.
- **Helm chart** — Deployment, Service of type `LoadBalancer`, ConfigMap and Secret for environment variables, an HPA scaling based on CPU utilization, and a single-replica Postgres StatefulSet with a PVC.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured (`aws configure`)
- `kubectl`, [`helm`](https://helm.sh/docs/intro/install/) >= 3
- `docker`

## 1. Bootstrap the Terraform backend

Run the following command to bootstrap the remote state backend in S3 and DynamoDB:

```bash
make bootstrap
```

This command will initialize the backend, create the S3 bucket and DynamoDB table, and then migrate the state automatically. EKS cluster creation typically takes **10–15 minutes**.

## 2. Point kubectl at the cluster

```bash
make kubeconfig
# or:
aws eks update-kubeconfig --name lesson-7-eks --region eu-north-1
kubectl get nodes
```

## 3. Push the application image to ECR

```bash
make docker-push
# or directly:
./scripts/push-to-ecr.sh eu-north-1 lesson-7-ecr latest
```

## 4. Install metrics-server (required by the HPA)

```bash
make metrics-server
```

## 5. Deploy the Helm chart

Configure the ECR image URL and deploy the chart:

```bash
ECR_URL=$(terraform output -raw ecr_repository_url)

helm upgrade --install django-app charts/django-app \
  --set image.repository=$ECR_URL \
  --set image.tag=latest \
  --set secrets.POSTGRES_PASSWORD=$(openssl rand -hex 16) \
  --set secrets.DJANGO_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
```

*(Note: Never commit real secret values into `values.yaml` or version control. Use `--set` or a gitignored overrides file.)*

## 6. Verify

Check the deployed resources:

```bash
make status
# or:
kubectl get pods,svc,hpa -l app.kubernetes.io/instance=django-app
```

Get the external URL of the application:
```bash
kubectl get svc django-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

Test autoscaling:
```bash
kubectl run load-gen --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://django-app; done"
kubectl get hpa django-app -w
```

## 7. Teardown

To destroy the infrastructure, remove the Helm release first, then use the make command to tear down the infrastructure and the state bucket:

```bash
helm uninstall django-app
make destroy
```
