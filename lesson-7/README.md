# lesson-7 — EKS + ECR + Helm

Terraform provisions an EKS (Kubernetes) cluster and an ECR repository inside
a dedicated VPC. The Django application from theme 4 is **vendored into this
repo** (`app/`, with its own `Dockerfile`) so the CI/CD pipeline built in
themes 8-9 can build it directly from here — it does not depend on the
theme-4 repo being checked out anywhere. The image is pushed to ECR and
deployed onto the cluster with a Helm chart: Deployment, Service
(LoadBalancer), ConfigMap + Secret, a Horizontal Pod Autoscaler (2–6 pods,
70% CPU), and — like theme 4's docker-compose "db" service — an **in-cluster
PostgreSQL StatefulSet**, so `helm install` works with zero external setup.
A bonus Ingress + cert-manager TLS template is included and disabled by
default.

> This project is a dependency for themes 8-9 (Jenkins + Argo CD) and the
> final project: they deploy onto this EKS cluster, push to this ECR repo,
> and update `image.tag` in `values.yaml` as the Jenkins ↔ Argo CD handoff
> contract. See the **checklist** at the bottom before moving on.

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
├── app/                        # Django app + Dockerfile, vendored from theme 4
│   ├── Dockerfile              # <- Jenkins (theme 9) builds this
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
│           ├── configmap.yaml     # non-secret env vars
│           ├── secret.yaml        # POSTGRES_PASSWORD, DJANGO_SECRET_KEY
│           ├── hpa.yaml
│           ├── postgres.yaml      # in-cluster Postgres (StatefulSet + Service)
│           ├── ingress.yaml       # bonus, disabled by default
│           ├── serviceaccount.yaml
│           ├── _helpers.tpl
│           └── NOTES.txt
│
└── scripts/
    └── push-to-ecr.sh          # Builds app/ and pushes it to ECR
```

## Architecture

- **VPC** — `10.0.0.0/16` with 3 public and 3 private subnets across three
  AZs, an Internet Gateway, and a single NAT Gateway. Subnets are tagged
  (`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`,
  `kubernetes.io/cluster/<name>=shared`) so EKS can auto-discover them when
  provisioning load balancers.
- **EKS** — control plane spanning all 6 subnets, a managed node group
  (`node_min_size=2`, `node_max_size=4`, `t3.micro` — Free Tier eligible,
  override with `-var='node_instance_types=["t3.small"]'` if your account
  allows bigger types) in the private subnets, plus the `vpc-cni`,
  `coredns`, `kube-proxy`, `aws-ebs-csi-driver`
  add-ons. The node role carries the three required AWS managed policies —
  `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly` — plus `AmazonEBSCSIDriverPolicy` so
  PersistentVolumeClaims (used by the in-cluster Postgres below) actually
  bind (see `modules/eks/iam.tf`). The identity that runs `terraform apply`
  is granted cluster-admin automatically
  (`bootstrap_cluster_creator_admin_permissions`).
- **ECR** — one repository (`lesson-7-ecr`) with scan-on-push, a lifecycle
  policy that keeps only the 10 most recent images, and a repository policy
  restricting push/pull to the current AWS account.
- **Helm chart (`django-app`)** — Deployment (2 replicas by default, HPA
  overrides this) with `resources.requests.cpu` set (required for the HPA
  to compute a percentage), Service of type `LoadBalancer`, a ConfigMap for
  non-secret env vars, a Secret for `POSTGRES_PASSWORD` /
  `DJANGO_SECRET_KEY`, both injected via `envFrom`, an HPA scaling 2→6 pods
  at 70% average CPU utilization, and a single-replica Postgres StatefulSet
  (`postgresql.enabled: true` by default) with a 5Gi PVC, wired to the same
  ConfigMap/Secret — `helm install` needs no external database.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured (`aws configure`)
- `kubectl`, [`helm`](https://helm.sh/docs/intro/install/) >= 3
- `docker`

The Django app is already vendored in `app/` — no external repo checkout
needed to build the image.

## 1. Bootstrap the Terraform backend

`backend.tf` points at an S3 bucket that Terraform itself creates
(`module.s3_backend`) — a chicken-and-egg problem on the very first run,
since `terraform init` fails if the bucket doesn't exist yet.

```bash
cd lesson-7
make bootstrap
```

`make bootstrap` runs, in order:

```bash
mv backend.tf backend.tf.disabled                      # hide the backend block
terraform init -input=false                             # local state
terraform apply -target=module.s3_backend -auto-approve  # create the bucket
mv backend.tf.disabled backend.tf                       # restore it
terraform init -migrate-state -force-copy \              # now point at S3...
  -backend-config="bucket=lesson-7-tfstate-$(aws sts get-caller-identity --query Account --output text)" \
  -backend-config="region=eu-north-1"
terraform apply                                          # ...and migrate the state into it
```

> **Why rename the file instead of `terraform init -backend=false`?** On
> some Terraform CLI versions `-backend=false` doesn't reliably persist
> across separate command invocations — a later `terraform apply` in the
> same directory can still error with *"Backend initialization required...
> Reason: Initial configuration of the requested backend 's3'"* even though
> you already ran `init -backend=false`. Temporarily renaming `backend.tf`
> away removes the backend block from the configuration entirely, so
> Terraform has nothing to reconcile — the same trick used in lesson-5. If
> you hit that error anyway (e.g. after `make clean` mid-bootstrap), fix it
> with:
> ```bash
> rm -rf .terraform
> mv backend.tf backend.tf.disabled 2>/dev/null; true
> terraform init -input=false
> ```
> and re-run `make bootstrap`.

> **Node group fails with `AsgInstanceLaunchFailures: ... not eligible for
> Free Tier`?** Your AWS account has the Free Tier instance restriction
> enabled, and only Free Tier-eligible types (`t2.micro`/`t3.micro`, region
> dependent) can be launched — `t3.medium` and even `t3.small` get rejected.
> The default is already `t3.micro` for this reason. If you already ran
> `make bootstrap` and it failed partway through (VPC/ECR created, node
> group failed), just re-run `make bootstrap` — Terraform will pick up where
> it left off. To check exactly which types your account allows:
> ```bash
> aws ec2 describe-instance-types --filters "Name=free-tier-eligible,Values=true" \
>   --query "InstanceTypes[].InstanceType" --output text
> ```
> If your account has no such restriction and you want more headroom (the
> default `t3.micro` — 1 GiB RAM — is tight once kube-proxy/vpc-cni/ebs-csi
> DaemonSets and the app pods share a node), override it:
> ```bash
> terraform apply -var='node_instance_types=["t3.small"]'
> ```

EKS cluster creation typically takes **10–15 minutes**.

## 2. Point kubectl at the cluster

```bash
make kubeconfig
# or:
aws eks update-kubeconfig --name lesson-7-eks --region eu-north-1
kubectl get nodes
```

## 3. Push the Django image to ECR

```bash
make docker-push
# or directly:
./scripts/push-to-ecr.sh eu-north-1 lesson-7-ecr latest
```

The script resolves your AWS account id, logs Docker in to ECR, builds
`app/` (`--platform linux/amd64` so it runs on the EKS x86_64 nodes even
from an Apple Silicon laptop), and pushes
`<account>.dkr.ecr.eu-north-1.amazonaws.com/lesson-7-ecr:latest`. This is
the same `app/` directory (and the same command shape) the Jenkins pipeline
in theme 9 will run — nothing to check out from elsewhere.

## 4. Install metrics-server (required by the HPA)

```bash
make metrics-server
```

Without metrics-server, `kubectl get hpa` will show `<unknown>/70%` forever
— see the checklist at the bottom.

## 5. Deploy the Helm chart

The chart deploys its own Postgres by default, so the only value you *must*
set is the image:

```bash
ECR_URL=$(terraform output -raw ecr_repository_url)

helm upgrade --install django-app charts/django-app \
  --set image.repository=$ECR_URL \
  --set image.tag=latest
```

(`make helm-install IMAGE=$ECR_URL` does the same thing.) For anything
beyond a quick personal test, also override the placeholder secrets:

```bash
helm upgrade --install django-app charts/django-app \
  --set image.repository=$ECR_URL \
  --set image.tag=latest \
  --set secrets.POSTGRES_PASSWORD=$(openssl rand -hex 16) \
  --set secrets.DJANGO_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(50))")
```

Never commit real secret values into `values.yaml` — use `--set` or a
gitignored `-f secrets.local.yaml`.

> **ConfigMap vs Secret.** `values.yaml#config` carries the non-sensitive
> env vars from theme 4 (`DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS`,
> `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PORT`) and is rendered into a
> `ConfigMap` (`templates/configmap.yaml`). The sensitive ones —
> `POSTGRES_PASSWORD` and `DJANGO_SECRET_KEY` — live under
> `values.yaml#secrets` and are rendered into a Kubernetes `Secret`
> (`templates/secret.yaml`, base64-encoded at rest by Kubernetes). Both are
> injected into the container the same way, with `envFrom`
> (`templates/deployment.yaml`). The Deployment restarts automatically
> whenever either one changes (`checksum/config` / `checksum/secret` pod
> annotations).
>
> **Database.** The theme-4 app has **no SQLite fallback** — every request
> (including `/`, which the probes use) queries PostgreSQL. This chart
> deploys its own single-replica Postgres (`templates/postgres.yaml`,
> `postgresql.enabled: true`), reusing the same ConfigMap/Secret for
> `POSTGRES_DB`/`POSTGRES_USER`/`POSTGRES_PASSWORD` — one source of truth,
> and `POSTGRES_HOST` is computed automatically to point at it
> (`templates/configmap.yaml`). It needs the `aws-ebs-csi-driver` add-on
> (already in `modules/eks/eks.tf`) for its PVC to bind.
>
> For anything beyond learning/testing — no backups, no HA, no failover —
> set `postgresql.enabled=false` and point `config.POSTGRES_HOST` at a
> managed database instead, e.g. Amazon RDS in the same VPC
> (`module.vpc.private_subnet_ids`):
> ```bash
> helm upgrade --install django-app charts/django-app \
>   --set image.repository=$ECR_URL \
>   --set postgresql.enabled=false \
>   --set config.POSTGRES_HOST=<your-rds-endpoint> \
>   --set secrets.POSTGRES_PASSWORD=<your-rds-password>
> ```

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

Check the ConfigMap/Secret are actually mounted, and that Postgres is up:

```bash
kubectl get configmap django-app-config -o yaml
kubectl get secret django-app-secret -o yaml   # values are base64, not plaintext
kubectl exec deploy/django-app -- env | grep -E 'DJANGO_|POSTGRES_'

kubectl get statefulset,pvc -l app.kubernetes.io/instance=django-app
kubectl logs django-app-postgres-0
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

## Чек-лист перед здачею (мінімальна планка з 5 пунктів)

| # | Критерій | Де перевірити |
|---|---|---|
| 1 | `terraform plan` без помилок | `cd lesson-7 && make validate` (тимчасово ховає `backend.tf` і робить `terraform validate`) |
| 2 | EKS + node group існують, 3 IAM-політики на нодах, `max_size > 1` | `modules/eks/iam.tf` (3 `aws_iam_role_policy_attachment.node_*`), `variables.tf#node_max_size=4` |
| 3 | Усі 4 шаблони рендеряться | `helm template . charts/django-app \| grep -E "^kind:"` → має вивести Deployment, Service, ConfigMap, Secret, HorizontalPodAutoscaler, StatefulSet, ServiceAccount |
| 4 | `resources.requests.cpu` у deployment.yaml | `values.yaml#resources.requests.cpu: 100m`, `templates/deployment.yaml` → `toYaml .Values.resources` |
| 5 | `values.yaml` має `image.repository` і `image.tag` | `charts/django-app/values.yaml` |

Перед тим, як здавати, прогоніть проти реального кластера:

```bash
kubectl get hpa            # має показувати реальний % у колонці TARGET, а не <unknown>
kubectl get pods           # 2+ у статусі Running, не Pending
kubectl get svc            # у LoadBalancer є зовнішній IP
helm template charts/django-app | kubectl apply --dry-run=client -f -   # коректність рендерингу
```

Якщо `kubectl get hpa` показує `<unknown>` — спершу перевірте, чи
встановлено metrics-server (`make metrics-server`) і чи задано
`resources.requests.cpu` (пункт 4).

### П'ять типових помилок — як з ними тут

- **CPU/memory requests відсутні** → задані у `values.yaml#resources` і
  прокинуті в `deployment.yaml`.
- **Замалий `max_size` node group** → `node_min_size=2`, `node_max_size=4`
  (більше за мінімум `min=1/max=3`). Тип інстансу — `t3.micro` (Free Tier
  eligible за замовчуванням; збільшіть, якщо акаунт дозволяє, див.
  troubleshooting нижче).
- **Секрети в ConfigMap** → `POSTGRES_PASSWORD` і `DJANGO_SECRET_KEY`
  винесені в окремий `Secret` (`templates/secret.yaml`), не в ConfigMap.
- **Dockerfile залишився в репо теми 4** → застосунок і `Dockerfile`
  скопійовані в `app/` цього репозиторію.
- **Замкнене коло bootstrap S3-бекенду** → описано і автоматизовано в
  `make bootstrap` (розділ 1 вище).

## Критерії прийняття (мапінг)

| Критерій | Де реалізовано |
|---|---|
| EKS через Terraform | `modules/eks/` (`eks.tf`, `iam.tf`) |
| ECR через Terraform | `modules/ecr/ecr.tf` |
| Deployment/Service/HPA через Helm | `charts/django-app/templates/{deployment,service,hpa}.yaml` |
| ConfigMap + Secret з env з теми 4 | `charts/django-app/templates/{configmap,secret}.yaml` + `values.yaml#config`/`#secrets` |
| Dockerfile у цьому репо | `app/Dockerfile` |
| PostgreSQL (як у docker-compose теми 4) | `charts/django-app/templates/postgres.yaml`, `values.yaml#postgresql`, EBS CSI addon у `modules/eks/eks.tf` |
| Бонус: Ingress + TLS | `charts/django-app/templates/ingress.yaml` (disabled за замовчуванням) |
