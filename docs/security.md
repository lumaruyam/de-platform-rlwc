# Security and governance

Step 10. Least privilege, PII redaction, data classification (`docs/governance.md`).

## PII redaction (dbt)

Measured on 2026-11-06 in 111,322 reviews: 7 with an e-mail address, 86 with a phone-like number,
26 with a link.

- Macro `dbt/macros/redact_pii.sql` replaces e-mails with `[email]` and phone-like numbers with
  `[phone]`. Applied in `stg_review`, so free text is masked before silver.
- `stg_review` no longer carries `buyer_id`: no gold table needs to know who wrote a review.
- Test `assert_no_pii_in_reviews` fails if an e-mail or phone-like number survives.
  First run: PASS (dbt build, PASS=25 ERROR=0).
- Limits: regexes catch formats, not meaning (a name or a street in a review stays). Long
  product numbers may be masked as `[phone]` by mistake. Links are kept.

Data minimisation already in place before step 10: only `country` leaves the address tables
(`stg_customer_address`); `customer` and `payment_details` are never loaded.

## Least privilege

| Who | Should have | Today |
|---|---|---|
| Analysts, ML team | Read `group2_gold` only | `infra/access.tf`: `gold_readers` grants `roles/bigquery.dataViewer` on gold only. Empty list: everyone in the class project already has project-wide access (`infra/iam.md`) |
| Pipeline (Airflow tasks) | Write bronze and the 3 datasets, nothing else | Runs with the runner's own credentials. Target: one service account per job |
| Airbyte | Read 7 tables, write `bronze/airbyte/` | Admin database user and a personal HMAC key (`docs/ingestion-failure-modes.md`). Target: read-only DB user, service account key |
| Group members | Change infra through Terraform pull requests | `terraform plan` in CI on every pull request touching `infra/` |

Creating service accounts and narrowing project roles needs admin rights on the shared class
project, which the group does not have. The grants are written in code so they can be applied.

## Secrets

- No secret in Git or in images: `.env` files are ignored, `.dockerignore` keeps `.env` out of
  images, `profiles.yml` uses oauth, Terraform needs no key.
- Airflow: the database password is a Variable (`pg_password`), masked in UI and logs.
  A Fernet key (in `orchestration/.env`, not committed) now encrypts Variables and Connections
  in Airflow's database. Before it, they were stored in clear (warning `FERNET_KEY is not set`).
  Variables set before the key must be set again.

## Labels

Datasets: `data_class` = `confidential` (wh, silver) or `internal` (gold), applied with Terraform.
