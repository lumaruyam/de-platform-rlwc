-- GRAIN: one customer. Their default address wins; otherwise their lowest address_id.
SELECT
    c_id AS buyer_id,
    country
FROM {{ ref('stg_customer_address') }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY c_id
    ORDER BY IF(is_default, 0, 1), address_id
) = 1
