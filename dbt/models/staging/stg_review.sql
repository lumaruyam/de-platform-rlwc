-- GRAIN: one review.
-- Defects fixed:
--   1. Personal data in free text: customers write e-mails and phone numbers in reviews
--      (7 e-mails, 86 phone-like numbers in 111,322 reviews, measured 2026-11-06). Masked here
--      so they never reach silver or gold (ADR-0010). buyer_id is dropped: no consumer needs it.
--   2. seller_product_flag is 'S' on every row: it carries no information, dropped.
--   3. Empty strings instead of NULL in text columns.
SELECT
    review_id,
    rating,
    {{ redact_pii("NULLIF(TRIM(r_desc), '')") }} AS review_text,
    {{ redact_pii("NULLIF(TRIM(title), '')") }}  AS review_title
FROM {{ source('marketplace', 'review') }}
