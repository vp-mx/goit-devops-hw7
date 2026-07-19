# AWS provider configuration shared by all modules.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
