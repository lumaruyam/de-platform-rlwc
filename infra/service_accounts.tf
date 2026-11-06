# One service account for the pipeline, with only what it needs (step 8, ADR-0010).
# Off by default: creating it needs iam.serviceAccounts.create on the shared class project,
# which the group does not have (refused, see docs/infra.md). Turn on with -var manage_iam=true.
variable "manage_iam" {
  description = "Create the pipeline service account and its grants (needs admin rights)."
  type        = bool
  default     = false
}

resource "google_service_account" "pipeline" {
  count        = var.manage_iam ? 1 : 0
  account_id   = "${var.group}-pipeline"
  display_name = "Group 2 pipeline (Airflow tasks)"
}

# Write bronze and read it back.
resource "google_storage_bucket_iam_member" "pipeline_lake" {
  count  = var.manage_iam ? 1 : 0
  bucket = google_storage_bucket.lake.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline[0].email}"
}

# Build wh, silver and gold. Nothing else in the project.
resource "google_bigquery_dataset_iam_member" "pipeline_datasets" {
  for_each   = var.manage_iam ? local.datasets : {}
  dataset_id = google_bigquery_dataset.layer[each.key].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline[0].email}"
}
