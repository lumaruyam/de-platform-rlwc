# Monthly budget alert on the shared project, filtered on our team label.
# Needs the Cloud Billing API and the Billing Account Costs Manager role on the
# billing account, which the group does not have (checked 2026-11-06).
# Off until billing_account is set: then `terraform apply` creates it.
variable "billing_account" {
  description = "Billing account id (XXXXXX-XXXXXX-XXXXXX). Empty: no budget is created."
  type        = string
  default     = ""
}

data "google_project" "this" {
  count = var.billing_account == "" ? 0 : 1
}

resource "google_billing_budget" "group" {
  count           = var.billing_account == "" ? 0 : 1
  billing_account = var.billing_account
  display_name    = "${var.group} monthly budget"

  budget_filter {
    projects = ["projects/${data.google_project.this[0].number}"]
    labels   = { team = var.group }
  }

  amount {
    specified_amount {
      currency_code = "EUR"
      units         = "10"
    }
  }

  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.9 }
  threshold_rules { threshold_percent = 1.0 }
}
