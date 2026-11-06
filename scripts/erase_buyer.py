"""Erase one buyer everywhere we hold their data (step 10, docs/runbooks/erasure.md).

Usage (inside the ingestion image, which has pyarrow, gcsfs and google-cloud-bigquery):
    python erase_buyer.py <buyer_id>            # dry run: count only
    python erase_buyer.py <buyer_id> --apply    # erase

What happens to the buyer's data:
  orders, order lines  kept (revenue must not change), buyer_id set to NULL
  reviews              kept (ratings feed product scores), buyer_id, text and title set to NULL
  addresses            deleted (customer_shipping rows and their shipping_details rows)
  clickstream events   buyer_id and session_id set to NULL
Covered: every Parquet file under bronze/ (rewritten in place) and the group2_wh tables.
Silver and gold are rebuilt from group2_wh by dbt. Not covered: the shop database (the shop's
duty), old object versions (kept up to 30 days by versioning) and soft-deleted objects (7 days).
"""
import sys
from concurrent.futures import ThreadPoolExecutor

import gcsfs
import pyarrow as pa
import pyarrow.compute as pc
import pyarrow.parquet as pq
from google.cloud import bigquery

BUYER = sys.argv[1]
APPLY = "--apply" in sys.argv
BUCKET = "data-engineering-i2-group2"
fs = gcsfs.GCSFileSystem()
bq = bigquery.Client(project="data-engineering-i2", location="europe-west1")
WH = "data-engineering-i2.group2_wh"


def q(sql, **params):
    cfg = bigquery.QueryJobConfig(query_parameters=[
        bigquery.ScalarQueryParameter(k, "STRING", v) for k, v in params.items()])
    return list(bq.query(sql, job_config=cfg).result())


# Addresses of the buyer, needed to find their shipping_details rows.
ADDRESSES = sorted({str(r.address_id) for r in q(
    f"SELECT address_id FROM `{WH}.customer_shipping` WHERE c_id = @b", b=BUYER)})


def null_where(table, column, mask, also=()):
    cols = {}
    for name in [column, *also]:
        if name in table.column_names:
            col = table[name]
            cols[name] = pc.if_else(mask, pa.scalar(None, col.type), col)
    for name, col in cols.items():
        table = table.set_column(table.column_names.index(name), name, col)
    return table


def fix_file(path):
    """Return (path, rows touched). Rewrites the file only with --apply."""
    with fs.open(path, "rb") as f:
        table = pq.read_table(f)
    names = table.column_names
    touched = 0
    if "address_id" in names and "street_address" in names:          # shipping_details
        ids = pc.cast(table["address_id"], pa.string())
        mask = pc.is_in(ids, pa.array(ADDRESSES, pa.string())) if ADDRESSES else pc.equal(ids, "")
        touched = pc.sum(mask).as_py() or 0
        table = table.filter(pc.invert(mask))
    elif "c_id" in names and "is_default" in names:                   # customer_shipping
        mask = pc.equal(pc.cast(table["c_id"], pa.string()), BUYER)
        touched = pc.sum(mask).as_py() or 0
        table = table.filter(pc.invert(mask))
    elif "buyer_id" in names:                                         # orders, reviews, clicks
        mask = pc.fill_null(pc.equal(pc.cast(table["buyer_id"], pa.string()), BUYER), False)
        touched = pc.sum(mask).as_py() or 0
        if touched:
            table = null_where(table, "buyer_id", mask, also=("r_desc", "title", "session_id"))
    if touched and APPLY:
        with fs.open(path, "wb") as f:
            pq.write_table(table, f, compression="snappy")
    return path, touched


files = [p for p in fs.find(f"{BUCKET}/bronze") if p.endswith(".parquet")]
with ThreadPoolExecutor(16) as pool:
    hits = [(p, n) for p, n in pool.map(fix_file, files) if n]
print(f"buyer {BUYER}: {len(ADDRESSES)} address(es)")
print(f"bronze: {len(files)} files scanned, {len(hits)} files with {sum(n for _, n in hits)} rows "
      f"{'rewritten' if APPLY else 'to rewrite'}")
for p, n in hits:
    print(f"  {n:3d}  {p.split('/bronze/')[1]}")

WH_COUNT = f"""
SELECT
  (SELECT COUNT(*) FROM `{WH}.orders` WHERE buyer_id = @b) AS wh_orders,
  (SELECT COUNT(*) FROM `{WH}.review` WHERE buyer_id = @b) AS wh_reviews,
  (SELECT COUNT(*) FROM `{WH}.customer_shipping` WHERE c_id = @b) AS wh_addresses
"""
print("group2_wh before:", dict(q(WH_COUNT, b=BUYER)[0]))
if APPLY:
    for sql in [
        f"UPDATE `{WH}.orders` SET buyer_id = NULL WHERE buyer_id = @b",
        f"UPDATE `{WH}.review` SET buyer_id = NULL, r_desc = NULL, title = NULL WHERE buyer_id = @b",
        f"DELETE FROM `{WH}.shipping_details` WHERE address_id IN "
        f"(SELECT address_id FROM `{WH}.customer_shipping` WHERE c_id = @b)",
        f"DELETE FROM `{WH}.customer_shipping` WHERE c_id = @b",
    ]:
        q(sql, b=BUYER)
    print("group2_wh after: ", dict(q(WH_COUNT, b=BUYER)[0]))
