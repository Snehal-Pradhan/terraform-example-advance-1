# ── KMS key for Kubernetes secrets encryption ──

resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption key for ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-eks-cmk"
  }
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.project_name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

# ── EKS cluster ──

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Network
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # control plane ENIs live in private subnets

  # Access — public API for kubectl from outside, private for in-VPC traffic
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Secrets encryption with our CMK (your diagram's KMS box)
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # IRSA is enabled by default in v20 — creates the OIDC provider
  enable_irsa = true
  enable_cluster_creator_admin_permissions = true


  # ── Managed node group (EC2 Nodes from your diagram) ──
  eks_managed_node_groups = {
    default = {
      name = "${var.project_name}-nodes"

      instance_types = var.node_instance_types # c7i-flex.large
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Nodes get their own IAM role via the module
      create_node_security_group = true
    }
  }

  # ── Fargate profile (Serverless Pods from your diagram) ──
  fargate_profiles = {
    serverless = {
      name = "${var.project_name}-fargate"

      selectors = [
        {
          namespace = "serverless"
        }
      ]
    }
  }

  tags = {
    Project = var.project_name
  }
}
