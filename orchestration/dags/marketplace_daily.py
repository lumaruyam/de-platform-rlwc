"""Albert's Marketplace, group 2: one daily run from the shop database to gold.

    extract_orders -> load_warehouse -> dbt_build -> dbt_freshness

Each task starts one container. This file only says what runs, in what order,
and what happens on failure; the work is in the images built in step 6.
"""

import os

import pendulum
from airflow.providers.docker.operators.docker import DockerOperator
from airflow.sdk import DAG
from docker.types import Mount

# Host paths, not this container's: a DockerOperator asks the host's Docker
# daemon to start the task container, so every mount is resolved on the host.
HOST_DIR = os.environ["HOST_DIR"]        # the repository on the host
GCLOUD_DIR = os.environ["GCLOUD_DIR"]    # the host's gcloud config

# Read-only: a task has no business changing the gcloud config.
gcloud = Mount(source=GCLOUD_DIR, target="/gcloud-ro", type="bind", read_only=True)
load_sql = Mount(source=f"{HOST_DIR}/warehouse/06_daily_load.sql",
                 target="/sql/load.sql", type="bind", read_only=True)

cost_sql = Mount(source=f"{HOST_DIR}/warehouse/07_cost_check.sql",
                 target="/sql/cost.sql", type="bind", read_only=True)

GOOGLE_ENV = {
    "GOOGLE_APPLICATION_CREDENTIALS": "/gcloud-ro/application_default_credentials.json",
    "GOOGLE_CLOUD_PROJECT": "data-engineering-i2",
}

# Runs warehouse/06_daily_load.sql with the BigQuery Python client (inside the dbt image),
# using the same Application Default Credentials as the other tasks.
LOAD = (
    "from google.cloud import bigquery; "
    "c = bigquery.Client(project='data-engineering-i2', location='europe-west1'); "
    "[print(dict(r), flush=True) for r in c.query(open('/sql/load.sql').read()).result()]"
)

# Same runner, other file: month-to-date BigQuery spend; fails above the limit (step 9).
COST = LOAD.replace("/sql/load.sql", "/sql/cost.sql")


def alert(context):
    """Runs only when a task has failed for the last time."""
    ti = context["task_instance"]
    print(f"ALERT {ti.dag_id}.{ti.task_id} failed for "
          f"{context['data_interval_start']} after {ti.try_number} tries", flush=True)


COMMON = {"auto_remove": "success", "mount_tmp_dir": False}

# Images from the class registry, tagged with the git commit they were built from (ADR-0006).
# Bump IMAGE_TAG after scripts/release_images.sh.
REGISTRY = "europe-west1-docker.pkg.dev/data-engineering-i2/dataeng"
IMAGE_TAG = "4219782"
INGESTION_IMAGE = f"{REGISTRY}/group2-ingestion:{IMAGE_TAG}"
DBT_IMAGE = f"{REGISTRY}/group2-dbt:{IMAGE_TAG}"

with DAG(
    dag_id="marketplace_daily_group2",
    schedule="@daily",
    start_date=pendulum.datetime(2026, 11, 1, tz="UTC"),
    catchup=False,          # no backfill of past days: the cursor already covers them
    max_active_runs=1,      # two runs at once would read the same cursor
    default_args={
        "retries": 2,
        "retry_delay": pendulum.duration(minutes=1),
        "on_failure_callback": alert,
    },
    tags=["group2", "l07"],
) as dag:

    # New orders since the saved cursor -> bronze/orders_extract.
    # Joins the shop's network to reach the database as "db".
    # The password comes from an Airflow Variable; its name contains "password",
    # so Airflow masks it in the UI and the logs.
    extract_orders = DockerOperator(
        task_id="extract_orders",
        image=INGESTION_IMAGE,
        network_mode="albert-marketplace_default",
        environment={
            **GOOGLE_ENV,
            "PGHOST": "db", "PGPORT": "5432", "PGDATABASE": "marketplace",
            "PGUSER": "postgres", "PGPASSWORD": "{{ var.value.pg_password }}",
        },
        mounts=[gcloud],
        **COMMON,
    )

    # MERGE new orders and order lines into group2_wh (idempotent).
    load_warehouse = DockerOperator(
        task_id="load_warehouse",
        image=DBT_IMAGE,
        entrypoint=["python"],
        command=["-c", LOAD],
        environment=GOOGLE_ENV,
        mounts=[gcloud, load_sql],
        **COMMON,
    )

    # Silver and gold, with the 35 tests. A failed test fails the task.
    dbt_build = DockerOperator(
        task_id="dbt_build",
        image=DBT_IMAGE,
        command="build",
        environment=GOOGLE_ENV,
        mounts=[gcloud],
        **COMMON,
    )

    # Is the newest order recent enough? Fails after 7 days without new data.
    dbt_freshness = DockerOperator(
        task_id="dbt_freshness",
        image=DBT_IMAGE,
        command="source freshness",
        environment=GOOGLE_ENV,
        mounts=[gcloud],
        **COMMON,
    )

    # Our own cost alert. Runs even if an earlier task failed (all_done).
    cost_check = DockerOperator(
        task_id="cost_check",
        image=DBT_IMAGE,
        entrypoint=["python"],
        command=["-c", COST],
        environment=GOOGLE_ENV,
        mounts=[gcloud, cost_sql],
        trigger_rule="all_done",
        **COMMON,
    )

    extract_orders >> load_warehouse >> dbt_build >> dbt_freshness >> cost_check
