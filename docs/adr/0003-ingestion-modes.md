# ADR-0003: Stream the clickstream, batch the database, no change data capture yet

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L03

## Context

Bronze was filled once, by hand, in L02. It now needs paths that run without a person. There are two sources:

- **The shop's PostgreSQL database.** We need 7 tables (`orders`, `order_items`, `review`, `product_reviews`, `product`, `customer_shipping`, `shipping_details`). It is the shop's production database: reading it must stay light.
- **The clickstream**, in the Kafka topic `clickstream`. Events exist only there, and Kafka deletes them after one week or 256 MB per partition.

What the users need (see [architecture.md](../architecture.md)): daily freshness is enough. Nothing needs real-time data.

## Options considered

| Source | Option | For | Against |
|---|---|---|---|
| Clickstream | **Streaming consumer** (chosen) | The only way to read Kafka. Our position is kept by the consumer group, so each run continues where the last stopped. | Must run at least once a week, or events expire unread. |
| `orders` | **Incremental batch, cursor `order_id`** (chosen) | Reads only new orders: 71 rows on a normal run, instead of 244,215. Light on the shop's database. | Does not see updates or deletes. |
| `orders` | Change data capture (rejected) | Sees inserts, updates and deletes, from the database log. | The database keeps its log until a reader confirms it. If our reader stops, the shop's disk fills up. More to run and to watch. |
| `orders` | Full reload every day (rejected) | Sees everything, deletes included. | Reads 244,215 rows from the shop's database every day to find about 200 new ones. |
| 5 reference tables | **Full refresh with the connector** (chosen) | Small tables (42,858 to 200,001 rows): a full read is cheap and also catches updates and deletes. | Each sync rewrites the whole table. |

## Criteria

| Criterion | What we measured (2026-11-03) |
|---|---|
| New orders | Cursor run after the first load: 71 new orders, 1 day touched |
| Updates | Order 1 changed in the database: not read again by the cursor |
| Source down | 5 tries (2, 4, 8, 16 s), then the script gives up; cursor unchanged, nothing lost |
| Malformed event | 2 broken events sent on purpose: both in `bronze/_dlq/clickstream/`, stream kept running |
| Kafka retention | Our first read started at offset about 90,000 per partition: about 270,000 older events had already expired |
| Duplicates | Both paths write first and save their position after: a crash replays, never loses |

## Decision

- **Clickstream:** streaming, with `ingestion/consume_clickstream.py`. Partitioned by `event_time`. At-least-once. Run at least daily.
- **`orders`:** incremental batch, with `ingestion/extract_orders.py`, cursor `order_id`. At-least-once.
- **The 7 tables:** batch, with Airbyte. Full refresh for the 5 reference tables; incremental append on `order_id` for `orders` and `order_items`. `pwd`, `card_no` and `cvv` are deselected in the connection.
- **No change data capture** for now.

## Consequences

**What we commit to**
- Every path is at-least-once. Duplicates are expected and removed in silver: on `order_id` for orders, on `event_id` for events.
- The consumer must run at least once a week, or events are lost with no warning.

**What we accept**
- Updates and deletes on `orders` are not seen. An order cancelled after extraction stays in bronze, and could be counted in revenue.

**What would make us change**
- If revenue must reflect cancellations and corrections, `orders` moves to change data capture, with an alert on how much log the database keeps.
- If the reference tables grow to millions of rows, full refresh becomes too heavy: they move to incremental.