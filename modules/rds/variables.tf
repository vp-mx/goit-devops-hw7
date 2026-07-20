# ---------------------------------------------------------------------------
# Naming / networking
# ---------------------------------------------------------------------------
variable "identifier" {
  description = "Name prefix for every resource this module creates (DB instance/cluster identifier, subnet group, security group, parameter group)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the database's security group is created in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB Subnet Group. Use private subnets — at least 2, in different AZs (RDS requirement)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "RDS requires a DB Subnet Group spanning at least 2 subnets in different Availability Zones."
  }
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to connect to the database on var.port (e.g. the EKS node security group). Combined with allowed_cidr_blocks."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to the database on var.port, in addition to allowed_security_group_ids. Leave empty to only allow access via security group references."
  type        = list(string)
  default     = []
}

variable "publicly_accessible" {
  description = "Whether the database gets a public IP. Leave false for anything but local experimentation — the app should always reach the DB over the private VPC network."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Engine selection -- this is what makes the module "flexible": the same
# variables (engine/engine_version/instance_class/multi_az) drive either a
# standard aws_db_instance (rds.tf) or an Aurora cluster (aurora.tf),
# switched purely by use_aurora. Only one of the two is ever created
# (count = var.use_aurora ? 1 : 0 / 0 : 1), so the caller's Terraform stays
# identical either way -- just flip the flag and re-apply.
# ---------------------------------------------------------------------------
variable "use_aurora" {
  description = "true = create an Aurora Cluster (aurora.tf); false = create a standard single-instance RDS database (rds.tf)"
  type        = bool
  default     = false
}

variable "engine" {
  description = "Database engine. Standard RDS: \"postgres\", \"mysql\", \"mariadb\", etc. Aurora (use_aurora = true): \"aurora-postgresql\" or \"aurora-mysql\"."
  type        = string
  default     = "postgres"
}

variable "engine_version" {
  description = "Engine version, e.g. \"16.4\" for postgres or \"16.4\" for aurora-postgresql. Leave null to let AWS pick its current default for the engine (not recommended for anything beyond quick experiments)."
  type        = string
  default     = null
}

variable "family" {
  description = "Parameter group family, e.g. \"postgres16\", \"mysql8.0\", \"aurora-postgresql16\". Must match engine/engine_version -- look up valid values with: aws rds describe-db-engine-versions --engine <engine> --query 'DBEngineVersions[].DBParameterGroupFamily'"
  type        = string
}

variable "instance_class" {
  description = "Compute/memory class for the database instance(s). Standard RDS free-tier eligible: \"db.t3.micro\" / \"db.t4g.micro\". Aurora has no free tier -- \"db.t3.medium\" or larger is the practical minimum."
  type        = string
  default     = "db.t3.micro"
}

variable "multi_az" {
  description = "Standard RDS: provisions a synchronous standby in a second AZ for automatic failover (roughly doubles cost). Aurora: ignored here -- Aurora HA is controlled by aurora_instance_count instead (each extra instance is a reader in a different AZ)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Standard RDS-only (ignored when use_aurora = true)
# ---------------------------------------------------------------------------
variable "allocated_storage" {
  description = "Storage size in GiB for a standard RDS instance. Ignored for Aurora (Aurora storage auto-scales)."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound in GiB for RDS storage autoscaling. Set to 0 to disable autoscaling. Ignored for Aurora."
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Storage type for a standard RDS instance (\"gp3\", \"gp2\", \"io1\"). Ignored for Aurora."
  type        = string
  default     = "gp3"
}

# ---------------------------------------------------------------------------
# Aurora-only (ignored when use_aurora = false)
# ---------------------------------------------------------------------------
variable "aurora_instance_count" {
  description = "Number of instances in the Aurora cluster (1 writer + N-1 readers). Ignored for standard RDS."
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Database / credentials
# ---------------------------------------------------------------------------
variable "database_name" {
  description = "Name of the default database created inside the instance/cluster"
  type        = string
}

variable "port" {
  description = "Port the database listens on. Leave null to use the engine's default (5432 for postgres/aurora-postgresql, 3306 for mysql/mariadb/aurora-mysql)."
  type        = number
  default     = null
}

variable "master_username" {
  description = "Master database username"
  type        = string
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master database password. Leave null to have the module generate and store a random one in Terraform state (recommended -- avoids a plaintext secret in *.tfvars/CLI history). Read it back via the sensitive master_password output."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Shared parameter group base parameters
# ---------------------------------------------------------------------------
variable "max_connections" {
  description = "Value for the max_connections parameter group entry"
  type        = string
  default     = "100"
}

variable "log_statement" {
  description = "Value for the log_statement parameter group entry (postgres-family engines: \"none\" | \"ddl\" | \"mod\" | \"all\")"
  type        = string
  default     = "ddl"
}

variable "work_mem" {
  description = "Value for the work_mem parameter group entry, in KB as a string (postgres-family engines only, e.g. \"4096\")"
  type        = string
  default     = "4096"
}

variable "extra_parameters" {
  description = "Extra parameter group entries beyond max_connections/log_statement/work_mem, as {name, value} pairs -- merged in on top of the base three."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# ---------------------------------------------------------------------------
# Lifecycle / misc
# ---------------------------------------------------------------------------
variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Prevent accidental deletion via the AWS API/Terraform. Leave false for coursework/sandbox environments so `terraform destroy` works cleanly."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip taking a final snapshot on deletion. true is friendlier for coursework (faster, no leftover billed snapshot); set false for anything you actually care about keeping."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every resource this module creates"
  type        = map(string)
  default     = {}
}
