{{ config(
    partition_by={'field': 'order_date', 'data_type': 'date', 'granularity': 'month'},
    cluster_by=['p_id', 'country']
) }}
-- GRAIN: one product, in one country, on one day. For the ML team.
SELECT
    {{ dbt_utils.generate_surrogate_key(['p_id', 'country', 'order_date']) }} AS demand_key,
    p_id,
    country,
    order_date,
    SUM(qty) AS units,
    SUM(line_revenue) AS revenue
FROM {{ ref('fct_order_items') }}
GROUP BY p_id, country, order_date
