# Main VPC that will host the EKS cluster and the Django workload.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

# Tags added to every subnet so the AWS cloud controller / EKS can discover
# them for the cluster and for provisioning Elastic Load Balancers. Empty
# (no cluster_name) yields no extra tag, keeping the VPC cluster-agnostic.
locals {
  cluster_tag = var.cluster_name != "" ? {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  } : {}
}

# Public subnets, one per availability zone. Instances launched here get a
# public IP automatically. kubernetes.io/role/elb lets EKS place
# internet-facing (Service type=LoadBalancer) load balancers here.
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.cluster_tag, {
    Name                     = "${var.vpc_name}-public-${count.index + 1}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

# Private subnets, one per availability zone. This is where the EKS worker
# nodes run. kubernetes.io/role/internal-elb lets EKS place internal load
# balancers here.
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.cluster_tag, {
    Name                              = "${var.vpc_name}-private-${count.index + 1}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Internet Gateway: gives the public subnets access to the internet.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# Elastic IP for the NAT Gateway.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.vpc_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.this]
}

# Single NAT Gateway (in the first public subnet), shared by all private
# subnets. Cheaper than one NAT per AZ, sufficient for this exercise; lets
# the private-subnet worker nodes reach the internet (pull images, talk to
# the EKS API) without being publicly reachable themselves.
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.vpc_name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}
