# Infrastructure

Step 8. Terraform 1.17.1, Google provider `~> 8.4` (pinned, `.terraform.lock.hcl` committed),
code in `infra/`, state in a GCS backend. Details of the adoption: `docs/infrastructure-as-code.md`.

## One line per resource: why it exists

| Resource | Why |
|---|---|
| `google_storage_bucket.lake` | Holds bronze (raw data, never deleted) and the Terraform state. Versioned so a bad state write can be rolled back |
| `google_bigquery_dataset.layer["wh"]` | Typed copy of bronze that dbt reads (L04) |
| `google_bigquery_dataset.layer["silver"]` | dbt silver: one clean version of each fact, as views |
| `google_bigquery_dataset.layer["gold"]` | dbt gold: tables for analysts and the ML team; the only dataset consumers read |
| `google_bigquery_dataset_iam_member.gold_reader` | Gives consumers read access to gold only (empty list today, ADR-0010) |
| `google_service_account.pipeline` (+ 2 grants) | The pipeline's own identity, with write access to the bucket and the 3 datasets only. Off: creation refused (below) |
| `google_billing_budget.group` | 10 EUR monthly budget on `team=group2`. Off: no billing rights (ADR-0009) |
| `data.google_artifact_registry_repository.class` | The class registry `dataeng`, read only: where our images live (ADR-0006) |

## Remote state

`backend "gcs"`: bucket `data-engineering-i2-group2`, prefix `terraform/state`, outside `bronze/`.
Versioning turned on through Terraform on 2026-11-06 (plan: 1 to change, applied). Old versions
are kept at most 10 per object and 30 days, so versioning costs almost nothing: bronze files are
never overwritten, only the state and the cursor are.

## A drift we caused and caught (2026-11-06)

1. **First try, not caught.** We added a label `owner=by-hand` to `group2_gold` with SQL, outside
   Terraform. `terraform plan`: No changes. Since provider 5, Terraform manages only the labels in
   its code; a label added by hand is not drift for it.
2. **Second try, caught.** We changed a label Terraform manages, `data_class`, from `internal` to
   `public`: the dangerous case, someone declassifying data without a pull request.

```text
  ~ resource "google_bigquery_dataset" "layer" {
          ~ "data_class" = "public" -> "internal"
Plan: 0 to add, 1 to change, 0 to destroy.
Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
No changes. Your infrastructure matches the configuration.
```

Lesson: drift detection covers what the code declares. Anything that matters must be in the code.

## What we could not do

```text
Error: Error creating service account: googleapi: Error 403:
Permission 'iam.serviceAccounts.create' denied on resource '//cloudresourcemanager.googleapis.com/projects/data-engineering-i2'
Error creating Repository: Permission 'artifactregistry.repositories.create' denied
```

The shared class project does not let groups create service accounts or registries. The code is
written and switched off (`manage_iam = false`); `terraform apply -var manage_iam=true` creates
them once someone grants the rights.

## CI

`.github/workflows/terraform-plan.yml`: `terraform fmt -check` and `terraform validate` on every
pull request that touches `infra/`; `terraform plan` when the `GCP_CREDENTIALS` secret exists.
