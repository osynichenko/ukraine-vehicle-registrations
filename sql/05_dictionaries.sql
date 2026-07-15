
-- Creating the koatuu_regions directory

CREATE TABLE koatuu_regions (code2 TEXT PRIMARY KEY, region TEXT NOT NULL);
INSERT INTO koatuu_regions VALUES
('01','АР Крим'),('05','Вінницька'),('07','Волинська'),('12','Дніпропетровська'),
('14','Донецька'),('18','Житомирська'),('21','Закарпатська'),('23','Запорізька'),
('26','Івано-Франківська'),('32','Київська'),('35','Кіровоградська'),('44','Луганська'),
('46','Львівська'),('48','Миколаївська'),('51','Одеська'),('53','Полтавська'),
('56','Рівненська'),('59','Сумська'),('61','Тернопільська'),('63','Харківська'),
('65','Херсонська'),('68','Хмельницька'),('71','Черкаська'),('73','Чернівецька'),
('74','Чернігівська'),('80','м. Київ'),('85','м. Севастополь');
```



-- Coverage check

SELECT LEFT(koatuu, 2) AS code2, COUNT(*) AS cnt
FROM tz_clean
WHERE koatuu <> '' AND koatuu IS NOT NULL
  AND LEFT(koatuu, 2) NOT IN (SELECT code2 FROM koatuu_regions)
GROUP BY code2 ORDER BY cnt DESC;


-- English names for Tableau geocoder

ALTER TABLE koatuu_regions ADD COLUMN region_en TEXT;
UPDATE koatuu_regions SET region_en = CASE code2
  WHEN '01' THEN 'Crimea'          WHEN '05' THEN 'Vinnytsia'
  WHEN '07' THEN 'Volyn'           WHEN '12' THEN 'Dnipropetrovsk'
  WHEN '14' THEN 'Donetsk'         WHEN '18' THEN 'Zhytomyr'
  WHEN '21' THEN 'Zakarpattia'     WHEN '23' THEN 'Zaporizhzhia'
  WHEN '26' THEN 'Ivano-Frankivsk' WHEN '32' THEN 'Kyiv Oblast'
  WHEN '35' THEN 'Kirovohrad'      WHEN '44' THEN 'Luhansk'
  WHEN '46' THEN 'Lviv'            WHEN '48' THEN 'Mykolaiv'
  WHEN '51' THEN 'Odesa'           WHEN '53' THEN 'Poltava'
  WHEN '56' THEN 'Rivne'           WHEN '59' THEN 'Sumy'
  WHEN '61' THEN 'Ternopil'        WHEN '63' THEN 'Kharkiv'
  WHEN '65' THEN 'Kherson'         WHEN '68' THEN 'Khmelnytskyi'
  WHEN '71' THEN 'Cherkasy'        WHEN '73' THEN 'Chernivtsi'
  WHEN '74' THEN 'Chernihiv'       WHEN '80' THEN 'Kyiv'
  WHEN '85' THEN 'Sevastopol'
END;


-- Operations Directory oper_directory
-- oper_name is not an identifier

SELECT oper_code, oper_name, COUNT(*) AS cnt
FROM tz_raw 
GROUP BY oper_code, oper_name 
ORDER BY cnt DESC 
LIMIT 25;




SELECT oper_code, oper_name, COUNT(*) AS cnt
FROM tz_clean WHERE oper_code IN (70, 71, 100, 172)
GROUP BY oper_code, oper_name ORDER BY oper_code, cnt DESC;



CREATE TABLE oper_directory AS
SELECT DISTINCT ON (oper_code)
       oper_code,
       oper_name        AS main_name,
       SUM(COUNT(*)) OVER (PARTITION BY oper_code) AS ops,
       NULL::TEXT       AS category
FROM tz_clean
GROUP BY oper_code, oper_name
ORDER BY oper_code, COUNT(*) DESC;      -- the MOST FREQUENT spelling wins




-- How many codes should be marked manually? We measure coverage

SELECT ROUND(SUM(cnt_top) * 100.0 / SUM(cnt_all), 1) AS top20_pct
FROM (
  SELECT COUNT(*) AS cnt_all,
         CASE WHEN oper_code IN (SELECT oper_code FROM tz_clean
                                 GROUP BY oper_code ORDER BY COUNT(*) DESC LIMIT 20)
              THEN COUNT(*) END AS cnt_top
  FROM tz_clean GROUP BY oper_code
) t;




-- Import of manual markup (cycle "data → export → human → import")

CREATE TABLE cat40_staging (oper_code INT, main_name TEXT, ops BIGINT, category TEXT);




-- Verified solutions to disputed codes

SELECT
  CASE
    WHEN source_year - make_year <= 1  THEN '0-1 (нові)'
    WHEN source_year - make_year <= 5  THEN '2-5'
    WHEN source_year - make_year <= 10 THEN '6-10'
    WHEN source_year - make_year <= 20 THEN '11-20'
    ELSE '20+'
  END AS age_group,
  COUNT(*) AS cnt,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM tz_clean WHERE oper_code = 71
GROUP BY age_group ORDER BY MIN(source_year - make_year);




SELECT source_year, COUNT(*) FROM tz_clean WHERE oper_code = 213 GROUP BY source_year;





-- Final category structure (first analytical table of the project)

SELECT category, COUNT(*) AS codes, SUM(ops) AS total_ops,
       ROUND(SUM(ops) * 100.0 / (SELECT SUM(ops) FROM oper_directory), 1) AS pct
FROM oper_directory GROUP BY category ORDER BY total_ops DESC;
