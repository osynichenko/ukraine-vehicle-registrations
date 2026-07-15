#!/bin/bash
DB=tz_registry
DIR=/Users/oleksandr/Documents/CASE2/Cars/CSV

COLS19="person, reg_addr_koatuu, oper_code, oper_name, d_reg, dep_code, dep, brand, model, make_year, color, kind, body, purpose, fuel, capacity, own_weight, total_weight, n_reg_new"

for YEAR in 2019 2020 2021 2022 2023 2024 2025; do
  echo "=== Рік $YEAR ==="
  psql -d $DB -c "TRUNCATE tz_staging;"
  if [ "$YEAR" -le 2020 ]; then
    psql -d $DB -c "\copy tz_staging($COLS19) FROM '$DIR/tz_${YEAR}.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true)"
  else
    psql -d $DB -c "\copy tz_staging FROM '$DIR/tz_${YEAR}.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true)"
  fi
  psql -d $DB -c "INSERT INTO tz_raw SELECT *, $YEAR FROM tz_staging;"
done

echo "=== ЗВІРКА ==="
psql -d $DB -c "SELECT source_year, COUNT(*) FROM tz_raw GROUP BY 1 ORDER BY 1;"
