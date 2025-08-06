#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${AWS_REGION:-"ap-southeast-1"}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
ENVIRONMENT=${ENVIRONMENT:-"staging"}

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Function to check if ECR repository exists
check_ecr_repo() {
    local repo_name=$1
    aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" >/dev/null 2>&1
}

# Function to create ECR repository
create_ecr_repo() {
    local repo_name=$1
    log "Creating ECR repository: $repo_name"
    
    aws ecr create-repository \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
    
    # Set lifecycle policy to keep only latest 20 images
    aws ecr put-lifecycle-policy \
        --repository-name "$repo_name" \
        --region "$AWS_REGION" \
        --lifecycle-policy-text '{
            "rules": [
                {
                    "rulePriority": 1,
                    "description": "Keep last 20 images",
                    "selection": {
                        "tagStatus": "tagged",
                        "countType": "imageCountMoreThan",
                        "countNumber": 20
                    },
                    "action": {
                        "type": "expire"
                    }
                },
                {
                    "rulePriority": 2,
                    "description": "Delete untagged images older than 1 day",
                    "selection": {
                        "tagStatus": "untagged",
                        "countType": "sinceImagePushed",
                        "countUnit": "days",
                        "countNumber": 1
                    },
                    "action": {
                        "type": "expire"
                    }
                }
            ]
        }'
    
    log "ECR repository $repo_name created successfully"
}

# Function to setup S3 buckets for tiered storage
setup_s3_buckets() {
    local env=$1
    local bucket_name="cfk-tiered-storage-${env}-${AWS_ACCOUNT_ID}"
    
    log "Setting up S3 bucket: $bucket_name"
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log "S3 bucket $bucket_name already exists"
    else
        # Create bucket
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$bucket_name" --region "$AWS_REGION"
        else
            aws s3api create-bucket \
                --bucket "$bucket_name" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        
        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        # Setup lifecycle configuration
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "$bucket_name" \
            --lifecycle-configuration '{
                "Rules": [
                    {
                        "ID": "TieredStorageRule",
                        "Status": "Enabled",
                        "Filter": {},
                        "Transitions": [
                            {
                                "Days": 30,
                                "StorageClass": "STANDARD_IA"
                            },
                            {
                                "Days": 90,
                                "StorageClass": "GLACIER"
                            },
                            {
                                "Days": 365,
                                "StorageClass": "DEEP_ARCHIVE"
                            }
                        ]
                    }
                ]
            }'
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket_name" \
            --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        
        log "S3 bucket $bucket_name created and configured"
    fi
}

# Function to create IAM roles for Confluent
setup_iam_roles() {
    local env=$1
    local role_name="confluent-${env}-role"
    
    log "Setting up IAM role: $role_name"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        log "IAM role $role_name already exists"
    else
        # Create trust policy
        local trust_policy='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                },
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Federated": "arn:aws:iam::'$AWS_ACCOUNT_ID':oidc-provider/oidc.eks.'$AWS_REGION'.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
                    },
                    "Action": "sts:AssumeRoleWithWebIdentity"
                }
            ]
        }'
        
        # Create role
        aws iam create-role \
            --role-name "$role_name" \
            --assume-role-policy-document "$trust_policy"
        
        # Create and attach policy for S3 access
        local policy_document='{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket"
                    ],
                    "Resource": [
                        "arn:aws:s3:::cfk-tiered-storage-'$env'-'$AWS_ACCOUNT_ID'",
                        "arn:aws:s3:::cfk-tiered-storage-'$env'-'$AWS_ACCOUNT_ID'/*"
                    ]
                }
            ]
        }'
        
        aws iam create-policy \
            --policy-name "confluent-${env}-s3-policy" \
            --policy-document "$policy_document"
        
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/confluent-${env}-s3-policy"
        
        log "IAM role $role_name created successfully"
    fi
}

# Main execution
main() {
    log "Starting environment setup for: $ENVIRONMENT"
    
    # Validate required environment variables
    if [ -z "${AWS_ACCOUNT_ID:-}" ]; then
        error "AWS_ACCOUNT_ID environment variable is required"
    fi
    
    # Confluent images to manage
    declare -a CONFLUENT_IMAGES=(
        "confluentinc/cp-server"
        "confluentinc/confluent-init-container"
        "confluentinc/cp-enterprise-control-center"
        "confluentinc/confluent-operator"
        "confluentinc/cp-kafka-rest"
        "confluentinc/cp-schema-registry"
    )
    
    log "Setting up ECR repositories..."
    for image in "${CONFLUENT_IMAGES[@]}"; do
        if ! check_ecr_repo "$image"; then
            create_ecr_repo "$image"
        else
            log "ECR repository $image already exists"
        fi
    done
    
    log "Setting up S3 bucket for tiered storage..."
    setup_s3_buckets "$ENVIRONMENT"
    
    log "Setting up IAM roles..."
    setup_iam_roles "$ENVIRONMENT"
    
    log "Environment setup completed successfully for: $ENVIRONMENT"
    
    # Output useful information
    echo
    log "🎉 Setup Summary:"
    echo "  📦 ECR Registry: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    echo "  🪣 S3 Bucket: cfk-tiered-storage-${ENVIRONMENT}-${AWS_ACCOUNT_ID}"
    echo "  🔑 IAM Role: confluent-${ENVIRONMENT}-role"
    echo "  🌍 Region: ${AWS_REGION}"
    echo
    log "Next steps:"
    echo "  1. Update your EKS cluster OIDC provider in the IAM role trust policy"
    echo "  2. Configure GitHub Actions secrets with AWS credentials"
    echo "  3. Update certificate ARNs in the Kubernetes manifests"
    echo "  4. Run the CI/CD pipeline!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi