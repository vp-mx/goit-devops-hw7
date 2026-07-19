# EKS cluster (control plane) plus a managed node group and the core add-ons.
# The cluster runs inside the existing VPC (module.vpc): the control plane
# ENIs live in the supplied subnets, and the worker nodes run in the private
# subnets, reaching the internet through the VPC's NAT Gateway.

# ---------------------------------------------------------------------------
# Control plane
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    # Control plane ENIs are spread across every supplied subnet so the API
    # server is reachable from every AZ.
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # Grants the identity that runs `terraform apply` cluster-admin rights
  # automatically, so kubectl works right after apply without hand-editing
  # the aws-auth ConfigMap.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = { Name = var.cluster_name }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# ---------------------------------------------------------------------------
# Managed node group — the worker nodes that run the Django pods
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ng"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.node_subnet_ids

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Roll nodes one at a time on updates so the app stays available.
  update_config {
    max_unavailable = 1
  }

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  ami_type       = var.node_ami_type
  disk_size      = var.node_disk_size

  labels = {
    role = "app"
  }

  tags = { Name = "${var.cluster_name}-ng" }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]

  # The Horizontal Pod Autoscaler only scales pods, not nodes. If a Cluster
  # Autoscaler later adjusts desired_size, we don't want a subsequent
  # `terraform apply` to fight it and reset the count.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ---------------------------------------------------------------------------
# Core add-ons — managed versions of the components every cluster needs
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # CoreDNS runs as pods, so it needs the node group to exist first.
  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

# EBS CSI driver: required for PersistentVolumeClaims to actually provision
# and attach EBS volumes on modern EKS (the in-tree "kubernetes.io/aws-ebs"
# provisioner is migrated to this driver automatically once it's installed).
# Used by the Helm chart's in-cluster Postgres StatefulSet.
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this,
    aws_iam_role_policy_attachment.node_ebs_csi,
  ]
}
