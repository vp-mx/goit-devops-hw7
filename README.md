# EKS + ECR + RDS + Helm + Jenkins + Argo CD + Prometheus/Grafana

This repository contains Terraform code to provision a full DevOps stack on AWS: a VPC, an EKS (Kubernetes) cluster, an ECR repository, an optional RDS/Aurora database, and — on top of the cluster — a Helm chart deploying a Django application, a full CI/CD pipeline (**Jenkins** + **Argo CD**), and a monitoring stack (**Prometheus** + **Grafana** + `metrics-server`).

**CI/CD:** Jenkins builds the Django image with Kaniko and pushes it to ECR, then bumps `charts/django-app/values.yaml#image.tag` and pushes that commit back to this repo; Argo CD watches the same repo/path and automatically syncs the cluster to match — Git is the handoff between the two.

The application image is built from the `app/` directory. The Helm chart deploys a Deployment, Service (LoadBalancer), ConfigMap, Secret, a Horizontal Pod Autoscaler, and an in-cluster PostgreSQL StatefulSet (or point it at the `rds` module's output instead — see [Architecture](#architecture)).

## Project structure

```text
goit-devops-hw7/
│
├── main.tf                    # Wires the modules together
├── backend.tf                 # State backend configuration (S3 + DynamoDB)
├── provider.tf                # AWS + helm + kubernetes providers
├── versions.tf                # Terraform / provider version constraints
├── variables.tf               # Root input variables
├── locals.tf                  # AZs, state bucket name, cluster name
├── outputs.tf                 # Aggregated outputs from all modules
├── Jenkinsfile                 # Kaniko build+push, then bump chart tag + push to Git
├── Makefile                   # `make help` for all common commands
│
├── modules/
│   ├── s3-backend/            # S3 bucket + DynamoDB table for state
│   ├── vpc/                   # VPC, public/private subnets, IGW, NAT, routing
│   ├── ecr/                   # ECR repository for the application image
│   ├── eks/                   # EKS cluster, managed node group, IAM, OIDC provider
│   ├── rds/                   # Flexible standard-RDS/Aurora module (off by default, see rds_enabled)
│   ├── jenkins/                # Jenkins via Helm: JCasC, pipeline auto-created via jobs:, IRSA for Kaniko
│   ├── argo_cd/                 # Argo CD via Helm + Application/repository-credential chart
│   └── monitoring/              # kube-prometheus-stack (Prometheus+Grafana) + metrics-server via Helm
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
    └── push-to-ecr.sh         # Builds app/ and pushes it to ECR (manual/first push, before Jenkins takes over)
```

## Architecture

- **VPC** — `10.0.0.0/16` with 3 public and 3 private subnets across three AZs, an Internet Gateway, and a single NAT Gateway. Subnets are tagged for EKS auto-discovery.
- **EKS** — control plane spanning all 6 subnets, a managed node group in the private subnets, plus necessary add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`). The node role carries the required AWS managed policies.
- **ECR** — repository with scan-on-push, a lifecycle policy to keep the 10 most recent images, and an access policy.
- **Helm chart** — Deployment, Service of type `LoadBalancer`, ConfigMap and Secret for environment variables, an HPA scaling based on CPU utilization, and a single-replica Postgres StatefulSet with a PVC.
- **Jenkins** (`modules/jenkins`) — installed via the `jenkinsci/jenkins` Helm chart. JCasC provisions a `github-token` credential and, via its native `jobs:` key (a trusted Job DSL script run directly at controller boot — no separate seed job or manual Script Approval needed), creates the `django-app-pipeline` pipeline job pointed at the `Jenkinsfile` in this repo. Builds run as short-lived Kubernetes pod agents (`kaniko` + `git` containers) under a `jenkins-sa` service account bound via IRSA to an IAM role scoped to `ecr:PutImage`/etc. on this project's ECR repo only — no static AWS keys anywhere in Jenkins.
- **Argo CD** (`modules/argo_cd`) — installed via the official `argo/argo-cd` Helm chart (dex/applicationSet/notifications disabled to save resources), plus a small local chart (`modules/argo_cd/charts`) that declares the `django-app` `Application` CRD (pointing at `charts/django-app` on the tracked branch, `automated: {prune: true, selfHeal: true}`) and a repository-credential `Secret` so Argo CD can pull this (private) repo.
- **Monitoring** (`modules/monitoring`) — `prometheus-community/kube-prometheus-stack` (Prometheus + Grafana + kube-state-metrics + node-exporter; Alertmanager and the EKS-unreachable control-plane scrape targets are disabled) plus `metrics-server` (feeds the HPA and `kubectl top`). Everything is ClusterIP-only and PVC-free (no `aws-ebs-csi-driver` add-on installed) — reached via `kubectl port-forward`, see the [Verification checklist](#verification-checklist) below. Always on: unlike RDS, it creates no billable AWS resources.
- **RDS** (`modules/rds`, off by default via `rds_enabled = false`) — a flexible module that creates either a standard `aws_db_instance` or an Aurora cluster (`use_aurora`), plus its own DB Subnet Group, Security Group and Parameter Group. See `modules/rds/README.md` for the full variable reference. Left disabled by default because it's a real, billable resource on top of everything else; the chart's own in-cluster Postgres is what `charts/django-app` uses out of the box. To point the app at RDS instead:
  ```bash
  terraform apply -var='rds_enabled=true'
  helm upgrade --install django-app charts/django-app \
    --set postgresql.enabled=false \
    --set config.POSTGRES_HOST=$(terraform output -json | jq -r '.rds_endpoint.value' | cut -d: -f1)
  ```

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.10
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured (`aws configure`)
- `kubectl`, [`helm`](https://helm.sh/docs/intro/install/) >= 3
- `docker` (only needed for the manual first push in step 3 — after that, Jenkins builds images itself)
- A GitHub [Personal Access Token](https://github.com/settings/tokens) (classic, `repo` scope) for the account that owns this repo — Jenkins uses it to push the chart-tag-bump commit, Argo CD uses it to pull the repo.

## 1. Bootstrap the Terraform backend

`github_username` and `github_pat` have no defaults (Jenkins and Argo CD both need them to read/write this repo) — set them as `TF_VAR_*` env vars so they're picked up automatically by every `terraform`/`make` command below, and never end up typed into a shell history or committed to a `.tfvars` file:

```bash
export TF_VAR_github_username=<your-github-username>
export TF_VAR_github_pat=<your-personal-access-token>
```

Or, to avoid re-typing them every session, copy `.env.example` to `.env` (gitignored) and fill in real values, then load it with either:

```bash
set -a && source .env && set +a
# or, via the Makefile:
eval "$(make reload-env)"
```

(`make reload-env` on its own can't set variables in your shell — a Makefile recipe runs in a subshell — so it just prints `export ...` lines; `eval` is what actually applies them to your current shell.)

Then bootstrap the remote state backend in S3 and DynamoDB:

```bash
make bootstrap
```

This command will initialize the backend, create the S3 bucket and DynamoDB table, and then migrate the state automatically. It also creates the EKS cluster, ECR repo, Jenkins and Argo CD in the same run. EKS cluster creation typically takes **10–15 minutes**; Jenkins/Argo CD come up a couple of minutes after that.

## 2. Point kubectl at the cluster

```bash
make kubeconfig
# or:
aws eks update-kubeconfig --name lesson-7-eks --region eu-north-1
kubectl get nodes
```

## 3. Push the application image to ECR (first time only)

Jenkins builds and pushes every image from here on (see step 7); this manual push is only needed once, to have something for the very first `helm install` in step 5 to deploy.

```bash
make docker-push
# or directly:
./scripts/push-to-ecr.sh eu-north-1 lesson-7-ecr latest
```

## 4. Deploy the Helm chart

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

## 5. Verify

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

## 6. CI/CD: run the Jenkins pipeline, watch Argo CD sync

Jenkins and Argo CD are both installed and configured by the same `make bootstrap` / `terraform apply` from step 1 — nothing extra to install by hand.

**Open Jenkins:**

```bash
make jenkins-url        # external LoadBalancer hostname
make jenkins-password   # admin / <this password>, or TF_VAR_jenkins_admin_password if you overrode it
```

Log in and confirm `django-app-pipeline` already exists in the job list — JCasC creates it automatically at controller boot (via its `jobs:` key), no manual clicking required. Open it → **Build Now**. The pipeline:
1. **Build & Push Docker Image** — runs `app/Dockerfile` through Kaniko (as the `jenkins-sa` pod, using IRSA — no AWS keys stored anywhere) and pushes `<ecr-repo>:v1.0.<build-number>` and `:latest` to ECR.
2. **Update Chart Tag in Git** — `sed`s the new tag into `charts/django-app/values.yaml#image.tag`, commits, and pushes to the tracked branch using the `github-token` credential.

Watch the build's console output for both stages; a green build means the tag-bump commit is now on the tracked branch (`git_branch`, default `final-project`; override with `-var git_branch=main` once merged).

**Open Argo CD and watch it pick up the commit:**

```bash
make argocd-url         # external LoadBalancer hostname
make argocd-password    # initial admin password (user: admin)
make argocd-app-status  # sync/health status from the CLI, e.g.:
kubectl get application django-app -n argocd
```

`syncPolicy.automated` (`prune: true`, `selfHeal: true`) means Argo CD re-syncs on its own polling interval after the Jenkins push — no manual sync needed, though you can trigger one immediately from the UI (**django-app → SYNC**) if you don't want to wait. Once synced, `kubectl get pods -l app.kubernetes.io/instance=django-app` should show pods running the new tag.

**Capacity note:** Jenkins + Argo CD + Django + Postgres + the monitoring stack (Prometheus, Grafana, kube-state-metrics, node-exporter, metrics-server) all run on the same node group, sized `t3.small` by default (see `node_instance_types`/`node_desired_size` in `variables.tf`) — `t3.micro`'s AWS VPC CNI pod-per-node limit (~4 pods/node) is too low to fit everything together, so `t3.small` (~11 pods/node) is the default instead. Requests/limits are deliberately small everywhere and Argo CD's dex/applicationSet/notifications components plus Alertmanager are disabled to leave headroom regardless. If pods still stay `Pending`, bump `node_desired_size`/`node_max_size`, or fall back to `t3.micro` with more nodes if your AWS account doesn't cover `t3.small` under its Free Tier (see the note above `node_instance_types` in `variables.tf`).

## 7. Monitoring: Prometheus + Grafana

Installed and configured by the same `terraform apply` as everything else — `modules/monitoring` (`kube-prometheus-stack` + `metrics-server`), no manual Helm install needed.

```bash
kubectl get all -n monitoring
```

**Open Grafana** (username `admin`):

```bash
kubectl port-forward -n monitoring svc/grafana 3000:80
terraform output -raw grafana_admin_password
```

Then visit `http://localhost:3000` — the `Prometheus` datasource and two dashboards (Kubernetes cluster, Node Exporter) are auto-provisioned, so there's something to look at immediately.

**Open Prometheus** (confirm targets are `UP` under Status → Targets):

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

Alertmanager and the `kubeScheduler`/`kubeControllerManager`/`kubeEtcd`/`kubeProxy` scrape jobs are disabled on purpose — EKS is a managed control plane, so those targets are never reachable and would just sit permanently `down` (see `modules/monitoring/values.yaml`).

## 8. Verification checklist

Quick end-to-end smoke test — confirms every piece is actually up, not just that `terraform apply` exited 0:

```bash
kubectl get all -n jenkins
kubectl get all -n argocd
kubectl get all -n monitoring

kubectl port-forward svc/jenkins 8080:8080 -n jenkins
kubectl port-forward svc/argocd-server 8081:443 -n argocd
kubectl port-forward svc/grafana 3000:80 -n monitoring

kubectl get hpa django-app   # real %, not <unknown> -- needs metrics-server (modules/monitoring)
kubectl get pods             # 2+ Running
kubectl get svc django-app   # external LoadBalancer address
```

| Area | Where it lives |
|---|---|
| Architecture (VPC/EKS/ECR/RDS) | `modules/vpc`, `modules/eks`, `modules/ecr`, `modules/rds` |
| Security (VPC, IAM, Security Groups) | private subnets for nodes/RDS, IRSA (no static AWS keys), least-privilege ECR policy, RDS/EKS security groups |
| CI/CD | `charts/django-app` + `modules/jenkins` + `modules/argo_cd`, step 6 above |
| Monitoring + autoscaling | `modules/monitoring` (Prometheus/Grafana/metrics-server) + `charts/django-app/templates/hpa.yaml`, step 7 above |
| Docs | this README + `modules/rds/README.md` |

## 9. Teardown

To destroy the infrastructure, remove the `django-app` Helm release first (Jenkins/Argo CD are Terraform-managed `helm_release` resources, so `make destroy` cleans those — and their LoadBalancers — up on its own):

```bash
helm uninstall django-app
make destroy
```
