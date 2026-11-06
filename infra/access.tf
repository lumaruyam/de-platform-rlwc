# Least privilege (step 10): consumers read gold only, never bronze, wh or silver.
# Members look like "group:ml-team@example.com" or "user:name@example.com".
# Empty by default: today every member of the shared class project already has
# project-wide access (infra/iam.md); these grants are what we would keep.
variable "gold_readers" {
  description = "Who may read gold (analysts, ML team)."
  type        = list(string)
  default     = []
}

resource "google_bigquery_dataset_iam_member" "gold_reader" {
  for_each   = toset(var.gold_readers)
  dataset_id = google_bigquery_dataset.layer["gold"].dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = each.value
}
