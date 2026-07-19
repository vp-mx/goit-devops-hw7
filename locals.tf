# Current region availability zones and the caller's AWS account.
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project   = var.project
    ManagedBy = "Terraform"
    Lesson    = "lesson-7"
  }

  # Pick as many AZs as there are subnets, straight from the current region,
  # so the project is not tied to hardcoded zone names.
  azs = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))

  # When state_bucket_name is left empty, derive a globally unique name from
  # the project and the current AWS account id, so any account can deploy
  # this project without editing the code.
  state_bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Cluster name computed once here so it can be passed to both the VPC
  # module (subnet tags) and the EKS module without a dependency cycle.
  cluster_name = "${var.project}-eks"
}
