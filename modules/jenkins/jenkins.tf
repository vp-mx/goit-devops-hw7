# Jenkins, installed via Helm straight from Terraform, running as a
# Kubernetes-native CI server: the controller runs as a pod in this
# namespace, and every build spins up its own short-lived agent pod
# (Kaniko + git) via the Jenkins Kubernetes plugin.

locals {
  # Condition key for the OIDC trust policy below needs the issuer host
  # without the "https://" scheme, e.g. "oidc.eks.eu-north-1.amazonaws.com/id/XXXX".
  oidc_provider = replace(var.oidc_issuer_url, "https://", "")
}

# ---------------------------------------------------------------------------
# IRSA: lets the jenkins-sa service account (used by the Kaniko build pod)
# assume an IAM role scoped to just pushing images to our ECR repo — no
# static AWS keys anywhere in Jenkins.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "jenkins_kaniko_role" {
  name = "${var.cluster_name}-jenkins-kaniko-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:sub" = "system:serviceaccount:${var.namespace}:jenkins-sa"
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = { Name = "${var.cluster_name}-jenkins-kaniko-role" }
}

resource "aws_iam_role_policy" "jenkins_ecr_policy" {
  name = "${var.cluster_name}-jenkins-ecr-policy"
  role = aws_iam_role.jenkins_kaniko_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken does not support resource-level scoping —
        # AWS requires Resource "*" for this specific action.
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
        ]
        Resource = var.ecr_repository_arn
      }
    ]
  })
}

# Kubernetes service account Kaniko pods run as, bound to the IAM role above.
resource "kubernetes_service_account" "jenkins_sa" {
  metadata {
    name      = "jenkins-sa"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.jenkins_kaniko_role.arn
    }
  }

  # The Jenkins Helm release below references this namespace/SA, so make
  # sure the namespace exists first (Helm creates it via create_namespace,
  # but that only happens once the release itself is applied — instead we
  # create the namespace object directly here to avoid the race).
  depends_on = [kubernetes_namespace.jenkins]
}

resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = var.namespace
  }
}

# Optional: StorageClass for Jenkins' PersistentVolumeClaim. Only created
# when persistence is enabled — requires the aws-ebs-csi-driver EKS add-on
# to actually provision volumes (see modules/eks).
resource "kubernetes_storage_class_v1" "ebs_sc" {
  count = var.persistence_enabled ? 1 : 0

  metadata {
    name = "ebs-sc"
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "gp3"
  }
}

# ---------------------------------------------------------------------------
# Jenkins itself
# ---------------------------------------------------------------------------
resource "helm_release" "jenkins" {
  name             = "jenkins"
  namespace        = var.namespace
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = var.chart_version
  create_namespace = false
  # Default (300s) is tight for a first-time image pull + node group churn;
  # module "jenkins" also gets an explicit depends_on = [module.eks] at the
  # root so this never races a node group replacement (see main.tf).
  timeout = 600

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      admin_username      = var.admin_username
      admin_password      = var.admin_password
      persistence_enabled = var.persistence_enabled
      resources           = var.resources
      github_username     = var.github_username
      github_pat          = var.github_pat
      git_repo_url        = var.git_repo_url
      git_branch          = var.git_branch
      ecr_repository_url  = var.ecr_repository_url
    })
  ]

  depends_on = [
    kubernetes_service_account.jenkins_sa,
    kubernetes_storage_class_v1.ebs_sc,
  ]
}
