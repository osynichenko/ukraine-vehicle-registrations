
-- Динаміка категорій по роках (Запит №12)

SELECT d.category,
       c.source_year,
       COUNT(*) AS ops,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY c.source_year), 1) AS pct_of_year
FROM tz_clean c
JOIN oper_directory d ON d.oper_code = c.oper_code
GROUP BY d.category, c.source_year
ORDER BY d.category, c.source_year;




-- Паливо: бензин / дизель / електро

SELECT fuel, COUNT(*) AS total,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM tz_clean GROUP BY fuel ORDER BY total DESC;




-- Розслідування порожнього палива

SELECT kind, COUNT(*) AS cnt FROM tz_clean
WHERE fuel = '' OR fuel IS NULL GROUP BY kind ORDER BY cnt DESC;





-- Розслідування «дивних гібридів» (перевірка назв даними по марках/моделях)

SELECT fuel, brand, model, COUNT(*) AS cnt
FROM tz_clean
WHERE fuel IN ('ЕЛЕКТРО АБО ДИЗЕЛЬНЕ ПАЛИВО', 'БЕНЗИН, ГАЗ АБО ЕЛЕКТРО', 'ГАЗ ТА ЕЛЕКТРО')
GROUP BY fuel, brand, model ORDER BY fuel, cnt DESC LIMIT 30;





-- Кольори
`SELECT color, COUNT(*)...` → лідер **СІРИЙ 4 324 500**, далі ЧОРНИЙ 2 924 735, БІЛИЙ 2 851 013, СИНІЙ 1 690 064, ЧЕРВОНИЙ 1 078 776...





-- Гігієна перед рейтингом: перевірка чистоти brand

SELECT brand, COUNT(*) AS ops FROM tz_clean
WHERE kind = 'ЛЕГКОВИЙ' GROUP BY brand ORDER BY ops DESC LIMIT 30;




-- Топ-3 марки по областях

SELECT region, region_en, brand, ops, place
FROM (
  SELECT r.region, r.region_en, c.brand,
         COUNT(*) AS ops,
         ROW_NUMBER() OVER (PARTITION BY r.region ORDER BY COUNT(*) DESC) AS place
  FROM tz_clean c
  JOIN koatuu_regions r ON r.code2 = LEFT(c.koatuu, 2)
  WHERE c.kind = 'ЛЕГКОВИЙ'
    AND c.koatuu IS NOT NULL AND c.koatuu <> ''
  GROUP BY r.region, r.region_en, c.brand
) t
WHERE place <= 3
ORDER BY region, place;




-- «BA3 ≠ ВАЗ»: омогліфи + LADA

SELECT brand, COUNT(*) FROM tz_clean
WHERE brand IN ('ВАЗ', 'VAZ', 'BA3', 'LADA') GROUP BY brand;


UPDATE tz_clean SET brand = 'ВАЗ' WHERE brand = 'LADA';


SELECT r.region, COUNT(*) AS ops
FROM tz_clean c JOIN koatuu_regions r ON r.code2 = LEFT(c.koatuu, 2)
WHERE r.code2 IN ('01', '85') AND c.kind = 'ЛЕГКОВИЙ'
GROUP BY r.region;




UNION ALL SELECT 'АР Крим', 'Crimea', 'дані відсутні', NULL::BIGINT, 1
UNION ALL SELECT 'м. Севастополь', 'Sevastopol', 'дані відсутні', NULL::BIGINT, 1
ORDER BY region, place;





-- Розслідування «нульового розмитнення» та EV-бум
-- Перевірка — місячний розріз 2022:**

SELECT EXTRACT(MONTH FROM c.reg_date) AS month, COUNT(*) AS ops
FROM tz_clean c
JOIN oper_directory d ON d.oper_code = c.oper_code
WHERE d.category = 'import_used' AND c.source_year = 2022
GROUP BY month ORDER BY month;




-- Електромобілі: динаміка (fuel = 'ЕЛЕКТРО', чисті BEV, легкові)

SELECT source_year, COUNT(*) AS ev_ops
FROM tz_clean
WHERE fuel = 'ЕЛЕКТРО' AND kind = 'ЛЕГКОВИЙ'
GROUP BY source_year ORDER BY source_year;





-- Топ EV-моделей

SELECT brand, model, COUNT(*) AS ops
FROM tz_clean
WHERE fuel = 'ЕЛЕКТРО' AND kind = 'ЛЕГКОВИЙ'
GROUP BY brand, model ORDER BY ops DESC LIMIT 20;




-- made_in_ukraine: «Український автопром — це Skoda і причепи
-- Кардіограма Skoda

SELECT DATE_TRUNC('month', c.reg_date)::date AS month, COUNT(*) AS ops
FROM tz_clean c JOIN oper_directory d ON d.oper_code = c.oper_code
WHERE d.category = 'made_in_ukraine' AND c.brand = 'SKODA'
GROUP BY month ORDER BY month;




