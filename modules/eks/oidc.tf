# OIDC identity provider for the cluster — required for IRSA (IAM Roles for
# Service Accounts). Every Kubernetes service account that needs to assume
# an AWS IAM role (Jenkins' jenkins-sa for ECR push via Kaniko, Argo CD if it
# ever needs AWS access, etc.) trusts this provider in its role's
# assume-role policy.
#
# EKS clusters have an OIDC issuer URL by default (aws_eks_cluster.this.identity),
# but the IAM side (this resource) has to be created explicitly before any
# role can trust it.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]

  tags = { Name = "${var.cluster_name}-oidc" }
}
