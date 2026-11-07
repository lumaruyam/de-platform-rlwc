"""Incremental extractor for the orders table, written by hand (L03).

Plain SQL through a database driver (psycopg 3). No ORM, no framework.

What it does, each run:
1. reads the cursor: the highest order_id already extracted;
2. selects only the orders with order_id > cursor (strictly greater:
   order_id never repeats, so the boundary row is not read twice);
3. writes them as Parquet into bronze, one folder per order_date;
4. only then saves the new cursor.

Step 3 before step 4, on purpose: a crash between the two means the next
run reads the same rows again (at-least-once, duplicates possible). The
other order would lose them silently (at-most-once).

What it cannot see: an order that is updated or deleted after it was
extracted. The cursor only moves forward on new order_id values.

Configuration, all from the environment (never in this file):
  PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD  read by psycopg itself
  OUT    where to write  (default: the group bucket, bronze/orders_extract)
  STATE  where the cursor lives (default: the group bucket, _state/...)
  BATCH  rows per run, at most (default 50000)
"""
import json
import os
import sys
import time
from datetime import datetime, timezone

import fsspec
import pandas as pd
import psycopg

BUCKET = "gs://data-engineering-i2-group2"
OUT = os.environ.get("OUT", f"{BUCKET}/bronze/orders_extract")
STATE = os.environ.get("STATE", f"{BUCKET}/_state/orders_extract_cursor.json")
BATCH = int(os.environ.get("BATCH", "50000"))

MAX_TRIES = 5          # give up after this many failed connections
FIRST_WAIT = 2         # seconds; doubles after each failure: 2, 4, 8, 16

SQL = """
    SELECT order_id, buyer_id, discount_id, payment_id, order_date
    FROM orders
    WHERE order_id > %(cursor)s
    ORDER BY order_id
    LIMIT %(batch)s
"""


def read_cursor():
    """The last order_id extracted. 0 the first time."""
    try:
        with fsspec.open(STATE, "r") as f:
            return int(json.load(f)["last_order_id"])
    except FileNotFoundError:
        return 0


def save_cursor(value):
    with fsspec.open(STATE, "w") as f:
        json.dump({"last_order_id": int(value),
                   "saved_at": datetime.now(timezone.utc).isoformat()}, f)


def connect():
    """Connect, retrying with a growing delay, then give up."""
    wait = FIRST_WAIT
    for attempt in range(1, MAX_TRIES + 1):
        try:
            return psycopg.connect(connect_timeout=5)
        except psycopg.OperationalError as exc:
            print(f"connection failed (try {attempt}/{MAX_TRIES}): {exc}".strip())
            if attempt == MAX_TRIES:
                print("giving up")
                sys.exit(1)
            print(f"retrying in {wait}s")
            time.sleep(wait)
            wait *= 2


def main():
    cursor_value = read_cursor()
    print(f"cursor: order_id > {cursor_value}")

    with connect() as conn, conn.cursor() as cur:
        cur.execute(SQL, {"cursor": cursor_value, "batch": BATCH})
        rows = cur.fetchall()
        columns = [c.name for c in cur.description]

    if not rows:
        print("no new orders")
        return

    df = pd.DataFrame(rows, columns=columns)
    df["dt"] = pd.to_datetime(df["order_date"]).dt.strftime("%Y-%m-%d")

    # A timestamp in the file name, so two runs never overwrite each other.
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    for dt, part in df.groupby("dt"):
        path = f"{OUT}/dt={dt}/part-{stamp}.parquet"
        with fsspec.open(path, "wb") as f:
            part.drop(columns=["dt"]).to_parquet(f, index=False)
    print(f"wrote {len(df)} rows over {df['dt'].nunique()} day(s) to {OUT}")

    # Only now: the files are written, so the cursor can move.
    save_cursor(df["order_id"].max())
    print(f"cursor saved: order_id > {df['order_id'].max()}")


if __name__ == "__main__":
    main()