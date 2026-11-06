# Data dictionary

Bronze tables in `gs://data-engineering-i2-group2/bronze/`, loaded on 2026-11-03 from the legacy CSV export (release v1.0.0) with `ingestion/load_bronze_export.py`. Layout: [ADR-0002](adr/0002-bronze-layout.md).

**Every column is stored as text in bronze**, exactly as in the export. Types are set in silver. The "Type in silver" column says what each one should become.

Personal data:
- **Yes, direct**: identifies a person on its own (name, phone, address).
- **Yes, indirect**: an id that links data to a person.
- **Maybe (free text)**: free text where anyone could have written anything.
- **No**: no personal content.

## Tables loaded

| Table | Path | Rows | Partition |
|---|---|---|---|
| `orders` | `bronze/orders/dt=YYYY-MM-DD/` | 222,644 | by day, on `order_date` |
| `order_items` | `bronze/order_items/dt=YYYY-MM-DD/` | 408,560 | by day, on the order's `order_date` |
| `review` | `bronze/review/` | 111,322 | none |
| `product_reviews` | `bronze/product_reviews/` | 111,322 | none |
| `product` | `bronze/product/` | 42,858 | none |
| `customer_shipping` | `bronze/customer_shipping/` | 200,001 | none |
| `shipping_details` | `bronze/shipping_details/` | 200,001 | none |

## orders

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `Unnamed: 0` | (dropped) | Row index added by the export. Not a business column. | No |
| `order_id` | integer | Order id. | No |
| `buyer_id` | string | Customer who placed the order. | Yes, indirect |
| `discount_id` | integer | Discount used. Always empty in the export. | No |
| `payment_id` | integer | Link to the saved card used to pay. | Yes, indirect |
| `order_date` | date | Day of the order, 2023-09-15 to 2026-09-14. | No |
| `dt` | (partition) | Copy of `order_date`, used for the folder name. | No |

## order_items

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `order_id` | integer | Order this line belongs to. | No |
| `p_id` | string | Product id. Some start with 0: must stay text. | No |
| `qty` | integer | Units bought. | No |
| `price_at_purchase` | numeric | Unit price at the time of the order. | No |
| `dt` | (partition) | `order_date` of the order, added for the folder name. | No |

## review

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `Unnamed: 0` | (dropped) | Row index added by the export. | No |
| `review_id` | integer | Review id. | No |
| `buyer_id` | string | Customer who wrote the review. | Yes, indirect |
| `r_desc` | string | Review text. | Maybe (free text) |
| `title` | string | Review title. | Maybe (free text) |
| `rating` | integer | Rating from 1 to 5. | No |
| `seller_product_flag` | (to check) | Always `S` in the export. | No |

## product_reviews

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `Unnamed: 0` | (dropped) | Row index added by the export. | No |
| `p_id` | string | Product reviewed. | No |
| `review_id` | integer | Review. | No |

## product

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `Unnamed: 0` | (dropped) | Row index added by the export. | No |
| `p_id` | string | Product id. Some start with 0: must stay text. | No |
| `p_name` | string | Product name. | No |
| `p_desc` | JSON | Product details (brand, size...) as JSON text. | No |
| `price` | numeric | Current price. Not the price paid: see `order_items.price_at_purchase`. | No |
| `qty` | integer | Units in stock. | No |
| `category_id` | integer | Product category (2 values). | No |

## customer_shipping

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `Unnamed: 0` | (dropped) | Row index added by the export. | No |
| `address_id` | integer | Address id. | Yes, indirect |
| `c_id` | string | Customer id. | Yes, indirect |
| `is_default` | boolean | `1` if it is the customer's default address. | No |

## shipping_details

| Column | Type in silver | Meaning | Personal data |
|---|---|---|---|
| `Unnamed: 0` | (dropped) | Row index added by the export. | No |
| `address_id` | integer | Address id. | Yes, indirect |
| `street_address` | string | Street and number. | Yes, direct |
| `city` | string | City. | Yes, direct |
| `state` | string | Region. | Yes, direct (with the rest of the address) |
| `zip` | string | Postal code. Some start with 0: must stay text. | Yes, direct |
| `country` | string | Country. Used as the country of the order. | No on its own |
| `phone` | string | Phone number. Starts with 0: must stay text. | Yes, direct |

## Not ingested

| Table | Why |
|---|---|
| `customer` | Holds `pwd`, plain-text passwords. Must never reach bronze. |
| `payment_details` | Holds `card_no` and `cvv`. Must never reach bronze. |
| The 18 other tables | Not used by the project. We load only what a named question needs. |

## Known defects (for silver, L05)

| Defect | Where | Fix in silver |
|---|---|---|
| Row index column `Unnamed: 0` | every table except `order_items` | drop it |
| Every order appears twice, a few days apart | `orders` | deduplicate, with a written rule |
| `discount_id` always empty | `orders` | keep as null, or drop |
| `seller_product_flag` always `S` | `review` | check its meaning before using it |
| Empty or blank review text (124 rows) | `review.r_desc` | turn blank text into null |
| Text values like `NA` written as words | `review.r_desc`, `review.title` | keep them: they are real text, not missing values |
| Prices with float noise (many decimals) | `product.price` | round to 2 decimals |
| Leading zeros in ids and phones | `p_id`, `zip`, `phone` | keep as text, never cast to a number |


## Where each bronze table comes from (L03)

Bronze no longer has one shape. Whoever models silver must check the path first.

| Folder in bronze | Written by | Extra columns | Notes |
|---|---|---|---|
| `orders/`, `order_items/` and the 5 reference tables | `ingestion/load_bronze_export.py`, once, by hand (L02) | none | All columns stored as text |
| `orders_extract/` | `ingestion/extract_orders.py` (incremental, cursor `order_id`) | none | Typed by PostgreSQL: `order_id` integer, `order_date` date |
| `clickstream/` | `ingestion/consume_clickstream.py` (Kafka) | none | See the clickstream section below |
| `_dlq/clickstream/` | `ingestion/consume_clickstream.py` | | Rejected events, see below |
| Airbyte folders | The Airbyte connection (7 tables) | `_airbyte_raw_id`, `_airbyte_extracted_at`, `_airbyte_meta`, `_airbyte_generation_id` | Added after the first sync |

The 4 Airbyte columns:

| Column | Meaning |
|---|---|
| `_airbyte_raw_id` | A unique id Airbyte gives each row it writes |
| `_airbyte_extracted_at` | When Airbyte read the row from the source |
| `_airbyte_meta` | Airbyte's notes on the row, for example a value it had to change |
| `_airbyte_generation_id` | Which full refresh the row belongs to |

## clickstream (Kafka topic `clickstream`, schema_version 1)

Partitioned by `event_time`. Schema: [`ingestion/clickstream.schema.json`](../ingestion/clickstream.schema.json).

| Field | Type | In which events | Meaning | Personal data |
|---|---|---|---|---|
| `schema_version` | integer | all | Version of the event shape. Decides which schema checks it. | No |
| `event_id` | string (UUID) | all | Unique id of the event. Used to remove duplicates in silver. | No |
| `event_type` | string | all | `product_viewed`, `added_to_cart` or `order_placed` | No |
| `event_time` | timestamp (UTC) | all | When it happened. Decides the `dt=` folder. | No |
| `emitted_at` | timestamp (UTC) | all | When it was sent to Kafka. Can be later than `event_time`. | No |
| `session_id` | string (UUID) | all | One visit to the shop. | Yes, indirect: always sent with `buyer_id`, so it ties a whole visit to a person |
| `buyer_id` | string | all | The customer. Same id as `orders.buyer_id`. | Yes, indirect |
| `p_id` | string | `product_viewed`, `added_to_cart` | Product. Can start with 0: keep as text. | No |
| `price` | number | `product_viewed`, `added_to_cart` | Price shown to the customer | No |
| `qty` | integer | `added_to_cart` | Units added to the basket | No |
| `order_id` | integer | `order_placed` | The order created. Joins to `orders.order_id`. | No |
| `payment_method` | string | `order_placed` | `Credit Card` or `PayPal` | No |
| `amount` | number | `order_placed` | Total paid | No |
| `currency` | string | `order_placed` | Always `EUR` so far | No |
| `items` | JSON text | `order_placed` | The basket lines: `p_id`, `qty`, `price`. Stored as JSON text so every file has the same column type. | No |

## _dlq/clickstream (rejected events)

| Column | Meaning | Personal data |
|---|---|---|
| `raw` | The message exactly as it arrived | Maybe: it can hold a `buyer_id` |
| `reason` | Why it was rejected | No |
| `received_at` | When our consumer read it. Decides the `dt=` folder. | No |
| `topic`, `partition`, `offset` | Where to find the message again in Kafka | No |

## Warehouse (BigQuery, step 4)

Dataset `data-engineering-i2.group2_wh`, region `europe-west1`.
SQL in `warehouse/`, measures in `docs/warehouse-tuning.md`.

### Tables and views

| Name | Type | Built from | Notes |
|---|---|---|---|
| `ext_*` (8 tables) | external | Parquet files in `bronze/` | No copy. `ext_orders`, `ext_order_items` and `ext_orders_extract` get `dt` as a DATE partition column |
| `orders` | native | `ext_orders` | `dt` renamed `order_date`. Ids as INT64 |
| `order_items` | native | `ext_order_items` | `qty` INT64, `price_at_purchase` NUMERIC (exact, for money) |
| `review`, `product_reviews` | native | `ext_review`, `ext_product_reviews` | `rating` INT64. No date column |
| `product` | native | `ext_product` | `price` FLOAT64, `category_id` INT64 |
| `customer_shipping`, `shipping_details` | native | `ext_*` | `zip` and `phone` stay text, to keep leading zeros and "+" |
| `orders_p`, `order_items_p` | native | the native tables | Partitioned by month of `order_date` |
| `order_items_pc` | native | `order_items` | Partitioned by month, clustered by `p_id` |
| `mv_daily_demand` | materialized view | `order_items_p` | One row per day and product: `units`, `revenue`, `order_lines`. For the ML team |
| `mv_daily_demand_category` | materialized view | `order_items_p` + `product` | One row per day and range: same measures. For dashboards |

Personal data in the warehouse follows the bronze columns above:
`buyer_id` (Yes, indirect), `shipping_details` address and phone (Yes, direct).
`customer` and `payment_details` are not loaded.

### Known issues found in step 4

| Column | Issue | What we do |
|---|---|---|
| `review.seller_product_flag` | `S` on all 111,322 rows. Tells nothing | Not used. Every review counts as a product review |
| `product.category_id` | Only 2 values: 1 = All Beauty (42,637 products), 2 = Premium Beauty (221). Checked in the source table `category` | Not a bug: the catalogue has two ranges. The `category` table itself is not loaded yet (names come from the source) |
| `orders_extract.payment_id`, `discount_id` | FLOAT in some files, INT in others: pandas turns a column with empty values (PayPal, no discount) into FLOAT | `orders` is loaded from `ext_orders` (step 2 copy). Fix planned in `ingestion/extract_orders.py` (nullable `Int64`) |
| Native tables | Loaded with `SAFE_CAST`: an unreadable value becomes NULL silently | Row counts checked table by table. NULL checks planned in silver |
### Known issue found in step 7

| Column | Issue | What we do |
|---|---|---|
| `orders.order_date` | 8,189 orders dated after today (2026-11-07 to 2026-12-02, ids 236,548 to 244,743): the traffic simulator's clock runs ahead | Kept. dbt test `assert_no_future_orders` warns on every run |
