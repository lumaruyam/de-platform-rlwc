-- GRAIN: one product.
-- Defect fixed: category_id is a bare code (1, 2). The source table category is not loaded,
-- so the names come from the seed category.csv, checked against the source on 2026-11-06.
-- p_desc (long free text, unused) is dropped.
SELECT
    p_id,
    p_name,
    price AS list_price,
    stock_qty,
    category_id
FROM {{ source('marketplace', 'product') }}
