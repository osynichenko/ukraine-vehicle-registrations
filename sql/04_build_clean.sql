-- Final CREATE

DROP TABLE IF EXISTS tz_clean;

CREATE TABLE tz_clean AS
SELECT
  reg_addr_koatuu                                     AS koatuu,
  oper_code::INT                                      AS oper_code,
  oper_name,
  CASE                                                              -- two formats of date
    WHEN d_reg ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(d_reg, 'DD.MM.YYYY')
    WHEN d_reg ~ '^\d{2}\.\d{2}\.\d{2}$'  THEN to_date(d_reg, 'DD.MM.YY')
  END                                                 AS reg_date,
  brand, model,
  make_year::INT                                      AS make_year,
  color, kind, body, fuel,
  CASE WHEN capacity ~ '^\d+([.,]\d+)?$'                            -- regex filter: everything that
       THEN REPLACE(capacity, ',', '.')::NUMERIC END  AS capacity,  -- not a number → NULL,
  CASE WHEN own_weight ~ '^\d+([.,]\d+)?$'                          -- comma → period
       THEN REPLACE(own_weight, ',', '.')::NUMERIC END AS own_weight,
  n_reg_new,
  source_year
FROM tz_raw;




-- Controls after CREATE

SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE reg_date IS NULL) AS bad_dates FROM tz_clean;


SELECT source_year, EXTRACT(YEAR FROM reg_date) AS reg_year, COUNT(*)
FROM tz_clean GROUP BY source_year, reg_year ORDER BY source_year, reg_year;
