"""One-off repair (2026-11-06) of bronze/orders_extract files written before the type fix.

Before the fix, pandas stored ids with empty values as FLOAT in some files and INT in
others, so BigQuery could not read the folder as one table. This rewrites only the
FLOAT files with nullable Int64. Values and row counts do not change. The bucket keeps
the old versions for 7 days (soft delete).
"""
from concurrent.futures import ThreadPoolExecutor

import fsspec
import pandas as pd

ROOT = "data-engineering-i2-group2/bronze/orders_extract"
IDS = ["order_id", "discount_id", "payment_id"]
fs = fsspec.filesystem("gs")


def fix(path):
    with fs.open(path, "rb") as f:
        df = pd.read_parquet(f)
    rows = len(df)
    if all(pd.api.types.is_integer_dtype(df[c]) for c in IDS):
        return rows, 0
    for c in IDS:
        df[c] = df[c].astype("Int64")
    with fs.open(path, "wb") as f:
        df.to_parquet(f, index=False)
    return rows, 1


files = fs.glob(f"{ROOT}/dt=*/*.parquet")
with ThreadPoolExecutor(16) as pool:
    results = list(pool.map(fix, files))
print(f"{len(files)} files, {sum(r for r, _ in results)} rows, "
      f"{sum(x for _, x in results)} files rewritten")
