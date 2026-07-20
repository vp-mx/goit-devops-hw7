# Terraform and provider version constraints for the whole project.
# The AWS provider is pinned to >= 5.40 because the EKS module uses the
# access_config block (authentication_mode / bootstrap_cluster_creator_admin_permissions),
# which was added in that release. Terraform itself is pinned to >= 1.10
# because backend.tf uses the S3 backend's use_lockfile option, introduced
# in that release (replaces the older DynamoDB-table locking mechanism).
#
# helm/kubernetes: used to install Jenkins and Argo CD straight from
# Terraform (modules/jenkins, modules/argo-cd), authenticating against the
# EKS cluster's own endpoint/token instead of a local kubeconfig.
# tls: used by modules/eks to fetch the OIDC issuer's certificate thumbprint
# for the IAM OIDC provider (IRSA).
# random: used by modules/argo_cd to generate stable POSTGRES_PASSWORD /
# DJANGO_SECRET_KEY values once (persisted in state) and pass them to the
# django-app Application as Helm parameters, instead of shipping placeholder
# secrets in charts/django-app/values.yaml.
terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25, < 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
