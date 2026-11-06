-- Step 4: precomputed daily demand.
SET @@location = 'europe-west1';

-- Per day and per product: what the ML team needs to forecast demand.
CREATE MATERIALIZED VIEW `data-engineering-i2.group2_wh.mv_daily_demand`
PARTITION BY DATE_TRUNC(order_date, MONTH)
CLUSTER BY p_id
AS
SELECT order_date,
       p_id,
       SUM(qty) AS units,
       SUM(qty * price_at_purchase) AS revenue,
       COUNT(*) AS order_lines
FROM `data-engineering-i2.group2_wh.order_items_p`
GROUP BY order_date, p_id;

-- Per day and per range (1 = All Beauty, 2 = Premium Beauty): for dashboards.
CREATE MATERIALIZED VIEW `data-engineering-i2.group2_wh.mv_daily_demand_category`
AS
SELECT oi.order_date,
       p.category_id,
       SUM(oi.qty) AS units,
       SUM(oi.qty * oi.price_at_purchase) AS revenue,
       COUNT(*) AS order_lines
FROM `data-engineering-i2.group2_wh.order_items_p` AS oi
JOIN `data-engineering-i2.group2_wh.product` AS p USING (p_id)
GROUP BY oi.order_date, p.category_id;

-- Check: the join must not lose any order line (expect 408560).
SELECT COUNT(*) AS view_rows,
       SUM(order_lines) AS lines_covered,
       COUNT(DISTINCT category_id) AS nb_ranges
FROM `data-engineering-i2.group2_wh.mv_daily_demand_category`;