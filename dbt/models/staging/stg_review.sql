-- GRAIN: one review. seller_product_flag is dropped: it is 'S' on every row (warehouse-tuning.md).
SELECT
    review_id,
    buyer_id,
    rating,
    NULLIF(TRIM(r_desc), '') AS review_text,
    NULLIF(TRIM(title), '')  AS review_title
FROM {{ source('marketplace', 'review') }}
