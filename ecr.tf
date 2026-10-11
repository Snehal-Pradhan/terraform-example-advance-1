resource "aws_ecr_repository" "app" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE" # allow overwriting tags like "latest"; use "IMMUTABLE" in prod

  image_scanning_configuration {
    scan_on_push = true # automatic vulnerability scanning on every push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.eks.arn # reuse the same CMK
  }

  tags = {
    Name = "${var.project_name}-${var.ecr_repository_name}"
  }
}
