# Acceptance criteria

What the platform must guarantee, and the dbt test that enforces each line. All tests run in
`dbt build`, every day, in the Airflow task `dbt_build`; a failing test fails the task.

| # | Criterion | Enforced by |
|---|---|---|
| 1 | There is one revenue figure: monthly revenue equals the sum of order lines, to the cent | [`assert_revenue_reconciles`](../dbt/tests/assert_revenue_reconciles.sql) |
| 2 | No order line is lost between the source and gold | [`assert_no_order_lines_lost`](../dbt/tests/assert_no_order_lines_lost.sql) |
| 3 | One row per order, per order line, per review, per product in silver | `unique` / `unique_combination_of_columns` in [`_staging.yml`](../dbt/models/staging/_staging.yml) |
| 4 | Every gold table holds exactly its declared grain | `unique_combination_of_columns` on `fct_order_items`; `unique` on `demand_key`, `month`, `p_id`, `date_day` in [`_marts.yml`](../dbt/models/marts/_marts.yml) |
| 5 | Facts join the star: every product and date in a fact exists in its dimension | `relationships` to `dim_product` and `dim_date` in [`_marts.yml`](../dbt/models/marts/_marts.yml) |
| 6 | The ML team gets units per product, per country, per day, with a known country | `not_null` on `country`, `expression_is_true units > 0` on `fct_daily_demand` |
| 7 | Data is at most one day old; a missed run is visible | source freshness, warn 2 days, error 7 days, in [`sources.yml`](../dbt/models/sources.yml) (task `dbt_freshness`) |
| 8 | No e-mail or phone number reaches silver or gold | [`assert_no_pii_in_reviews`](../dbt/tests/assert_no_pii_in_reviews.sql) |
| 9 | Ratings are valid, quantities are positive | `accepted_values [1..5]` on `rating`, `expression_is_true qty > 0` |
| 10 | Orders dated in the future are visible (warning, not a failure) | [`assert_no_future_orders`](../dbt/tests/assert_no_future_orders.sql) |

Not covered by a test yet: updated or deleted orders in the source (no CDC, ADR-0003).
