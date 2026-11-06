{{ config(
    partition_by={'field': 'order_date', 'data_type': 'date', 'granularity': 'month'},
    cluster_by=['p_id']
) }}
-- GRAIN: one product in one order.
SELECT
    i.order_id,
    i.p_id,
    i.order_date,
    COALESCE(c.country, 'unknown') AS country,
    i.qty,
    i.price_at_purchase,
    i.qty * i.price_at_purchase AS line_revenue,
    r.avg_rating
FROM {{ ref('int_order_items') }} AS i
LEFT JOIN {{ ref('int_buyer_country') }} AS c USING (buyer_id)
LEFT JOIN {{ ref('int_product_ratings') }} AS r USING (p_id)
