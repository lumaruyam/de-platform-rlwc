# Costs

Updated every lesson. Prices in USD.

## Prices used

Read on 2026-11-03 on the [Cloud Storage pricing page](https://cloud.google.com/storage/pricing). The page did not let us select Belgium (`europe-west1`) directly; the values shown match the ones given in the L02 exercise for `europe-west1`.

| Item | Price |
|---|---|
| Standard storage | $0.020 per GiB per month |
| Nearline storage | $0.010 per GiB per month (30 days minimum, $0.01 per GiB read) |
| Coldline storage | $0.004 per GiB per month (90 days minimum, $0.02 per GiB read) |
| Archive storage | $0.0012 per GiB per month (365 days minimum, $0.05 per GiB read) |
| Write operations (Class A) | $0.005 per 1,000 |
| Read and list operations (Class B) | $0.0004 per 1,000 |
| Deletes | free |

## L02: the bronze bucket

What we store: 2,197 files, 93,546,467 bytes = 0.0871 GiB, in `gs://data-engineering-i2-group2/bronze/`.

| Item | How | Cost |
|---|---|---|
| Storage, first month (Standard) | 0.0871 GiB × $0.020 | $0.0017 |
| Writes | 3,926 files (first load) + 2,197 files (reload) = 6,123 × $0.005 / 1,000 | $0.031 |
| Soft delete of the first load | 0.091 GiB kept 7 days × $0.020 × 7/30 | $0.0004 |
| **Total, first month** | | **about $0.033** |

**Writes cost about 18 times more than a month of storage.** With many small files, we pay for operations, not for bytes. The failed first load (3,926 files) cost more than the storage itself.

After the first month, the lifecycle rule ([`infra/lifecycle.json`](../infra/lifecycle.json)) moves bronze down: Nearline after 30 days ($0.0009 per month), Coldline after 90 ($0.0003), Archive after 365 ($0.0001).

## If the data were 100 times larger

About 8.7 GiB: storage would cost about $0.17 per month in Standard, still small. A full load would still write about 2,200 files, so write costs would barely move. Each daily file would grow from about 43 KB to about 4 MB, which is the size ADR-0002 is waiting for: daily partitions would then be fully justified.