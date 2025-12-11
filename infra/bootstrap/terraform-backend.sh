#!/usr/bin/env bash

set -e

PROJECT_ID="$(gcloud config get-value project)"
REGION="$(gcloud config get-value compute/region)"

# Validate environment variables
if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ]; then
    echo "Error: Missing project ID or region in the gcloud configuration."
    exit 1
fi

echo "Using configuration:"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"

echo "Enabling required APIs..."
gcloud services enable storage-component.googleapis.com

# Create GCS bucket for Terraform state
BUCKET_NAME="${PROJECT_ID}-tf-state"

echo "Creating GCS bucket for Terraform state..."

if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
    gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${BUCKET_NAME}"
    echo "Created bucket: gs://${BUCKET_NAME}"
else
    echo "Bucket already exists: gs://${BUCKET_NAME}"
fi

echo "Enabling versioning on bucket..."
if ! gsutil versioning get "gs://${BUCKET_NAME}" &> /dev/null; then
  gsutil versioning set on "gs://${BUCKET_NAME}"
  echo "Enabled versioning on bucket"
else
  echo "Versioning already enabled on bucket"
fi

# write the backend.tf file
cat <<EOF > backend.tf
terraform {
  backend "gcs" {
    bucket = "$BUCKET_NAME"
    prefix = "terraform/state"
  }
}
EOF

echo -e "\n✓ GCP Terraform backend infrastructure deployed successfully!"
echo "  Bucket: gs://${BUCKET_NAME}"
