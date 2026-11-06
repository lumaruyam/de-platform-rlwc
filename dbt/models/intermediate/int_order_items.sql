-- GRAIN: one product in one order, with the order's date and buyer.
SELECT
    i.order_id, i.p_id, i.qty, i.price_at_purchase,
    o.order_date, o.buyer_id
FROM {{ ref('stg_order_items') }} AS i
JOIN {{ ref('stg_orders') }} AS o USING (order_id)
