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