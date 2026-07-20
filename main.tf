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

# Container registry for the Django Docker image.
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

# ---------------------------------------------------------------------------
# CI/CD (theme 8-9): Jenkins builds the Django image with Kaniko, pushes it
# to the ECR repo above, and updates charts/django-app/values.yaml#image.tag
# in this same Git repo. Argo CD watches that same chart path and syncs the
# cluster automatically — the Jenkins -> Git -> Argo CD handoff is the whole
# point of this pipeline.
# ---------------------------------------------------------------------------
module "jenkins" {
  source = "./modules/jenkins"

  cluster_name        = module.eks.cluster_name
  oidc_provider_arn   = module.eks.oidc_provider_arn
  oidc_issuer_url     = module.eks.oidc_issuer_url
  ecr_repository_arn  = module.ecr.ecr_repository_arn
  ecr_repository_url  = module.ecr.ecr_repository_url
  admin_password      = var.jenkins_admin_password
  persistence_enabled = var.jenkins_persistence_enabled

  git_repo_url    = var.git_repo_url
  git_branch      = var.git_branch
  github_username = var.github_username
  github_pat      = var.github_pat

  # module.eks.cluster_name/oidc_*/etc. don't touch aws_eks_node_group, so
  # without this Terraform schedules helm_release.jenkins in parallel with
  # any node group replacement (e.g. an instance_types change) instead of
  # after it — jenkins-0 then has zero nodes to schedule onto and the Helm
  # install times out. Force the whole eks module (node group included) to
  # finish first, same as module.argo_cd below.
  depends_on = [module.eks]
}

module "argo_cd" {
  source = "./modules/argo_cd"

  git_repo_url    = var.git_repo_url
  git_branch      = var.git_branch
  github_username = var.github_username
  github_pat      = var.github_pat

  app_chart_path       = "charts/django-app"
  app_namespace        = "default"
  app_image_repository = module.ecr.ecr_repository_url

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# RDS (lesson-db-module): flexible standard-RDS/Aurora database module.
# Off by default (count = var.rds_enabled ? 1 : 0) -- it creates billable,
# non-Free-Tier-safe resources (t3.micro RDS is Free Tier eligible, but
# Aurora never is), so it only gets created when explicitly opted into with
# -var='rds_enabled=true'. Values below mirror charts/django-app/values.yaml
# (POSTGRES_DB=app_db, POSTGRES_USER=app_user, port 5432) so the two line up
# if you switch the chart to an external DB per the README's
# `--set postgresql.enabled=false --set config.POSTGRES_HOST=<rds-endpoint>`
# flow instead of the chart's own in-cluster Postgres.
# ---------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"
  count  = var.rds_enabled ? 1 : 0

  identifier = "${var.project}-db"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  # Managed node groups (modules/eks) don't get their own security group --
  # nodes use the cluster's, so this is the right SG to allow DB access from.
  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  use_aurora     = var.rds_use_aurora
  engine         = var.rds_engine
  engine_version = var.rds_engine_version
  family         = var.rds_family
  instance_class = var.rds_instance_class
  multi_az       = var.rds_multi_az

  database_name   = var.rds_database_name
  master_username = var.rds_master_username
  # master_password left unset -- the module generates and stores one in state

  tags = {
    Project = var.project
  }

  depends_on = [module.eks]
}
