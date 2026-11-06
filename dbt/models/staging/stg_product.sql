-- GRAIN: one product.
SELECT
    p_id,
    p_name,
    price AS list_price,
    stock_qty,
    category_id
FROM {{ source('marketplace', 'product') }}
