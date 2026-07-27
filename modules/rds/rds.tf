# Standard single-instance RDS database. Created only when use_aurora =
# false (see variables.tf); the Aurora equivalent lives in aurora.tf.
# Shared networking/parameter-group resources live in shared.tf.

resource "aws_db_instance" "this" {
  count = var.use_aurora ? 0 : 1

  identifier = var.identifier

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > 0 ? var.max_allocated_storage : null
  storage_type          = var.storage_type

  db_name  = var.database_name
  port     = local.effective_port
  username = var.master_username
  password = local.effective_master_password

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this[0].name

  multi_az            = var.multi_az
  publicly_accessible = var.publicly_accessible

  backup_retention_period   = var.backup_retention_period
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"

  tags = merge(var.tags, {
    Name = var.identifier
  })
}
