# Resources shared by both the standard RDS path (rds.tf) and the Aurora
# path (aurora.tf): a DB Subnet Group, a Security Group, and the "base"
# parameter values (max_connections / log_statement / work_mem). Which
# actual parameter-group resource type gets these depends on use_aurora --
# a plain instance uses aws_db_parameter_group, a cluster uses
# aws_rds_cluster_parameter_group -- so that split lives here too, but the
# *values* stay defined in exactly one place (local.parameters).

locals {
  effective_port = coalesce(
    var.port,
    contains(["postgres", "aurora-postgresql"], var.engine) ? 5432 : 3306
  )

  parameters = concat(
    [
      { name = "max_connections", value = var.max_connections },
      { name = "log_statement", value = var.log_statement },
      { name = "work_mem", value = var.work_mem },
    ],
    var.extra_parameters
  )
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier}-subnet-group"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.identifier}-sg"
  description = "Access to the ${var.identifier} database on port ${local.effective_port}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.identifier}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "from_security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "DB access from sg ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = local.effective_port
  to_port                      = local.effective_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr_blocks" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "DB access from ${each.value}"
  cidr_ipv4          = each.value
  from_port          = local.effective_port
  to_port            = local.effective_port
  ip_protocol        = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description        = "Allow all outbound"
  cidr_ipv4          = "0.0.0.0/0"
  ip_protocol        = "-1"
}

# --- Parameter group: standard RDS instance -----------------------------
resource "aws_db_parameter_group" "this" {
  count = var.use_aurora ? 0 : 1

  name   = "${var.identifier}-params"
  family = var.family

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# --- Parameter group: Aurora cluster -------------------------------------
resource "aws_rds_cluster_parameter_group" "this" {
  count = var.use_aurora ? 1 : 0

  name   = "${var.identifier}-cluster-params"
  family = var.family

  dynamic "parameter" {
    for_each = local.parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# --- Master password: generate one if the caller didn't supply it --------
resource "random_password" "master" {
  count = var.master_password == null ? 1 : 0

  length  = 20
  special = false # avoid characters some engines/connection strings choke on
}

locals {
  effective_master_password = coalesce(var.master_password, try(random_password.master[0].result, null))
}
