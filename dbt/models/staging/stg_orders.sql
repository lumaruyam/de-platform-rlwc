-- GRAIN: one order.
-- Defect fixed: duplicate orders. Every load is at-least-once (ADR-0003), so the same
-- order_id can arrive twice; one row per order_id is kept.
SELECT
    order_id,
    buyer_id,
    payment_id,
    discount_id,
    order_date
FROM {{ source('marketplace', 'orders') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_date DESC) = 1
