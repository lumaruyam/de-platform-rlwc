# Runbook: a pipeline run failed

Use this when the phone gets **"Airflow: group 2 pipeline failed"** (ntfy, on-call: Rania Mehria),
or when a run is red in Airflow (`http://localhost:8080`, DAG `marketplace_daily_group2`).

## 1. Find the failed task and read its log

The alert names the task and the run: `marketplace_daily_group2.<task> failed in run <run_id> after 3 tries`.

```bash
cd orchestration
docker compose exec airflow-scheduler airflow tasks states-for-dag-run marketplace_daily_group2 <run_id>
less logs/dag_id=marketplace_daily_group2/run_id=<run_id>/task_id=<task>/attempt=3.log
```

## 2. Act by task

| Task | Usual cause | What to do |
|---|---|---|
| `extract_orders` | Shop database down or unreachable (5 tries, then stop) | Check `docker compose ps` in the shop folder. Rerun: the cursor was not saved, nothing is lost |
| `load_warehouse` | BigQuery credentials expired; a bronze file with a new type | Renew `gcloud auth application-default login`. A type error: see `ingestion/fix_extract_types.py` |
| `dbt_build` | **A test failed: the quality gate stopped bad data before gold** | Read which test in the log (`[ERROR]: in test ...`). Fix the data at its source, never the test, then rerun |
| `dbt_freshness` | No new orders for 7 days | Check that `extract_orders` and Airbyte still run |
| `cost_check` | BigQuery spend this month above 1 USD | Find the expensive queries: `docs/runbooks/slow-query.md` |

## 3. Rerun

Every task is idempotent (ADR-0007): rerunning the whole DAG is always safe.

```bash
docker compose exec airflow-scheduler airflow dags trigger marketplace_daily_group2 --run-id repair_<date>
```

`airflow tasks clear` only selects runs by logical date: a manually triggered run has none in
Airflow 3, so trigger a new run instead (learned in the gate drill, 2026-11-06).

## 4. Write it down

Add one line to `docs/orchestration.md` (date, task, cause, fix) if the cause was new.
