-- GRAIN: one review.
-- PII redaction (step 10): e-mails and phone numbers written by customers in their reviews are
-- masked here, so they never reach silver or gold. buyer_id is dropped: no gold table needs to
-- know who wrote a review, only which product it is about.
-- seller_product_flag is dropped: it is 'S' on every row (warehouse-tuning.md).
SELECT
    review_id,
    rating,
    {{ redact_pii("NULLIF(TRIM(r_desc), '')") }} AS review_text,
    {{ redact_pii("NULLIF(TRIM(title), '')") }}  AS review_title
FROM {{ source('marketplace', 'review') }}
