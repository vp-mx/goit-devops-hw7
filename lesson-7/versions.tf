# Terraform and provider version constraints for the whole project.
# The AWS provider is pinned to >= 5.40 because the EKS module uses the
# access_config block (authentication_mode / bootstrap_cluster_creator_admin_permissions),
# which was added in that release.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
  }
}
