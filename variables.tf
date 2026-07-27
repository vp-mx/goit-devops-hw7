# ---------------------------------------------------------------------------
# Global
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project name, used as a resource name prefix and in tags"
  type        = string
  default     = "lesson-7"
}

# ---------------------------------------------------------------------------
# Remote state backend
# ---------------------------------------------------------------------------
variable "state_bucket_name" {
  description = "S3 bucket for the Terraform state. Leave empty to derive a globally unique name from the account id."
  type        = string
  default     = ""
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-locks"
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------
variable "ecr_scan_on_push" {
  description = "Scan images for vulnerabilities on push"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Kubernetes control plane version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  # t3.micro's pod-per-node limit (AWS VPC CNI, ~4 pods/node) is too small to
  # fit Django + Postgres + Jenkins + Argo CD across 3 nodes, producing
  # FailedScheduling: "Too many pods" / "Insufficient memory". t3.small
  # roughly doubles both (2 GiB RAM, ~11 pods/node) and avoids this.
  #
  # Free Tier eligibility depends on when your AWS account was created:
  #   - before 2025-07-15: legacy Free Tier, t2.micro/t3.micro only
  #     (750 hrs/month) — t3.small WILL be billed.
  #   - on/after 2025-07-15: "$200 credit / 6 months" Free plan, which does
  #     cover t3.small.
  # If your account rejects t3.small with AsgInstanceLaunchFailures, fall
  # back to t3.micro with more nodes instead:
  #   terraform apply -var='node_instance_types=["t3.micro"]' -var='node_desired_size=5' -var='node_max_size=6'
  # Check what your account is actually allowed with:
  #   aws ec2 describe-instance-types --filters "Name=free-tier-eligible,Values=true" --query "InstanceTypes[].InstanceType"
  description = "EC2 instance types for the EKS worker nodes"
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}

# ---------------------------------------------------------------------------
# CI/CD: Jenkins + Argo CD (theme 8-9)
# ---------------------------------------------------------------------------
variable "git_repo_url" {
  description = "HTTPS URL of this Git repository — Jenkins builds app/Dockerfile from it, updates charts/django-app/values.yaml#image.tag and pushes back; Argo CD watches it to deploy charts/django-app"
  type        = string
  default     = "https://github.com/vp-mx/goit-devops-hw7.git"
}

variable "git_branch" {
  description = "Branch Jenkins pushes the image-tag-bump commit to and Argo CD tracks for deployments."
  type        = string
  default     = "lesson-8-9"
}

variable "github_username" {
  description = "GitHub username for the Personal Access Token below (used by both Jenkins and Argo CD to access the repo)"
  type        = string
}

variable "github_pat" {
  description = "GitHub Personal Access Token (repo scope) — required. Supply via TF_VAR_github_pat env var or a gitignored *.tfvars file; never commit a real value."
  type        = string
  sensitive   = true
}

variable "jenkins_admin_password" {
  description = "Jenkins admin password. Override for anything beyond a local/learning deployment."
  type        = string
  default     = "ChangeMe123!"
  sensitive   = true
}

variable "jenkins_persistence_enabled" {
  description = "Give Jenkins a PersistentVolumeClaim (requires the aws-ebs-csi-driver EKS add-on, currently NOT installed — see modules/eks). Left false by default: on t3.micro nodes, Jenkins + Argo CD + the app already use most of the available capacity, and JCasC/the seed job make Jenkins fully reproducible from code, so losing state on a pod restart isn't a big deal here."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Monitoring (final project, modules/monitoring)
# ---------------------------------------------------------------------------
variable "monitoring_grafana_admin_password" {
  description = "Grafana admin password. Leave null to have the module generate and store a random one in Terraform state (read it back via the sensitive grafana_admin_password output)."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# RDS (lesson-db-module, modules/rds)
# ---------------------------------------------------------------------------
variable "rds_enabled" {
  description = "Create the RDS database (module.rds). Off by default -- it's a real, billable AWS resource (standard RDS is Free Tier eligible on db.t3.micro/single-AZ, Aurora never is). Opt in with -var='rds_enabled=true'."
  type        = bool
  default     = false
}

variable "rds_use_aurora" {
  description = "true = Aurora Cluster, false = standard single-instance RDS. See modules/rds/README.md for the tradeoffs."
  type        = bool
  default     = false
}

variable "rds_engine" {
  description = "Database engine passed to module.rds (\"postgres\"/\"mysql\"/... or \"aurora-postgresql\"/\"aurora-mysql\" when rds_use_aurora = true)"
  type        = string
  default     = "postgres"
}

variable "rds_engine_version" {
  description = "Engine version passed to module.rds"
  type        = string
  default     = "16.4"
}

variable "rds_family" {
  description = "Parameter group family passed to module.rds -- must match rds_engine/rds_engine_version"
  type        = string
  default     = "postgres16"
}

variable "rds_instance_class" {
  description = "Instance class passed to module.rds. db.t3.micro is Free Tier eligible for standard RDS; Aurora needs db.t3.medium or larger."
  type        = string
  default     = "db.t3.micro"
}

variable "rds_multi_az" {
  description = "Multi-AZ standby for standard RDS (ignored for Aurora -- see modules/rds)"
  type        = bool
  default     = false
}

variable "rds_database_name" {
  # Matches charts/django-app/values.yaml#config.POSTGRES_DB, so this lines
  # up if you point the Django app at this RDS instance instead of the
  # chart's own in-cluster Postgres (--set postgresql.enabled=false --set
  # config.POSTGRES_HOST=<module.rds address>).
  description = "Default database name passed to module.rds"
  type        = string
  default     = "app_db"
}

variable "rds_master_username" {
  # Matches charts/django-app/values.yaml#config.POSTGRES_USER, same reason
  # as rds_database_name above.
  description = "Master username passed to module.rds"
  type        = string
  default     = "app_user"
}
