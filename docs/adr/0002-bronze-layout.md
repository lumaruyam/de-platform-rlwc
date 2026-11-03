# ADR-0002: Store bronze as Parquet files, partitioned by day

- **Status:** proposed
- **Date:** 2026-10-20
- **Author:** Rania Mehria
- **Lesson:** L02

## Context

Bronze is the first layer of the lakehouse chosen in [ADR-0001](0001-target-architecture.md). It lives in the bucket `gs://data-engineering-i2-group2` (region `europe-west1`, storage class Standard, public access prevented). Bronze keeps the export exactly as it arrived: no cleaning, no deduplication, no dropped columns.

Three pipelines will write into this layout from L03, so we need to fix three things now: the file format, the compression, and the partition key.

What we know about how the data is read:
- The ML team needs units sold per product, per country, **per day**.
- Analysts ask questions over date ranges (a month, a year).
- Volumes are small today: one month of `order_items` is 9,893 rows.

All figures below come from our own measurements in L02 exercise 1 (Rania Mehria, October 2026), on `order_items`, month of August 2026.

## Options considered

| Option | For | Against |
|---|---|---|
| **CSV, not partitioned** | Simple; opens in any tool. | 10,373,925 bytes for `order_items`, 2.9x larger than Parquet. No types: every column is text. A query must read every column. |
| **Parquet, partitioned by day (`dt`)** (chosen) | 2.9x smaller than CSV. Types are kept. 31 objects for a month. A date filter reads only the days it needs. Same grain as the ML team's table. |    Files are very small today: about 12 KB per day (372,214 bytes for August 2026 / 31 days). |
| **Parquet, partitioned by day and product (`dt` + `p_id`)** | Could help a query that filters on one product. | 8,649 objects for one month instead of 31 (279x). About 85x more bytes stored. The same query took 373 ms instead of 87 ms (about 4x slower). |
| **Parquet, not partitioned** | One file per table, the largest possible files. | Every query reads the whole table, even for one day. |

## Criteria

| Criterion | What we measured | Winner |
|---|---|---|
| **Storage size** | CSV 10,373,925 bytes vs Parquet (Snappy) 3,546,854 bytes: 2.9x smaller | Parquet |
| **Number of objects** | One month: 31 (`dt`) vs 8,649 (`dt` + `p_id`) | `dt` |
| **Query time** | Same query: 87 ms (`dt`) vs 373 ms (`dt` + `p_id`) | `dt` |
| **Cost** | Writing the 8,680 objects of step 7 cost about $0.043. Storing all our data (0.068 GiB) costs about $0.0014 per month. Writes cost about 30x more than a month of storage. With small files, you pay for operations, not for bytes. | Fewer objects: `dt` |
| **Fit with how data is read** | ML table is per day; analysts filter on date ranges; nobody filters on one product only. | `dt` |

Bytes processed showed 0 for both layouts (external tables), so we could not compare query cost on that number. The difference is in storage, number of objects and time.

Prices used: Cloud Storage Standard, $0.020 per GiB per month; write operations, $0.005 per 1,000. Read in October 2026.

## Decision

Bronze tables are stored as **Parquet files with Snappy compression**, in `gs://data-engineering-i2-group2/bronze/<table>/dt=YYYY-MM-DD/`.

- **Tables with a date** (orders, order lines, payments) are partitioned by day, on the order date.
- **Small reference tables** (products, customers, categories) are **not partitioned**: one folder per table. Our rule: only partition on a column that queries filter on, and only if each partition still holds enough rows to be worth opening as a file.

We did not compare compression codecs; Snappy is the default and was the only one measured.

## Consequences

**What becomes easier**
- A query on a date range opens only the days it needs.
- The ML team's daily table reads exactly one partition per day.
- Few objects, so low operation costs and fast listing.

**What becomes harder**
- A query on one product over a long period still opens every day in that period.
- A late row for a past day means rewriting that day's partition.
- Bronze does not have one shape: dated tables are partitioned, reference tables are not. The data dictionary must say which is which.

**What we will have to watch, and what would make us change**
- **File size.**    Today a daily partition is about 12 KB (372,214 bytes for one month / 31 days; the 3,546,854 bytes measured in step 2 are the whole history, not one month), which is far below "keep files large". If daily files stay under about 1 MB once the pipelines run, we will move to **monthly partitions** (`month=YYYY-MM`) and write a new ADR that supersedes this one.
- **Query patterns.** If most queries start to filter on product or seller, the partition key must be reviewed.
- **Personal data.** The export contains names, addresses and phone numbers. The data dictionary marks them, and L03 decides what must never be ingested.