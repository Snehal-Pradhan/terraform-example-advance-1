module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true # one NAT to save cost; use false for multi-AZ NAT in prod
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags required by EKS for automatic subnet discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = 1 # public subnets get internet-facing LBs
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = 1 # private subnets get internal LBs
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = {
    Project = var.project_name
  }
}
