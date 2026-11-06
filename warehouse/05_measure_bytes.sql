-- Step 4: read the bytes processed by our own queries from the job log.
-- cache_hit must be false, otherwise the measure is not valid.
-- tables_read shows when BigQuery rewrote a query to use a materialized view.
SELECT
  FORMAT_TIMESTAMP('%H:%M:%S', creation_time, 'Europe/Paris') AS time_paris,
  ARRAY_TO_STRING(ARRAY(SELECT table_id FROM UNNEST(referenced_tables)), ', ') AS tables_read,
  total_bytes_processed,
  ROUND(total_bytes_processed / 1024 / 1024, 2) AS mib_processed,
  cache_hit
FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
WHERE creation_time > TIMESTAMP '2026-11-06 08:52:00 UTC'
  AND statement_type = 'SELECT'
  AND query NOT LIKE '%INFORMATION_SCHEMA%'
ORDER BY creation_time;