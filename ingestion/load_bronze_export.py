"""Load the legacy CSV export into bronze, as described in ADR-0002.

This is how bronze was filled on 2026-11-03 (L02, project step 2).

- Only the 7 tables the project needs (customer and payment_details are left out:
  they hold passwords and card numbers).
- Every column is read as text, exactly as in the file: no cleaning, no
  deduplication, no dropped columns. Types are decided in silver.
- Parquet with Snappy compression.
- orders and order_items: one folder per day (dt = order_date).
- The other tables: one folder each, not partitioned.

How to run it again (Cloud Shell, project data-engineering-i2):

    curl -L -o legacy_csv.tar.gz https://github.com/TangoAI-AlbertSchool-Data-Eng-Cloud/albert-marketplace/releases/download/v1.0.0/legacy_csv.tar.gz
    tar -xzf legacy_csv.tar.gz
    pip install --user pandas pyarrow
    ulimit -n 4096 && python3 load_bronze_export.py
    gcloud storage cp -r out/bronze gs://data-engineering-i2-group2/

Why ulimit and max_open_files: 1,096 daily partitions means about 1,100 files
open at once. Cloud Shell allows 1,024 ("Too many open files"), and pyarrow
closes files above 1,024 by default, which split days into several small files
(3,926 files instead of 2,197 on the first run).

Result on 2026-11-03: 2,197 files, 93,546,467 bytes.
"""
import pathlib
import shutil

import pandas as pd

SRC = pathlib.Path("legacy_csv")
OUT = pathlib.Path("out/bronze")

DATED = ["orders", "order_items"]
REFERENCE = ["review", "product_reviews", "product", "customer_shipping", "shipping_details"]


def read(table):
    # dtype=str and keep_default_na=False: keep every value as written
    # (leading zeros in p_id and phone, empty cells stay empty).
    return pd.read_csv(SRC / f"{table}.csv", dtype=str, keep_default_na=False)


if OUT.exists():
    shutil.rmtree(OUT)
OUT.mkdir(parents=True)

orders = read("orders")
orders["dt"] = orders["order_date"].str[:10]
order_dates = orders[["order_id", "dt"]].drop_duplicates("order_id")

items = read("order_items")
items_dt = items.merge(order_dates, on="order_id", how="left")
items_dt["dt"] = items_dt["dt"].replace("", None).fillna("unknown")

for table, df, source_rows in [("orders", orders, len(orders)), ("order_items", items_dt, len(items))]:
    assert len(df) == source_rows, f"{table}: row count changed"
    df.to_parquet(OUT / table, partition_cols=["dt"], compression="snappy",
                  index=False, max_partitions=2000, max_open_files=2000,
                  basename_template="part-{i}.parquet")
    days = df["dt"].nunique()
    print(f"{table:18} {len(df):>8,} rows  {days:>5} days")

for table in REFERENCE:
    df = read(table)
    (OUT / table).mkdir()
    df.to_parquet(OUT / table / "part-0.parquet", compression="snappy", index=False)
    print(f"{table:18} {len(df):>8,} rows  not partitioned")

print("done:", OUT)