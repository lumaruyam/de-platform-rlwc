# Packaging data jobs (Docker)

Step 6. Two images, one per job family. Both tested on 2026-11-06.

| Image | Dockerfile | What it runs | Size (content) |
|---|---|---|---|
| `group2-ingestion:0.1` | `ingestion/Dockerfile` | `extract_orders.py` (default) or `consume_clickstream.py` | 178 MB |
| `group2-dbt:0.1` | `dbt/Dockerfile` | `dbt build` (default) or any dbt command | 276 MB |

## Rules applied (from the naive to the clean Dockerfile)

| Naive | Ours | Why |
|---|---|---|
| `FROM python:3.12` | `FROM python:3.13.7-slim-bookworm` | Exact version: the same build tomorrow. Slim: much smaller image |
| `COPY . /app` first | `requirements.txt` first, code after | Dependencies stay cached when only the code changes |
| `pip install` | `pip install --no-cache-dir` | No pip cache inside the image |
| Runs as root | Runs as uid 10001 (`ingest`, `dbt`) | A compromised container is not root |
| Whole folder copied | Only the job files, plus `.dockerignore` | No `.env`, no credentials, no build output in the image |

Versions are pinned in `ingestion/requirements.txt` and `dbt/requirements.txt`.
The dbt image fetches `dbt_utils` at build time (`dbt deps`), so a run only needs BigQuery.

## No secret in the image

Secrets are given at run time, never baked in:

- Database: `--env-file .env` (`PGHOST`, `PGUSER`, `PGPASSWORD`...), with `PGHOST=host.docker.internal`
  because `localhost` inside a container is the container itself.
- Google Cloud: the runner's Application Default Credentials, mounted read-only.

## How to run

```bash
docker build -t group2-ingestion:0.1 ingestion/
docker run --rm --env-file .env -e PGHOST=host.docker.internal \
  -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json -e GOOGLE_CLOUD_PROJECT=data-engineering-i2 \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/adc.json:ro" \
  group2-ingestion:0.1

docker build -t group2-dbt:0.1 dbt/
docker run --rm -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/adc.json:ro" \
  group2-dbt:0.1 build
```

## First runs (2026-11-06)

- Ingestion: cursor `order_id > 244303`, wrote 383 rows over 2 days to `bronze/orders_extract`,
  cursor saved at 244687.
- dbt: `PASS=50 WARN=0 ERROR=0` in 15 s, same result as outside Docker.

## Problems met

- `dbt deps` failed as the non-root user: `WORKDIR` creates `/app` as root, and
  `COPY --chown` only changes the copied files. Fix: `chown dbt /app` when creating the user.
- Outside Docker, dbt had picked a pre-release (1.13.0-rc1) and an extra module (dbt State)
  that tried to open a browser login. The image pins 1.12.6 and installs nothing else:
  this is the problem packaging solves.

## Limits

- The Google credentials are a person's own login. In production the job would run as a
  service account with only the rights it needs (step 10).
- Images are built on a laptop and not pushed to a registry yet.