# Orchestration (Airflow)

Step 7. One DAG runs the whole chain every day: `orchestration/dags/marketplace_daily.py`.

    extract_orders -> load_warehouse -> dbt_build -> dbt_freshness

| Task | Image | What it does |
|---|---|---|
| `extract_orders` | `group2-ingestion:0.1` | New orders since the saved cursor -> `bronze/orders_extract` |
| `load_warehouse` | `group2-dbt:0.1` (Python BigQuery client) | Runs `warehouse/06_daily_load.sql`: MERGE new orders (from our extractor) and order lines (from Airbyte) into `group2_wh` |
| `dbt_build` | `group2-dbt:0.1` | Silver and gold, with all tests |
| `dbt_freshness` | `group2-dbt:0.1` | Fails if the newest order is older than 7 days |

Airbyte (daily, `postgres-to-bronze`) is scheduled in Airbyte itself, not in this DAG.

## Choices

- **Each task is a container** (`DockerOperator`). The DAG says what runs and in what order;
  the work is in the step 6 images. Mounts are host paths (`HOST_DIR`, `GCLOUD_DIR`), because
  the host's Docker daemon starts the task containers.
- **Idempotent load.** `MERGE` only inserts keys that are not there yet, so a retry or a rerun adds nothing.
- `schedule="@daily"`, `catchup=False` (the cursor already covers past days),
  `max_active_runs=1` (two runs at once would read the same cursor).
- `retries=2`, one minute apart, then an alert callback.
- **No secret in the DAG.** The database password is the Airflow Variable `pg_password`:
  its name contains "password", so Airflow masks it in the UI and logs.
  Google access: the host's Application Default Credentials, mounted read-only.

## First runs (2026-11-06)

- The scheduled run failed 3 times on `load_warehouse`: the `bq` command line used the gcloud
  user login, which needed a re-login. Airflow retried twice, then marked it failed and called the alert.
- Fix: run the same SQL with the BigQuery Python client inside the dbt image, with the same
  credentials as the other tasks. The `google/cloud-sdk` image is no longer needed.
- After the fix, both runs (manual and scheduled) succeeded on all 4 tasks.
  Warehouse after load: 244,731 orders, 450,342 order lines.
- Before the first load, 1,175 of the 1,177 files in `bronze/orders_extract` were rewritten once
  (`ingestion/fix_extract_types.py`): ids were FLOAT in files written before the type fix, so
  BigQuery could not read the folder. Same values, same 244,675 rows.

## Known issue: orders dated in the future

8,189 orders (ids 236,548 to 244,743) are dated 2026-11-07 to 2026-12-02, after today.
Ids and dates grow together, so the shop's traffic simulator most likely runs its clock ahead
of real time. Consequence: `dbt_freshness` is green partly because of these dates.
The test `assert_no_future_orders` (severity warn) shows them on every run. Rows are kept.

## How to run

```bash
cd orchestration
cp .env.example .env      # fill in HOST_DIR and GCLOUD_DIR
docker compose up -d      # UI on http://localhost:8080
docker compose exec airflow-scheduler airflow variables set pg_password <password>
docker compose exec airflow-scheduler airflow dags unpause marketplace_daily_group2
```
