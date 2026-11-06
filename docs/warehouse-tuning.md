# Warehouse tuning

Step 4. Where our BigQuery tables live, how we made the queries cheaper,
and the numbers that prove it. All measures were taken on 2026-11-06.

## Setup

- Dataset: `data-engineering-i2.group2_wh`, region `europe-west1` (same as the bucket).
- "Today" for every query is `2026-09-14`, the last day of data in the shop.
- SQL files are in `warehouse/`, in the order we ran them.

### Row counts

Native tables hold every row of the bucket. We counted each table after loading.

| Table | Rows |
|---|---|
| orders | 222,644 |
| order_items | 408,560 |
| review | 111,322 |
| product_reviews | 111,322 |
| product | 42,858 |
| customer_shipping | 200,001 |
| shipping_details | 200,001 |

## How we measured

- **Cache off.** "Use cached results" was unchecked. A cached query reads 0 bytes,
  which would fake the result. Every measure below has `cache_hit = false`.
- **Bytes processed, not bytes billed.** BigQuery bills at least 10 MB per table read.
  On tables this small, that minimum hides the difference. Bytes processed show
  the real work. On large tables, the bill follows the bytes processed.
- **Read from the job log.** Numbers come from `INFORMATION_SCHEMA.JOBS_BY_USER`
  (`warehouse/05_measure_bytes.sql`), not from screenshots.
- **Same query on every table.** Only the table name changes.

The three versions of `order_items`:

| Table | Layout |
|---|---|
| `order_items` | no partition, no cluster |
| `order_items_p` | partitioned by month of `order_date` |
| `order_items_pc` | partitioned by month, clustered by `p_id` |

## Results

### Q1: revenue per month, last 12 months

| Table | Bytes processed | vs base |
|---|---|---|
| order_items | 13,073,920 (12.47 MiB) | - |
| order_items_p | 4,497,632 (4.29 MiB) | 2.9x less (-66%) |
| order_items_pc | 4,497,632 (4.29 MiB) | same as `_p` |

The data covers about 36 months. The query asks for 13 of them (the first and
last months are partial). With partitions, BigQuery reads about 13/36 = 36% of
the table. We measured 34%. The gain can be predicted before running the query.

### Q2: top 10 products by revenue, last quarter

| Table | Bytes processed | vs base |
|---|---|---|
| order_items | 17,976,640 (17.14 MiB) | - |
| order_items_p | 1,572,824 (1.50 MiB) | 11.4x less (-91%) |
| order_items_pc | 1,572,824 (1.50 MiB) | same as `_p` |

The window is shorter (4 monthly partitions), so the gain is bigger.
The base table reads more than in Q1 because Q2 also reads the `p_id` column.
BigQuery stores data by column and only reads the columns a query uses.

We rank by revenue, not by units. The top product (`B088BCCTN6`) sold only
8 units, but at more than 2,000 each.

### Clustering test: one product, last quarter

| Table | Bytes processed |
|---|---|
| order_items_p | 1,572,824 |
| order_items_pc | 1,572,736 |

88 bytes of difference: clustering gives nothing at our size. BigQuery skips
blocks only inside large partitions, and ours are about 0.4 MiB per month.
Clustering only helps a query that filters on `p_id`. Q1 and Q2 do not.
We keep it: it costs nothing and will help when the data grows.

### Q3: average rating of products with more than 50 reviews

| Table | Bytes processed |
|---|---|
| review + product_reviews | 4,007,592 (3.82 MiB) |

124 products have more than 50 reviews. The review tables have no date column,
so partitioning is not possible. The right fix for this query is precomputing,
not partitioning.

## Materialized views

A materialized view stores the result of a query and keeps it up to date.

| View | Grain | Rows | Rows vs `order_items` |
|---|---|---|---|
| `mv_daily_demand` | day x product | 356,981 | 1.14x less |
| `mv_daily_demand_category` | day x range | 2,163 | 189x less |

Bytes processed, last quarter:

| Question | Without view (`order_items_pc`) | With view | Gain |
|---|---|---|---|
| Demand per day and product | 1,572,824 | 1,376,892 | 1.14x less (-12%) |
| Demand per day and range | 2,429,984 | 943,680 | 2.6x less (-61%) |

What we learned:

- **The gain depends on how much the view summarises.** Demand per product is
  very sparse: a product sells on about 8 days in 3 years, often in one order
  line. So the day x product view merges almost nothing. We keep it because
  it is the grain the ML team needs.
- **The catalogue has only two ranges.** `category` holds 1 = All Beauty
  (42,637 products) and 2 = Premium Beauty (221 products). We checked this in
  the source database, not only in BigQuery. The range view is for dashboards.
- **BigQuery rewrites queries by itself.** A query written on `order_items_p`
  read the view instead (`tables_read` in the job log). Analysts do not need
  to know the view exists. To measure "without view" we used `order_items_pc`,
  which has no view on it.
- **189x fewer rows, but only 2.6x fewer bytes.** Our guess: each read of the
  view also checks the base table for rows added since the last refresh.
  We did not prove this.
- **No order line is lost by the join.** `SUM(order_lines)` in the range view
  is 408,560.

## Cost guard: maximum bytes billed

We set "Maximum bytes billed" to 10,485,760 (10 MiB). A query above the limit
is refused before it runs, and costs nothing.

- Q1 on `order_items_p` (billed 10 MiB): runs.
- Q1 on `order_items` (needs 13,631,488): refused.
  Proof: `warehouse/max-bytes-billed-error.png`.
- In a script, the limit is for the **whole script**, not for each query.
  Our first test ran both queries in one script: the second one was refused
  with "limit: 0" because the first one had used the budget.

## Data issues found on the way

- `review.seller_product_flag` is `S` on all 111,322 rows. It tells nothing.
- `orders_extract.payment_id` is FLOAT in some files and INT in others
  (empty for PayPal). `orders` is loaded from the step 2 copy instead.
  To fix in `ingestion/extract_orders.py`.

## Decisions

1. Fact tables are **partitioned by month** of `order_date`. Most questions are
   about a date range. Month gives about 36 partitions; day would give
   about 1,100 small ones.
2. `order_items` is **clustered by `p_id`**. No gain today, no cost, useful later.
3. Two **materialized views**: day x product for ML, day x range for dashboards.
4. **10 MiB billing cap** on our queries. Pricing choice: see
   `docs/adr/0004-warehouse-pricing.md`.