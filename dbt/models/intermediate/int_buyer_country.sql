-- GRAIN: one customer. Their default address wins; otherwise their lowest address_id.
SELECT
    cs.c_id AS buyer_id,
    sd.country
FROM {{ ref('stg_customer_shipping') }} AS cs
LEFT JOIN {{ ref('stg_shipping_details') }} AS sd USING (address_id)
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY cs.c_id
    ORDER BY IF(cs.is_default, 0, 1), cs.address_id
) = 1
