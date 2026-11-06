-- Step 4: partitioned and clustered copies of the fact tables.
-- Partition by month: queries on a date range read only those months.
-- Cluster by p_id: rows of the same product are stored together.
SET @@location = 'europe-west1';

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.orders_p`
PARTITION BY DATE_TRUNC(order_date, MONTH) AS
SELECT * FROM `data-engineering-i2.group2_wh.orders`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.order_items_p`
PARTITION BY DATE_TRUNC(order_date, MONTH) AS
SELECT * FROM `data-engineering-i2.group2_wh.order_items`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.order_items_pc`
PARTITION BY DATE_TRUNC(order_date, MONTH)
CLUSTER BY p_id AS
SELECT * FROM `data-engineering-i2.group2_wh.order_items`;

-- Check: row counts must match the bucket.
SELECT 'orders' AS t, COUNT(*) AS n FROM `data-engineering-i2.group2_wh.orders`
UNION ALL SELECT 'order_items', COUNT(*) FROM `data-engineering-i2.group2_wh.order_items`
UNION ALL SELECT 'review', COUNT(*) FROM `data-engineering-i2.group2_wh.review`
UNION ALL SELECT 'product_reviews', COUNT(*) FROM `data-engineering-i2.group2_wh.product_reviews`
UNION ALL SELECT 'product', COUNT(*) FROM `data-engineering-i2.group2_wh.product`
UNION ALL SELECT 'customer_shipping', COUNT(*) FROM `data-engineering-i2.group2_wh.customer_shipping`
UNION ALL SELECT 'shipping_details', COUNT(*) FROM `data-engineering-i2.group2_wh.shipping_details`;