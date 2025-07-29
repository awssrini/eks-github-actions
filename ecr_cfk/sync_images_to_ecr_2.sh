#!/bin/bash

set -e

AWS_ACCOUNT_ID=141884504154
AWS_REGION=ap-southeast-1

IMAGES=(
  "confluentinc/cp-server:7.7.1"
  "confluentinc/confluent-init-container:2.9.3"
  "confluentinc/cp-enterprise-control-center:7.7.1"
  "confluentinc/confluent-operator:0.1033.87"
)

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

for IMAGE in "${IMAGES[@]}"; do
  SRC_IMAGE="docker.io/${IMAGE}"
  REPO_NAME=$(echo $IMAGE | cut -d':' -f1)           # e.g., confluentinc/cp-server
  TAG=$(echo $IMAGE | cut -d':' -f2)                 # e.g., 7.7.1
  DEST_IMAGE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:${TAG}"

  echo -e "\n--- 🚀 Processing $SRC_IMAGE ---"
  echo "📥 Pulling from Docker Hub..."
  docker pull $SRC_IMAGE

  echo "🏷️ Tagging for ECR as $DEST_IMAGE"
  docker tag $SRC_IMAGE $DEST_IMAGE

  echo "📦 Ensuring ECR repo '$REPO_NAME' exists..."
  aws ecr describe-repositories --repository-names "$REPO_NAME" --region $AWS_REGION >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$REPO_NAME" --region $AWS_REGION

  echo "📤 Pushing to ECR..."
  docker push $DEST_IMAGE
done

echo -e "\n✅ All images pushed successfully to ECR with original structure."

