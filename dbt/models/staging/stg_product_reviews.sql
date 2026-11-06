-- GRAIN: one review of one product.
-- Defect fixed: the table is reloaded in full every day (Airbyte full refresh); a replay
-- can repeat a (p_id, review_id) pair. One row per pair is kept.
SELECT
    p_id,
    review_id
FROM {{ source('marketplace', 'product_reviews') }}
QUALIFY ROW_NUMBER() OVER (PARTITION BY p_id, review_id ORDER BY review_id) = 1
