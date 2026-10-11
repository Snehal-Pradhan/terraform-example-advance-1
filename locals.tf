locals {
  env_config = {
    dev = {
      ec2_count     = 1
      ddb_count     = 1
      s3_count      = 1
      instance_type = "t3.micro"
    }
    staging = {
      ec2_count     = 2
      ddb_count     = 1
      s3_count      = 1
      instance_type = "t3.micro"
    }
    prod = {
      ec2_count     = 2
      ddb_count     = 2
      s3_count      = 2
      instance_type = "t3.micro"
    }
  }

  short_env = terraform.workspace == "staging" ? "stg" : terraform.workspace

  env = contains(keys(local.env_config), terraform.workspace) ? local.env_config[terraform.workspace] : file("ERROR: workspace '${terraform.workspace}' is not valid. Use one of: ${join(", ", keys(local.env_config))}")
}
