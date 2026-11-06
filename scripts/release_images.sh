#!/usr/bin/env bash
# Build and push both job images, tagged with the current git commit (ADR-0006).
# Refuses: a dirty working tree (the tag would lie about the code), the tag "latest",
# and a tag that already exists in the registry (tags are immutable by our convention,
# because the class registry does not enforce it).
set -euo pipefail
REG="europe-west1-docker.pkg.dev/data-engineering-i2/dataeng"
TAG="${1:-$(git rev-parse --short HEAD)}"

[ "$TAG" = "latest" ] && { echo "refused: never tag latest"; exit 1; }
[ -n "$(git status --porcelain -- ingestion dbt)" ] && { echo "refused: uncommitted changes in ingestion/ or dbt/"; exit 1; }

gcloud auth application-default print-access-token \
  | docker login -u oauth2accesstoken --password-stdin https://europe-west1-docker.pkg.dev >/dev/null

for job in ingestion dbt; do
  image="$REG/group2-$job:$TAG"
  if docker manifest inspect "$image" >/dev/null 2>&1; then
    echo "refused: $image already exists (tags are immutable)"; exit 1
  fi
  docker build -q -t "$image" "$job/" >/dev/null
  docker push -q "$image"
done
echo "released $TAG"
