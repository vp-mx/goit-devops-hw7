# Aggregated outputs from all modules.

# --- S3 backend --------------------------------------------------------
output "state_bucket_name" {
  description = "Name of the S3 bucket that stores the Terraform state"
  value       = module.s3_backend.bucket_name
}

output "dynamodb_lock_table" {
  description = "Name of the DynamoDB table used for state locking"
  value       = module.s3_backend.dynamodb_table_name
}

# --- VPC -----------------------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# --- ECR -------------------------------------------------------------------
output "ecr_repository_url" {
  description = "URL of the ECR repository (use as image.repository in the Helm chart)"
  value       = module.ecr.ecr_repository_url
}

# --- EKS -------------------------------------------------------------------
output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the Kubernetes API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = module.eks.cluster_version
}

output "update_kubeconfig_command" {
  description = "Run this to point kubectl at the cluster"
  value       = module.eks.update_kubeconfig_command
}

# --- Jenkins ---------------------------------------------------------------
output "jenkins_namespace" {
  description = "Namespace Jenkins is deployed into"
  value       = module.jenkins.jenkins_namespace
}

output "jenkins_url_command" {
  description = "Command to fetch the Jenkins UI's external URL"
  value       = module.jenkins.jenkins_url_command
}

# --- Argo CD -----------------------------------------------------------------
output "argocd_url_command" {
  description = "Command to fetch the Argo CD UI's external URL"
  value       = module.argo_cd.argocd_url_command
}

output "argocd_admin_password_command" {
  description = "Command to fetch the Argo CD initial admin password"
  value       = module.argo_cd.admin_password_command
}
