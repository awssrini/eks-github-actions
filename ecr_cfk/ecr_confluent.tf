provider "aws" {
  region = "ap-southeast-1"   # AWS region for all resources
}

# ======================================================
# ECR Repository: confluentinc (for non-prod/dev images)
# ======================================================
resource "aws_ecr_repository" "confluentinc" {
  name                 = "confluentinc"   # Repository name
  image_tag_mutability = "MUTABLE"        # Allow images to be overwritten (mutable tags)

  image_scanning_configuration {
    scan_on_push = true   # Enable vulnerability scanning for pushed images
  }
}

# ------------------------------------------------------
# ECR Lifecycle Policy for confluentinc
#   - Expire untagged images older than 7 days
#   - Keep only the last 5 "latest"-tagged images
# ------------------------------------------------------
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
        description  = "Keep last 5 tagged 'latest' images, expire older ones"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["latest"]   # Required when using tagStatus=tagged
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

# ======================================================
# ECR Repository: confluentinc_prod (for production images)
# ======================================================
resource "aws_ecr_repository" "confluentinc_prod" {
  name                 = "confluentinc_prod"   # Production repository
  image_tag_mutability = "MUTABLE"             # Allow images to be overwritten (mutable tags)

  image_scanning_configuration {
    scan_on_push = true   # Enable vulnerability scanning for pushed images
  }
}

# ------------------------------------------------------
# ECR Lifecycle Policy for confluentinc_prod
#   - Expire untagged images older than 7 days
#   - Keep only the last 5 "latest"-tagged images
# ------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "confluentinc_prod_lifecycle" {
  repository = aws_ecr_repository.confluentinc_prod.name

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
        description  = "Keep last 5 tagged 'latest' images, expire older ones"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["latest"]
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
