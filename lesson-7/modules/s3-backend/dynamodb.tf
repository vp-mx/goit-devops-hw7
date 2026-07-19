# DynamoDB table used by the S3 backend to lock the state during
# concurrent `terraform apply` runs. The LockID attribute name is required
# by Terraform's S3 backend locking mechanism.
resource "aws_dynamodb_table" "locks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name = var.table_name
  }
}
