-- GRAIN: one calendar day, from the first order to the last one.
WITH bounds AS (
    SELECT MIN(order_date) AS first_day, MAX(order_date) AS last_day
    FROM {{ ref('stg_orders') }}
)
SELECT
    d AS date_day,
    EXTRACT(YEAR FROM d) AS year,
    EXTRACT(MONTH FROM d) AS month,
    FORMAT_DATE('%A', d) AS day_name,
    EXTRACT(DAYOFWEEK FROM d) IN (1, 7) AS is_weekend
FROM bounds, UNNEST(GENERATE_DATE_ARRAY(first_day, last_day)) AS d
