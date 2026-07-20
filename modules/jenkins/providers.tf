# Declares which providers this module uses. No explicit provider blocks
# here — helm/kubernetes/aws are configured once in the root module
# (provider.tf) and passed down implicitly, since none of them need an
# alias for this module.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}
