-- Step 7: daily load of new rows from bronze into group2_wh. Run by the Airflow task `load_warehouse`.
-- Idempotent: MERGE inserts only rows whose key is not there yet, so a retry or a rerun adds nothing.

-- 1. Orders, from our extractor (bronze/orders_extract). One row per order_id.
MERGE `data-engineering-i2.group2_wh.orders` AS t
USING (
  SELECT order_id, buyer_id, discount_id, payment_id, dt AS order_date
  FROM `data-engineering-i2.group2_wh.ext_orders_extract`
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY dt DESC) = 1
) AS s
ON t.order_id = s.order_id
WHEN NOT MATCHED THEN
  INSERT (order_id, buyer_id, discount_id, payment_id, order_date)
  VALUES (s.order_id, s.buyer_id, s.discount_id, s.payment_id, s.order_date);

-- 2. Order lines, from Airbyte (bronze/airbyte/order_items). Airbyte has no order date:
--    it comes from the order. Airbyte writes prices as FLOAT64; money is stored as NUMERIC.
MERGE `data-engineering-i2.group2_wh.order_items` AS t
USING (
  SELECT a.order_id, a.p_id, a.qty,
         CAST(ROUND(a.price_at_purchase, 2) AS NUMERIC) AS price_at_purchase,
         o.order_date
  FROM `data-engineering-i2.group2_wh.ext_airbyte_order_items` AS a
  JOIN `data-engineering-i2.group2_wh.orders` AS o USING (order_id)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.order_id, a.p_id ORDER BY a._airbyte_extracted_at DESC) = 1
) AS s
ON t.order_id = s.order_id AND t.p_id = s.p_id
WHEN NOT MATCHED THEN
  INSERT (order_id, p_id, qty, price_at_purchase, order_date)
  VALUES (s.order_id, s.p_id, s.qty, s.price_at_purchase, s.order_date);

-- 3. What the warehouse holds now (shown in the task log).
SELECT
  (SELECT COUNT(*) FROM `data-engineering-i2.group2_wh.orders`)        AS orders,
  (SELECT MAX(order_date) FROM `data-engineering-i2.group2_wh.orders`) AS last_order_date,
  (SELECT COUNT(*) FROM `data-engineering-i2.group2_wh.order_items`)   AS order_items;
