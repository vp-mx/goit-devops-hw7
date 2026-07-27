# Aurora Cluster. Created only when use_aurora = true (see variables.tf);
# the standard single-instance equivalent lives in rds.tf. Shared
# networking/parameter-group resources live in shared.tf.
#
# An Aurora cluster is two layers: aws_rds_cluster (the storage layer/
# endpoint) plus one-or-more aws_rds_cluster_instance resources (the actual
# compute, one of which becomes the writer -- Aurora elects it automatically,
# there's no separate "primary instance" resource to manage).

resource "aws_rds_cluster" "this" {
  count = var.use_aurora ? 1 : 0

  cluster_identifier = var.identifier

  engine         = var.engine
  engine_version = var.engine_version

  database_name   = var.database_name
  port            = local.effective_port
  master_username = var.master_username
  master_password = local.effective_master_password

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this[0].name

  backup_retention_period   = var.backup_retention_period
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final-snapshot"

  tags = merge(var.tags, {
    Name = var.identifier
  })
}

resource "aws_rds_cluster_instance" "this" {
  count = var.use_aurora ? var.aurora_instance_count : 0

  identifier         = "${var.identifier}-${count.index}"
  cluster_identifier = aws_rds_cluster.this[0].id

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.this.name
  publicly_accessible  = var.publicly_accessible

  tags = merge(var.tags, {
    Name = "${var.identifier}-${count.index}"
  })
}
