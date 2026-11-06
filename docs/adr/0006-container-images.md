# ADR-0006: Package each job family in its own pinned, non-root image with no secret inside

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L06

## Context

Our jobs ran from one Python environment on a laptop. On 2026-11-06 this broke twice:

- `pip install dbt-bigquery` picked a pre-release (dbt 1.13.0-rc1) and an extra module that opened a
  browser login in the middle of `dbt build`.
- The same install downgraded `google-cloud-storage`, and `gcsfs` (used by the ingestion jobs) stopped
  importing.

A job must run the same way on any machine, and in Airflow (L07).

## Options considered

1. **Keep one shared virtual environment**, with a `requirements.txt`.
2. **One image for all jobs.**
3. **One image per job family:** ingestion (`group2-ingestion`) and dbt (`group2-dbt`).

## Criteria

| Criterion | 1. Shared venv | 2. One image | 3. One image per family |
|---|---|---|---|
| Same result on another machine | No | Yes | Yes |
| dbt and ingestion libraries can conflict | Yes (it happened) | Yes | No |
| Image size | - | Largest | 178 MB and 276 MB |
| Rebuild when one job changes | - | Everything | That family only |

## Decision

Option 3. Both Dockerfiles follow the same rules, measured against the naive version from the course:

| Rule | Why |
|---|---|
| `python:3.13.7-slim-bookworm`, exact versions in `requirements.txt` | Same build tomorrow; slim is much smaller |
| `requirements.txt` copied before the code | Dependency layer stays cached when only code changes |
| `pip install --no-cache-dir` | No pip cache in the image |
| Runs as uid 10001 (`ingest`, `dbt`) | A compromised container is not root |
| `.dockerignore` excludes `.env` | No credentials in the image |

Secrets come at run time: `--env-file .env` for the database, the Google credentials file mounted read-only.

## Consequences

- Tested: the extractor ran in its container (383 new orders, cursor 244303 -> 244687);
  `dbt build` in its container gave PASS=50, as outside Docker.
- The dbt project is copied into the image: adding a model or a test needs a rebuild (a few
  seconds thanks to the cache).
- Non-root has a cost: `dbt deps` failed until `/app` was given to the `dbt` user.
- Images are built on a laptop and not pushed to a registry yet.
- The credentials inside are a person's login, not a service account (ADR-0010).
