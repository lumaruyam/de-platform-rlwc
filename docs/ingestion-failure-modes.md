# Ingestion failure modes

What each path into bronze does when something goes wrong. "Tested" means we caused it on purpose on 2026-11-03 and watched what happened.

Paths:
- **Extractor**: `ingestion/extract_orders.py`, table `orders`, cursor `order_id`. At-least-once.
- **Consumer**: `ingestion/consume_clickstream.py`, Kafka topic `clickstream`. At-least-once.
- **Connector**: Airbyte, 7 tables. Added after its first sync.

## Extractor (orders)

| Failure | Handled? | By what | What happens if it occurs |
|---|---|---|---|
| New rows | Yes | Cursor `order_id > last value`, saved in the bucket (`_state/`) | Only new orders are read. Tested: 71 new orders on the second run, 1 day touched. |
| Updates | **No** | Nothing: the cursor only moves forward on new `order_id` values | Bronze keeps the old version, with no warning. Tested: order 1 changed in the database was not read again. Change data capture would see it. |
| Deletes | **No** | Nothing | A deleted order stays in bronze forever. Revenue can count an order that no longer exists. |
| Source is down | Yes | 5 tries, waiting 2, 4, 8 then 16 s, then exit with an error | Tested: database stopped, the script gave up after about 30 s. The cursor did not move, so the next run reads the same rows. Nothing lost. |
| Malformed row | Partly | PostgreSQL types every column, so a row cannot be malformed on arrival | A bad value (for example a date in the future) is written to bronze as it is. Silver must catch it. |
| Schema change | Partly | The `SELECT` names its columns | A new column is ignored, silently. A removed or renamed column makes the query fail: the script stops, the cursor does not move, nothing is lost. |
| Duplicate after a restart | Yes, by design | Files are written first, the cursor is saved after | A crash between the two re-reads the same orders on the next run: duplicates, never loss. Removed in silver on `order_id`. Not tested by killing the script. |
| Credential expires | Partly | Database password from `.env`; bucket access from Application Default Credentials (ADC) | If the database password changes, the connection fails and the script gives up after 5 tries. If the ADC token cannot be refreshed, the write fails before the cursor moves: nothing lost, but nothing loaded until someone logs in again. |

Also seen: `order_id` values have gaps (244,215 orders up to `order_id` 244,226). An order that fails at checkout uses a number and rolls back. The cursor is not affected.

## Consumer (clickstream)

| Failure | Handled? | By what | What happens if it occurs |
|---|---|---|---|
| New rows | Yes | Kafka consumer group `clickstream-group2` keeps our position | Each run starts where the last one stopped. Tested: 113 new events on a rerun. |
| Updates | Not applicable | Events are never changed after they are sent | |
| Deletes | Not applicable | Events are never deleted by the source | A customer asking to be forgotten is handled in L10, not here. |
| Source is down | Partly | The Kafka client keeps trying to reconnect | The run writes nothing and stops after 5 minutes. Events wait in Kafka, so the next run reads them. Not tested. |
| Malformed row | Yes | JSON Schema check, then `bronze/_dlq/clickstream/` | Tested: 2 broken events sent on purpose (not JSON, missing `buyer_id`). Both are in the dead letter queue with the reason, partition and offset. The stream kept running: 104 good events before, 9 after. |
| Schema change | Yes | The schema is chosen by `schema_version` | An event with an unknown `schema_version` goes to the dead letter queue, never into bronze. Supporting a new version means adding its schema to the consumer. |
| Duplicate after a restart | Yes, by design | Files are written first, the Kafka offset is committed after | A crash between the two replays the last batch: duplicates, never loss. Removed in silver on `event_id`. |
| Credential expires | Partly | Bucket access from ADC; Kafka has no password on this setup | If the ADC token cannot be refreshed, the write fails before the commit: events stay in Kafka and are read again later. |
| Consumer stopped longer than Kafka keeps messages | **No** | Nothing | Kafka keeps messages one week or 256 MB per partition. Older events are deleted before anyone reads them, with no warning. Seen: our first read started at offset about 90,000 on each partition, so about 270,000 older events had already expired. Airflow must run the consumer often enough (L07). |

## Where the credentials live

| Credential | Where | Who can read it | In the repository? |
|---|---|---|---|
| Database password | `.env` at the repository root, on the laptop that runs the job | Whoever uses that laptop | No: `.env` is in `.gitignore`. `.env.example` lists the variable names with empty values. |
| Bucket access | Application Default Credentials, in the user's home folder (`~/.config/gcloud/`), created with `gcloud auth application-default login` | Whoever uses that laptop | No: outside the repository. |
| Kafka | No credential: the broker runs locally without authentication | Anyone on the laptop | Not applicable |

Known gap: these are a person's credentials on a person's laptop, not a service account. When the jobs move to Airflow (L07), they need a service account with access to this bucket only, and the database password in Airflow's own secret store.

Seen on 2026-11-03: deleting files with `gcloud` asked for the account password again ("Reauthentication required"). A human credential can stop working at any time; a scheduled job cannot rely on one.