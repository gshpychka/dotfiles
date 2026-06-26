#!/usr/bin/env bash

set -e

# Creates the versioned GCS bucket that holds Terraform state; run once per GCP project.
PROJECT_ID="$(gcloud config get-value project)"
REGION="$(gcloud config get-value compute/region)"

# Validate environment variables
if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ]; then
  echo "Error: Missing project ID or region in the gcloud configuration."
  exit 1
fi
if [ -z "$TF_STATE_BUCKET" ]; then
  echo "Error: TF_STATE_BUCKET is unset; run this inside the infra devshell."
  exit 1
fi

echo "Using configuration:"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"

echo "Enabling required APIs..."
gcloud services enable storage-component.googleapis.com

BUCKET_NAME="$TF_STATE_BUCKET"

echo "Creating GCS bucket for Terraform state..."

if ! gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
  gsutil mb -p "$PROJECT_ID" -l "$REGION" "gs://${BUCKET_NAME}"
  echo "Created bucket: gs://${BUCKET_NAME}"
else
  echo "Bucket already exists: gs://${BUCKET_NAME}"
fi

echo "Enabling versioning on bucket..."
if ! gsutil versioning get "gs://${BUCKET_NAME}" &>/dev/null; then
  gsutil versioning set on "gs://${BUCKET_NAME}"
  echo "Enabled versioning on bucket"
else
  echo "Versioning already enabled on bucket"
fi

echo -e "\n✓ Terraform state bucket ready."
echo "  Bucket: gs://${BUCKET_NAME}"
