# lesson-7 — EKS + ECR + Helm

Terraform provisions an EKS (Kubernetes) cluster and an ECR repository inside
a dedicated VPC. The Django application built in theme 4
(`../goit-devops-hw`) is pushed to ECR and deployed onto the cluster with a
Helm chart: Deployment, Service (LoadBalancer), ConfigMap and a Horizontal
Pod Autoscaler (2–6 pods, 70% CPU). A bonus Ingress + cert-manager TLS
template is included and disabled by default.

## Project structure

```
lesson-7/
│
├── main.tf                    # Wires the modules together
├── backend.tf                 # State backend configuration (S3 + DynamoDB)
├── provider.tf                # AWS provider + default tags
├── versions.tf                # Terraform / provider version constraints
├── variables.tf                # Root input variables
├── locals.tf                  # AZs, state bucket name, cluster name
├── outputs.tf                 # Aggregated outputs from all modules
├── Makefile                   # `make help` for all common commands
│
├── modules/
│   ├── s3-backend/            # S3 bucket + DynamoDB table for state
│   ├── vpc/                   # VPC, public/private subnets, IGW, NAT, routing
│   ├── ecr/                   # ECR repository for the Django image
│   └── eks/                   # EKS cluster, managed node group, IAM, add-ons
│
├── charts/
│   └── django-app/            # Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── configmap.yaml
│           ├── hpa.yaml
│           ├── ingress.yaml       # bonus, disabled by default
│           ├── serviceaccount.yaml
│           ├── _helpers.tpl
│           └── NOTES.txt
│
└── scripts/
    └── push-to-ecr.sh          # Builds the theme-4 image and pushes it to ECR
```

## Architecture

- **VPC** — `10.0.0.0/16` with 3 public and 3 private subnets across three
  AZs, an Internet Gateway, and a single NAT Gateway. Subnets are tagged
  (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`,
  `kubernetes.io/cluster/<name>=shared`) so EKS can auto-discover them when
  provisioning load balancers.
- **EKS** — control plane spanning all 6 subnets, a managed node group
  (2–4 `t3.medium` nodes) in the private subnets, and the `vpc-cni`,
  `coredns`, `kube-proxy` add-ons. The identity that runs `terraform apply`
  is granted cluster-admin automatically (`bootstrap_cluster_creator_admin_permissions`).
- **ECR** — one repository (`lesson-7-ecr`) with scan-on-push, a lifecycle
  policy that keeps only the 10 most recent images, and a repository policy
  restricting push/pull to the current AWS account.
- **Helm chart (`django-app`)** — Deployment (2 replicas by default, HPA
  overrides this), Service of type `LoadBalancer`, ConfigMap with the
  theme-4 environment variables injected via `envFrom`, and an HPA scaling
  2→6 pods at 70% average CPU utilization.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured (`aws configure`)
- `kubectl`, [`helm`](https://helm.sh/docs/intro/install/) >= 3
- `docker`
- The theme-4 Django project checked out as a sibling directory:
  `../goit-devops-hw` (used to build the image pushed to ECR)

## 1. Bootstrap the Terraform backend

Same chicken-and-egg problem as in lesson-5: `backend.tf` points at an S3
bucket that doesn't exist yet on the first run.

```bash
cd lesson-7
make bootstrap
```

This creates the S3 bucket + DynamoDB table with local state, migrates the
state into S3, then applies the rest (VPC, ECR, EKS). Equivalent manual
steps:

```bash
terraform init -backend=false
terraform apply -target=module.s3_backend -auto-approve
terraform init -migrate-state -force-copy \
  -backend-config="bucket=lesson-7-tfstate-$(aws sts get-caller-identity --query Account --output text)" \
  -backend-config="region=eu-north-1"
terraform apply
```

EKS cluster creation typically takes **10–15 minutes**.

## 2. Point kubectl at the cluster

```bash
make kubeconfig
# or:
aws eks update-kubeconfig --name lesson-7-eks --region eu-north-1
kubectl get nodes
```

## 3. Push the theme-4 Django image to ECR

```bash
make docker-push
# or directly:
./scripts/push-to-ecr.sh eu-north-1 lesson-7-ecr latest
```

The script resolves your AWS account id, logs Docker in to ECR, builds the
image from `../goit-devops-hw` (the theme-4 project, `--platform linux/amd64`
so it runs on the EKS x86_64 nodes even from an Apple Silicon laptop), and
pushes `<account>.dkr.ecr.eu-north-1.amazonaws.com/lesson-7-ecr:latest`.

If your theme-4 project lives somewhere else, pass its path as the 4th
argument: `./scripts/push-to-ecr.sh eu-north-1 lesson-7-ecr latest /path/to/goit-devops-hw`.

## 4. Install metrics-server (required by the HPA)

```bash
make metrics-server
```

## 5. Deploy the Helm chart

Get the ECR URL and install:

```bash
ECR_URL=$(terraform output -raw ecr_repository_url)

helm upgrade --install django-app charts/django-app \
  --set image.repository=$ECR_URL \
  --set image.tag=latest \
  --set config.POSTGRES_HOST=<your-postgres-host> \
  --set config.POSTGRES_PASSWORD=<your-postgres-password> \
  --set config.DJANGO_SECRET_KEY=<your-secret-key>
```

(`make helm-install IMAGE=$ECR_URL` does the same for the image, then you can
`--set` the rest or edit `charts/django-app/values.yaml` directly.)

> **About the ConfigMap / env vars.** `values.yaml#config` carries over the
> variables from theme 4 (`goit-devops-hw/.env.example`):
> `DJANGO_SECRET_KEY`, `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`, `POSTGRES_DB`,
> `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`, `POSTGRES_PORT`.
> They're rendered into a ConfigMap (`templates/configmap.yaml`) and injected
> into the container with `envFrom` (`templates/deployment.yaml`). The
> Deployment restarts automatically whenever the ConfigMap content changes
> (`checksum/config` pod annotation).
>
> The theme-4 app has **no SQLite fallback** — every request (including `/`,
> which the probes use) queries PostgreSQL. `POSTGRES_HOST` must point at a
> reachable database for the pods to become `Ready` — e.g. an Amazon RDS
> instance in the same VPC (`module.vpc.private_subnet_ids`), or any Postgres
> reachable from the cluster. Provisioning RDS is outside this chart's scope
> (not part of the required deliverables); for a quick manual test you can
> also run Postgres as a throwaway pod:
> `kubectl run postgres --image=postgres:16-alpine --env=POSTGRES_PASSWORD=<pwd> --port=5432 --expose`
> and point `POSTGRES_HOST` at `postgres.default.svc.cluster.local`.

## 6. Verify

```bash
make status
# or:
kubectl get pods,svc,hpa -l app.kubernetes.io/instance=django-app

# External URL (may take ~1 min for the ELB to be provisioned):
kubectl get svc django-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

Open `http://<that-hostname>/` — the app's only route (`core.views.index`)
returns `{"status": "ok", "message": "Django + PostgreSQL + Nginx are working"}`
once it can reach Postgres.

Check the ConfigMap is actually mounted:

```bash
kubectl get configmap django-app-config -o yaml
kubectl exec deploy/django-app -- env | grep -E 'DJANGO_|POSTGRES_'
```

Load-test to see the HPA react:

```bash
kubectl run load-gen --image=busybox --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://django-app; done"
kubectl get hpa django-app -w
```

## 7. Teardown

Removing everything with a single `terraform destroy` deletes the S3 bucket
that holds the state along with everything else and the state is lost mid
run. Do it in order:

```bash
helm uninstall django-app          # removes the pods AND the ELB (Service)
make destroy                       # destroys EKS/VPC/ECR, then the S3 backend
```

`make destroy` internally: destroys `module.eks`, `module.vpc`, `module.ecr`
first (keeping the backend intact), pulls the now-small state locally, then
destroys the S3 bucket + DynamoDB table.

---

## Бонус: Ingress + TLS через cert-manager (домен на Cloudflare — mx.od.ua)

Кроки нижче для домену **mx.od.ua**, керованого через Cloudflare. Вони
універсальні для будь-якого домену на Cloudflare — просто підставте свій.

### 1. Встановіть ingress-nginx controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

Дочекайтеся зовнішньої адреси контролера (AWS ELB):

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

### 2. Створіть DNS-запис у Cloudflare

У Cloudflare Dashboard → **mx.od.ua** → DNS → Add record:

- Type: `CNAME`
- Name: субдомен, наприклад `django` (тобто `django.mx.od.ua`) — не
  використовуйте apex-домен для CNAME
- Target: hostname ELB з попереднього кроку
- Proxy status: **DNS only** (сіра хмаринка). Це важливо для першого
  запуску — HTTP-01 challenge cert-manager повинен достукатись напряму до
  ingress-controller. Проксі (помаранчева хмаринка) можна ввімкнути після
  того, як сертифікат випущено.

### 3. Встановіть cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true
```

### 4. Створіть ClusterIssuer (Let's Encrypt)

**Варіант A — HTTP-01** (простіший, вимагає Proxy status = DNS only):

```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```

**Варіант B — DNS-01 через Cloudflare API token** (працює і з увімкненим
проксі Cloudflare — рекомендовано, якщо хочете тримати orange-cloud):

```bash
# API token у Cloudflare: My Profile → API Tokens → Create Token →
# шаблон "Edit zone DNS", обмежений на зону mx.od.ua.
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token=<your-cloudflare-api-token>
```

```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

```bash
kubectl apply -f cluster-issuer.yaml
```

### 5. Увімкніть Ingress у Helm-чарті

```bash
helm upgrade --install django-app charts/django-app \
  --set image.repository=$ECR_URL \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.host=django.mx.od.ua \
  --set ingress.tls=true \
  --set ingress.clusterIssuer=letsencrypt-prod
```

### 6. Перевірте сертифікат

```bash
kubectl get certificate
kubectl describe certificate django-app-tls
```

Коли `READY=True`, відкрийте `https://django.mx.od.ua/`. Після цього можна
повернути в Cloudflare Proxy status на "Proxied" (помаранчева хмаринка), якщо
використовувався DNS-01 issuer.

---

## Критерії прийняття (мапінг)

| Критерій | Де реалізовано |
|---|---|
| EKS через Terraform | `modules/eks/` (`eks.tf`, `iam.tf`) |
| ECR через Terraform | `modules/ecr/ecr.tf` |
| Deployment/Service/HPA через Helm | `charts/django-app/templates/{deployment,service,hpa}.yaml` |
| ConfigMap з env з теми 4 | `charts/django-app/templates/configmap.yaml` + `values.yaml#config` |
| Бонус: Ingress + TLS | `charts/django-app/templates/ingress.yaml` (disabled за замовчуванням) |
