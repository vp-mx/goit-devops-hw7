# Remote state stored in S3, with DynamoDB used for state locking.
#
# The bucket name is account-specific (derived from the AWS account id in
# locals.tf), so it is not hardcoded here. Supply it at init time with
# -backend-config="bucket=..." — `make bootstrap` / `make init` do this
# automatically. This keeps the project portable: any AWS account can deploy
# it without editing this file (see README.md).
terraform {
  backend "s3" {
    key            = "lesson-7/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
