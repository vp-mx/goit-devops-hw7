variable "cluster_name" {
  description = "Name of the EKS cluster Jenkins is installed into"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace Jenkins is installed into"
  type        = string
  default     = "jenkins"
}

variable "chart_version" {
  description = "Version of the jenkinsci/jenkins Helm chart"
  type        = string
  default     = "5.9.29"
}

# --- IRSA (so the jenkins-sa service account / Kaniko builds can push to ECR) ----
variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (modules/eks output oidc_provider_arn)"
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster, including https:// (modules/eks output oidc_issuer_url)"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository Kaniko pushes images to"
  type        = string
}

variable "ecr_repository_url" {
  description = "URL of the ECR repository (module.ecr.ecr_repository_url) — wired in as the ECR_REPOSITORY parameter default on the generated pipeline job, so the Jenkinsfile never needs a hardcoded account id/region"
  type        = string
}

# --- Jenkins controller ------------------------------------------------------
variable "admin_username" {
  description = "Jenkins admin username"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Jenkins admin password. Override for anything beyond a local/learning deployment."
  type        = string
  default     = "ChangeMe123!"
  sensitive   = true
}

variable "persistence_enabled" {
  description = "Whether Jenkins gets a PersistentVolumeClaim (requires the aws-ebs-csi-driver EKS add-on and an 'ebs-sc' StorageClass). Left false by default: on small (t3.micro) clusters, Jenkins + Argo CD + the app already fill up available node capacity, and JCasC/the seed job make Jenkins fully reproducible from code anyway, so losing state on a pod restart is not a big deal for this project."
  type        = bool
  default     = false
}

variable "resources" {
  # 1.5Gi limit leaves enough headroom for plugin loading on first boot
  # (kubernetes/workflow-aggregator/git/configuration-as-code/github/job-dsl
  # all initializing at once) without OOM-killing the controller; pair with
  # an explicit -Xmx (see controller.javaOpts in values.yaml.tpl). t3.small
  # nodes (2GiB each) have room for this alongside Django/Postgres/Argo CD.
  description = "CPU/memory requests and limits for the Jenkins controller pod"
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "300m", memory = "768Mi" }
    limits   = { cpu = "1000m", memory = "1536Mi" }
  }
}

# --- Git / CI configuration ---------------------------------------------------
variable "git_repo_url" {
  description = "HTTPS URL of the Git repository Jenkins clones (this repo — contains the Jenkinsfile, the Django app under app/, and the Helm chart under charts/django-app)"
  type        = string
}

variable "git_branch" {
  description = "Branch Jenkins builds from and the seed-job/pipeline track"
  type        = string
  default     = "main"
}

variable "github_username" {
  description = "GitHub username Jenkins authenticates as (for cloning + pushing the updated image tag)"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token with repo read/write scope, used by Jenkins (JCasC credential) to clone the repo and push the updated Helm chart tag"
  type        = string
  sensitive   = true
}
