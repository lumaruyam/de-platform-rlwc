-- Step 4: the three business queries.
-- "Today" is 2026-09-14, the last day of data.
-- Run each one on order_items, order_items_p and order_items_pc,
-- with "Use cached results" turned off.
SET @@location = 'europe-west1';

-- Q1: revenue per month, last 12 months
SELECT DATE_TRUNC(order_date, MONTH) AS month,
       SUM(qty * price_at_purchase) AS revenue
FROM `data-engineering-i2.group2_wh.order_items`
WHERE order_date BETWEEN DATE_SUB(DATE '2026-09-14', INTERVAL 12 MONTH) AND DATE '2026-09-14'
GROUP BY month
ORDER BY month;

-- Q2: top 10 products by revenue, last quarter
SELECT p_id, SUM(qty * price_at_purchase) AS revenue, SUM(qty) AS units
FROM `data-engineering-i2.group2_wh.order_items`
WHERE order_date BETWEEN DATE_SUB(DATE '2026-09-14', INTERVAL 3 MONTH) AND DATE '2026-09-14'
GROUP BY p_id
ORDER BY revenue DESC
LIMIT 10;

-- Q3: average rating of products with more than 50 reviews
-- (review has no date column, so no partitioning is possible here)
SELECT pr.p_id,
       COUNT(*) AS nb_reviews,
       ROUND(AVG(r.rating), 2) AS avg_rating
FROM `data-engineering-i2.group2_wh.product_reviews` AS pr
JOIN `data-engineering-i2.group2_wh.review` AS r USING (review_id)
GROUP BY pr.p_id
HAVING COUNT(*) > 50
ORDER BY avg_rating DESC;

-- Clustering test: one product only
SELECT SUM(qty * price_at_purchase) AS revenue, SUM(qty) AS units
FROM `data-engineering-i2.group2_wh.order_items_pc`
WHERE order_date BETWEEN DATE_SUB(DATE '2026-09-14', INTERVAL 3 MONTH) AND DATE '2026-09-14'
  AND p_id = 'B088BCCTN6';