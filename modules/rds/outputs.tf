# Every output resolves to the right resource regardless of use_aurora, so
# the caller never needs to branch -- module.rds.endpoint always works.

output "endpoint" {
  description = "Connection endpoint. Standard RDS: host:port. Aurora: the cluster's writer endpoint, host:port."
  value       = var.use_aurora ? aws_rds_cluster.this[0].endpoint : aws_db_instance.this[0].endpoint
}

output "reader_endpoint" {
  description = "Read-only endpoint. Aurora: the cluster's load-balanced reader endpoint (spreads across replica instances). Standard RDS: null -- there is no separate reader endpoint."
  value       = var.use_aurora ? aws_rds_cluster.this[0].reader_endpoint : null
}

output "address" {
  description = "Hostname only (no port)"
  value       = var.use_aurora ? aws_rds_cluster.this[0].endpoint : aws_db_instance.this[0].address
}

output "port" {
  description = "Port the database listens on"
  value       = local.effective_port
}

output "database_name" {
  description = "Name of the default database created inside the instance/cluster"
  value       = var.database_name
}

output "master_username" {
  description = "Master database username"
  value       = var.master_username
}

output "master_password" {
  description = "Effective master password (either the one you passed in var.master_password, or the one the module generated). Sensitive -- read it with `terraform output -raw master_password`."
  value       = local.effective_master_password
  sensitive   = true
}

output "arn" {
  description = "ARN of the instance or cluster, whichever was created"
  value       = var.use_aurora ? aws_rds_cluster.this[0].arn : aws_db_instance.this[0].arn
}

output "identifier" {
  description = "Instance/cluster identifier"
  value       = var.identifier
}

output "security_group_id" {
  description = "ID of the security group guarding the database -- reference this from the security group of whatever needs to connect (e.g. add an aws_vpc_security_group_ingress_rule on the app's SG pointing at it), or pass the app's SG ID in via allowed_security_group_ids instead."
  value       = aws_security_group.this.id
}

output "db_subnet_group_name" {
  description = "Name of the DB Subnet Group"
  value       = aws_db_subnet_group.this.name
}

output "parameter_group_name" {
  description = "Name of the parameter group actually in use (instance-level or cluster-level, depending on use_aurora)"
  value       = var.use_aurora ? aws_rds_cluster_parameter_group.this[0].name : aws_db_parameter_group.this[0].name
}
