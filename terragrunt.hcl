locals {
  user       = get_env("DEVBOX_USER", get_env("USER", "default"))
  account_id = get_aws_account_id()
}

terraform_binary = "tofu"

terraform {
  source = "./terraform"
}

remote_state {
  backend = "s3"
  generate = {
    path      = "terraform/backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "devimage-tfstate-${local.account_id}"
    key            = "users/${local.user}/devbox.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devimage-tfstate-locks"
  }
}

inputs = {
  devbox_user      = local.user
  ami_id           = "ami-0b7cfe2135f319a55"
  key_name         = "me"
  subnet_id        = "subnet-07513680b824b3dbe"
  vpc_id           = "vpc-0dafcc61f21dac9cd"
  instance_type    = "t3.medium"
  root_volume_size = 50
  instance_name    = "devbox"
  aws_region       = "us-east-1"
}
