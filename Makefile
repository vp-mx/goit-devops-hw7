# Makefile for the lesson-7 Terraform + Helm project.
# Run `make help` to see the available targets.
#
# The project is account-agnostic: the state bucket name is derived from the
# current AWS account id, so anyone can plug in their own credentials and
# deploy into their own account without editing a single file.

PROJECT   ?= lesson-7
REGION    ?= eu-north-1
CLUSTER   ?= $(PROJECT)-eks
RELEASE   ?= django-app
NAMESPACE ?= default
CHART     ?= charts/django-app

# The state bucket name is unique per account. The account id is resolved at
# recipe run time because it needs live AWS credentials.
BACKEND_CONFIG = -backend-config="bucket=$(PROJECT)-tfstate-$$(aws sts get-caller-identity --query Account --output text)" -backend-config="region=$(REGION)"
TF_VARS        = -var="aws_region=$(REGION)" -var="project=$(PROJECT)"

.DEFAULT_GOAL := help
.PHONY: help init fmt validate plan apply bootstrap destroy clean \
        kubeconfig ecr-login docker-push metrics-server \
        helm-lint helm-template helm-install helm-uninstall status

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform and the remote backend
	terraform init $(BACKEND_CONFIG)

fmt: ## Format all Terraform files
	terraform fmt -recursive

validate: ## Validate the configuration without touching AWS
	mv backend.tf backend.tf.disabled
	terraform init -input=false || (mv backend.tf.disabled backend.tf && exit 1)
	terraform validate
	mv backend.tf.disabled backend.tf

plan: ## Show the execution plan
	terraform plan $(TF_VARS)

apply: ## Create or update the infrastructure (VPC + ECR + EKS)
	terraform apply $(TF_VARS)

# Bootstrap works around the chicken-and-egg problem: backend.tf points at an
# S3 bucket this same code creates, so the very first `terraform init` can't
# talk to a backend that doesn't exist yet. `-backend=false` is unreliable
# for this across separate CLI invocations on recent Terraform versions (it
# does not always "stick"), so instead we temporarily rename backend.tf out
# of the way — the same approach used in lesson-5.
bootstrap: ## First run: create the S3 backend, then migrate the state into it
	mv backend.tf backend.tf.disabled
	terraform init -input=false
	terraform apply -target=module.s3_backend -auto-approve $(TF_VARS)
	mv backend.tf.disabled backend.tf
	terraform init -migrate-state -force-copy $(BACKEND_CONFIG)
	terraform apply -auto-approve $(TF_VARS)

destroy: ## Destroy everything. Run `make helm-uninstall` first to remove the LoadBalancer.
	terraform destroy -target=module.eks -target=module.vpc -target=module.ecr -auto-approve $(TF_VARS)
	terraform state pull > terraform.tfstate
	mv backend.tf backend.tf.disabled
	terraform init -input=false
	terraform destroy -auto-approve $(TF_VARS)
	mv backend.tf.disabled backend.tf
	rm -f terraform.tfstate terraform.tfstate.backup

clean: ## Remove local Terraform working files
	rm -rf .terraform terraform.tfstate terraform.tfstate.backup backend.tf.disabled

total-cleanup: ## Fix backend state error after make destroy by cleaning up local and remote state
	rm -rf .terraform
	terraform init -backend=false
	terraform destroy -auto-approve $(TF_VARS)
	mv backend.tf.disabled backend.tf || true
	$(MAKE) clean

# ---------------------------------------------------------------------------
# Kubernetes / image
# ---------------------------------------------------------------------------
kubeconfig: ## Point kubectl at the cluster
	aws eks update-kubeconfig --name $(CLUSTER) --region $(REGION)

ecr-login: ## Log Docker in to the account's ECR registry
	aws ecr get-login-password --region $(REGION) | \
		docker login --username AWS --password-stdin \
		$$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$(REGION).amazonaws.com

docker-push: ## Build the theme-4 Django image and push it to ECR (uses scripts/push-to-ecr.sh)
	./scripts/push-to-ecr.sh $(REGION) $(PROJECT)-ecr

metrics-server: ## Install metrics-server (required by the HPA) into kube-system
	kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------
helm-lint: ## Lint the Helm chart
	helm lint $(CHART)

helm-template: ## Render the chart locally without a cluster
	helm template $(RELEASE) $(CHART)

helm-install: ## Install/upgrade the chart. Pass IMAGE=<ecr-url> to set the image.
	helm upgrade --install $(RELEASE) $(CHART) --namespace $(NAMESPACE) --create-namespace \
		$(if $(IMAGE),--set image.repository=$(IMAGE),)

helm-uninstall: ## Remove the release (also deletes the LoadBalancer / ELB)
	helm uninstall $(RELEASE) --namespace $(NAMESPACE)

status: ## Show pods, service, HPA and the external LoadBalancer address
	kubectl get pods,svc,hpa -l app.kubernetes.io/instance=$(RELEASE) -n $(NAMESPACE)
