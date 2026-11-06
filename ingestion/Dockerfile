# One image for the ingestion jobs. Default: the orders extractor.
# Clickstream consumer: docker run ... ingestion python consume_clickstream.py
FROM python:3.13.7-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencies first: this layer stays cached when only the code changes.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home --uid 10001 ingest

# Only the job files. No .env, no credentials in the image.
COPY extract_orders.py consume_clickstream.py clickstream.schema.json ./

USER ingest
CMD ["python", "extract_orders.py"]
