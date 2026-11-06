# Resources created by hand before L08. Terraform adopts them instead of
# creating new ones. Once the import is applied, these blocks can stay: they are no-ops.
import {
  to = google_storage_bucket.lake
  id = "data-engineering-i2-group2"
}

import {
  for_each = local.datasets
  to       = google_bigquery_dataset.layer[each.key]
  id       = "projects/data-engineering-i2/datasets/group2_${each.key}"
}
