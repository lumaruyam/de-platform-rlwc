provider "google" {
  project = var.project_id
  region  = var.region

  # On every resource that takes labels: the bill can be split by group in the shared project.
  default_labels = {
    team       = var.group
    project    = "albert-marketplace"
    env        = "dev"
    managed_by = "terraform"
  }
}
