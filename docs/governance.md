# Governance: classification, access, enforcement

Step 10. Who may read what, and how far the platform enforces it today.
The decision behind it is [ADR-0010](adr/0010-data-classification.md). Erasure: [runbooks/erasure.md](runbooks/erasure.md).

## Classes

| Class | Meaning | Example |
|---|---|---|
| `restricted` | Secrets and payment data. Never leaves the shop database. | `customer.pwd`, `payment_details.card_no` |
| `pii.contact` | Identifies or reaches a person on its own. | phone, street address |
| `pii.identifier` | An id that links rows to a person. Harmless alone, identifying once joined. | `buyer_id`, `c_id` |
| `unclassified` | Free text. Anyone could have written anything in it, so we cannot say it is clean. | review text |
| `internal` | Business data with no personal content. | order dates, quantities, prices |
| `public` | Could be published. | product catalogue |

Dataset labels (Terraform, `infra/bigquery.tf`) give the highest class a dataset holds:
`data_class=confidential` for `group2_wh` and `group2_silver` (they hold `pii.*`), `internal` for `group2_gold`.
dbt carries the same classes in `meta` (`dbt/models/staging/_staging.yml`).

## Owners

An owner is a role that can answer questions about a column: what it means, who may read it, when it can be deleted.

| Owner role | Person today | Owns |
|---|---|---|
| Ingestion & platform lead | Wei-Ling Hung | bronze files, the Airbyte copies, clickstream |
| Warehouse & FinOps lead | Chanelle Sanchez | `orders`, `order_items` in `group2_wh` |
| Data modelling lead | Luli Maruyama | `product`, `review`, `product_reviews`, silver and gold models |
| Architecture lead (privacy) | Rania Mehria | `customer_shipping`, `shipping_details`, every `pii.*` column, erasure requests |

## Classification policy: every column in `group2_wh`

| Table.column | Class | Owner | Why |
|---|---|---|---|
| `orders.order_id` | internal | Warehouse lead | sequence number, no personal content |
| `orders.buyer_id` | pii.identifier | Architecture lead | links every order to one customer |
| `orders.discount_id` | internal | Warehouse lead | always empty in the export |
| `orders.payment_id` | pii.identifier | Architecture lead | links to the saved card in `payment_details` |
| `orders.order_date` | internal | Warehouse lead | no personal content |
| `order_items.order_id` | internal | Warehouse lead | no personal content |
| `order_items.p_id` | public | Data modelling lead | product id, in the catalogue |
| `order_items.qty` | internal | Warehouse lead | sales volume |
| `order_items.price_at_purchase` | internal | Warehouse lead | price paid, commercial |
| `order_items.order_date` | internal | Warehouse lead | copied from the order |
| `review.review_id` | internal | Data modelling lead | no personal content |
| `review.buyer_id` | pii.identifier | Architecture lead | author of the review |
| `review.r_desc` | **unclassified** | Data modelling lead | free text; we found 7 e-mails and 86 phone-like numbers in it, and cannot tell what else |
| `review.title` | **unclassified** | Data modelling lead | free text; 1 e-mail found |
| `review.rating` | internal | Data modelling lead | 1 to 5 |
| `review.seller_product_flag` | internal | Data modelling lead | always `S` |
| `product_reviews.p_id` | public | Data modelling lead | product id |
| `product_reviews.review_id` | internal | Data modelling lead | link table |
| `product.p_id` | public | Data modelling lead | catalogue |
| `product.p_name` | public | Data modelling lead | catalogue |
| `product.p_desc` | **unclassified** | Data modelling lead | JSON text written by sellers; we have not checked every value |
| `product.price` | public | Data modelling lead | shown on the site |
| `product.stock_qty` | internal | Data modelling lead | stock level |
| `product.category_id` | public | Data modelling lead | 2 ranges |
| `customer_shipping.address_id` | pii.identifier | Architecture lead | links to an address |
| `customer_shipping.c_id` | pii.identifier | Architecture lead | the customer |
| `customer_shipping.is_default` | internal | Architecture lead | no personal content alone |
| `shipping_details.address_id` | pii.identifier | Architecture lead | links to a customer |
| `shipping_details.street_address` | pii.contact | Architecture lead | **policy tag** |
| `shipping_details.city` | pii.contact | Architecture lead | locates a person with the street |
| `shipping_details.state` | pii.contact | Architecture lead | same |
| `shipping_details.zip` | pii.contact | Architecture lead | **policy tag** |
| `shipping_details.country` | internal | Architecture lead | 6 values, used for demand per country |
| `shipping_details.phone` | pii.contact | Architecture lead | **policy tag** |

The `ext_*` external tables read the same bronze files and carry the same classes column for column.
The 4 `_airbyte_*` columns are internal. The 2 materialized views hold product, day and units only: internal.

Silver and gold: `stg_orders.buyer_id` and `stg_customer_shipping.c_id` stay `pii.identifier`.
`stg_shipping_details` keeps only `address_id` and `country`. `stg_review` drops `buyer_id` and masks
e-mails and phone numbers (`redact_pii`), but its text stays **unclassified**: masking catches formats,
not a name or a street written in words. Gold holds no `pii.*` column and no free text.

## Access matrix

| Role | public | internal | pii.identifier | pii.contact | unclassified | restricted |
|---|---|---|---|---|---|---|
| Analyst | read | read (gold) | no | no | no | no |
| ML service account | read | read (gold) | no | no | no | no |
| Data engineer (group 2) | read, write | read, write | read, write | read, erase | read | no |
| Pipeline (Airflow jobs) | read, write | read, write | read, write | no (reads `address_id` and `country` only) | read, mask | no |

Route for each "no":

- **Analyst or ML team needs a `pii.*` or free-text column**: open an issue in this repository, assigned
  to the column's owner, saying which question needs it. The owner answers with a gold model that
  aggregates it (for example per country), not with access to the raw column. Answer within 5 working days.
- **Anyone needs `restricted` data**: no route through the platform. It stays in the shop database,
  which is the shop's responsibility.
- **Data engineer needs to erase**: only on a written erasure request, following
  [runbooks/erasure.md](runbooks/erasure.md).

## What is enforced, and the gaps

| Rule | Enforced? | How, or why not |
|---|---|---|
| `restricted` never reaches the platform | Yes | Not selected in Airbyte, not read by the extractor (ADR-0003) |
| `pii.contact` columns tagged | Yes | Taxonomy `group2-data-classification`, policy tag `confidential-direct-pii` (`infra/policy_tags.tf`), applied to `phone`, `street_address`, `zip` (`scripts/apply_policy_tags.py`) |
| Reading a tagged column is refused | **No, gap** | See below |
| Free text masked before silver | Yes | `redact_pii`, test `assert_no_pii_in_reviews` on every run |
| Gold holds no personal data | Yes | Checked by the same tests and by the model columns |
| Analysts and ML read gold only | **No, gap** | `infra/access.tf` writes the grant; the list is empty because everyone already has project-wide access |
| One service account per job | **No, gap** | Creation refused (403, `infra/service_accounts.tf`); jobs run with the runner's credentials |

**Before tagging, we checked who reads the columns.** The only reader of `shipping_details` is
`stg_shipping_details`, which selects `address_id` and `country`. Tagging `phone`, `street_address`
and `zip` could not break the pipeline, and `dbt build` after tagging gave PASS=57 ERROR=0.

**Why the refusal could not be shown.** After tagging, our own account could still read the 200,001
phone numbers. A column tag refuses readers who lack `datacatalog.categories.fineGrainedGet` on the
tag. In the shared class project, every member holds a broad project role that includes it, and we
cannot change project roles. So the tag is in place and would protect the columns from any principal
without that role (an analyst group, a future ML service account), but we could not demonstrate a
refusal with an identity we control. To prove it, an admin would remove the broad role, or create one
test service account with `bigquery.dataViewer` only, and run `SELECT phone` with it: expected result,
`Access Denied: ... policy tag`.

The 403 errors we hit in steps 6 and 8 (creating a registry, a service account, a budget) are the same
least privilege, applied to us.
