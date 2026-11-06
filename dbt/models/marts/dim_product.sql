-- GRAIN: one product.
SELECT
    p.p_id,
    p.p_name,
    p.list_price,
    p.category_id,
    c.category_name,
    COALESCE(r.n_reviews, 0) AS n_reviews,
    r.avg_rating
FROM {{ ref('stg_product') }} AS p
LEFT JOIN {{ ref('category') }} AS c USING (category_id)
LEFT JOIN {{ ref('int_product_ratings') }} AS r USING (p_id)
