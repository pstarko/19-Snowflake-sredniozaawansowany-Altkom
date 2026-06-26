--1. Przygotowanie procedury

--Network rule (zezwól na wyjście do hosta API)
CREATE OR REPLACE NETWORK RULE restcountries_api_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('api.restcountries.com:443');
  
  
 --Secret na bearer token (nie trzymaj tokenu w kodzie):
 
 CREATE OR REPLACE SECRET restcountries_bearer
  TYPE = GENERIC_STRING
  SECRET_STRING = 'TWOJ_API_KEY';
  
-- External Access Integration (wiąże regułę sieci i sekret):

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION restcountries_eai
  ALLOWED_NETWORK_RULES = (restcountries_api_rule)
  ALLOWED_AUTHENTICATION_SECRETS = (restcountries_bearer)
  ENABLED = TRUE;
 
 
-- Najpierw upewnij się, że tabela istnieje
CREATE TABLE IF NOT EXISTS countries_data (
    official_name   VARCHAR,
    region          VARCHAR,
    population      NUMBER,
    borders         VARCHAR,
    loaded_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Procedura
CREATE OR REPLACE PROCEDURE load_countries_from_api(country_names ARRAY)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    country_name STRING;
    result VARIANT;
    v_official_name STRING;
    v_region STRING;
    v_population NUMBER;
    v_borders STRING;
    i INT DEFAULT 0;
    n INT;
    loaded_count INT DEFAULT 0;
BEGIN
    n := ARRAY_SIZE(country_names);

    WHILE i < n DO
        country_name := country_names[i]::STRING;

        -- Wywołaj funkcję pobierającą dane z API
        result := restcountries_by_common_name(:country_name);

        -- Wyciągnij potrzebne pola z odpowiedzi JSON
        v_official_name := result[0]:name:official::STRING;
        v_region        := result[0]:region::STRING;
        v_population    := result[0]:population::NUMBER;
        v_borders       := ARRAY_TO_STRING(
                              ARRAY_CONSTRUCT(result[0]:borders),
                              ','
                           );

        -- Wstaw rekord do tabeli (pomijaj duplikaty)
        MERGE INTO countries_data AS target
        USING (
            SELECT
                :v_official_name AS official_name,
                :v_region        AS region,
                :v_population    AS population,
                :v_borders       AS borders
        ) AS source
        ON target.official_name = source.official_name
        WHEN NOT MATCHED THEN
            INSERT (official_name, region, population, borders)
            VALUES (source.official_name, source.region, source.population, source.borders);

        loaded_count := loaded_count + 1;
        i := i + 1;
    END WHILE;

    RETURN 'Załadowano ' || loaded_count || ' krajów.';
END;
$$;

--wywołanie procedury
CALL load_countries_from_api(ARRAY_CONSTRUCT('France', 'Germany', 'Italy'));

--2. STAGE
-- Utwórz bazę i schemat (jeśli nie istnieją)
CREATE DATABASE IF NOT EXISTS COUNTRIES_DB;
USE DATABASE COUNTRIES_DB;
CREATE SCHEMA IF NOT EXISTS PUBLIC;

-- Utwórz wewnętrzny stage
CREATE OR REPLACE STAGE countries_stage
  FILE_FORMAT = (TYPE = 'CSV' FIELD_OPTIONALLY_ENCLOSED_BY = '"' SKIP_HEADER = 1);
  
--3
snowsql -a <account> -u <user> -d COUNTRIES_DB -s PUBLIC
PUT file://countries.csv @countries_stage AUTO_COMPRESS=FALSE;
  
  
--4a. Tabela docelowa

CREATE OR REPLACE TABLE countries_data (
    official_name   VARCHAR,
    region          VARCHAR,
    population      NUMBER,
    borders         VARCHAR,
    loaded_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);


--4b.Task ładujący dane ze stage do tabeli co 15 minut
CREATE OR REPLACE TASK load_countries_task
  WAREHOUSE = COMPUTE_WH
  SCHEDULE = '15 MINUTE'
AS
  CALL load_countries_from_api(ARRAY_CONSTRUCT(
      'France', 'Germany', 'Italy',
      'Norway', 'Sweden', 'Denmark'
  ));

ALTER TASK load_countries_task RESUME;

