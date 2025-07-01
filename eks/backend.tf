terraform {
  required_version = "~> 1.9.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.49.0"
    }
  }
  backend "s3" {
    bucket         = "poc-srini-terraform-state-s3-bucket"
    region         = "ap-southeast-1"
    key            = "eks/terraform.tfstate"
    dynamodb_table = "LockID"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.aws-region
}
