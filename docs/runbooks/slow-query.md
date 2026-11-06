# Runbook: slow or expensive query

Use this when a BigQuery query is slow, costs too much, or is refused with
"Query exceeded limit for bytes billed".

## 1. Find the query and its numbers

In the BigQuery console, open the query, then **Job information**:
read **Bytes processed** and **Duration**.

Or read the job log (works for anyone's own queries):

```sql
SELECT creation_time, total_bytes_processed, total_slot_ms, cache_hit,
       ARRAY_TO_STRING(ARRAY(SELECT table_id FROM UNNEST(referenced_tables)), ', ') AS tables_read,
       query
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY total_bytes_processed DESC
LIMIT 10;
```

## 2. Check the usual causes, in this order

| Check | How to see it | Fix |
|---|---|---|
| Reads the unpartitioned table | FROM `order_items` or `orders` | Use `order_items_p` or `orders_p` |
| No date filter, or the filter is on a function of the date | WHERE missing, or `WHERE EXTRACT(YEAR FROM order_date) = 2026` | Filter directly on `order_date`: `WHERE order_date BETWEEN ... AND ...` |
| `SELECT *` | the query text | List only the columns you need |
| Demand per day already exists | groups `order_items` by day and product or range | Read `mv_daily_demand` or `mv_daily_demand_category` |
| Cache turned off on purpose | `cache_hit = false` on a query that runs often | Turn "Use cached results" back on, except for measures |

A filter on a function of the date (`EXTRACT`, `FORMAT_DATE`...) may stop
BigQuery from skipping partitions. A plain range on `order_date` always works.

## 3. Check before running again

Paste the fixed query in the editor without running it. The top right shows
"This query will process X when run". Compare with the old number.

## 4. Refused by the billing cap

The cap is 10 MiB per query (`docs/adr/0004-warehouse-pricing.md`).

- First, apply step 2. Most refused queries read an unpartitioned table.
- In a script, the cap is for the whole script. Split the script, or run the
  big statement alone.
- Raise the cap only for a known big job (for example rebuilding tables with
  `warehouse/01_native_tables.sql` or `02_partition_cluster.sql`), and set it
  back after.

## 5. Still slow after all this

- Open **Execution graph** on the query: the stage with the most time or
  the most rows is the problem.
- A JOIN that multiplies rows: check the join keys. For example, `review`
  joins `product_reviews` on `review_id`, one row each.
- Write what you found and the numbers in `docs/warehouse-tuning.md`.