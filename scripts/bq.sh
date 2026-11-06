#!/usr/bin/env bash
# Run one SQL statement in BigQuery from the dbt image (no gcloud CLI session needed).
# Usage: scripts/bq.sh "SELECT ..."
REG="europe-west1-docker.pkg.dev/data-engineering-i2/dataeng"; TAG="${IMAGE_TAG:-4219782}"
docker run --rm -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/adc.json \
  -v "$HOME/.config/gcloud/application_default_credentials.json:/tmp/adc.json:ro" \
  --entrypoint python "$REG/group2-dbt:$TAG" -c "
import sys
from google.cloud import bigquery
c = bigquery.Client(project='data-engineering-i2', location='europe-west1')
for r in c.query(sys.argv[1]).result(): print(dict(r))" "$1"
