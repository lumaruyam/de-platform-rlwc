# dbt models (silver and gold)

Step 5. dbt Core 1.12.6 with the BigQuery adapter. Project in `dbt/`.
Run from `dbt/`: `dbt deps`, then `dbt build` (seed, models and tests in order).

## Layers

| Layer | BigQuery dataset | Models | Guarantee |
|---|---|---|---|
| Source | `group2_wh` | 7 typed native tables (L04) | Same rows as bronze |
| Silver | `group2_silver` (views) | `stg_*` (6), `int_*` (3), seed `category` | One row per real fact: duplicates removed with `QUALIFY ROW_NUMBER()`. Only `country` leaves the address tables |
| Gold | `group2_gold` (tables) | `fct_order_items`, `fct_daily_demand`, `fct_monthly_revenue`, `dim_product`, `dim_date` | Each table answers a named question at a declared grain |

## Gold tables

| Table | Grain | For whom |
|---|---|---|
| `fct_order_items` | one product in one order | base fact for the others |
| `fct_daily_demand` | product x country x day | ML team (units sold per product, per country, per day) |
| `fct_monthly_revenue` | month | analysts: the one agreed revenue figure |
| `dim_product` | product | product name, range (All Beauty / Premium Beauty), rating |
| `dim_date` | day | calendar |

Revenue is `SUM(qty * price_at_purchase)`, before discounts: discount amounts are not loaded.
Fact tables are partitioned by month of `order_date`, like in L04.

## Tests (first run, 2026-11-06)

`dbt build`: PASS=50 WARN=0 ERROR=0 (1 seed, 14 models, 35 tests) in 20 s.

- Keys: unique and not null on every grain.
- Relationships: order lines to orders, facts to `dim_product` and `dim_date`, products to `category`.
- Values: ratings in 1 to 5, quantities and units above 0.
- `assert_revenue_reconciles`: monthly revenue equals the sum of order lines, to the cent.
- `assert_no_order_lines_lost`: every distinct order line in the source reaches gold.

Country coverage: 6 countries, 0% unknown (Germany 28.3%, France 24.2%, Italy 20.1%,
Spain 17.0%, Netherlands 6.4%, Belgium 4.1%).

## Source freshness

`dbt source freshness` on `orders` and `order_items`: warn after 2 days, error after 7.
First run: ERROR STALE on both. Expected: `group2_wh` was loaded once by hand in L04 and
the last order there is 2026-09-14. Airbyte lands new data in the bucket every day, but
nothing reloads BigQuery yet. Orchestration in L07 closes this gap.

## Choices

- Silver as views: cheap to store, always up to date with the source.
- Gold as tables: read often by people and dashboards.
- `profiles.yml` has no secret: `oauth` uses the runner's gcloud login.
  `maximum_bytes_billed` is 1 GiB per query (ADR-0004); a full build reads about 100 MiB.