"""Read clickstream events from Kafka and write them to bronze as partitioned Parquet.

Delivery guarantee: at-least-once. Each batch is written to the bucket first,
and the Kafka offset is committed only after the write succeeds, so a crash
between the two re-reads that batch on restart: events can be duplicated,
never lost. Duplicates are removed in silver on event_id.

Partitioned by event_time (when it happened), not emitted_at (when it was
sent): a late event lands in the day it belongs to, so a day's partition is
the day's activity, which is what the ML team counts.

Every event is checked against ingestion/clickstream.schema.json, chosen by
its schema_version. An event that fails goes to bronze/_dlq/clickstream/ with
the raw message, the reason and where it came from. It is never dropped, and
it never stops the stream.

Configuration, all from the environment:
  KAFKA_BOOTSTRAP   default localhost:9092
  KAFKA_TOPIC       default clickstream
  CONSUMER_GROUP    required, e.g. clickstream-group2 (where Kafka keeps our offsets)
  OUT, DLQ          default: the group bucket
  BATCH             events per file at most, default 5000
  FLUSH_EVERY       write at least every this many seconds, default 60
  MAX_RUNTIME       stop after this many seconds, default 300 (0 = never)
  MAX_IDLE          stop after this many quiet seconds, default 30 (0 = never)

Why FLUSH_EVERY and not "write whenever the topic is quiet": the live traffic
pauses for a second every few seconds, and writing on every pause produced a
file every 2 to 10 seconds with 1 to 12 rows in it (first run, 2026-11-03).
"""
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import fsspec
import jsonschema
import pandas as pd
from confluent_kafka import Consumer

BUCKET = "gs://data-engineering-i2-group2"
BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP", "localhost:9092")
TOPIC = os.environ.get("KAFKA_TOPIC", "clickstream")
GROUP = os.environ["CONSUMER_GROUP"]  # no default: the group IS our progress
OUT = os.environ.get("OUT", f"{BUCKET}/bronze/clickstream")
DLQ = os.environ.get("DLQ", f"{BUCKET}/bronze/_dlq/clickstream")
BATCH = int(os.environ.get("BATCH", "5000"))
FLUSH_EVERY = float(os.environ.get("FLUSH_EVERY", "60"))
MAX_RUNTIME = float(os.environ.get("MAX_RUNTIME", "300"))
MAX_IDLE = float(os.environ.get("MAX_IDLE", "30"))

SCHEMA_FILE = Path(__file__).with_name("clickstream.schema.json")
SCHEMAS = {1: json.loads(SCHEMA_FILE.read_text())}  # schema_version -> schema
VALIDATORS = {v: jsonschema.Draft202012Validator(s) for v, s in SCHEMAS.items()}


def check(raw):
    """Return the event if it is valid, or raise ValueError with the reason."""
    event = json.loads(raw)  # not JSON at all -> ValueError
    if not isinstance(event, dict):
        raise ValueError("not a JSON object")
    version = event.get("schema_version")
    if version not in VALIDATORS:
        raise ValueError(f"unknown schema_version: {version!r}")
    errors = sorted(VALIDATORS[version].iter_errors(event), key=str)
    if errors:
        raise ValueError("; ".join(e.message for e in errors[:3]))
    return event


def write(rows, root, time_field):
    """One Parquet file per day under dt=YYYY-MM-DD/, never overwriting."""
    df = pd.DataFrame(rows)
    if "items" in df:
        # basket lines stay as their JSON text: same column type in every file
        df["items"] = df["items"].map(lambda x: json.dumps(x) if isinstance(x, list) else None)
    df["dt"] = pd.to_datetime(df[time_field], utc=True, format="ISO8601").dt.strftime("%Y-%m-%d")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    for dt, part in df.groupby("dt"):
        path = f"{root}/dt={dt}/part-{stamp}.parquet"
        with fsspec.open(path, "wb") as f:
            part.drop(columns=["dt"]).to_parquet(f, index=False)
        print(f"  wrote {len(part):4d} rows  {path}")


def main():
    consumer = Consumer({
        "bootstrap.servers": BOOTSTRAP,
        "group.id": GROUP,
        "auto.offset.reset": "earliest",  # a new group starts from the beginning
        "enable.auto.commit": False,      # committed by hand, after the write
    })
    consumer.subscribe([TOPIC])
    print(f"reading {TOPIC} from {BOOTSTRAP} as group {GROUP}")

    good, bad = [], []
    total_good = total_bad = 0
    started = last_flush = quiet_since = time.monotonic()

    def flush():
        nonlocal good, bad, total_good, total_bad, last_flush
        last_flush = time.monotonic()
        if not good and not bad:
            return
        if good:
            write(good, OUT, "event_time")
        if bad:
            write(bad, DLQ, "received_at")
            print(f"  {len(bad)} event(s) sent to the dead letter queue")
        # Only now, after the files exist: a crash above means a replay, not a loss.
        consumer.commit(asynchronous=False)
        total_good += len(good)
        total_bad += len(bad)
        good, bad = [], []

    try:
        while True:
            now = time.monotonic()
            if MAX_RUNTIME and now - started > MAX_RUNTIME:
                print(f"ran for {MAX_RUNTIME:.0f}s, stopping")
                break
            if now - last_flush >= FLUSH_EVERY:
                flush()
            msg = consumer.poll(1.0)
            if msg is None:
                if MAX_IDLE and time.monotonic() - quiet_since > MAX_IDLE:
                    print(f"quiet for {MAX_IDLE:.0f}s, stopping")
                    break
                continue
            if msg.error():
                print(f"  kafka error: {msg.error()}")
                continue
            quiet_since = time.monotonic()
            raw = msg.value().decode("utf-8", errors="replace")
            try:
                good.append(check(raw))
            except Exception as exc:  # malformed: quarantine, never drop
                bad.append({"raw": raw, "reason": str(exc),
                            "received_at": datetime.now(timezone.utc).isoformat(),
                            "topic": msg.topic(), "partition": msg.partition(),
                            "offset": msg.offset()})
            if len(good) + len(bad) >= BATCH:
                flush()
    except KeyboardInterrupt:
        print("stopped by hand")
    finally:
        flush()
        consumer.close()
        print(f"done: {total_good} events written, {total_bad} sent to the dead letter queue")


if __name__ == "__main__":
    main()