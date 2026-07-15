# 📗 Детальний Handbook проєкту «Реєстрації транспортних засобів України 2019–2025»
### Повний покроковий опис: що робили, навіщо, яким SQL і що це дало

**Стан на:** 10 липня 2026
**Середовище:** PostgreSQL 18 (Homebrew, macOS Apple Silicon) · pgAdmin 4 · psql · Tableau Public
**База:** `tz_registry`
**Джерело:** data.gov.ua → «Відомості про транспортні засоби та їх власників», МВС України
**Обсяг:** 7 річних CSV (2019–2025), ~5 ГБ, **14 497 205 рядків**

> Формат кожного кроку: **Навіщо** (мотивація) → **Як** (команда/SQL) → **Результат** → **Вплив на проєкт**.

---

# ЧАСТИНА 0. Вибір датасету і перший контакт із даними

## Крок 0.1. Чому саме цей датасет
**Навіщо:** для другого портфоліо-кейсу потрібні були дані: (а) реальні й «живі», а не навчальні; (б) великі (мільйони рядків — привід для СУБД, а не Excel); (в) з потенціалом сторітелінгу. Реєстр МВС дає все одразу: смаки українців в авто (марки, пальне, кольори, регіони) + слід двох криз — COVID і повномасштабної війни.

**Вплив:** сформульована головна тема проєкту — «автомобільні смаки українців і як їх змінили пандемія та війна».

## Крок 0.2. Перша спроба відкрити CSV у RStudio — і чому вона провалилась
**Що сталося:** `read.csv("tz_2022.csv")` прочитав файл як **одну колонку** (`'data.frame': 1746702 obs. of 1 variable`), а `subset(select = -OPER_NAME)` впав із помилкою `object 'OPER_NAME' not found`.

**Причина:** файл розділений **крапкою з комою `;`**, а `read.csv` за замовчуванням чекає кому. Вся шапка склеїлась в одне довге ім'я колонки, кожен рядок — в один довгий текст. Колонки `OPER_NAME` не існувало — існувала одна колонка-монстр.

**Урок:** перш ніж читати файл будь-яким інструментом — подивитись на його сирий вміст (роздільник, лапки, кодування). Прев'ю Finder «бреше на користь» — він сам вгадує роздільник.

**Вплив:** рішення перейти на PostgreSQL — і за масштабом даних, і для розвитку SQL-навичок після BigQuery у першому кейсі.

## Крок 0.3. Звірка структури всіх файлів БЕЗ їх відкриття
**Навіщо:** файли 600–800 МБ; відкривати їх цілком для перевірки шапки — марнування часу й пам'яті. Якщо структура між роками різна, UNION-об'єднання мовчки переплутає дані.

```bash
head -1 tz_2019.csv    # ... і так для кожного з 7 файлів
wc -l tz_*.csv         # кількість рядків = майбутній еталон звірки
file -I tz_*.csv       # кодування (очікуємо utf-8; кирилиця!)
```

**Результат:**
- Шапки 2021–2025 ідентичні: 20 колонок, роздільник `;`, значення в лапках.
- **2019–2020 — лише 19 колонок: немає `VIN`** (його додали у 2021).
- Кодування скрізь UTF-8.
- `wc -l` дав еталонні числа (див. Крок 3.4).

**Вплив:** (1) план завантаження з двома варіантами `\copy`; (2) поява «еталона звірки» — центрального механізму контролю якості всього ETL.

---

# ЧАСТИНА 1. Середовище: сага про три PostgreSQL

## Крок 1.1. Симптом: pgAdmin не підключається
`Connection refused` → **сервер не запущений**. pgAdmin через «Register – Server» НЕ створює сервер — лише підключається до вже працюючого процесу.

## Крок 1.2. Діагностика «хто на порту»
```bash
lsof -i :5432                 # хто взаємодіє з портом (свої процеси)
sudo lsof -i :5432 -sTCP:LISTEN   # хто РЕАЛЬНО слухає порт (усі процеси!)
brew services list            # стан brew-сервісів
ls /Library/LaunchDaemons/ | grep -i postgres   # автозапуск старих EDB-інсталяцій
```
**Знахідки:** у системі жили залишки EDB-інсталяцій PostgreSQL 14/17/18 (`/Library/PostgreSQL`, LaunchDaemons `postgresql-14.plist`, `postgresql-18.plist`). Після перезавантаження Mac вони перехоплювали порт 5432 і вимагали давно забутий пароль. Без `sudo` слухач від чужого користувача взагалі не видно — тому здавалося, що «порт порожній, але пароль хтось питає».

## Крок 1.3. Уроки-симптоми (шпаргалка діагнозів)
| Повідомлення | Діагноз |
|---|---|
| `Connection refused` | сервер не запущений |
| `password authentication failed` | відповідає НЕ той сервер (чужий кластер зі своїм паролем) |
| `role "postgres" does not exist` | brew-інсталяція: суперюзер = маковський користувач, а не postgres |
| Таблиця «є», але порожня | незакомічена транзакція в іншому інструменті (див. Крок 7.2) |

## Крок 1.4. Чисте рішення
```bash
# вимкнути старі демони EDB
sudo launchctl bootout system /Library/LaunchDaemons/postgresql-14.plist
sudo launchctl bootout system /Library/LaunchDaemons/postgresql-18.plist
# TCC-захист macOS блокує rm -rf /Library/PostgreSQL навіть під sudo →
# System Settings → Privacy & Security → Full Disk Access для Terminal → перезапуск Terminal

brew install postgresql@18
echo 'export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
brew services start postgresql@18

createuser -s postgres     # для сумісності з pgAdmin/туторіалами
createdb tz_registry
psql -l                    # контроль: список баз, без пароля
```
**Вплив:** стабільне середовище; у pgAdmin підключення `127.0.0.1:5432`, користувач `postgres` (або `oleksandr`), без пароля. Побічний урок — записи «PostgreSQL 14/18» у дереві pgAdmin — це закладки з'єднань, а не інсталяції.

## Крок 1.5. Дрібні звички psql, які заощадили нерви
- `(END)` унизу = пейджер; вихід — клавіша **q**.
- Запрошення `tz_registry-#` (дефіс!) = команда не завершена, psql чекає `;`. Скинути — **Ctrl+C**. Саме так «TRUNCATE без крапки з комою» одного разу зробив вигляд, що виконався.
- `\copy` — команда **psql**, живе ОДНИМ рядком; у pgAdmin не працює (там Import/Export Data або чистий SQL).
- `\o file` теж лише для psql; надійніший експорт запиту: `\copy (SELECT ...) TO 'file.csv' WITH (FORMAT csv, HEADER true)`.

---

# ЧАСТИНА 2. Архітектура даних: три шари

## Крок 2.1. Проєктування
```
CSV (7 файлів)
   │  \copy (клієнтське копіювання, все TEXT)
   ▼
tz_staging (20 колонок TEXT)      ← тимчасовий буфер, 1 файл за раз
   │  INSERT ... SELECT *, <рік>
   ▼
tz_raw (20 TEXT + source_year INT) ← сирий шар: ДЗЕРКАЛО джерела, недоторканне
   │  CREATE TABLE ... AS SELECT (типізація + чистка ЗНАЧЕНЬ, не рядків)
   ▼
tz_clean (14 типізованих колонок)  ← аналітичний шар: усі запити ходять сюди
```

**Навіщо саме так:**
- **Все TEXT у raw** → `\copy` ніколи не падає на битих значеннях (`-1130`, коми в дробах, будь-що). Якби типізували одразу — COPY зупинявся б на першому ж «abc» у числовій колонці.
- **source_year** — мітка походження рядка. Саме вона двічі зловила помилки завантаження (див. 3.2, 3.3).
- **Рядки не видаляються ніколи.** Биті значення стають NULL; рядок лишається (урок Cyclistic: «глобальний фільтр» там колись викинув 1.2 млн валідних рядків).

## Крок 2.2. DDL
```sql
CREATE TABLE tz_staging (
    person TEXT, reg_addr_koatuu TEXT, oper_code TEXT, oper_name TEXT,
    d_reg TEXT, dep_code TEXT, dep TEXT, brand TEXT, model TEXT,
    vin TEXT, make_year TEXT, color TEXT, kind TEXT, body TEXT,
    purpose TEXT, fuel TEXT, capacity TEXT, own_weight TEXT,
    total_weight TEXT, n_reg_new TEXT
);

CREATE TABLE tz_raw (
    person TEXT, reg_addr_koatuu TEXT, oper_code TEXT, oper_name TEXT,
    d_reg TEXT, dep_code TEXT, dep TEXT, brand TEXT, model TEXT,
    vin TEXT, make_year TEXT, color TEXT, kind TEXT, body TEXT,
    purpose TEXT, fuel TEXT, capacity TEXT, own_weight TEXT,
    total_weight TEXT, n_reg_new TEXT,
    source_year INT
);
```

---

# ЧАСТИНА 3. ETL: завантаження семи років (включно з двома повчальними провалами)

## Крок 3.1. Правильний цикл (фінальна версія)
Для КОЖНОГО року, строго по черзі, з перевіркою після кожної команди:
```sql
TRUNCATE tz_staging;                            -- 1) чистимо буфер (ЗАВЖДИ перед COPY!)
```
```
\copy tz_staging FROM '/шлях/tz_2022.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true)
```
```sql
INSERT INTO tz_raw SELECT *, 2022 FROM tz_staging;   -- 3) переливаємо з міткою року
```
**Контроль:** число `INSERT 0 N` **мусить дорівнювати** числу `COPY N`. Не дорівнює → стоп, розслідування.

**Для 2019–2020 (19 колонок, без VIN)** — `\copy` зі СПИСКОМ колонок; пропущений `vin` отримує NULL:
```
\copy tz_staging(person, reg_addr_koatuu, oper_code, oper_name, d_reg, dep_code, dep, brand, model, make_year, color, kind, body, purpose, fuel, capacity, own_weight, total_weight, n_reg_new) FROM '/шлях/tz_2019.csv' WITH (FORMAT csv, DELIMITER ';', HEADER true)
```
Без списку COPY впав би: 19 значень у файлі проти 20 колонок таблиці (`missing data for column "n_reg_new"`).

## Крок 3.2. Провал №1 (навчальний): «усі роки стали 2022-м»
**Що зробили не так:** виконали ЧОТИРИ `\copy` підряд (без проміжних INSERT), потім перший `INSERT ... , 2022`.
**Що сталося:** staging накопичив усі роки (сума COPY = 8 445 088 — це видно було по `INSERT 0 8445088`), і всі вони отримали мітку 2022. Наступні INSERT'и чесно вставили нуль.
**Як зловили:** звірка `SELECT source_year, COUNT(*) ... GROUP BY source_year` показала один рядок «2022 | 8 445 088».
**Лікування:** `TRUNCATE tz_raw;` і перезаливка правильним циклом.

## Крок 3.3. Провал №2 (навчальний): «кумулятивні дублі»
**Що зробили не так:** цикл COPY→INSERT відновили, але забули `TRUNCATE tz_staging` МІЖ роками.
**Що сталося:** кожен INSERT переливав новий рік ПЛЮС усі попередні: 2023 = 2022+2023 (3 870 640), 2025 = усі чотири (8 445 088). Патерн видно миттєво: числа звірки — це наростаючі суми.
**Висновок-правило:** **TRUNCATE ставиться ПЕРЕД COPY**, а не після INSERT — тоді забудькуватість не страшна: буфер завжди чистий на старті циклу.

## Крок 3.4. Фінальна звірка (еталон = wc -l мінус 1 шапка)
```sql
SELECT source_year, COUNT(*) FROM tz_raw GROUP BY source_year ORDER BY source_year;
```
| Рік | Рядків | Збіг із файлом |
|---|---|---|
| 2019 | 2 079 481 | ✅ |
| 2020 | 1 771 329 | ✅ |
| 2021 | 2 201 307 | ✅ |
| 2022 | 1 745 908 | ✅ |
| 2023 | 2 124 732 | ✅ |
| 2024 | 2 344 544 | ✅ |
| 2025 | 2 229 904 | ✅ |
| **Σ** | **14 497 205** | ✅ |

**Контроль VIN** (перевірка, що список колонок для 2019–2020 спрацював як задумано):
```sql
SELECT source_year, COUNT(*) AS total, COUNT(vin) AS vin_not_null
FROM tz_raw GROUP BY source_year ORDER BY source_year;
-- 2019–2020: vin_not_null = 0 (NULL за визначенням джерела); 2021–2025: повне покриття
```

## Крок 3.5. Bash-скрипт (автоматизація як бонус, не заміна розуміння)
Методологічне рішення: для навчального кейсу основний шлях — ручне покомандне виконання (розуміння кожного кроку), а скрипт `load_tz.sh` — демонстрація автоматизації в репозиторії:
```bash
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
psql -d $DB -c "SELECT source_year, COUNT(*) FROM tz_raw GROUP BY 1 ORDER BY 1;"
```

---

# ЧАСТИНА 4. Діагностика якості даних (на tz_raw, ДО типізації)

> Принцип: спочатку дивимось і рахуємо, нічого не змінюючи. Кожен запит — відповідь на конкретне «а чи не зламає нам це типізацію/аналіз?»

## Крок 4.1. Порожні значення по ключових колонках (по роках!)
**Навіщо:** зрозуміти, чи можна довіряти колонкам, і чи пропуски рівномірні (шум) або сконцентровані (системна дірка). Перевіряємо і NULL, і порожній рядок `''` — різні інструменти читають порожнечу по-різному (урок Cyclistic: R бачив "", BigQuery бачив NULL).
```sql
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
```
**Результат:**
- `d_reg`, `oper_code`, `make_year` — **нуль порожніх** в усіх роках (несподівано чисто для держреєстру).
- `n_reg_new` — ~13–34 тис./рік (~1–1.5%): нормально, не всі операції видають номер (зняття з обліку тощо).
- **`reg_addr_koatuu` у 2020 — 404 584 порожніх (~23% року!)** при 0–8 в інших роках → системна дірка, розслідування у Кроці 4.2.

## Крок 4.2. Розслідування дірки KOATUU-2020
**Навіщо:** перш ніж вирішувати «що робити з пропусками», треба зрозуміти їхню ПРИРОДУ: вони випадкові чи структуровані (в часі? по операціях? по регіонах?).

**(а) Розріз по місяцях:**
```sql
SELECT SUBSTRING(d_reg FROM 4 FOR 2) AS month,
       COUNT(*) AS total,
       COUNT(*) FILTER (WHERE reg_addr_koatuu = '' OR reg_addr_koatuu IS NULL) AS no_koatuu
FROM tz_raw
WHERE source_year = 2020
GROUP BY month ORDER BY month;
```
| Місяць | Всього | Без KOATUU |
|---|---|---|
| 01 | 156 399 | 29 |
| 02 | 157 387 | 33 |
| 03 | 91 888 | 526 |
| **04** | **6 984** | 1 600 |
| 05 | 127 677 | 32 591 |
| 06 | 165 373 | 46 398 |
| 07 | 202 252 | 59 773 |
| 08 | 163 785 | 49 401 |
| 09 | 182 406 | 54 532 |
| 10 | 184 050 | 55 427 |
| 11 | 154 240 | 47 911 |
| 12 | 178 888 | 56 363 |

**Дві знахідки в одному запиті:**
1. **Дірка KOATUU має чіткий старт — травень 2020** (січень–лютий чисті, з травня стабільно 25–30% щомісяця до кінця року; у 2021 знову 0). Це збій/зміна на боці джерела, не випадковість.
2. **Бонус, якого не шукали: квітень 2020 — 6 984 операції проти звичайних 150–200 тис.** Провал у 20+ разів = слід першого жорсткого COVID-локдауну (сервісні центри МВС фактично стояли). Датасет фіксує ДВІ кризи — пандемію і війну.

**(б) Розріз по операціях:**
```sql
SELECT oper_code, MIN(oper_name) AS name, COUNT(*) AS no_koatuu
FROM tz_raw
WHERE source_year = 2020 AND (reg_addr_koatuu = '' OR reg_addr_koatuu IS NULL)
GROUP BY oper_code ORDER BY no_koatuu DESC LIMIT 10;
```
**Результат:** топ «безадресних» кодів повторює загальний топ операцій → пропуски розмазані пропорційно, до типу операції не прив'язані.

**Методологічне рішення (у README):** рядки НЕ видаляємо (для аналізу марок/операцій/віку вони повноцінні); регіональний аналіз 2020 року ведеться по ~77% покриття З ЯВНИМ ЗАСТЕРЕЖЕННЯМ.

## Крок 4.3. Формати дат
**Навіщо:** перед конвертацією в DATE треба знати ВСІ формати, інакше `to_date` або впаде, або (гірше) мовчки збреше.
```sql
SELECT source_year,
  COUNT(*) FILTER (WHERE d_reg ~ '^\d{2}\.\d{2}\.\d{4}$') AS fmt_yyyy,
  COUNT(*) FILTER (WHERE d_reg ~ '^\d{2}\.\d{2}\.\d{2}$')  AS fmt_yy,
  COUNT(*) FILTER (WHERE d_reg !~ '^\d{2}\.\d{2}\.\d{4}$'
               AND d_reg !~ '^\d{2}\.\d{2}\.\d{2}$')       AS other
FROM tz_raw GROUP BY source_year ORDER BY source_year;
```
**Результат:** ідеально чистий розріз — **2019–2022: `dd.mm.yyyy`; 2023–2025: `dd.mm.yy`; other = 0 скрізь.** МВС змінило формат вивантаження між 2022 і 2023. Двогілковий CASE закриває 100% рядків.

## Крок 4.4. Числові колонки: коми, сміття
```sql
SELECT
  COUNT(*) FILTER (WHERE make_year !~ '^\d{4}$')                                            AS bad_make_year,
  COUNT(*) FILTER (WHERE capacity   LIKE '%,%')                                             AS comma_capacity,
  COUNT(*) FILTER (WHERE own_weight LIKE '%,%')                                             AS comma_own_weight,
  COUNT(*) FILTER (WHERE capacity !~ '^\d+([.,]\d+)?$'   AND capacity <> ''   AND capacity IS NOT NULL)   AS weird_capacity,
  COUNT(*) FILTER (WHERE own_weight !~ '^\d+([.,]\d+)?$' AND own_weight <> '' AND own_weight IS NOT NULL) AS weird_own_weight
FROM tz_raw;
```
**Результат:** `bad_make_year = 0`; коми лише в `own_weight` — **8 435** значень типу `105,5` (українська локаль: кома як десятковий роздільник); «дивних» значень 2 — обидва **`-1130`** (від'ємна вага = фізичне сміття → підуть у NULL).
**Перша зустріч із цією проблемою:** перший CREATE tz_clean впав з `invalid input syntax for type numeric: "105,5"` — так кома і була знайдена.

---

# ЧАСТИНА 5. Побудова tz_clean (типізація)

## Крок 5.1. Фінальний CREATE (з усіма загартуваннями з діагностики)
```sql
DROP TABLE IF EXISTS tz_clean;

CREATE TABLE tz_clean AS
SELECT
  reg_addr_koatuu                                     AS koatuu,
  oper_code::INT                                      AS oper_code,
  oper_name,
  CASE                                                              -- два формати дат (Крок 4.3)
    WHEN d_reg ~ '^\d{2}\.\d{2}\.\d{4}$' THEN to_date(d_reg, 'DD.MM.YYYY')
    WHEN d_reg ~ '^\d{2}\.\d{2}\.\d{2}$'  THEN to_date(d_reg, 'DD.MM.YY')
  END                                                 AS reg_date,
  brand, model,
  make_year::INT                                      AS make_year,
  color, kind, body, fuel,
  CASE WHEN capacity ~ '^\d+([.,]\d+)?$'                            -- regex-фільтр: усе, що
       THEN REPLACE(capacity, ',', '.')::NUMERIC END  AS capacity,  -- не число → NULL,
  CASE WHEN own_weight ~ '^\d+([.,]\d+)?$'                          -- кома → крапка
       THEN REPLACE(own_weight, ',', '.')::NUMERIC END AS own_weight,
  n_reg_new,
  source_year
FROM tz_raw;
```
**Пояснення рішень:**
- CASE навколо `::NUMERIC` — щоб «-1130» та будь-яке майбутнє сміття ставали NULL, а не валили CREATE на 14.5 млн рядків.
- `to_date(..., 'DD.MM.YY')` трактує «23» як 2023 — для періоду 2019–2025 коректно.
- Колонки, що свідомо НЕ увійшли: `person, dep_code, dep, vin, purpose, total_weight` (не потрібні аналізу; лишаються в tz_raw — «видалення» без втрати сирих даних; це і є відповідь на первісне бажання «повидаляти стовпчики»).

## Крок 5.2. Контролі після CREATE
```sql
SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE reg_date IS NULL) AS bad_dates FROM tz_clean;
-- 14 497 205 | 0    → жодна дата не втрачена

SELECT source_year, EXTRACT(YEAR FROM reg_date) AS reg_year, COUNT(*)
FROM tz_clean GROUP BY source_year, reg_year ORDER BY source_year, reg_year;
-- ІДЕАЛЬНА ДІАГОНАЛЬ: у кожному файлі лише дати свого року.
-- Висновки: (а) записів «заднім числом» немає; (б) source_year підтверджено незалежним шляхом.
```

---

# ЧАСТИНА 6. Довідник регіонів koatuu_regions

## Крок 6.1. Контекст класифікаторів (для README)
Поле джерела — `REG_ADDR_KOATUU`, 10-значні коди **КОАТУУ** (Класифікатор адміністративно-територіального устрою України). З 26.11.2020 його офіційно замінив **КАТОТТГ** (коди формату `UA` + 17 цифр), але МВС продовжує вивантажувати старі КОАТУУ-коди. **Ключовий факт: перші 2 цифри = область, і вони збігаються в обох системах** → `LEFT(koatuu, 2)` коректний для всього періоду.

## Крок 6.2. Створення довідника
```sql
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

## Крок 6.3. Перевірка покриття (обов'язкова для будь-якого довідника!)
**Навіщо:** JOIN мовчки ВИКИДАЄ рядки, що не знайшли пару. Треба знати заздалегідь, скільки й чого втрачаємо.
```sql
SELECT LEFT(koatuu, 2) AS code2, COUNT(*) AS cnt
FROM tz_clean
WHERE koatuu <> '' AND koatuu IS NOT NULL
  AND LEFT(koatuu, 2) NOT IN (SELECT code2 FROM koatuu_regions)
GROUP BY code2 ORDER BY cnt DESC;
```
**Результат:** поза довідником лише префікс **`52`** — **18 рядків** з ~14 млн. Коду 52 в КОАТУУ не існує (51 Одеська, 53 Полтавська, 52 — пропуск) → операторські одруківки → у регіональному аналізі unknown. Покриття ≈ 100%.

## Крок 6.4. Англійські назви для геокодера Tableau (додано на етапі мапи)
```sql
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
```
Українська назва — підписи на графіках; англійська — розпізнавання геокодером (Geographic Role → State/Province).

## Крок 6.5. Альтернативне джерело регіону (ідея на майбутнє, НЕ реалізовано)
Перші 2 літери номерного знака (`n_reg_new`) = регіон видачі номера. Задокументовані підводні камені: (а) колізії серій між поколіннями (напр., `КК` = Крим у серії-2013 і м. Київ у серії-2021 — омонім без дати видачі не розв'язується); (б) з 2015+ авто реєструють у будь-якому ТСЦ → префікс каже, ДЕ видано номер, а не де живе власник (КОАТУУ ↔ префікс вимірюють різні речі — а їхня розбіжність сама по собі потенційний сигнал релокації); (в) ~1–1.5% операцій без номера.

---

# ЧАСТИНА 7. Довідник операцій oper_directory: головна методологічна битва проєкту

## Крок 7.1. Відкриття проблеми: oper_name — не ідентифікатор
Перший же огляд операцій:
```sql
SELECT oper_code, oper_name, COUNT(*) AS cnt
FROM tz_raw GROUP BY oper_code, oper_name ORDER BY cnt DESC LIMIT 25;
```
показав: **один код має КІЛЬКА варіантів написання назви** (код 308 — два, код 100 — з різницею «ТОРГІВЕЛЬНІЙ»/«ТОРГОВЕЛЬНІЙ», код 70 — три варіанти, частина БЕЗ маркера «Б/В»). Причина — різні роки/вивантаження джерела.
**Правило проєкту №1: групуємо ТІЛЬКИ по oper_code; oper_name — коментар.**

## Крок 7.2. Хибний старт №1: пастка MIN(oper_name)
Перший експорт довідника робився як `SELECT oper_code, MIN(oper_name) AS sample_name, ...` — а `MIN` текстів повертає **алфавітно перший** варіант. Для кодів 70 і 100 «виграв» варіант без «Б/В» → при ручній розмітці ці коди (насправді б/в імпорт!) були помилково зараховані до «нових авто», а категорія import_used лишилась майже порожньою. Помилку виявило порівняння з повним списком варіантів назв:
```sql
SELECT oper_code, oper_name, COUNT(*) AS cnt
FROM tz_clean WHERE oper_code IN (70, 71, 100, 172)
GROUP BY oper_code, oper_name ORDER BY oper_code, cnt DESC;
```
**Урок:** агрегат `MIN/MAX` від тексту — лотерея, а не «репрезентативна назва».

**Побічний казус цього ж етапу:** таблиця, створена в pgAdmin Query Tool, виглядала порожньою з psql — **незакомічена транзакція** pgAdmin. Правило: DDL робимо в одному інструменті за раз; у pgAdmin стежимо за Commit.

## Крок 7.3. Правильний механізм: найчастіша назва через DISTINCT ON
```sql
CREATE TABLE oper_directory AS
SELECT DISTINCT ON (oper_code)
       oper_code,
       oper_name        AS main_name,
       SUM(COUNT(*)) OVER (PARTITION BY oper_code) AS ops,
       NULL::TEXT       AS category
FROM tz_clean
GROUP BY oper_code, oper_name
ORDER BY oper_code, COUNT(*) DESC;      -- перемагає НАЙЧАСТІШЕ написання
-- SELECT 145  (145 унікальних кодів)
```
**Як це працює:** `GROUP BY oper_code, oper_name` рахує частоту кожного ВАРІАНТА назви; `DISTINCT ON (oper_code)` лишає один рядок на код — перший після сортування, тобто найчастіший варіант; віконна `SUM(...) OVER (PARTITION BY oper_code)` дає повну кількість операцій коду по всіх варіантах разом. Контроль: код 70 у довіднику тепер «РЕЄСТРАЦIЯ **Б/В** ТЗ ПРИВЕЗЕНОГО З-ЗА КОРДОНУ ПО ВМД».

## Крок 7.4. Скільки кодів розмічати вручну? Вимірюємо покриття
```sql
SELECT ROUND(SUM(cnt_top) * 100.0 / SUM(cnt_all), 1) AS top20_pct
FROM (
  SELECT COUNT(*) AS cnt_all,
         CASE WHEN oper_code IN (SELECT oper_code FROM tz_clean
                                 GROUP BY oper_code ORDER BY COUNT(*) DESC LIMIT 20)
              THEN COUNT(*) END AS cnt_top
  FROM tz_clean GROUP BY oper_code
) t;
-- 93.0  → топ-20 кодів = 93% операцій; топ-40 ≈ 97%
```
**Рішення:** вручну розмічається топ-40; хвіст (105 дрібних кодів, сумарно 1.2%) → `other`. Групування НЕ знищує деталі: oper_code лишається в даних, будь-коли можна провалитись назад.

## Крок 7.5. Імпорт ручної розмітки (цикл «дані → експорт → людина → імпорт»)
```sql
CREATE TABLE cat40_staging (oper_code INT, main_name TEXT, ops BIGINT, category TEXT);
```
```
\copy cat40_staging FROM '/шлях/oper_categories.csv' WITH (FORMAT csv, HEADER true)   -- COPY 40
```
```sql
UPDATE oper_directory d
SET category = TRIM(c.category)          -- TRIM: у CSV був пробіл ПЕРЕД " diia"
FROM cat40_staging c
WHERE d.oper_code = c.oper_code;          -- UPDATE 40

UPDATE oper_directory SET category = 'other' WHERE category IS NULL;   -- UPDATE 105
```
**Пастки цього кроку, які реально стріляли:** невидимі пробіли в категоріях (лікуємо TRIM завжди); службовий перший рядок у CSV з Numbers (HEADER true пропускає лише ОДИН рядок); дві копії файлу в різних папках (UPDATE 0 як симптом «редагував не той файл» — див. 7.6).

## Крок 7.6. Верифіковані рішення по спірних кодах
**Код 71 «по посвідченню митниці» (1 109 291 операція — №3 у реєстрі).** Назва не каже новий/б-в. Відповіли ДАНИМИ — розподіл віку авто на момент реєстрації:
```sql
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
```
| Вік | К-сть | % |
|---|---|---|
| 0–1 (нові) | 18 637 | 1.7 |
| 2–5 | 261 381 | 23.6 |
| 6–10 | 327 383 | 29.5 |
| 11–20 | 451 528 | 40.7 |
| 20+ | 50 362 | 4.5 |

70%+ авто віком 6–20 років → **import_used**. Тріангуляція другим незалежним джерелом: стаття МВС від 06.08.2024 (з ~250 тис. первинних реєстрацій за пів року нових лише 86 тис.). `UPDATE oper_directory SET category='import_used' WHERE oper_code = 71;`

**Код 314 «перереєстрація через електронні сервіси» (425 815, з 2023).** Виділений в окрему категорію **diia** — маркер діджиталізації. ВАЖЛИВО: віковий тест тут НЕ застосовний (це перереєстрація — на вторинному ринку авто старі за визначенням, це не імпорт!). Методологічний наслідок: у трендах вторинного ринку рахувати **ownership_change + diia**, інакше 2023+ виглядатиме як «падіння» перереєстрацій, хоча вони просто перетекли в онлайн.

**Код 213 «тимчасовий облік на період воєнного стану» (62 664).** Гіпотеза «не існував до 2022» (умовивід із назви) формально ПЕРЕВІРЕНА даними:
```sql
SELECT source_year, COUNT(*) FROM tz_clean WHERE oper_code = 213 GROUP BY source_year;
-- first_year = 2022; у 2019–2021 — нуль. ✅ Перша підтверджена гіпотеза проєкту.
```

## Крок 7.7. Фінальна структура категорій (перша аналітична таблиця проєкту)
```sql
SELECT category, COUNT(*) AS codes, SUM(ops) AS total_ops,
       ROUND(SUM(ops) * 100.0 / (SELECT SUM(ops) FROM oper_directory), 1) AS pct
FROM oper_directory GROUP BY category ORDER BY total_ops DESC;
```
| Категорія | Кодів | Операцій | % |
|---|---|---|---|
| ownership_change | 9 | 7 013 277 | 48.4 |
| import_used | 3 | 2 811 193 | 19.4 |
| new_vehicle | 3 | 978 439 | 6.7 |
| proper_user | 1 | 897 705 | 6.2 |
| car_conversion | 3 | 432 260 | 3.0 |
| diia | 1 | 425 815 | 2.9 |
| plate_change | 1 | 275 282 | 1.9 |
| abroad_travel | 2 | 258 066 | 1.8 |
| registration_lost | 1 | 200 079 | 1.4 |
| other | 105 | 170 219 | 1.2 |
| personality_change | 2 | 150 239 | 1.0 |
| uniq_plate | 2 | 145 409 | 1.0 |
| car_scrappage | 1 | 144 765 | 1.0 |
| temp_registration | 2 | 108 632 | 0.7 |
| made_in_ukraine | 1 | 97 874 | 0.7 |
| registration_change | 1 | 94 822 | 0.7 |
| wartime | 2 | 84 197 | 0.6 |
| proper_user_remove | 1 | 83 746 | 0.6 |
| leasing | 1 | 61 648 | 0.4 |
| car_credentials_update | 1 | 26 122 | 0.2 |
| color_change | 1 | 20 054 | 0.1 |
| new_moped | 1 | 17 362 | 0.1 |

**Інсайт №1 проєкту:** вторинний ринок (ownership_change + diia) = **51.3%** усіх операцій; вживаний імпорт **утричі** перевищує реєстрації нових авто (19.4% проти 6.7%).

---

# ЧАСТИНА 8. Перший великий JOIN: динаміка категорій по роках (Запит №12)

```sql
SELECT d.category,
       c.source_year,
       COUNT(*) AS ops,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY c.source_year), 1) AS pct_of_year
FROM tz_clean c
JOIN oper_directory d ON d.oper_code = c.oper_code
GROUP BY d.category, c.source_year
ORDER BY d.category, c.source_year;
```
**Механіка:** JOIN 14.5 млн рядків × довідник 145; `pct_of_year` через вікно `PARTITION BY source_year` — частка категорії всередині СВОГО року (чесніше за абсолюти, бо 2020 і 2022 самі по собі менші).

**Результат: 141 рядок (не 154 = 22×7!).** Відсутні комбінації — це категорії, яких не існувало в тому році (wartime з 2022, diia з 2023). **Відсутність рядка — теж дані.**

**Перші сигнали (з видимої частини):**
- `abroad_travel`: 2019: 25 959 → 2021: 21 601 → **2022: 48 301 → 2023: 57 863** (подвоєння: виїзд/евакуація) → 2024–2025 спад до ~42 тис.
- `car_conversion`: **2019: 174 636 → 2020: 48 761** і далі 27–58 тис. — обвал хвилі переобладнання на ГБО після 2019 (кандидат на окреме розслідування).

**Статус:** дані експортовано в CSV; візуалізація (три аркуші: лінії топ-категорій із групуванням, теплова карта категорія×рік, індекс 2019=100 через LOOKUP) — у черзі.

---

# ЧАСТИНА 9. Побічні дослідження (профілювання «смакових» колонок)

## Крок 9.1. Паливо: від трьох WHERE-запитів до GROUP BY
Початкове питання «скільки бензинових / дизельних / електро» розв'язане одним запитом замість трьох:
```sql
SELECT fuel, COUNT(*) AS total,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM tz_clean GROUP BY fuel ORDER BY total DESC;
```
**Результат: 14 значень** — БЕНЗИН 5 719 848 (39.45%), ДИЗЕЛЬНЕ ПАЛИВО 4 926 725 (33.98%), БЕНЗИН АБО ГАЗ 2 480 077 (17.11%), порожнє 631 653 (4.36%), ЕЛЕКТРО 428 523 (2.96%), ЕЛЕКТРО АБО БЕНЗИН 216 586 (1.49%), ГАЗ 50 769, ЕЛЕКТРО АБО ДИЗЕЛЬНЕ 32 671, БЕНЗИН/ГАЗ/ЕЛЕКТРО 7 432, НЕ ВИЗНАЧЕНО 1 609, ДИЗЕЛЬНЕ АБО ГАЗ 639, ВІДСУТНЄ 454, «.» 124, ГАЗ ТА ЕЛЕКТРО 95.

**Розслідування порожнього палива (631 653):**
```sql
SELECT kind, COUNT(*) AS cnt FROM tz_clean
WHERE fuel = '' OR fuel IS NULL GROUP BY kind ORDER BY cnt DESC;
```
**99.4% — причепи (306 303) і напівпричепи (321 401): нема двигуна — нема палива.** Порожнє поле = логіка джерела, не помилка. Легкові без палива — 2 242 (0.03% легкових) = статистичний шум. **Розрізнення «системна діра vs шум» — за масштабом і структурою.**

**Розслідування «дивних гібридів» (перевірка назв даними по марках/моделях):**
```sql
SELECT fuel, brand, model, COUNT(*) AS cnt
FROM tz_clean
WHERE fuel IN ('ЕЛЕКТРО АБО ДИЗЕЛЬНЕ ПАЛИВО', 'БЕНЗИН, ГАЗ АБО ЕЛЕКТРО', 'ГАЗ ТА ЕЛЕКТРО')
GROUP BY fuel, brand, model ORDER BY fuel, cnt DESC LIMIT 30;
```
- «ЕЛЕКТРО АБО ДИЗЕЛЬНЕ» = переважно преміальні дизельні MHEV/PHEV SUV (Audi Q7/Q8, Volvo XC90, Range Rover, Mercedes GLE) — весь свіжий євро-преміум-дизель формально гібрид.
- «ГАЗ ТА ЕЛЕКТРО» = заводські корейські **LPi-гібриди** (Kia Forte, Hyundai Avante/Sonata) — б/в імпорт із Кореї. Найекзотичніше значення виявилось найчеснішим.
- Для графіків заплановано звести 14 значень до ~7 категорій: petrol / diesel / gas+petrol / hybrid / electric / unknown / no_engine.

## Крок 9.2. Кольори
`SELECT color, COUNT(*)...` → лідер **СІРИЙ 4 324 500**, далі ЧОРНИЙ 2 924 735, БІЛИЙ 2 851 013, СИНІЙ 1 690 064, ЧЕРВОНИЙ 1 078 776...
**Пастка нормалізації:** помаранчевий живе у ТРЬОХ написаннях — ОРАНЖЕВИЙ (85 374) + ПОМАРАНЧЕВИЙ (ОРАНЖЕВИЙ) (15 282) + ЖОВТОГАРЯЧИЙ (2) ≈ 100 тис. разом. Перед візуалізацією — злити; НЕВИЗНАЧЕНИЙ → unknown. Перший Tableau-графік кольорів побудовано (порада: колір стовпчика = сам колір; вісь у %; підпис «операцій», не «авто»).

## Крок 9.3. Формулювання (методологічна чесність)
Ми рахуємо **ОПЕРАЦІЇ, а не автопарк**: одне авто може пройти кілька операцій. Коректне формулювання скрізь: «частка X серед реєстраційних операцій».

---

# ЧАСТИНА 10. Регіональний аналіз брендів + мапа (найбільший візуальний етап)

## Крок 10.1. Гігієна перед рейтингом: перевірка чистоти brand
**Навіщо:** реєстр уже показав звичку писати одне й те саме по-різному (oper_name, три помаранчевих) — перш ніж рахувати топи, дивимось на топ-30 брендів очима:
```sql
SELECT brand, COUNT(*) AS ops FROM tz_clean
WHERE kind = 'ЛЕГКОВИЙ' GROUP BY brand ORDER BY ops DESC LIMIT 30;
```

## Крок 10.2. Топ-3 марки по областях: ROW_NUMBER() OVER (PARTITION BY)
```sql
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
```
**Механіка:** `PARTITION BY r.region` — нумерація заново в межах кожної області; `ORDER BY COUNT(*) DESC` — №1 найпопулярнішому; зовнішній `WHERE place <= 3` лишає п'єдестал. ~81 рядок.

**Урок підзапитів (реальна помилка):** `region_en` було додано у внутрішній SELECT, але забуто у зовнішньому — колонка «зникла» з виводу. Зовнішній запит показує ЛИШЕ те, що явно перелічено, навіть якщо віртуальна таблиця `t` містить більше. (Сюди ж — навіщо аліас `) t`: підзапит у FROM зобов'язаний мати ім'я.)

## Крок 10.3. Кейс «BA3 ≠ ВАЗ»: омогліфи + LADA, що перекинула область
**Підозра:** у легенді Tableau «BA3» і «ВАЗ» виглядали як два бренди (латиниця vs кирилиця).
**Перевірка даними:**
```sql
SELECT brand, COUNT(*) FROM tz_clean
WHERE brand IN ('ВАЗ', 'VAZ', 'BA3', 'LADA') GROUP BY brand;
-- ВАЗ  | 711 723
-- LADA |  10 288
```
**Розгадка №1:** латинського двійника НЕ існує — «BA3» це кирилична **В-А-З**, що на екрані ідентична латинським B-A-3 (**омогліфи**). Дублікати перевіряємо запитом, не очима.
**Розгадка №2:** справжній двійник — **LADA** (сучасне/експортне ім'я тієї ж марки). Рішення: злити з приміткою в README:
```sql
UPDATE tz_clean SET brand = 'ВАЗ' WHERE brand = 'LADA';   -- UPDATE 10288; разом 722 011
```
(tz_raw незмінний — правило «сирі дані недоторканні» дозволяє UPDATE лише в похідному шарі.)

**Наслідок, що став уроком проєкту:** переранжування після злиття ПЕРЕКИНУЛО лідера **Запорізької області**: було VW 35 766 (№1) проти ВАЗ 35 704; стало **ВАЗ 36 223 проти VW 35 766** — розрив **457 операцій**. «Дрібні» 1.4% змінили мапу. Гіпотеза «маленьке злиття нічого не змінить» — спростована.

## Крок 10.4. Крим і Севастополь: чесна повна мапа
**Проблема:** мапа України без Криму — не мапа України; але в реєстрі 2019–2025 кримських записів мізер (окупація з 2014) — «лідер» на такій вибірці = дезінформація.
**Вимір масштабу:**
```sql
SELECT r.region, COUNT(*) AS ops
FROM tz_clean c JOIN koatuu_regions r ON r.code2 = LEFT(c.koatuu, 2)
WHERE r.code2 IN ('01', '85') AND c.kind = 'ЛЕГКОВИЙ'
GROUP BY r.region;
-- АР Крим: 4 224;  м. Севастополь: 982
```
**Рішення:** основний рейтинг рахується БЕЗ 01/85 (`AND r.code2 NOT IN ('01','85')` у Кроці 10.2), а до результату двома рядками-константами дошиваються «нейтральні» записи:
```sql
...
UNION ALL SELECT 'АР Крим', 'Crimea', 'дані відсутні', NULL::BIGINT, 1
UNION ALL SELECT 'м. Севастополь', 'Sevastopol', 'дані відсутні', NULL::BIGINT, 1
ORDER BY region, place;
```
`UNION ALL` з SELECT без FROM = легальні рукописні рядки; `NULL::BIGINT` вирівнює тип ops; place=1 — щоб пройти фільтр Tableau. На мапі обидва — світло-сірі, «дані відсутні»; підзаголовок: «Autonomous Republic of Crimea and the city of Sevastopol — data is missing in the register». **Принцип: відсутність даних показуємо ЯК відсутність даних, а не вирізанням території і не чиєюсь «перемогою».**

## Крок 10.5. Tableau: покрокова збірка мапи
1. CSV → Tableau; `region_en` → **Geographic Role → State/Province** (іконка глобуса).
2. Подвійний клік по region_en → мапа точок → Marks: **Map** → filled map.
3. «X unknown» внизу праворуч → **Edit Locations → Country: Ukraine** → ручне зіставлення залишків.
4. **Фільтр лідерів:** поле `Place` → картка **Filters** → лишити тільки значення **1**.
5. `Brand` → **Color**; **Edit Colors** — закріпити палітру вручну (VW, ВАЗ контрастний, «дані відсутні» = світло-сірий). Ручне закріплення = кольори не «поїдуть» при оновленні даних.
6. `Region` (укр.) → **Label**; Map → Background Layers: приглушити фон (Washout), вимкнути конкуруючі підписи країн.
7. Заголовок-історія + підзаголовок-методологія (Крим; «за операціями, не автопарком»).

## Крок 10.6. Дві класичні пастки Tableau (спіймані наживо)
**(а) `ATTR(Brand)` і символ `*`.** Поки не було фільтра place=1, на одну область потрапляло 3 бренди → ATTR повертає `*` («багато значень») → палітра «з'їхала»: області з підписом VOLKSWAGEN фарбувались кольором RENAULT з легенди. Мапа брехала кольором при чесних підписах. **Правило: `*` від ATTR — діагноз зайвої деталізації мітки або відсутнього фільтра.** Лікування: фільтр place=1 + чисте поле Brand на Color.

**(б) Viz in Tooltip і `filter="<All Fields>"`.** Механіка: окремий аркуш `top3_bar` (brand → Rows, SUM(ops) → Columns, сортування за спаданням, ops → Label, БЕЗ фільтра place — потрібні всі 3 місця; осі/сітку прибрано) → на мапі Tooltip → **Insert → Sheets → top3_bar** → службовий тег `<Sheet name="top3_bar" maxwidth="350" maxheight="180" filter="...">`. Дефолтний `filter="<All Fields>"` передає у вкладений аркуш УСІ поля мітки, включно з Brand → у tooltip лишався ОДИН стовпчик (бренд-лідер). Лікування: **`filter="<Region En>"`** — фільтрація лише за областю; всі три місця повертаються. Зайві службові рядки (Region En, дубль Ops) з tooltip прибрано.

## Крок 10.7. Географічні висновки (легкові операції 2019–2025)
- **Volkswagen — лідер у ~20 областях** (захід, центр, північ, більшість півдня): «коричнева імперія».
- **ВАЗ — пояс сходу/південного сходу:** Донецька, Луганська, Запорізька (після злиття LADA!), Кіровоградська — портрет старішого автопарку й економіки регіонів.
- **Toyota — лідер Одеської області.**
- Градієнт «захід = європейські марки ↔ схід = ВАЗ» підтверджений і в цифрах, і на мапі.
- Публікація: Tableau Public — «The most popular car brands in Ukraine by region, 2019–2025».

---

# ЧАСТИНА 11. Гіпотези проєкту: журнал стану

| # | Гіпотеза | Метод перевірки | Статус |
|---|---|---|---|
| H0 | Код 213 (воєнний облік) не існував до 2022 | MIN(source_year) по коду | ✅ ПІДТВЕРДЖЕНА (2022) |
| H0b | Код 71 — переважно б/в імпорт | Розподіл віку + стаття МВС | ✅ ПІДТВЕРДЖЕНА (70%+ авто 6–20 р.) |
| H0c | «BA3» — латинський двійник ВАЗ | GROUP BY brand | ❌ СПРОСТОВАНА (омогліфи; але знайдено LADA) |
| H0d | Злиття LADA (1.4%) не змінить лідерів | Переранжування place | ❌ СПРОСТОВАНА (Запорізька перейшла до ВАЗ) |
| H1 | Сплеск/злам імпорту вживаних у 2022+ | Запит №12 по import_used | 🔜 дані є, аналіз у черзі |
| H2 | Динаміка вторинного ринку (ownership_change + diia) | Запит №12 | 🔜 дані є, аналіз у черзі |
| H3 | Географічні зсуви реєстрацій (релокація) | Регіони × роки | 🔜 частково: статична мапа лідерів готова |
| — | COVID-провал new_vehicle 2020 | Запит №12 | 🔜 (квітень-2020 вже видно в 4.2) |
| — | Зростання car_scrappage 2022+ | Запит №12 | 🔜 |
| — | Частка ЕЛЕКТРО зростає | fuel × роки | 🔜 |
| — | Чому обвалився car_conversion після 2019? | окреме розслідування | 🔜 НОВА |

---

# ЧАСТИНА 12. Повна шпаргалка правил проєкту

1. **Код, не назва.** Групуємо по oper_code; oper_name — коментар. MIN(текст) = алфавітна лотерея; «репрезентативна назва» = найчастіший варіант (DISTINCT ON + ORDER BY COUNT DESC).
2. **Сирі дані недоторканні.** tz_raw — дзеркало джерела; чистка значень і злиття брендів — лише у похідних шарах.
3. **Кожне завантаження звіряється двічі:** COPY N = INSERT N; підсумок по source_year = wc -l − 1.
4. **TRUNCATE перед COPY**, не після INSERT.
5. **Гіпотеза ≠ факт.** Кожне «очевидне» твердження — через дані (213, 71, «дивні гібриди», BA3, «LADA нічого не змінить»).
6. **Аномалія → root cause.** Спершу природа (системна діра vs шум: масштаб + структура), потім рішення (KOATUU-2020: 23% системно → застереження; легкові без палива: 0.03% → шум).
7. **\copy живе в psql** одним рядком; \o — теж лише psql; експорт запиту — `\copy (SELECT...) TO`.
8. **DDL в одному інструменті за раз** (кейс «зниклої таблиці» = незакомічена транзакція pgAdmin).
9. **Один запит — одна перевірка.** Кожна розбіжність очікування/результату розслідується (UPDATE 0 → «не той файл»; INSERT 0 8445088 → «злиплі роки»).
10. **Омогліфи:** кирилиця/латиниця ідентичні на вигляд (ВАЗ ↔ «BA3»). Дублікати шукаємо запитом, не очима.
11. **Малий обсяг ≠ малий вплив:** 1.4% LADA перекинули лідера області (розрив 457 операцій). Після будь-якого злиття — переперевірити рейтинги.
12. **Відсутність даних показуємо як відсутність даних** (сірий колір + примітка), територію з мапи не вирізаємо.
13. **`*` від ATTR у Tableau — діагноз**, не косметика: зайва деталізація мітки або відсутній фільтр.
14. **Viz in Tooltip:** дефолтний filter="<All Fields>" передає ВСІ поля мітки; для «топ-N у підказці» фільтрувати лише за географією.
15. **Ми рахуємо операції, не автопарк** — формулювання висновків відповідне.
16. **Довідник без перевірки покриття — не довідник** (JOIN мовчки губить рядки; кейс префікса 52).
17. **Підзапит у FROM зобов'язаний мати аліас**; зовнішній SELECT показує лише явно перелічене.

---

# ЧАСТИНА 13. Поточний стан і дорожня карта

**Готово ✅:** середовище · звірений ETL 7 років (14 497 205) · діагностика з двома знахідками (KOATUU-2020, COVID-квітень) · tz_clean · koatuu_regions (+ region_en) · oper_directory (145 кодів, 22 категорії, верифіковані 71/314/213) · злиття ВАЗ+LADA · профілі палива й кольорів · дані Запиту №12 (141 рядок) · **опубліковано 2 візуалізації** (кольори; мапа брендів по областях із Кримом «дані відсутні»).

**У черзі 🔜:**
1. Візуалізація динаміки категорій (лінії топ-5 із групою «інше», теплова карта категорія×рік, індекс 2019=100 через LOOKUP + Compute Using) — головний графік проєкту.
2. Аналіз H1/H2 (імпорт, вторинний ринок) + COVID/війна у цифрах.
3. Розслідування обвалу car_conversion після 2019.
4. Паливо × роки (тренд ЕЛЕКТРО) з нормалізацією до 7 категорій; кольори × роки зі злиттям помаранчевих.
5. Вік імпортованих авто по роках (чи «молодшає» імпорт?).
6. Збірка дашборда (кольори + мапа + динаміка + текстова панель висновків) → публікація → README на GitHub (методологія = цей handbook).

---

# ЧАСТИНА 14. Розслідування «нульового розмитнення» та EV-бум (11 липня 2026)

## Крок 14.1. Гіпотеза H5: пік імпорту-2022 створило «нульове розмитнення»
**Контекст:** річний ряд import_used показав дивину — 2022 (рік вторгнення!) НЕ найгірший рік імпорту (463k), найгірші — «стабільні» 2023–2024 (274k / 266k). Зовнішній контекст-кандидат: у квітні–червні 2022 діяло скасування мита/акцизу/ПДВ на ввезення авто («нульове розмитнення»).

**Перевірка — місячний розріз 2022:**
```sql
SELECT EXTRACT(MONTH FROM c.reg_date) AS month, COUNT(*) AS ops
FROM tz_clean c
JOIN oper_directory d ON d.oper_code = c.oper_code
WHERE d.category = 'import_used' AND c.source_year = 2022
GROUP BY month ORDER BY month;
```
| Міс | Ops | Коментар |
|---|---|---|
| 01 | 35 446 | довоєнна норма |
| 02 | 33 720 | (вторгнення 24.02) |
| **03** | **9 144** | шок вторгнення: −74% |
| 04 | 35 542 | старт нульового розмитнення |
| **05** | **88 516** | пік ×2.5 від норми |
| **06** | **95 356** | абсолютний пік року |
| 07 | 54 438 | «хвіст»: розмитнені до 01.07 авто реєструються з лагом |
| 08 | 25 301 | нова воєнна норма |
| 09–12 | 21–22 тис./міс | плато воєнної економіки |

**Висновок: H5 ПІДТВЕРДЖЕНА.** У місячних даних видно ТРИ події поспіль: обвал вторгнення (березень, −74%), горб пільги (травень–червень, ×2.5) з інерційним хвостом у липні (реєстрація відстає від розмитнення), і вихід на нижче воєнне плато (~21 тис./міс проти ~35 тис. довоєнних). Річна цифра 2022 «пристойна» лише завдяки 3-місячній пільзі — слід конкретного закону в даних.
**Методологічний бонус:** річна агрегація МАСКУВАЛА три різноспрямовані події одного року; місячний розріз — обов'язковий інструмент для криз.

## Крок 14.2. Електромобілі: динаміка (fuel = 'ЕЛЕКТРО', чисті BEV, легкові)
```sql
SELECT source_year, COUNT(*) AS ev_ops
FROM tz_clean
WHERE fuel = 'ЕЛЕКТРО' AND kind = 'ЛЕГКОВИЙ'
GROUP BY source_year ORDER BY source_year;
```
| Рік | EV-операцій |
|---|---|
| 2019 | 11 920 |
| 2020 | 13 280 |
| 2021 | 17 656 |
| 2022 | 27 409 |
| 2023 | 65 985 |
| 2024 | 99 308 |
| 2025 | **185 223** |

**Зростання ×15.5 за 7 років; 2025 майже подвоює 2024.** Війна EV-тренд не зламала — прискорила (пальне дороге/дефіцитне 2022-го, генерація+зарядка вдома, пільги на ввезення електро). Гібриди ('ЕЛЕКТРО АБО БЕНЗИН' тощо) свідомо НЕ включені — окрема лінія за бажанням.

## Крок 14.3. Топ EV-моделей (гіпотеза «Leaf + Tesla у топі» — підтверджена)
```sql
SELECT brand, model, COUNT(*) AS ops
FROM tz_clean
WHERE fuel = 'ЕЛЕКТРО' AND kind = 'ЛЕГКОВИЙ'
GROUP BY brand, model ORDER BY ops DESC LIMIT 20;
```
Топ: **NISSAN LEAF 66 286** (король б/в EV-імпорту), TESLA MODEL 3 40 118 + MODEL Y 29 308 + MODEL S 19 313 + MODEL X 7 431 (Tesla сумарно ~96 тис. — фактичний бренд-лідер), VW E-GOLF 18 742, RENAULT ZOE 14 820, HYUNDAI KONA 11 753, VW ID.4 10 089 (+ ID.4 CROZZ 4 550 — китайська збірка!), CHEVROLET BOLT 8 122...
**Сигнали в хвості топу:** HONDA M-NV (6 016; модель існує ЛИШЕ для ринку Китаю) і BYD SONG PLUS (3 667) — маркер нової хвилі імпорту EV з Китаю. Кандидат на розслідування: топ EV-моделей ПО РОКАХ (чи зсувається структура Leaf → Tesla/BYD).

## Оновлення журналу гіпотез
| # | Гіпотеза | Статус |
|---|---|---|
| H1 | Динаміка імпорту вживаних у кризи | ✅ ЧАСТКОВО ЗАКРИТА: COVID −14%, пік-2021, воєнне плато ~21 тис./міс |
| H5 (нова) | Пік-2022 = нульове розмитнення (кві–чер) | ✅ ПІДТВЕРДЖЕНА місячним розрізом |
| H6 (нова) | EV-бум прискорюється попри війну | ✅ ПІДТВЕРДЖЕНА (×15.5; 2025 ≈ ×2 до 2024) |
| H7 (нова) | Структура EV зсувається до Китаю (BYD, China-only моделі) | 🔜 топ моделей по роках |

## Оновлення правил
18. **Річна агрегація маскує різноспрямовані події всередині року** (2022: обвал + пільговий горб + плато). Для криз — місячний розріз обов'язково.
19. **Зовнішній контекст (закони, локдауни) — джерело гіпотез, а не висновків**: висновок з'являється, лише коли слід контексту знайдено в даних (нульове розмитнення: знайдено; ГБО-обвал: поки інтерпретація).

---

# ЧАСТИНА 15. Глава made_in_ukraine: «Український автопром — це Skoda і причепи» (13–14 липня 2026)

## Крок 15.1. Хто взагалі «виготовлений в Україні» (структура категорії)
Запит brand × kind по категорії made_in_ukraine (код 99) зруйнував очікування «побачити ЗАЗи»:
- **№1 — SKODA, 19 683 легкових**: завод Єврокар (Соломоново, Закарпаття) збирає Skoda з машинокомплектів → юридично «виготовлено в Україні». Код 99 фіксує МІСЦЕ виготовлення, а не національність бренду. Сюди ж KIA (1 237), ВАЗ (3 173), Renault, Toyota — залишки крупновузлової збірки.
- **Хребет галузі — причепи:** ЛЕВ, АМС, КРД, ДНІПРО, ЛІДЕР, БОБЕР, ПАЛИЧ, КИЯШКО... — сумарно більше за легкові.
- **Автобуси на місці, але штучні:** ATAMAN 983, ЗАЗ 632, ЕТАЛОН 355.
- **Легкових моделей власне ЗАЗ (Sens/Vida/Lanos) майже немає** — масове легкове виробництво зупинилось ДО 2019 року. Відсутність — теж результат.
- Бонус-двійник у стилі проєкту: `INTERCARGO TRUCK` (1 030) і `INTERCARGOTRUCK` (745) — злити при рейтингах.

## Крок 15.2. Динаміка по типах ТЗ (spoiler: різноспрямована)
| kind | 2019 | 2021 (пік) | 2022 | 2024 | 2025 |
|---|---|---|---|---|---|
| ЛЕГКОВИЙ | 6 268 | 8 991 | 3 606 | 2 937 | **1 683 (−81% від піку)** |
| ПРИЧІП | 8 681 | 7 914 | 4 356 | 6 394 | 4 143 |
| ВАНТАЖНИЙ | 1 797 | 3 217 | 1 336 | 2 423 | 2 105 |
| АВТОБУС | 461 | 418 | 157 | 399 | 388 (≈ повне відновлення) |

**Журнал гіпотез:** «причепи ростуть у війну» — ❌ СПРОСТОВАНА (падіння ~2×); «загадка 2025 = обвал легкової збірки» — ✅ ПІДТВЕРДЖЕНА (1 683). Автобуси — єдиний сегмент із повним відновленням.

## Крок 15.3. Кардіограма Skoda (DATE_TRUNC('month'))
```sql
SELECT DATE_TRUNC('month', c.reg_date)::date AS month, COUNT(*) AS ops
FROM tz_clean c JOIN oper_directory d ON d.oper_code = c.oper_code
WHERE d.category = 'made_in_ukraine' AND c.brand = 'SKODA'
GROUP BY month ORDER BY month;
```
84 точки; ключові: **груд-2019: 904** (новорічний пік + видно сезонність), **кві-2020: 163** (COVID, проти 312 роком раніше), **лют-2022: 33** (війна), далі плато ~100–200/міс; кінець 2025 лише трохи вище рівнів бер–кві 2022.
**Тріангуляція із зовнішнім джерелом:** Єврокар офіційно відновив виробництво вже через кілька місяців після вторгнення (skoda-auto.ua, новина про resumption) — але дані показують: ВИРОБНИЦТВО відновилось, ПОПИТ — ні. Пропозиція ≠ попит; реєстр бачить попит.
**Tableau-урок:** поле дати за замовчуванням лягає як YEAR() — для часового ряду вибирати нижній (continuous, зелений) Month у меню пігулки; 84 точки, не 7.

## Висновки глави (для README)
1. «Made in Ukraine» ≠ українські бренди: найбільший легковий «українець» — Skoda закарпатської збірки.
2. Реальна масова продукція галузі — причепи; автобуси — нішеві, але єдині повністю відновились після 2022.
3. Легкова збірка згасає: −81% від піку 2021, і тренд 2023→2025 низхідний попри відновлення виробничих потужностей.
4. Застереження: реєстрації в Україні ≠ виробництво (експорт не видно).

# ЧАСТИНА 16. Фінальний стан проєкту
**Опубліковано 9 візуалізацій** (Tableau Public, колекція «Vehicle registrations in Ukraine 2019 2025»): What color is Ukraine · Brands map by region · Heat map categories×years · Dynamics of imports 2022 (нульове розмитнення) · Dynamics of EV registrations · TOP-20 EV · The EV throne race · Ukrainian automotive industry after 2022 · Skoda pulse.
**Далі:** збірка дашборда (6 блоків, сюжет «огляд → де/що → кризи → майбутнє → висновки») → публікація → README на GitHub.
