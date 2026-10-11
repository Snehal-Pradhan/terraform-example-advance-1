provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project     = var.project_name
        Environment = terraform.workspace
        ManagedBy   = "terraform"
      },
      var.common_tags
    )
  }
}
