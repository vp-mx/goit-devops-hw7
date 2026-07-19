variable "name" {
  description = "Helm release name for Argo CD"
  type        = string
  default     = "argocd"
}

variable "namespace" {
  description = "Kubernetes namespace Argo CD is installed into"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Version of the argo/argo-cd Helm chart"
  type        = string
  default     = "10.1.4"
}

# --- What Argo CD should watch and deploy -------------------------------
variable "git_repo_url" {
  description = "HTTPS URL of the Git repository containing charts/django-app"
  type        = string
}

variable "git_branch" {
  description = "Branch Argo CD tracks (Jenkins pushes the updated image tag here)"
  type        = string
  default     = "main"
}

variable "app_name" {
  description = "Name of the Argo CD Application"
  type        = string
  default     = "django-app"
}

variable "app_chart_path" {
  description = "Path inside the Git repo to the Helm chart Argo CD deploys"
  type        = string
  default     = "charts/django-app"
}

variable "app_namespace" {
  description = "Kubernetes namespace the django-app chart gets deployed into"
  type        = string
  default     = "default"
}

variable "github_username" {
  description = "GitHub username Argo CD authenticates as to read the (private) repo"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token (read scope is enough) Argo CD uses to pull the repo"
  type        = string
  sensitive   = true
}

# --- django-app Helm values Argo CD must override -----------------------
# charts/django-app/values.yaml ships with placeholder values for these
# (REPLACE_WITH_ECR_REPOSITORY_URL / empty secrets) -- deliberately, so
# nothing real is ever committed. The manual `helm install --set ...` in
# the README covers a human running it by hand; Argo CD needs the
# equivalent passed as Application Helm parameters instead.
variable "app_image_repository" {
  description = "ECR repository URL for the django-app image (module.ecr.ecr_repository_url) -- overrides the values.yaml placeholder"
  type        = string
}
