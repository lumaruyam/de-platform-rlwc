# ADR-0009: Label every resource, keep the budget in code, and run our own daily cost alert

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L09

## Context

The whole class shares one Google Cloud project, so the bill does not say what our group costs.
We want an alert before spend becomes a problem. On 2026-11-06 we checked: the Cloud Billing API is
not enabled on the project, and a budget needs the Billing Account Costs Manager role, which we do not have.

## Options considered

1. **Only document** a budget we cannot create.
2. **Enable the Billing API on the shared project** and try.
3. **Budget in Terraform, off until someone with billing rights sets one variable, plus our own
   cost alert** that works with our rights.

## Criteria

| Criterion | 1. Document | 2. Enable API | 3. Code + own alert |
|---|---|---|---|
| A real alert today | No | Probably not (missing role) | Yes |
| Touches the class's shared settings | No | Yes | No |
| Ready when billing rights exist | No | - | Yes, one variable |

## Decision

Option 3.

- **Labels** on the bucket and the datasets, from Terraform `default_labels`: `team=group2`,
  `project=albert-marketplace`, `env=dev`, `managed_by=terraform`, plus `layer` per dataset.
  The bill can be split by group.
- **Budget** `infra/budget.tf`: 10 EUR a month on `team=group2`, alerts at 50%, 90%, 100%. `count = 0`
  while `billing_account` is empty.
- **Own alert**: Airflow task `cost_check` sums our jobs' bytes billed since the 1st of the month at
  6.25 USD per TiB. Above 1 USD, `ERROR()` fails the query, the task fails and the alert runs.

## Consequences

- 2026-11-06: 0.0218 USD month to date. Tested with a 0.01 USD limit: the task fails as expected.
- The alert counts the jobs of the account that runs it, at list price, without storage.
- Measured optimisation (L04): monthly partitions cut bytes read by 2.9x (Q1) and 11.4x (Q2).
  On-demand pricing bills bytes read, so the bill drops by the same ratio.
