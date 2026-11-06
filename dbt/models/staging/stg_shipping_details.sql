-- GRAIN: one address.
-- Defects fixed:
--   1. Personal data: street, zip and phone identify a person directly. Only country leaves
--      this model (data minimisation, ADR-0010).
--   2. Empty strings instead of NULL for a missing country.
SELECT
    address_id,
    NULLIF(TRIM(country), '') AS country
FROM {{ source('marketplace', 'shipping_details') }}
