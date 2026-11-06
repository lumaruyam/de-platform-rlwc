-- GRAIN: one month. The one agreed revenue figure for analysts:
-- revenue = SUM(qty * price_at_purchase), before discounts (discount amounts are not loaded).
SELECT
    DATE_TRUNC(order_date, MONTH) AS month,
    COUNT(DISTINCT order_id) AS orders,
    SUM(qty) AS units,
    SUM(line_revenue) AS revenue
FROM {{ ref('fct_order_items') }}
GROUP BY month
