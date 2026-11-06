-- GRAIN: one product in one order.
-- Defect fixed: duplicate order lines from at-least-once loads; one row per (order_id, p_id).
SELECT
    order_id,
    p_id,
    qty,
    price_at_purchase
FROM {{ source('marketplace', 'order_items') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id, p_id ORDER BY qty DESC) = 1
