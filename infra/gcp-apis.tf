resource "google_project_service" "gcp_services" {
  for_each = toset(
    [
      "compute.googleapis.com",
      "storage.googleapis.com",
      "storage-component.googleapis.com",
      "secretmanager.googleapis.com"
    ]
  )
  project = var.gcp_project_id
  service = each.key
}

