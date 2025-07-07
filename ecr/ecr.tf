provider "aws" {
  region = "ap-southeast-1"
}

resource "aws_ecr_repository" "confluent_cp_server" {
  name                 = "cp-server"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_lifecycle_policy" "cp_server_lifecycle" {
  repository = aws_ecr_repository.confluent_cp_server.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 30 days"
        selection = {
          tagStatus     = "untagged"
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

