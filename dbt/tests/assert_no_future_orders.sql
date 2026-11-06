{{ config(severity='warn') }}
-- Orders dated after today. The shop's traffic simulator runs its clock ahead of real time
-- (found 2026-11-06: 8,189 orders dated 2026-11-07 to 2026-12-02). Freshness only checks that
-- data is not too old; this test shows the other side. Warn, not error: the orders are real rows.
SELECT order_id, order_date
FROM {{ source('marketplace', 'orders') }}
WHERE order_date > CURRENT_DATE()
