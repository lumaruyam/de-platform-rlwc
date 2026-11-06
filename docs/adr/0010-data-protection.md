# ADR-0010: Mask personal data in silver, drop what consumers do not need, and grant gold only

- **Status:** proposed
- **Date:** 2026-11-06
- **Author:** Rania Mehria
- **Lesson:** L10

## Context

Passwords and card numbers never leave the database (ADR-0003). But free text does: on 2026-11-06,
in 111,322 reviews, 7 contained an e-mail address and 86 a phone-like number. Reviews also carried
the author's `buyer_id`. Analysts and the ML team read gold; they do not need to know who wrote a review.
Everyone in the shared class project can read every dataset today (`infra/iam.md`).

## Options considered

1. **Keep raw text, restrict who reads it.**
2. **Remove the review text entirely.**
3. **Mask e-mails and phone numbers in silver, drop the author, and grant consumers gold only.**

## Criteria

| Criterion | 1. Restrict | 2. Remove text | 3. Mask + minimise |
|---|---|---|---|
| Personal data reaches gold | Yes | No | No |
| Review text still usable | Yes | No | Yes |
| Works without admin rights | No | Yes | Yes (masking); grants need admin |
| Checked on every run | No | - | Yes, a test |

## Decision

Option 3.

- Macro `redact_pii` in dbt replaces e-mails with `[email]` and phone-like numbers with `[phone]`
  in `stg_review` (text and title). `buyer_id` is dropped from `stg_review`.
- Test `assert_no_pii_in_reviews` fails if one survives. First run: PASS. Masked: 8 e-mails
  (7 in texts, 1 in a title) and 86 phone-like numbers.
- Classification: `data_class` label on each dataset (`confidential` for wh and silver, `internal` for
  gold), `classification` and `pii` in dbt `meta` (docs/data-classification.md).
- Least privilege: `infra/access.tf` grants `roles/bigquery.dataViewer` on gold only to `gold_readers`.
- Airflow Fernet key: Variables are now encrypted in Airflow's database.

## Consequences

- Regexes catch formats, not meaning: a name or a street written in a review stays. Some long product
  numbers may be masked by mistake.
- `gold_readers` is empty: project-wide access in the shared class project makes a dataset grant
  meaningless until project roles are narrowed, which needs admin rights. Same for one service account
  per job and a read-only database user for Airbyte.
- The ML team keeps everything it needs: product, country, day, units.
