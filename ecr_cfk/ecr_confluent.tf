provider "aws" {
  region = "ap-southeast-1"
}

# --- confluentinc ECR Repository ---
resource "aws_ecr_repository" "confluentinc" {
  name                 = "confluentinc"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# --- Lifecycle Policy for confluentinc ---
resource "aws_ecr_lifecycle_policy" "confluentinc_lifecycle" {
  repository = aws_ecr_repository.confluentinc.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 tagged images, expire older"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["latest"]   # ✅ Mandatory if tagStatus=tagged
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}