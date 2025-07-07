#!/bin/bash

# Inputs
DOCKERHUB_IMAGE="confluentinc/cp-server"
TAG="7.7.0"
AWS_REGION="us-east-1"
ECR_REPO="cp-server"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ECR_IMAGE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${TAG}"

# Authenticate with ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Pull from Docker Hub
docker pull ${DOCKERHUB_IMAGE}:${TAG}

# Tag for ECR
docker tag ${DOCKERHUB_IMAGE}:${TAG} ${ECR_IMAGE}

# Push to ECR
docker push ${ECR_IMAGE}
