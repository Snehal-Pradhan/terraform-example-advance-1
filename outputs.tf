output "workspace" {
  description = "Currently active workspace"
  value       = terraform.workspace
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

output "instance_ids" {
  description = "IDs of all EC2 instances in this workspace"
  value       = module.ec2_instance[*].id
}

output "instance_private_ips" {
  description = "Private IPs of all EC2 instances"
  value       = module.ec2_instance[*].private_ip
}

output "data_volume_ids" {
  description = "IDs of the attached EBS data volumes"
  value       = aws_ebs_volume.data[*].id
}

output "s3_bucket_names" {
  description = "Names of all S3 buckets in this workspace"
  value       = [for b in local.s3_buckets : b.id]
}

output "dynamodb_table_names" {
  description = "Names of all DynamoDB tables in this workspace"
  value       = concat(aws_dynamodb_table.prod[*].name, aws_dynamodb_table.nonprod[*].name)
}

output "kms_key_arn" {
  description = "ARN of the workspace KMS key"
  value       = aws_kms_key.main.arn
}

output "log_group_name" {
  description = "CloudWatch log group for servers"
  value       = aws_cloudwatch_log_group.servers.name
}
