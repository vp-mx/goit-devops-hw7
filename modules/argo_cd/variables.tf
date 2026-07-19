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
