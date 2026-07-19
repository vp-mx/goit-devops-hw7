variable "vpc_name" {
  description = "Name tag applied to the VPC and its resources"
  type        = string
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR block, for example 10.0.0.0/16."
  }
}

variable "public_subnets" {
  description = "List of CIDR blocks for the public subnets"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of CIDR blocks for the private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones, one per subnet"
  type        = list(string)
}

# Name of the EKS cluster sharing this VPC. When set, subnets get the
# kubernetes.io/... discovery tags Kubernetes needs to provision Elastic Load
# Balancers. Left empty, the VPC stays a plain, cluster-agnostic network.
variable "cluster_name" {
  description = "EKS cluster name used to tag subnets for load balancer discovery. Empty disables the tags."
  type        = string
  default     = ""
}
