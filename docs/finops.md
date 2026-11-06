# FinOps

Step 9. Labels, a budget, a cost alert that runs every day, and one measured optimisation.

## Labels

Set in Terraform (`infra/providers.tf`, `default_labels`) on the bucket and the 3 datasets,
applied on 2026-11-06 (plan: 0 to add, 4 to change, 0 to destroy; then No changes).

| Label | Value | Why |
|---|---|---|
| `team` | `group2` | The class shares one project: this is how the bill is split by group |
| `project` | `albert-marketplace` | Which product the cost belongs to |
| `env` | `dev` | No production yet |
| `managed_by` | `terraform` | Change it in code, not in the console |
| `layer` (datasets) | `wh`, `silver`, `gold` | Cost per medallion layer |

## Budget

`infra/budget.tf` declares a 10 EUR monthly budget, filtered on `team=group2`, with alerts at
50%, 90% and 100%. It is **off** (`count = 0`) until `billing_account` is set.

Checked on 2026-11-06: the Cloud Billing API is not enabled on the shared class project, and a
budget needs the Billing Account Costs Manager role on the billing account. The group has neither.
Whoever owns the billing account can turn it on with one variable.

## Our own cost alert (works today)

Airflow task `cost_check`, every day, after the other tasks (`trigger_rule="all_done"`):
`warehouse/07_cost_check.sql` sums the bytes billed by our BigQuery jobs since the 1st of the month,
at the on-demand list price (6.25 USD per TiB). Above 1 USD, `ERROR()` fails the query, so the task
fails and the alert callback runs.

- 2026-11-06: 0.0218 USD month to date (about 3.5 GiB billed), status "under limit".
- Tested with a 0.01 USD limit: "BigQuery spend this month is 0.02 USD, above the 0.01 USD limit",
  container exit code 1.
- Limits: it counts the jobs of the account that runs it (`JOBS_BY_USER`); it is list price, not the
  invoice (the first TiB each month is free); storage is not included (see `docs/costs.md`).

## Measured optimisation: monthly partitions (L04)

Same queries, cache off, bytes processed read from the job log (`docs/warehouse-tuning.md`).

| Query | Unpartitioned | Partitioned by month | Less read |
|---|---|---|---|
| Q1 revenue per month, 12 months | 13,073,920 B | 4,497,632 B | 2.9x (-66%) |
| Q2 top 10 products, last quarter | 17,976,640 B | 1,572,824 B | 11.4x (-91%) |

On-demand pricing bills bytes read, so the bill drops by the same ratio. At our size each query
costs a fraction of a cent (and 10 MB minimum billing hides part of the gain). Scaled to a 1 TiB
fact table, Q2 would cost about 6.25 USD unpartitioned and about 0.55 USD partitioned, per run.
The materialized view by range reads 2.6x less again for daily demand per range.

## Other cost choices already in place

- Bucket: Nearline at 30 days, Coldline at 90, Archive at 365 for bronze; never deleted
  (first month about 0.033 USD, `docs/costs.md`).
- BigQuery on demand with billing caps: 10 MiB in the console, 1 GiB per dbt query (ADR-0004).
- Silver as views (no storage), gold as tables.
