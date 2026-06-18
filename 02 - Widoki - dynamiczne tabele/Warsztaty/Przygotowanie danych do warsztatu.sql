-- =========================================================
-- 0. SETUP
-- =========================================================

CREATE OR REPLACE DATABASE WORKSHOP_VIEWS_DTS;
CREATE OR REPLACE SCHEMA WORKSHOP_VIEWS_DTS.LAB;
USE DATABASE WORKSHOP_VIEWS_DTS;
USE SCHEMA LAB;


-- =========================================================
-- 1. TABLES
-- =========================================================

CREATE OR REPLACE TABLE FACT_ORDERS_RAW (
    ORDER_ID        NUMBER(10,0),
    ORDER_TS        TIMESTAMP_NTZ,
    ORDER_DATE      DATE,
    CUSTOMER_ID     NUMBER(10,0),
    PRODUCT_ID      NUMBER(10,0),
    STORE_ID        NUMBER(10,0),
    PROMO_ID        NUMBER(10,0),
    QUANTITY        NUMBER(10,0),
    UNIT_PRICE      NUMBER(10,2),
    DISCOUNT_PCT    NUMBER(5,2),
    ORDER_STATUS    VARCHAR(20),
    CHANNEL         VARCHAR(20),
    REGION          VARCHAR(50),
    LAST_UPDATE_TS  TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE DIM_CUSTOMERS (
    CUSTOMER_ID     NUMBER(10,0),
    CUSTOMER_NAME   VARCHAR(100),
    SEGMENT         VARCHAR(50),
    CITY            VARCHAR(50),
    COUNTRY         VARCHAR(50),
    IS_ACTIVE       BOOLEAN
);

CREATE OR REPLACE TABLE DIM_PRODUCTS (
    PRODUCT_ID      NUMBER(10,0),
    PRODUCT_NAME    VARCHAR(100),
    CATEGORY        VARCHAR(50),
    SUBCATEGORY     VARCHAR(50),
    BRAND           VARCHAR(50),
    IS_ACTIVE       BOOLEAN
);

CREATE OR REPLACE TABLE DIM_STORES (
    STORE_ID        NUMBER(10,0),
    STORE_NAME      VARCHAR(100),
    STORE_TYPE      VARCHAR(30),
    CITY            VARCHAR(50),
    REGION          VARCHAR(50)
);

CREATE OR REPLACE TABLE DIM_PROMOTIONS (
    PROMO_ID        NUMBER(10,0),
    PROMO_NAME      VARCHAR(100),
    PROMO_TYPE      VARCHAR(30),
    START_DATE      DATE,
    END_DATE        DATE,
    DISCOUNT_PCT    NUMBER(5,2)
);

CREATE OR REPLACE TABLE DIM_RETURNS (
    ORDER_ID        NUMBER(10,0),
    RETURN_DATE     DATE,
    RETURN_REASON   VARCHAR(100),
    RETURN_STATUS   VARCHAR(20)
);

CREATE OR REPLACE TABLE DIM_CALENDAR (
    CAL_DATE        DATE,
    YEAR_NUM        NUMBER(4,0),
    MONTH_NUM       NUMBER(2,0),
    MONTH_NAME      VARCHAR(20),
    WEEK_NUM        NUMBER(2,0),
    DAY_OF_WEEK     VARCHAR(20),
    IS_WEEKEND      BOOLEAN
);

-- =========================================================
-- 2. DATA DEMO
-- =========================================================

INSERT INTO DIM_CUSTOMERS VALUES
(1, 'Anna Nowak', 'Consumer', 'Poznań', 'PL', TRUE),
(2, 'Piotr Kowalski', 'Corporate', 'Warszawa', 'PL', TRUE),
(3, 'Marta Zielińska', 'Consumer', 'Wrocław', 'PL', TRUE),
(4, 'Tomasz Wiśniewski', 'SMB', 'Gdańsk', 'PL', TRUE),
(5, 'Katarzyna Lewandowska', 'Corporate', 'Kraków', 'PL', TRUE);

INSERT INTO DIM_PRODUCTS VALUES
(101, 'Laptop Pro 14', 'Electronics', 'Computers', 'NorthPeak', TRUE),
(102, 'Monitor 27', 'Electronics', 'Displays', 'NorthPeak', TRUE),
(103, 'Wireless Mouse', 'Electronics', 'Accessories', 'ClickLab', TRUE),
(104, 'Office Chair', 'Office', 'Furniture', 'SeatOne', TRUE),
(105, 'Desk Lamp', 'Office', 'Lighting', 'BrightCo', TRUE);

INSERT INTO DIM_STORES VALUES
(10, 'Poznań Center', 'Retail', 'Poznań', 'West'),
(11, 'Warszawa West', 'Retail', 'Warszawa', 'Central'),
(12, 'Online PL', 'Ecommerce', 'Remote', 'All'),
(13, 'Kraków Mall', 'Retail', 'Kraków', 'South');

INSERT INTO DIM_PROMOTIONS VALUES
(201, 'Spring Sale', 'Percent', '2026-03-01', '2026-04-15', 10.00),
(202, 'Q2 Clearance', 'Percent', '2026-04-01', '2026-06-30', 15.00),
(203, 'Free Shipping', 'Shipping', '2026-01-01', '2026-12-31', 0.00);

INSERT INTO DIM_RETURNS VALUES
(1004, '2026-05-02', 'Damaged product', 'approved'),
(1012, '2026-05-03', 'Wrong item', 'approved'),
(1018, '2026-05-10', 'Customer changed mind', 'pending');

INSERT INTO DIM_CALENDAR
SELECT
    d::DATE AS CAL_DATE,
    YEAR(d)::NUMBER(4,0) AS YEAR_NUM,
    MONTH(d)::NUMBER(2,0) AS MONTH_NUM,
    TO_CHAR(d, 'MONTH') AS MONTH_NAME,
    WEEK(d)::NUMBER(2,0) AS WEEK_NUM,
    TO_CHAR(d, 'DY') AS DAY_OF_WEEK,
    IFF(DAYOFWEEK(d) IN (1,7), TRUE, FALSE) AS IS_WEEKEND
FROM (
    SELECT DATEADD(DAY, SEQ4(), '2026-04-01') AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 92))
);

INSERT INTO FACT_ORDERS_RAW
SELECT
    1000 + SEQ4() AS ORDER_ID,
    DATEADD(MINUTE, UNIFORM(0, 60*24*45, RANDOM()), '2026-04-01 08:00:00'::TIMESTAMP_NTZ) AS ORDER_TS,
    TO_DATE(DATEADD(MINUTE, UNIFORM(0, 60*24*45, RANDOM()), '2026-04-01 08:00:00'::TIMESTAMP_NTZ)) AS ORDER_DATE,
    UNIFORM(1, 6, RANDOM()) AS CUSTOMER_ID,
    UNIFORM(101, 106, RANDOM()) AS PRODUCT_ID,
    UNIFORM(10, 14, RANDOM()) AS STORE_ID,
    IFF(SEQ4() % 3 = 0, 201, IFF(SEQ4() % 3 = 1, 202, 203)) AS PROMO_ID,
    UNIFORM(1, 6, RANDOM()) AS QUANTITY,
    ROUND(UNIFORM(49, 4500, RANDOM()), 2) AS UNIT_PRICE,
    CASE
        WHEN SEQ4() % 10 = 0 THEN 20
        WHEN SEQ4() % 7 = 0 THEN 15
        ELSE 10
    END AS DISCOUNT_PCT,
    CASE
        WHEN SEQ4() % 11 = 0 THEN 'cancelled'
        WHEN SEQ4() % 13 = 0 THEN 'returned'
        ELSE 'completed'
    END AS ORDER_STATUS,
    IFF(SEQ4() % 2 = 0, 'online', 'store') AS CHANNEL,
    IFF(SEQ4() % 4 = 0, 'West', IFF(SEQ4() % 4 = 1, 'Central', IFF(SEQ4() % 4 = 2, 'South', 'All'))) AS REGION,
    CURRENT_TIMESTAMP() AS LAST_UPDATE_TS
FROM TABLE(GENERATOR(ROWCOUNT => 200));

-- Uzupełnij tabelę zwrotów o zamówienia rzeczywiście anulowane/zwrocone
INSERT INTO DIM_RETURNS
SELECT ORDER_ID, ORDER_DATE, 'Synthetic return', ORDER_STATUS
FROM FACT_ORDERS_RAW
WHERE ORDER_STATUS IN ('returned', 'cancelled')
LIMIT 12;
