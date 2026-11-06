# Column-level security (step 10, ADR-0010). Columns tagged here can only be read by
# principals granted roles/datacatalog.categoryFineGrainedReader on the tag.
resource "google_data_catalog_taxonomy" "classification" {
  region                 = var.region
  display_name           = "${var.group}-data-classification"
  description            = "Group 2 data classes (docs/governance.md)"
  activated_policy_types = ["FINE_GRAINED_ACCESS_CONTROL"]
}

resource "google_data_catalog_policy_tag" "confidential_direct" {
  taxonomy     = google_data_catalog_taxonomy.classification.id
  display_name = "confidential-direct-pii"
  description  = "Identifies a person directly: street address, phone, zip"
}

output "policy_tag_confidential_direct" {
  value = google_data_catalog_policy_tag.confidential_direct.name
}
