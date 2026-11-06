-- GRAIN: one review of one product.
SELECT
    p_id,
    review_id
FROM {{ source('marketplace', 'product_reviews') }}
