-- GRAIN: one product.
SELECT
    pr.p_id,
    COUNT(*) AS n_reviews,
    ROUND(AVG(r.rating), 3) AS avg_rating
FROM {{ ref('stg_product_reviews') }} AS pr
JOIN {{ ref('stg_review') }} AS r USING (review_id)
GROUP BY pr.p_id
