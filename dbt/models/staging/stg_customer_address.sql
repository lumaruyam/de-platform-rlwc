-- GRAIN: one address of one customer.
-- Data minimisation: only country leaves shipping_details. Street, zip and phone stay behind.
SELECT
    cs.c_id,
    cs.address_id,
    LOWER(TRIM(cs.is_default)) IN ('true', 't', '1', 'y', 'yes') AS is_default,
    NULLIF(TRIM(sd.country), '') AS country
FROM {{ source('marketplace', 'customer_shipping') }} AS cs
LEFT JOIN {{ source('marketplace', 'shipping_details') }} AS sd USING (address_id)
