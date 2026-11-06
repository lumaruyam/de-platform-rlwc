-- Step 9: our own cost alert, run daily by Airflow (task `cost_check`).
-- BigQuery spend of our jobs since the 1st of the month, at the on-demand list price.
-- Above the limit, ERROR() fails the query, so the task fails and the alert callback runs.
DECLARE price_usd_per_tib FLOAT64 DEFAULT 6.25;
DECLARE monthly_limit_usd FLOAT64 DEFAULT 1.0;
DECLARE spent_usd FLOAT64;

SET spent_usd = (
  SELECT IFNULL(SUM(total_bytes_billed), 0) / POW(1024, 4) * price_usd_per_tib
  FROM `region-europe-west1`.INFORMATION_SCHEMA.JOBS_BY_USER
  WHERE creation_time >= TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), MONTH)
    AND job_type = 'QUERY'
);

SELECT
  ROUND(spent_usd, 4) AS usd_month_to_date,
  monthly_limit_usd AS limit_usd,
  IF(spent_usd > monthly_limit_usd,
     ERROR(FORMAT('BigQuery spend this month is %.2f USD, above the %.2f USD limit', spent_usd, monthly_limit_usd)),
     'under limit') AS status;
