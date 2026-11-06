# Costs

Steps 2 and 9. What the platform costs, who owns each cost, and how we keep it down.
All figures measured on 2026-11-06 unless dated otherwise. Prices are public list prices
(Cloud Storage read 2026-11-03, BigQuery and Artifact Registry read 2026-11-06); the
europe-west1 rate can be slightly higher than the US list price.

## Label convention

Every resource Terraform manages carries these labels (`infra/providers.tf`, `default_labels`,
applied 2026-11-06). The class shares one project, so labels are the only way to split the bill.

| Label | Values | Why |
|---|---|---|
| `team` | `group2` | Owner of the spend in the shared project. Unlabelled spend is unowned spend |
| `project` | `albert-marketplace` | Which product the cost belongs to |
| `env` | `dev` | No production yet; a prod copy would be split out the same way |
| `managed_by` | `terraform` | Change it through code, not the console |
| `layer` | `wh`, `silver`, `gold` (datasets) | Cost per medallion layer |
| `data_class` | `confidential`, `internal` (datasets) | Governance, not cost: what the data is (ADR-0010) |

Labels are set at creation by Terraform, never by hand: a label added in the console is not
even seen as drift (`docs/infra.md`).

## Ledger: one row per resource

| Resource | Size / usage (2026-11-06) | Price | Cost per month |
|---|---|---|---|
| Bucket `data-engineering-i2-group2`, Standard storage | 239.1 MiB, 3,396 objects | 0.020 USD per GiB-month | 0.005 USD |
| Bucket writes (Class A operations) | about 4,600 writes so far (3,396 objects + 1,175 type-fix rewrites) | 0.005 USD per 1,000 | 0.023 USD so far, then a few per day |
| BigQuery storage `group2_wh` | 172.0 MiB, 21 tables | 0.02 USD per GiB-month (first 10 GiB free) | 0.003 USD |
| BigQuery storage `group2_gold` | 76.8 MiB, 5 tables | same | 0.002 USD |
| BigQuery storage `group2_silver` | 0 (12 views) | same | 0 |
| **BigQuery queries (on demand)** | **11.04 GiB billed this month, 1,050 jobs** | **6.25 USD per TiB (first TiB free)** | **0.067 USD month to date** |
| Artifact Registry, 2 images | about 0.45 GB (178 MB + 276 MB) | 0.10 USD per GB-month (0.5 GB free per billing account) | up to 0.045 USD |
| Airflow, Airbyte, Kafka, the shop | run on a laptop (Docker) | - | 0 |

First month of the bucket alone, estimated in L02: about 0.033 USD, with writes about 18 times
the storage. The invoice for all of this is 0 USD today: every line is inside a free tier.

## Largest cost: BigQuery queries

- **SKU:** BigQuery Analysis, on-demand, europe-west1.
- **Size:** 0.067 USD month to date at list price (11.04 GiB billed), against 0.005 USD for the bucket.
- **Shape:** it follows the number of runs, not the volume of data. We processed 4.61 GiB but were
  billed 11.04 GiB: 2.4 times more, because every query is billed at least 10 MB per table it reads.
  A `dbt build` runs about 58 small queries, so most of them are billed at the minimum. Spend
  comes in steps, one per build or test session, not as a steady line.
- **What would move it:** fewer full rebuilds (incremental gold models), fewer test queries on tiny
  tables, or capacity pricing if the volume grew past the free TiB (ADR-0004).

## Optimisation, before and after: monthly partitions (L04)

Same query, cache off, bytes processed from the job log (`docs/warehouse-tuning.md`).

| Query | Before (no partition) | After (partitioned by month) | Gain |
|---|---|---|---|
| Revenue per month, last 12 months | 13,073,920 B | 4,497,632 B | 2.9x less (-66%) |
| Top 10 products, last quarter | 17,976,640 B | 1,572,824 B | 11.4x less (-91%) |

On-demand pricing bills bytes read, so the query bill drops by the same ratio. At our size the
10 MB minimum hides part of it; on a 1 TiB fact table, the second query would go from about
6.25 USD to about 0.55 USD per run.

## Budget alert, and what it does not do

- **Budget:** `infra/budget.tf`, 10 EUR a month on `team=group2`, alerts at 50%, 90%, 100%.
  Off (`count = 0`): the Cloud Billing API is not enabled on the class project and a budget needs
  the Billing Account Costs Manager role (checked 2026-11-06).
- **Our own alert, working today:** the Airflow task `cost_check` fails above 1 USD of BigQuery
  queries this month and sends the on-call push alert. Tested with a 0.01 USD limit: it fired.
- **What neither does:** a budget alert only notifies, it never stops spending. Our `cost_check`
  counts BigQuery queries of the account that runs it, at list price: not storage, not the registry,
  not other members' queries, not free-tier credits. It runs once a day, so a costly query is seen
  the next morning; the per-query billing cap (10 MiB in the console, 1 GiB in dbt) is what stops it
  on the spot.

Decision record: `docs/adr/0009-cost-attribution.md`.
