# Remote state stored in S3. Locking uses use_lockfile (a plain lock file
# written to the same bucket via S3 conditional writes) — the modern
# replacement for the old DynamoDB-table locking mechanism, no separate
# table needed.
#
# The bucket name is account-specific (derived from the AWS account id in
# locals.tf), so it is not hardcoded here. Supply it at init time with
# -backend-config="bucket=..." — `make bootstrap` / `make init` do this
# automatically. This keeps the project portable: any AWS account can deploy
# it without editing this file (see README.md).
terraform {
  backend "s3" {
    key          = "lesson-7/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
    encrypt      = true
  }
}
