-- GRAIN: one order. Bronze keeps duplicates (at-least-once loads); silver keeps one row per order_id.
SELECT
    order_id,
    buyer_id,
    payment_id,
    discount_id,
    order_date
FROM {{ source('marketplace', 'orders') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_date DESC) = 1
