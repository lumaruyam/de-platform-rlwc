-- Silver must not lose order lines: every distinct (order_id, p_id) in the source reaches gold.
-- The test fails if this query returns a row.
SELECT src.n, gold.n
FROM (SELECT COUNT(DISTINCT FORMAT('%d-%s', order_id, p_id)) AS n
      FROM {{ source('marketplace', 'order_items') }}) AS src,
     (SELECT COUNT(*) AS n FROM {{ ref('fct_order_items') }}) AS gold
WHERE src.n != gold.n
