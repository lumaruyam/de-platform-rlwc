# ADR-0007: Make every task idempotent, so any run can be repeated safely

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L07

## Context

Airflow retries a failed task, and people rerun failed days or back-fill past ones. If a rerun
adds rows a second time, every retry corrupts the numbers. Our loads are at-least-once
(ADR-0003): the same order can reach bronze twice. Airflow runs the chain every day, one
container per task, with images from the registry (ADR-0006):

    extract_orders -> load_warehouse -> dbt_build -> dbt_freshness -> cost_check

## Options considered

1. **Append and clean later**: tasks insert, a weekly job removes duplicates.
2. **Delete then insert by date** (overwrite the day's partition).
3. **Key-based idempotency**: each task either reads a saved position or writes by key, so a
   second run changes nothing.

## Criteria

| Criterion | 1. Append, clean later | 2. Overwrite by date | 3. By key |
|---|---|---|---|
| A retry adds nothing | No | Yes | Yes |
| Works when rows are not grouped by date (cursor on order_id) | Yes | No | Yes |
| Wrong numbers visible to users between runs | Yes | No | No |
| Effort | Low | Medium | Medium |

## Decision

Option 3. The mechanism, task by task:

| Task | Mechanism |
|---|---|
| `extract_orders` | Cursor on `order_id`, saved **after** the file is written. A rerun before the save re-reads the same orders; a rerun after reads nothing new |
| `load_warehouse` | `MERGE ... WHEN NOT MATCHED THEN INSERT` on `order_id` and on `(order_id, p_id)`: an existing key is never inserted twice |
| `dbt_build` | Silver views deduplicate with `QUALIFY ROW_NUMBER()` on the key; gold tables are rebuilt in full from silver |
| `dbt_freshness` | Read only |
| `cost_check` | Read only |

Also: `max_active_runs=1` (two runs would read the same cursor), `retries=2`, then a push alert
to the on-call person (ntfy). `dbt_build` is the quality gate: a failed test stops the run before
gold is rebuilt.

## Consequences

- Gate drill (2026-11-06): a row with `qty = 0` inserted into `group2_wh.order_items`.
  `dbt_build` failed 3 times on `expression_is_true qty > 0` (PASS=39 ERROR=1 SKIP=17),
  `dbt_freshness` was `upstream_failed`, gold kept 450,342 lines with 0 drill rows.
- The same drill found a bug in our alert: it read `data_interval_start`, which a manual run does
  not have in Airflow 3, so no notification was sent. Fixed to use `run_id`; second drill: the
  phone received it.
- Back-fill and before/after counts: `docs/orchestration.md`.
- A cursor cannot see updated or deleted orders (ADR-0003): idempotency protects against
  duplicates, not against missed changes.
