# dbt runner: builds silver and gold in BigQuery.
# Usage: docker run ... group2-dbt:0.1 build   (or: source freshness, test, docs generate)
FROM python:3.13.7-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DBT_PROFILES_DIR=/app \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false

WORKDIR /app

# Dependencies first: cached while only models change.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home --uid 10001 dbt && chown dbt /app

# The project. Packages are fetched at build time, so a run needs no network but BigQuery.
COPY --chown=dbt . ./
USER dbt
RUN dbt deps

ENTRYPOINT ["dbt"]
CMD ["build"]
