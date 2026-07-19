# IAM roles assumed by the EKS control plane and by the worker nodes.
# The partition is read from the caller so the ARNs also work outside the
# standard "aws" partition (GovCloud, China).
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Control plane role
# ---------------------------------------------------------------------------
# The EKS service assumes this role to manage AWS resources on the cluster's
# behalf (ENIs, security groups, load balancers ...).
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.cluster_name}-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Worker node role
# ---------------------------------------------------------------------------
# The EC2 worker instances assume this role. It carries the three AWS managed
# policies every EKS node needs: the node policy, the VPC CNI policy, and
# read-only ECR access so the kubelet can pull the Django image without an
# imagePullSecret.
resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.cluster_name}-node-role" }
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Lets the EBS CSI driver (installed as a cluster add-on in eks.tf) provision
# and attach EBS volumes for PersistentVolumeClaims — needed by the in-cluster
# Postgres StatefulSet in the Helm chart. Attached directly to the node role
# for simplicity; a production setup would scope this down via IRSA (a
# dedicated IAM role bound to the aws-ebs-csi-driver's service account)
# instead of granting it to every pod on the node.
resource "aws_iam_role_policy_attachment" "node_ebs_csi" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
