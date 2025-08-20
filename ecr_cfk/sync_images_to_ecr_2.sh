#!/bin/bash
set -euo pipefail

AWS_ACCOUNT_ID=141884504154
AWS_REGION=ap-southeast-1

# ECR base repos (no "confluentinc" here to avoid double path issue)
STAGING_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
PROD_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/confluentinc_prod"

# Images to process
IMAGES=(
  'confluentinc/confluent-init-container:2.9.6'
  'confluentinc/cp-enterprise-control-center:7.7.4'
  'confluentinc/cp-enterprise-replicator:7.7.4'
  'confluentinc/cp-kafka-rest:7.7.4'
  'confluentinc/cp-ksqldb-server:7.7.4'
  'confluentinc/cp-schema-registry:7.7.4'
  'confluentinc/cp-server-connect:7.7.4'
  'confluentinc/cp-server:7.7.4'
  'confluentinc/confluent-operator:0.1033.87'
)

# --- Login to ECR ---
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# --- Process images ---
for IMAGE in "${IMAGES[@]}"; do
  SRC_IMAGE="docker.io/${IMAGE}"
  REPO_NAME=$(echo "$IMAGE" | cut -d':' -f1)   # e.g., confluentinc/cp-server
  TAG=$(echo "$IMAGE" | cut -d':' -f2)         # e.g., 7.7.4

  # Staging & Prod image names
  STAGING_IMAGE="${STAGING_REPO}/${REPO_NAME}:${TAG}"
  PROD_IMAGE="${PROD_REPO}/${REPO_NAME}:${TAG}"

  echo -e "\n--- 🚀 Processing $SRC_IMAGE ---"

  echo "📥 Pulling from Docker Hub..."
  docker pull "$SRC_IMAGE"

  echo "🏷️ Tagging for staging repo as $STAGING_IMAGE"
  docker tag "$SRC_IMAGE" "$STAGING_IMAGE"

  echo "📦 Ensuring ECR repo '$REPO_NAME' exists in staging..."
  aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION"

  echo "📤 Pushing to staging ECR..."
  docker push "$STAGING_IMAGE"

SCAN_LOG="/tmp/trivy_$(echo $REPO_NAME | tr '/' '_')_${TAG}.log"

echo "🔎 Scanning $STAGING_IMAGE with Trivy..."
set +e  # temporarily disable exit-on-error
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest \
  image --exit-code 1 --severity HIGH,CRITICAL "$STAGING_IMAGE" | tee "$SCAN_LOG"
SCAN_RESULT=${PIPESTATUS[0]}  # capture the exit code of Trivy
set -e  # re-enable exit-on-error

if [ $SCAN_RESULT -eq 0 ]; then
  echo "✅ No HIGH/CRITICAL vulnerabilities found. Promoting to production..."
else
  echo "❌ Vulnerabilities found in $STAGING_IMAGE. See $SCAN_LOG for details. Skipping promotion."
fi
done

echo -e "\n🎉 Process completed. Staging push done, production gated by scan."
