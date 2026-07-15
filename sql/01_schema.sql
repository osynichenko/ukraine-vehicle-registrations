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