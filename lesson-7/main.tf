# Root module: wires the S3 backend, VPC, ECR and EKS modules together.
# Every value has a sensible default in variables.tf, so `terraform apply`
# works without passing a single argument.

# Remote state storage: S3 bucket plus a DynamoDB table for locking.
module "s3_backend" {
  source      = "./modules/s3-backend"
  bucket_name = local.state_bucket_name
  table_name  = var.lock_table_name
}

# Network layer: VPC with public and private subnets across the region's AZs.
# The cluster name is passed so the subnets get tagged for EKS load balancer
# discovery. This is the same VPC layout the EKS cluster below runs in.
module "vpc" {
  source              = "./modules/vpc"
  vpc_name            = "${var.project}-vpc"
  vpc_cidr_block      = var.vpc_cidr_block
  public_subnets      = var.public_subnet_cidrs
  private_subnets     = var.private_subnet_cidrs
  availability_zones  = local.azs
  cluster_name        = local.cluster_name
}

# Container registry for the Django Docker image built in theme 4.
module "ecr" {
  source       = "./modules/ecr"
  ecr_name     = "${var.project}-ecr"
  scan_on_push = var.ecr_scan_on_push
}

# Kubernetes cluster (EKS), created inside the VPC above. The control plane
# spans every subnet; the worker nodes run in the private subnets and reach
# the internet through the VPC's NAT Gateway.
module "eks" {
  source     = "./modules/eks"
  aws_region = var.aws_region

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  subnet_ids      = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids = module.vpc.private_subnet_ids

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}
