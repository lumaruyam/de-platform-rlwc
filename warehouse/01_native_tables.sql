-- Step 4: external tables on bronze, then typed native tables.
-- External tables: exact DDL exported from INFORMATION_SCHEMA.TABLES (2026-11-06).
-- Native tables: query rebuilt from the live column types. Bronze stores
-- everything as text and empty values as '', so SAFE_CAST turns '' into NULL
-- (discount_id and payment_id are empty when there is no discount or for PayPal).
SET @@location = 'europe-west1';

-- 1. External tables (read the Parquet files in the bucket, no copy)
CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_orders`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS(
  format = "PARQUET",
  hive_partition_uri_prefix = "gs://data-engineering-i2-group2/bronze/orders/",
  uris = ["gs://data-engineering-i2-group2/bronze/orders/*"]
);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_order_items`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS(
  format = "PARQUET",
  hive_partition_uri_prefix = "gs://data-engineering-i2-group2/bronze/order_items/",
  uris = ["gs://data-engineering-i2-group2/bronze/order_items/*"]
);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_orders_extract`
WITH PARTITION COLUMNS (dt DATE)
OPTIONS(
  format = "PARQUET",
  hive_partition_uri_prefix = "gs://data-engineering-i2-group2/bronze/orders_extract/",
  uris = ["gs://data-engineering-i2-group2/bronze/orders_extract/*"]
);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_review`
OPTIONS(format = "PARQUET", uris = ["gs://data-engineering-i2-group2/bronze/review/*"]);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_product_reviews`
OPTIONS(format = "PARQUET", uris = ["gs://data-engineering-i2-group2/bronze/product_reviews/*"]);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_product`
OPTIONS(format = "PARQUET", uris = ["gs://data-engineering-i2-group2/bronze/product/*"]);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_customer_shipping`
OPTIONS(format = "PARQUET", uris = ["gs://data-engineering-i2-group2/bronze/customer_shipping/*"]);

CREATE OR REPLACE EXTERNAL TABLE `data-engineering-i2.group2_wh.ext_shipping_details`
OPTIONS(format = "PARQUET", uris = ["gs://data-engineering-i2-group2/bronze/shipping_details/*"]);

-- 2. Native tables: same rows, real types, no other change
-- orders is loaded from the step 2 copy (ext_orders), not from orders_extract:
-- in orders_extract, payment_id is FLOAT in some files and INT in others.
CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.orders` AS
SELECT SAFE_CAST(order_id AS INT64)    AS order_id,
       buyer_id,
       SAFE_CAST(discount_id AS INT64) AS discount_id,
       SAFE_CAST(payment_id AS INT64)  AS payment_id,
       dt                              AS order_date
FROM `data-engineering-i2.group2_wh.ext_orders`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.order_items` AS
SELECT SAFE_CAST(order_id AS INT64)            AS order_id,
       p_id,
       SAFE_CAST(qty AS INT64)                 AS qty,
       SAFE_CAST(price_at_purchase AS NUMERIC) AS price_at_purchase,
       dt                                      AS order_date
FROM `data-engineering-i2.group2_wh.ext_order_items`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.review` AS
SELECT SAFE_CAST(review_id AS INT64) AS review_id,
       buyer_id, r_desc, title,
       SAFE_CAST(rating AS INT64)    AS rating,
       seller_product_flag
FROM `data-engineering-i2.group2_wh.ext_review`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.product_reviews` AS
SELECT p_id,
       SAFE_CAST(review_id AS INT64) AS review_id
FROM `data-engineering-i2.group2_wh.ext_product_reviews`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.product` AS
SELECT p_id, p_name, p_desc,
       SAFE_CAST(price AS FLOAT64)     AS price,
       SAFE_CAST(stock_qty AS INT64)   AS stock_qty,
       SAFE_CAST(category_id AS INT64) AS category_id
FROM `data-engineering-i2.group2_wh.ext_product`;

CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.customer_shipping` AS
SELECT SAFE_CAST(address_id AS INT64) AS address_id,
       c_id, is_default
FROM `data-engineering-i2.group2_wh.ext_customer_shipping`;

-- zip and phone stay text: leading zeros and "+" must not be lost.
CREATE OR REPLACE TABLE `data-engineering-i2.group2_wh.shipping_details` AS
SELECT SAFE_CAST(address_id AS INT64) AS address_id,
       street_address, city, state, zip, country, phone
FROM `data-engineering-i2.group2_wh.ext_shipping_details`;