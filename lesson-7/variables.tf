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
  # t3.micro is Free Tier eligible (unlike t3.small/t3.medium) — AWS rejects
  # non-eligible types on accounts with the Free Tier restriction enabled:
  # "InvalidParameterCombination - The specified instance type is not
  # eligible for Free Tier". If your account doesn't have that restriction,
  # override with a bigger type for more headroom, e.g.:
  #   terraform apply -var='node_instance_types=["t3.small"]'
  # Check what your account is actually allowed with:
  #   aws ec2 describe-instance-types --filters "Name=free-tier-eligible,Values=true" --query "InstanceTypes[].InstanceType"
  description = "EC2 instance types for the EKS worker nodes"
  type        = list(string)
  default     = ["t3.micro"]
}

variable "node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}
