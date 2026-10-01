provider "google" {
  project = var.project_id
  region  = var.region

  # Attribute API quota / enablement checks to this branch's project_id, not a
  # different project number on the SA key (CI SERVICE_DISABLED otherwise).
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project = var.project_id
  region  = var.region

  user_project_override = true
  billing_project       = var.project_id
}
