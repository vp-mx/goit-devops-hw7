# Terraform and provider version constraints for the whole project.
# The AWS provider is pinned to >= 5.40 because the EKS module uses the
# access_config block (authentication_mode / bootstrap_cluster_creator_admin_permissions),
# which was added in that release. Terraform itself is pinned to >= 1.10
# because backend.tf uses the S3 backend's use_lockfile option, introduced
# in that release (replaces the older DynamoDB-table locking mechanism).
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }
}
