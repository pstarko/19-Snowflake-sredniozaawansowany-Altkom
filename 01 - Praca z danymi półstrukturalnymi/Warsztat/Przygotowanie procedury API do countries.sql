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
 
 
-- to zwróci JSON jako VARIANT(czyli idealnie pod OBJECT/ARRAY).
CREATE OR REPLACE FUNCTION restcountries_by_common_name(country_name STRING)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('requests')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (restcountries_eai)
SECRETS = ('RESTCOUNTRIES_TOKEN' = restcountries_bearer)
AS
$$
import requests
import _snowflake

def run(country_name: str):
    token = _snowflake.get_generic_secret_string("RESTCOUNTRIES_TOKEN")
    url = f"https://api.restcountries.com/countries/v5/names.common/{country_name}"
    r = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=30)
    r.raise_for_status()
    return r.json()
$$;

--wywołanie
SELECT restcountries_by_common_name('Poland') AS payload;

--weź pierwszy obiekt tego kraju:
SELECT
  restcountries_by_common_name('Poland'):data:objects[0] AS country_obj;


SELECT
  restcountries_by_common_name('Poland'):data:objects[0]:names:common::STRING AS name_common;

  --Kilka innych pól dla ćwiczeń OBJECT/ARRAY/VARIANT:
  WITH r AS (
  SELECT restcountries_by_common_name('Poland') AS v
)
SELECT
  v:data:objects[0]:names:common::STRING          AS name_common,
  v:data:objects[0]:names:official::STRING         AS name_official,
  v:data:objects[0]:codes:alpha_2::STRING          AS alpha_2,
  v:data:objects[0]:region::STRING                 AS region,
  v:data:objects[0]:population::NUMBER             AS population,
  v:data:objects[0]:borders                        AS borders_array,   -- ARRAY
  v:data:objects[0]:names:native                   AS native_names_obj, -- OBJECT
  v:data:objects[0]:capitals[0]:name::STRING       AS capital
FROM r;

--Flatten po tablicy Borders
WITH r AS (
  SELECT restcountries_by_common_name('Poland') AS v
)
SELECT f.value::STRING AS border_country
FROM r,
LATERAL FLATTEN(input => v:data:objects[0]:borders) f;


