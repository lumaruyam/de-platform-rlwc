# ADR-0007: Orchestrate the daily chain in Airflow, one container per task, with an idempotent load

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L07

## Context

After L06, each step worked when someone ran it. Nothing ran it every day, in order. Proof: dbt's
freshness check was red, because the warehouse had been loaded once, by hand, on 2026-11-06.
Daily freshness is enough for both users (architecture.md).

## Options considered

1. **cron on a machine**, one line per job.
2. **Airflow, with the work inside the DAG file** (PythonOperator).
3. **Airflow, each task starts one of our images** (DockerOperator).

## Criteria

| Criterion | 1. cron | 2. Airflow, Python tasks | 3. Airflow, containers |
|---|---|---|---|
| Order between steps, stop on failure | By hand | Yes | Yes |
| Retries and alert | No | Yes | Yes |
| History of runs | No | Yes | Yes |
| Job libraries mixed with Airflow's | - | Yes | No (L06 images) |
| Same code as outside Airflow | Yes | No | Yes |

## Decision

Option 3. DAG `marketplace_daily_group2`, daily:

    extract_orders -> load_warehouse -> dbt_build -> dbt_freshness -> cost_check

- **Idempotent load:** `warehouse/06_daily_load.sql` uses `MERGE ... WHEN NOT MATCHED THEN INSERT`
  on the key. A retry or a rerun adds nothing.
- `catchup=False`: the extractor's cursor already covers past days.
- `max_active_runs=1`: two runs at once would read the same cursor. Seen on the first day: the
  second run waited.
- `retries=2`, then an alert callback.
- The database password is an Airflow Variable, masked in logs.

## Consequences

- First run: `load_warehouse` failed 3 times. It used the `bq` command line, which needed a gcloud
  re-login. Airflow retried twice and raised the alert. Fix: the same SQL through the BigQuery Python
  client, with the same credentials as the other tasks. Then both runs succeeded on every task.
- Freshness is now green. It is green partly because the shop simulator dates 8,189 orders in the
  future (up to 2026-12-02); `assert_no_future_orders` warns about it on every run.
- Before the first load, 1,175 bronze files had to be rewritten once: ids were FLOAT in files
  written before the type fix, and BigQuery could not read the folder.
- Airbyte keeps its own daily schedule; Airflow does not trigger it.
- Mount paths are the host's: the host's Docker starts the task containers.
