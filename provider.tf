# AWS provider configuration shared by all modules.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# ---------------------------------------------------------------------------
# EKS cluster connection details, used to configure the helm/kubernetes
# providers below so Terraform can install Jenkins and Argo CD directly via
# helm_release (modules/jenkins, modules/argo-cd) — no local kubeconfig
# needed. These data sources depend on module.eks, so on a first-ever
# `terraform apply` Terraform creates the cluster before reading them.
# ---------------------------------------------------------------------------
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
