# Warehouse (L04) and the two dbt layers (L05), adopted here (see imports.tf).
locals {
  datasets = {
    wh     = "Typed native tables loaded from bronze (L04)"
    silver = "dbt silver: cleaned views (L05)"
    gold   = "dbt gold: tables for analysts and the ML team (L05)"
  }
}

resource "google_bigquery_dataset" "layer" {
  for_each = local.datasets

  dataset_id = "${var.group}_${each.key}"
  location   = var.region

  # Dropping a dataset from the code must not drop its tables.
  delete_contents_on_destroy = false
}
