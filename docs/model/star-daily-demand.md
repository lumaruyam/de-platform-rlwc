# Star Schema Sketch: Daily Demand

> **Note:** This is a conceptual sketch. We will build this for real, with dbt models and data tests, in Lesson 5. Sketching it now ensures our ingestion pipelines (Lesson 3) capture all the necessary columns from day one.

## Business Process

The business process being measured is **product sales** across Albert's Marketplace. Specifically, the ML team needs to forecast demand for each product, so independent sellers can stock up before the busy season. To do this, they need to understand historical daily sales volumes, broken down by geography.

## Grain

**One row per product, per country, per day.**

*(If a product is sold by multiple sellers, we must ensure the product dimension is uniquely identified to avoid fan-out. The fact table will aggregate the total units sold for that specific product in that specific country on that specific date.)*

## Dimensions

These are the "who, what, where, and when" contexts that describe the event. To build this, the ingestion pipelines must extract these attributes from the source PostgreSQL database.

| Dimension | Description | Example Attributes (to be defined in L05) |
|---|---|---|
| **Dim Date** | The calendar day the sales occurred. | `date_key`, `full_date`, `year`, `month`, `day_of_week`, `is_weekend` |
| **Dim Product** | The specific beauty product being sold. | `product_key`, `product_id`, `product_name`, `category`, `brand`. |
| **Dim Country** | The destination country for the order. | `country_key`, `country_code`, `country_name`, `region` (e.g., EU, EMEA). |

*(Note: the seller cannot be a dimension at this grain: an order line records the product, not who sold it.)*

## Facts

These are the quantitative measurements of the event. They are numeric, additive, and live in the center of the star schema.

| Fact | Description | Formula / Logic |
|---|---|---|
| **Units Sold** | The total number of a specific product sold on a specific day in a specific country. | `SUM(order_items.qty)` |
| **Order Count** | The number of distinct orders containing this product on this day in this country. *(Useful for ML to distinguish between one large B2B order vs. many small B2C orders).* | `COUNT(DISTINCT order_id)` |
| **Revenue** | The total monetary value of the units sold. | `SUM(order_items.qty * order_items.price_at_purchase)` |

## Engineering Implications for Ingestion (L03)

To make this star schema possible in Lesson 5, our ingestion pipelines must guarantee the following columns are captured from the source PostgreSQL database and preserved (unmodified) in the Bronze layer:
- **From `orders`:** `order_id`, `order_date`, `country` (or shipping country).
- **From `order_items`:** `order_id`, `p_id`, `qty`, `price_at_purchase`.
- **From `product`:** `product_id`, `product_name`, `category`, `brand`.