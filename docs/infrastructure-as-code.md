# Infrastructure as code (Terraform)

Step 8. Code in `infra/`. Terraform 1.17.1, Google provider `~> 8.4`.

## What is managed

| Resource | Terraform address | Created |
|---|---|---|
| Bucket `data-engineering-i2-group2` | `google_storage_bucket.lake` | by hand in L02, imported |
| Dataset `group2_wh` | `google_bigquery_dataset.layer["wh"]` | by hand in L04, imported |
| Dataset `group2_silver` | `google_bigquery_dataset.layer["silver"]` | by dbt in L05, imported |
| Dataset `group2_gold` | `google_bigquery_dataset.layer["gold"]` | by dbt in L05, imported |

The bucket code carries every setting chosen in L02: Standard class, public access blocked,
uniform access, 7-day soft delete, and the bronze lifecycle (Nearline at 30 days, Coldline at 90,
Archive at 365, never deleted; incomplete uploads aborted after 1 day).

## How it was adopted

`imports.tf` adopts the existing resources instead of creating new ones.

1. First plan: 4 to import, 1 to change. The change: Terraform wanted to remove the bucket's
   encryption enforcement rules, set by Google when the bucket was created.
   We do not manage them: `ignore_changes = [encryption]`.
2. Second plan: 4 to import, 0 to add, 0 to change, 0 to destroy.
3. `terraform apply` of that saved plan: only the state was written, no resource changed.
4. Third plan: No changes. Code and cloud match.

## Safety

- **Remote state** in the bucket (`terraform/state`), shared by the group and CI. It sits outside
  `bronze/`, so the lifecycle rules never move it.
- `prevent_destroy` on the bucket: it holds the data and the state.
- `delete_contents_on_destroy = false` on datasets: removing a dataset from the code cannot drop its tables.
- `.tfstate` files and `.terraform/` are never committed. The lock file `.terraform.lock.hcl` is.

## CI

`.github/workflows/terraform-plan.yml` runs on every pull request that touches `infra/`:

- always: `terraform fmt -check` and `terraform validate` (no cloud access);
- `terraform plan`, when the repository has a `GCP_CREDENTIALS` secret; the plan goes to the job summary.

Limit: we cannot create a service account on the shared class project, so the secret is not set
yet and CI runs fmt and validate only. With a read-only service account key in `GCP_CREDENTIALS`,
the plan runs with no change to the workflow.

## How to run

```bash
cd infra
terraform init
terraform plan
```
