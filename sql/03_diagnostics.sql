
-- Empty values by key columns (by year!)
-- Check both NULL and empty string `''`

SELECT
  source_year,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE d_reg IS NULL OR d_reg = '')                     AS empty_d_reg,
  COUNT(*) FILTER (WHERE oper_code IS NULL OR oper_code = '')             AS empty_oper_code,
  COUNT(*) FILTER (WHERE make_year IS NULL OR make_year = '')             AS empty_make_year,
  COUNT(*) FILTER (WHERE reg_addr_koatuu IS NULL OR reg_addr_koatuu = '') AS empty_koatuu,
  COUNT(*) FILTER (WHERE n_reg_new IS NULL OR n_reg_new = '')             AS empty_plate
FROM tz_raw
GROUP BY source_year ORDER BY source_year;




-- Breakdown by months

SELECT SUBSTRING(d_reg FROM 4 FOR 2) AS month,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE reg_addr_koatuu = '' OR reg_addr_koatuu IS NULL) AS no_koatuu
FROM tz_raw
WHERE source_year = 2020
GROUP BY month ORDER BY month;




-- Breakdown by operations

SELECT oper_code, MIN(oper_name) AS name, COUNT(*) AS no_koatuu
FROM tz_raw
WHERE source_year = 2020 AND (reg_addr_koatuu = '' OR reg_addr_koatuu IS NULL)
GROUP BY oper_code ORDER BY no_koatuu DESC LIMIT 10;




-- Date formats - before converting to DATE you need to know ALL formats

SELECT source_year,
  COUNT(*) FILTER (WHERE d_reg ~ '^\d{2}\.\d{2}\.\d{4}$') AS fmt_yyyy,
  COUNT(*) FILTER (WHERE d_reg ~ '^\d{2}\.\d{2}\.\d{2}$')  AS fmt_yy,
  COUNT(*) FILTER (WHERE d_reg !~ '^\d{2}\.\d{2}\.\d{4}$'
               AND d_reg !~ '^\d{2}\.\d{2}\.\d{2}$')       AS other
FROM tz_raw GROUP BY source_year ORDER BY source_year;




-- Numeric columns: commas, garbage

SELECT
  COUNT(*) FILTER (WHERE make_year !~ '^\d{4}$')                                            AS bad_make_year,
  COUNT(*) FILTER (WHERE capacity   LIKE '%,%')                                             AS comma_capacity,
  COUNT(*) FILTER (WHERE own_weight LIKE '%,%')                                             AS comma_own_weight,
  COUNT(*) FILTER (WHERE capacity !~ '^\d+([.,]\d+)?$'   AND capacity <> ''   AND capacity IS NOT NULL)   AS weird_capacity,
  COUNT(*) FILTER (WHERE own_weight !~ '^\d+([.,]\d+)?$' AND own_weight <> '' AND own_weight IS NOT NULL) AS weird_own_weight
FROM tz_raw;







