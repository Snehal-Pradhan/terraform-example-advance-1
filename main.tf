locals {
  is_prod = terraform.workspace == "prod"

  # Static keys ("prod-0", "nonprod-0"...) so for_each works at plan time
  s3_buckets = merge(
    { for i, b in aws_s3_bucket.prod : "prod-${i}" => b },
    { for i, b in aws_s3_bucket.nonprod : "nonprod-${i}" => b },
  )
}

# ──────────────────────────────── VPC ────────────────────────────────

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${local.short_env}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = true
  single_nat_gateway = !local.is_prod # one NAT to save cost; one per AZ in prod
}

# ────────────────────────── Security group ───────────────────────────

resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-web-${local.short_env}-"
  description = "Web tier - no inbound rules; access via SSM only"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-web-${local.short_env}"
  }
}

# ─────────────────────────── KMS key ─────────────────────────────────

resource "aws_kms_key" "main" {
  description             = "CMK for ${var.project_name} ${terraform.workspace}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${local.short_env}-cmk"
  }
}

# ────────────────────────────── EC2 ──────────────────────────────────

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  count = local.env.ec2_count

  name = "${var.project_name}-server-${local.short_env}-${count.index + 1}"

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = local.env.instance_type
  subnet_id                   = module.vpc.private_subnets[count.index]
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_profile.name
  associate_public_ip_address = false # private subnet, SSM only
  user_data_replace_on_change = true

  root_block_device = [
    {
      volume_type = var.root_volume_type
      volume_size = var.root_volume_size_gb
      encrypted   = true
      kms_key_id  = aws_kms_key.main.arn
    },
  ]

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }
 
  user_data = <<-EOF
    #!/bin/bash
    set -x
    exec > /var/log/ssm-bootstrap.log 2>&1
    apt-get update -y
    apt-get install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF


  tags = {
    Name = "${var.project_name}-server-${local.short_env}-${count.index + 1}"
  }
}

# ──────────────────────── EBS data volumes ───────────────────────────

resource "aws_ebs_volume" "data" {
  count = local.env.ec2_count

  availability_zone = element(data.aws_availability_zones.available.names, count.index)
  size              = var.data_volume_size_gb
  type              = "gp3"
  encrypted         = true
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "${var.project_name}-server-${local.short_env}-${count.index + 1}-data"
  }
}

resource "aws_volume_attachment" "data" {
  count = local.env.ec2_count

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data[count.index].id
  instance_id = module.ec2_instance[count.index].id
}

# ─────────────────── S3 buckets (guardrailed split) ──────────────────

# prod buckets refuse deletion; dev/staging destroy cleanly
resource "aws_s3_bucket" "prod" {
  count = local.is_prod ? local.env.s3_count : 0

  bucket = "${var.project_name}-${local.short_env}-s3-${count.index + 1}-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-s3-${local.short_env}-${count.index + 1}"
  }
}

resource "aws_s3_bucket" "nonprod" {
  count = local.is_prod ? 0 : local.env.s3_count

  bucket = "${var.project_name}-${local.short_env}-s3-${count.index + 1}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-s3-${local.short_env}-${count.index + 1}"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.s3_buckets

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.s3_buckets

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.s3_buckets

  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.s3_buckets

  bucket = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "arn:aws:s3:::${each.value.id}/*"
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ───────────────── DynamoDB tables (guardrailed split) ───────────────

resource "aws_dynamodb_table" "prod" {
  count = local.is_prod ? local.env.ddb_count : 0

  name         = "${var.project_name}-db-${local.short_env}-${count.index + 1}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "${var.project_name}-db-${local.short_env}-${count.index + 1}"
  }
}

resource "aws_dynamodb_table" "nonprod" {
  count = local.is_prod ? 0 : local.env.ddb_count

  name         = "${var.project_name}-db-${local.short_env}-${count.index + 1}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.main.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-db-${local.short_env}-${count.index + 1}"
  }
}

# ───────────────────── CloudWatch log group ──────────────────────────
# Logs won't flow until the CloudWatch agent is installed (Ansible later)

resource "aws_cloudwatch_log_group" "servers" {
  name              = "/${var.project_name}/${local.short_env}/servers"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.main.arn

  tags = {
    Name = "${var.project_name}-${local.short_env}-logs"
  }
}

# ──────────────── SSM State Manager (agent self-healing) ─────────────
# Ensures the SSM agent is installed/running on every managed instance daily

resource "aws_ssm_association" "ssm_agent" {
  name                = "AWS-RunShellScript"
  schedule_expression = "rate(1 day)"

  targets {
    key    = "tag:ManagedBy"
    values = ["terraform"]
  }

  parameters = {
    commands = <<-EOF
      #!/bin/bash
      if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
        snap install amazon-ssm-agent --classic
      fi
      systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service || true
    EOF
  }
}

