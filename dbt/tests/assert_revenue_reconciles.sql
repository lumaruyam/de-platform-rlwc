-- One agreed revenue figure: monthly revenue must add up to the order lines, to the cent.
-- The test fails if this query returns a row.
SELECT m.total, l.total
FROM (SELECT SUM(revenue) AS total FROM {{ ref('fct_monthly_revenue') }}) AS m,
     (SELECT SUM(line_revenue) AS total FROM {{ ref('fct_order_items') }}) AS l
WHERE m.total != l.total
