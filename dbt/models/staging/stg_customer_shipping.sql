-- GRAIN: one address of one customer.
-- Defect fixed: is_default is stored as text ('true', 't', '1'...) by the CSV-era export;
-- turned into a real boolean.
SELECT
    c_id,
    address_id,
    LOWER(TRIM(is_default)) IN ('true', 't', '1', 'y', 'yes') AS is_default
FROM {{ source('marketplace', 'customer_shipping') }}
