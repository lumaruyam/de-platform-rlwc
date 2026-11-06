# Reproduce from a clean environment

Step 6. Proof that the jobs run from the registry, with nothing from our laptops.

## Steps

```bash
REG=europe-west1-docker.pkg.dev/data-engineering-i2/dataeng; TAG=4219782
gcloud auth application-default login            # once, your own Google account
gcloud auth application-default print-access-token \
  | docker login -u oauth2accesstoken --password-stdin https://europe-west1-docker.pkg.dev
docker pull $REG/group2-ingestion:$TAG
docker pull $REG/group2-dbt:$TAG
docker run --rm --entrypoint python $REG/group2-ingestion:$TAG \
  -c "import pandas, gcsfs, psycopg, confluent_kafka, jsonschema; print('ingestion image: imports OK')"
docker run --rm -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/adc.json:ro" \
  $REG/group2-dbt:$TAG build
```

## Evidence (2026-11-06T18:42Z)

| Check | Result |
|---|---|
| Local `group2` images before pulling | 0 (all deleted with `docker rmi`) |
| Pull `group2-ingestion:4219782`, `group2-dbt:4219782` | both pulled from `dataeng` |
| Ingestion image imports its libraries | `ingestion image: imports OK` |
| `dbt build` from the pulled image | `Done. PASS=57 WARN=1 ERROR=0 SKIP=0 TOTAL=58` |

The warning is `assert_no_future_orders`, expected (`docs/orchestration.md`).
The only thing taken from the laptop is the reader's own Google login, mounted read-only.
