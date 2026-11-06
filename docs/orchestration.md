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

## Quality gate drill (2026-11-06)

A row with `qty = 0` and an unknown product was inserted into `group2_wh.order_items`.

| Run | extract_orders | load_warehouse | dbt_build | dbt_freshness | cost_check |
|---|---|---|---|---|---|
| `gate_drill_2` | success | success | **failed** (3 tries) | upstream_failed | success |

dbt: `[ERROR] in test dbt_utils_expression_is_true_stg_order_items_qty___0`, PASS=39 ERROR=1 SKIP=17.
Gold kept 450,342 order lines and 0 drill rows: the gate stopped the bad row before gold.
The on-call person received the push alert at 20:12 (`docs/evidence/alert-gate-drill-2.png`).
The first drill (`gate_drill_1959`) sent no alert: the callback read `data_interval_start`, which a
manual run does not have in Airflow 3. Fixed to `run_id` (ADR-0007).
Repair: drill row deleted, DAG triggered (`repair_after_drill`): all 5 tasks success.

## Back-fill (2026-11-06)

`airflow backfill create --dag-id marketplace_daily_group2 --from-date 2026-11-03 --to-date 2026-11-05`,
with the shop's traffic generator stopped so that no new order could arrive.

| Measure | Before (19:17Z) | After (19:19Z) |
|---|---|---|
| `group2_wh.orders` | 244,969 | 244,969 |
| `group2_wh.order_items` | 450,342 | 450,342 |
| `group2_gold.fct_order_items` | 450,342 | 450,342 |
| Gold revenue, all months | 43,094,831.88 | 43,094,831.88 |

Runs `backfill__2026-11-03`, `-04`, `-05`: success. Three past days re-run, nothing duplicated,
revenue identical to the cent: rerunning any interval gives the same result.
