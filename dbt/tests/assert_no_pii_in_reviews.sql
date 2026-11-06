-- No e-mail or phone-like number may survive the redaction in silver.
-- The test fails if this query returns a row.
SELECT review_id
FROM {{ ref('stg_review') }}
WHERE REGEXP_CONTAINS(CONCAT(IFNULL(review_text, ''), ' ', IFNULL(review_title, '')),
                      r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|\+?\d[\d .-]{8,}\d')
