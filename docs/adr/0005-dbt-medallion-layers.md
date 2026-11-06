# ADR-0005: Build silver as dbt views and gold as dbt tables, and prove one revenue figure with tests

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L05

## Context

The warehouse (`group2_wh`, L04) holds typed copies of bronze. Bronze keeps duplicates on purpose:
every load is at-least-once (ADR-0003). Two users need clean data:

- Analysts need **one agreed revenue figure**. Today, two reports give two figures.
- The ML team needs **units sold per product, per country, per day**.

We need a place where duplicates are removed, a place where each question has one table,
and a way to prove the numbers are right, every day.

## Options considered

1. **SQL scripts run by hand in the console.** What we did in L04.
2. **dbt, every layer as tables.** Simple, every query reads stored data.
3. **dbt, silver as views and gold as tables.** Silver costs no storage and is always up to date;
   gold is stored because people and dashboards read it often.
4. **Materialized views only** (like `mv_daily_demand` in L04).

## Criteria

| Criterion | 1. Scripts | 2. All tables | 3. Views + tables | 4. Materialized views |
|---|---|---|---|---|
| Versioned, reviewed in pull requests | No | Yes | Yes | Partly (DDL only) |
| Tests on the numbers | No | Yes | Yes | No |
| Storage cost of silver | - | Copy of everything | None | Copy |
| Silver always matches the source | No | Only after a run | Yes | Yes |
| Joins and window functions allowed | Yes | Yes | Yes | Limited |

## Decision

Option 3: dbt Core 1.12.6. Silver (`group2_silver`) as views, gold (`group2_gold`) as tables.

- Silver removes duplicates with `QUALIFY ROW_NUMBER()` on the key (`order_id`, `order_id + p_id`).
- Gold: `fct_order_items`, `fct_daily_demand` (product x country x day, for the ML team),
  `fct_monthly_revenue` (the one revenue figure), `dim_product`, `dim_date`.
- Revenue is defined once: `SUM(qty * price_at_purchase)`, before discounts.
- Two tests prove it: `assert_revenue_reconciles` (monthly revenue = sum of order lines, to the cent)
  and `assert_no_order_lines_lost` (every distinct order line in the source reaches gold).
- Source freshness on `orders` and `order_items`: warn after 2 days, error after 7.

First run: `dbt build` PASS=50 WARN=0 ERROR=0 (14 models, 35 tests) in 20 s.
Country known for 100% of order lines (6 countries).

## Consequences

- Silver views are re-computed on every read. Fine at our size; a large silver table would be
  materialized later.
- Revenue is before discounts: discount amounts are not loaded. Analysts must know this.
- The first freshness check was red (last order in `group2_wh` was 2026-09-14): nothing reloaded
  the warehouse. This is what made the L07 DAG necessary.
- Every model change needs `dbt build`; a failed test stops the run instead of shipping wrong numbers.
