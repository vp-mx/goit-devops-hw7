# Declares which providers this module uses. No explicit provider blocks
# here — helm is configured once in the root module (provider.tf) and
# passed down implicitly, since it needs no alias for this module.
terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}
