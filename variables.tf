variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resources"
  type        = string
  default     = "iac-workspaces"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.1.11.0/24", "10.1.12.0/24"]
}

variable "root_volume_size_gb" {
  description = "Size of each EC2 root volume in GB"
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size_gb >= 8 && var.root_volume_size_gb <= 100
    error_message = "Root volume size must be between 8 and 100 GB."
  }
}

variable "root_volume_type" {
  description = "Type of EC2 root volumes"
  type        = string
  default     = "gp3"
}

variable "data_volume_size_gb" {
  description = "Size of the additional EBS data volume attached to each server"
  type        = number
  default     = 10

  validation {
    condition     = var.data_volume_size_gb >= 10 && var.data_volume_size_gb <= 500
    error_message = "Data volume size must be between 10 and 500 GB."
  }
}

variable "common_tags" {
  description = "Extra tags applied to all resources"
  type        = map(string)
  default     = {}
}
