# Runbook: erase one customer

Use it when a customer asks to be forgotten (GDPR article 17). Owner: the architecture lead (privacy).
Tested once on 2026-11-06, on a real buyer id (results at the end). The id is not written here:
its SHA-256 starts with `9743b6087a1b`.

**What "erased" means here.** Orders and order lines are kept, because revenue must not change, but
they no longer point to anyone: `buyer_id` becomes NULL. Reviews are kept for product ratings, with
author, text and title set to NULL. Addresses are deleted.

**Before you start.** Ask the shop to erase the customer in its own database first. If you do not,
the next Airbyte full refresh (every 24 hours) brings back their reviews and addresses.

## 1. Find the person

The identifier is `buyer_id` (called `c_id` in the address tables). Where it lives:

| Where | Table / folder | Columns |
|---|---|---|
| Bronze, export of step 2 | `bronze/orders/`, `bronze/review/`, `bronze/customer_shipping/`, `bronze/shipping_details/` | `buyer_id`, `r_desc`, `title`, `c_id`, the whole address row |
| Bronze, our extractor | `bronze/orders_extract/` | `buyer_id` |
| Bronze, Airbyte | `bronze/airbyte/orders/`, `review/`, `customer_shipping/`, `shipping_details/` | same as the export |
| Bronze, clickstream | `bronze/clickstream/` | `buyer_id`, `session_id` |
| Warehouse | `group2_wh.orders`, `review`, `customer_shipping`, `shipping_details` | same |
| Silver | `stg_orders`, `stg_customer_shipping` (views) | `buyer_id`, `c_id` |
| Gold | nothing | no buyer id in gold |

Addresses are found through `customer_shipping.c_id`, then `address_id`.

Dry run, which only counts (terminal at the root of the repository, Docker running):

```bash
docker run --rm -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json -e GOOGLE_CLOUD_PROJECT=data-engineering-i2 \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/adc.json:ro" \
  -v "$PWD/scripts/erase_buyer.py:/tmp/erase_buyer.py:ro" --entrypoint sh \
  europe-west1-docker.pkg.dev/data-engineering-i2/dataeng/group2-ingestion:4219782 \
  -c "pip install -q --user google-cloud-bigquery; python /tmp/erase_buyer.py <buyer_id>"
```

It lists every bronze file holding the person and counts the warehouse rows. Keep this output.

## 2. Bronze and the warehouse

Same command, with `--apply` after the id. [`scripts/erase_buyer.py`](../../scripts/erase_buyer.py)
reads every Parquet file under `bronze/`, rewrites only the files that hold the person, then runs
`UPDATE` and `DELETE` on the 4 warehouse tables. About 2 minutes.

## 3. Silver and gold

```bash
cd dbt && dbt build
```

Silver models are views on `group2_wh`, so they show the change at once. Gold tables are rebuilt
from silver. About 2 minutes. Expect ERROR=0.

## 4. The copies that survive

| Copy | Retention | What we do |
|---|---|---|
| Old versions of the rewritten bronze files | Versioning is on (ADR-0008): noncurrent versions are deleted after **30 days** | **Not solved.** They still hold the person until then. Option: delete the noncurrent versions of the listed files by hand (`gcloud storage rm` with each file's generation). Not done because it removes our way to undo a bad rewrite; to decide as a group. |
| Soft-deleted objects | **7 days** after any deletion | Wait. Cannot be shortened below 7 days without turning soft delete off. |
| BigQuery time travel on `group2_wh` and gold | **7 days** (default), then 7 days of fail-safe | Wait. Could be shortened to 2 days with `max_time_travel_hours = 48` on the datasets. |
| Shop database | Not ours | The shop erases at source, before step 1. |
| Airbyte, next full refresh | Every 24 hours | Comes back if the shop has not erased. Check with a dry run the day after. |

So the honest answer to "is the person erased?" is: from everything a query reaches, at once; from
every copy, after 30 days.

## 5. Prove it

1. Run the dry run again: it must say `0 files with 0 rows` and warehouse counts of 0.
2. Count in silver: `SELECT COUNTIF(buyer_id = '<id>') FROM group2_silver.stg_orders` and the same on
   `stg_customer_shipping.c_id`: both 0.
3. Revenue unchanged: `SELECT SUM(revenue) FROM group2_gold.fct_monthly_revenue`.
4. Write in the erasure issue: the date, the hash of the id (not the id), the before and after counts,
   and the date the 30-day versions expire.

## Test, 2026-11-06

The buyer with the most data: 230 orders, 115 reviews, 1 address.

| Check | Before | After |
|---|---|---|
| Bronze files scanned | 3,394 | 3,394 |
| Files holding the person | 391 (924 rows) | 0 |
| `group2_wh`: orders / reviews / addresses | 230 / 115 / 1 | 0 / 0 / 0 |
| `dbt build` | | PASS=57 WARN=1 ERROR=0 |
| Silver: orders / addresses | | 0 / 0 |
| Gold revenue | 43,094,831.88 | 43,094,831.88 |

Timing: apply started at 19:29 UTC, dbt finished at 19:31 UTC: under 3 minutes for bronze, warehouse, silver and gold.

What we learned:
- **The same person existed 3 times over**: once per ingestion path (export, extractor, Airbyte).
  Each path we added in step 3 is one more place to erase.
- The clickstream held no event for this buyer.
- Writing the script took longer than running it. Without it, rewriting 391 files by hand is not realistic.
- Not covered by the test: the 30-day old versions, and whether Airbyte brings the person back.
