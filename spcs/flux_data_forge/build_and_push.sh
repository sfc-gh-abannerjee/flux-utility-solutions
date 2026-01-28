#!/bin/bash
# =============================================================================
# Build and Push Docker Image for FLUX Data Forge SPCS Deployment
# =============================================================================

set -e

REGISTRY_URL="sfsehol-si-ae-enablement-retail-hmjrfl.registry.snowflakecomputing.com"
REPO_PATH="si_demos/production/ami_streaming_repo"
IMAGE_NAME="flux_data_forge"
TAG=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo "FLUX Data Forge - SPCS Docker Build"
echo "============================================"
echo "Registry: $REGISTRY_URL"
echo "Repository: $REPO_PATH"
echo "Image: $IMAGE_NAME:$TAG"
echo ""

# Navigate to the ami_data_generator directory (parent of spcs_app)
cd "$(dirname "$0")/.."

# Login to Snowflake registry
echo "Step 1: Logging in to Snowflake Container Registry..."
echo "Run: snow spcs image-registry login --connection cpe_demo_CLI"
snow spcs image-registry login --connection cpe_demo_CLI

# Build the Docker image for linux/amd64 (required by SPCS)
echo ""
echo "Step 2: Building Docker image (linux/amd64)..."
docker build --platform linux/amd64 -f spcs_app/Dockerfile -t ${REGISTRY_URL}/${REPO_PATH}/${IMAGE_NAME}:${TAG} -t ${REGISTRY_URL}/${REPO_PATH}/${IMAGE_NAME}:latest .

# Push to Snowflake registry
echo ""
echo "Step 3: Pushing image to Snowflake Container Registry..."
docker push ${REGISTRY_URL}/${REPO_PATH}/${IMAGE_NAME}:${TAG}
docker push ${REGISTRY_URL}/${REPO_PATH}/${IMAGE_NAME}:latest

echo ""
echo "============================================"
echo "Build Complete!"
echo "============================================"
echo "Image: ${REGISTRY_URL}/${REPO_PATH}/${IMAGE_NAME}:${TAG}"
echo ""
echo "Next steps:"
echo "1. Run the SQL in deploy_spcs.sql to create/update the service"
echo "2. Check service status: SHOW SERVICES LIKE 'FLUX_DATA_FORGE_SERVICE';"
echo "3. Get endpoint URL: SELECT SYSTEM\$GET_SERVICE_STATUS('FLUX_DATA_FORGE_SERVICE');"
