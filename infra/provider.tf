terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.13.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.14.0"
    }
    age = {
      source  = "clementblaise/age"
      version = "0.1.1"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
