#!/usr/bin/env bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "${SCRIPT_DIR}/.." && pwd )"

# Configuration from environment variables
PROJECT_ID="${GOOGLE_CLOUD_PROJECT}"
REGION="${CLOUDSDK_COMPUTE_REGION}"
ZONE="${CLOUDSDK_COMPUTE_ZONE}"

# Validate environment variables
if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ] || [ -z "$ZONE" ]; then
    echo "Error: Missing required environment variables. Please ensure you're in the nix shell."
    echo "Required: GOOGLE_CLOUD_PROJECT, CLOUDSDK_COMPUTE_REGION, CLOUDSDK_COMPUTE_ZONE"
    exit 1
fi

echo "Using configuration:"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Zone: $ZONE"

# Check if gcloud is available
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI not found. Please ensure you're in the nix shell."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="get(account)" &> /dev/null; then
    echo "Please authenticate with Google Cloud:"
    gcloud auth login
fi

# Set the project
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo "Enabling required APIs..."
gcloud services enable compute.googleapis.com \
    storage-component.googleapis.com \
    secretmanager.googleapis.com \
    --project="$PROJECT_ID"

# Create GCS bucket for Terraform state
BUCKET_NAME="${PROJECT_ID}-tf-state"
echo "Creating GCS bucket for Terraform state..."

if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${BUCKET_NAME}"
    echo "Created bucket: gs://${BUCKET_NAME}"
else
    echo "Bucket already exists: gs://${BUCKET_NAME}"
fi

# Enable versioning on the bucket
echo "Enabling versioning on bucket..."
gsutil versioning set on "gs://${BUCKET_NAME}"

# Create backend configuration
cat > "${PROJECT_ROOT}/backend.tf" <<EOF
terraform {
  backend "gcs" {
    bucket = "${BUCKET_NAME}"
    prefix = "terraform/state"
  }
}
EOF

# Set up Application Default Credentials
echo "Setting up Application Default Credentials..."
gcloud auth application-default login

# Create a terraform.tfvars with the project ID
cat > "${PROJECT_ROOT}/terraform.tfvars" <<EOF
gcp_project_id = "${PROJECT_ID}"
gcp_region     = "${REGION}"
gcp_zone       = "${ZONE}"
domain_name    = "glib.sh"
hostname       = "buoy"
EOF

echo -e "\n✓ GCP Terraform backend infrastructure deployed successfully!"
echo "  Bucket: gs://${BUCKET_NAME}"
echo "  Project: ${PROJECT_ID}"
echo "  Region: ${REGION}"
