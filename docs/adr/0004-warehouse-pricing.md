# ADR-0004: Pay BigQuery on demand, with a 10 MiB cap per query

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L04

## Context

BigQuery bills compute in two ways:

- **On-demand:** pay for the bytes each query reads. $6.25 per TiB,
  first 1 TiB per month free, at least 10 MB billed per table read.
- **Capacity (editions):** rent slots (units of compute) by the hour,
  whether queries run or not. Standard edition: $0.04 per slot-hour.

Prices read on cloud.google.com/bigquery/pricing on 2026-11-06 (list prices;
the europe-west1 rate may be a little higher).

Our volume, measured in L04 (`docs/warehouse-tuning.md`):

- Biggest query on a tuned table: 4.29 MiB processed.
- Every query we ran on 2026-11-06 together: under 100 MiB.
- Even 1,000 queries a month at 13 MiB each is about 13 GiB,
  about 1% of the free TiB.

Who queries: our group, the ML team (daily demand), and a few dashboards.
Load is small and comes in short bursts, not all day.

## Options considered

1. **On-demand + billing cap.** Pay per query. Cap each query at 10 MiB
   ("Maximum bytes billed").
2. **Standard edition, reserved slots.** Fixed hourly cost. Even 50 slots
   running all month is 50 x 730 h x $0.04 = about $1,460 per month.
3. **Standard edition with autoscaling only.** Pay only for slots in use,
   billed per second with a 1-minute minimum. Needs a reservation to set up
   and watch.

## Criteria

| Criterion | Why it matters | 1. On-demand + cap | 2. Reserved slots | 3. Autoscaling |
|---|---|---|---|---|
| Cost at our volume | Small, bursty load | $0 (free TiB) | about $1,460 / month | low, but not zero |
| Protection from a runaway query | One bad query must not cost a lot | Cap refuses it before it runs | Fixed cost, but slows other queries | Can scale up and bill more |
| Rewards good tables | Partitions and views should lower the bill | Yes: we pay for bytes read | No: cost is the same | Partly |
| Effort to run | Small team, shared class project | Nothing to set up | Reservation to size and watch | Reservation to set up |
| Rights needed | We are not admins of the project | None | Admin | Admin |

## Decision

Option 1: on-demand, with a 10 MiB cap on our queries.

- At our volume, on-demand costs $0 (inside the free TiB). Option 2 costs
  money every hour for compute we would not use.
- The cap blocks a forgotten query on a large table before it runs.
  Tested: Q1 on the unpartitioned table needs 13,631,488 bytes billed and
  is refused (`warehouse/max-bytes-billed-error.png`).
- Partitioning already cut Q1 by 2.9x and Q2 by 11.4x. On-demand rewards
  this directly, because we pay for bytes read.

## Consequences

- Cost follows bytes read, so partitioning, column choice (no `SELECT *`)
  and materialized views lower the bill directly.
- The cap is set in the console query settings, per user. It is not yet
  enforced for the whole project. A project-level quota needs admin rights
  on the shared class project (see `infra/iam.md`).
- In a script, the cap applies to the whole script, not to each query.
  Big jobs (rebuilding tables) need the cap raised for that run.
- When to review: if monthly usage gets close to 1 TiB, or if the ML team
  runs heavy queries all day, compare again with autoscaling (option 3).