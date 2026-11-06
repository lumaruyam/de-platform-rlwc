# The lake bucket, created by hand in L02, adopted here (see imports.tf).
resource "google_storage_bucket" "lake" {
  name                        = "${var.project_id}-${var.group}"
  location                    = upper(var.region)
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  # Bronze gets colder with age and is never deleted (ADR-0002, infra/lifecycle.json).
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age            = 30
      matches_prefix = ["bronze/"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age            = 90
      matches_prefix = ["bronze/"]
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
    condition {
      age            = 365
      matches_prefix = ["bronze/"]
    }
  }

  lifecycle_rule {
    action {
      type = "AbortIncompleteMultipartUpload"
    }
    condition {
      age = 1
    }
  }

  # The bucket holds the data and the Terraform state: never destroy it from code.
  # Encryption enforcement is set by Google on the project, not by us: leave it as it is.
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [encryption]
  }
}
