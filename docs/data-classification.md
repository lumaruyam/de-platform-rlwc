# Data classification

Step 10. Every dataset carries a `data_class` label (Terraform, `infra/bigquery.tf`), and every
silver model a `classification` and, for sensitive columns, a `pii` level (dbt `meta`,
`dbt/models/staging/_staging.yml`). Shown in the dbt documentation site.

| Class | Meaning | Who may read |
|---|---|---|
| restricted | Secrets and payment data | Nobody outside the shop database |
| confidential | Identifies or locates a person, directly or indirectly | Data engineers |
| internal | Business data with no personal data | Analysts, ML team |
| public | Could be published | Anyone |

| Where | Data | Class | PII |
|---|---|---|---|
| Shop database only | `customer.pwd`, `payment_details.card_no`, `cvv` | restricted | direct |
| Bucket `bronze/`, dataset `group2_wh` | orders, order lines, reviews, addresses, clickstream | confidential | `shipping_details` address and phone: direct. `buyer_id`, `session_id`, `payment_id`: indirect |
| Dataset `group2_silver` | `stg_*`, `int_*` | confidential | `buyer_id` in orders, `c_id` in addresses: indirect. Address reduced to country |
| Dataset `group2_gold` | facts and dimensions | internal | none: no buyer id, country only, review text masked |
| `stg_product`, `dim_product` | catalogue | public | none |

`restricted` data never leaves the database: not selected in Airbyte, not read by our extractor
(step 3), and Airbyte does not add new columns without approval.
