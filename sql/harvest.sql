-- name: create_database
CREATE DATABASE IF NOT EXISTS {{database}} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- name: create_stage
CREATE TEMPORARY TABLE consultations_stage (
  stage_row_id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  source VARCHAR(32) NOT NULL,
  id VARCHAR(255) NOT NULL,
  name TEXT NULL,
  description TEXT NULL,
  raw_status TEXT NULL,
  tags TEXT NULL,
  parent_id TEXT NULL,
  department TEXT NULL,
  url TEXT NULL,
  publishdate_text TEXT NULL,
  expirydate_text TEXT NULL
);

-- name: insert_stage
INSERT INTO consultations_stage
(source, id, name, description, raw_status, tags, parent_id, department, url, publishdate_text, expirydate_text)
VALUES
(:source, :id, :name, :description, :raw_status, :tags, :parent_id, :department, :url, :publishdate_text, :expirydate_text);

-- name: drop_agency_rules
DROP TEMPORARY TABLE IF EXISTS agency_rules;

-- Agency rules are data, not control flow.
-- Lower rule_id wins when more than one rule matches a row.
-- match_type: url | tag | parent_id
-- match_mode: contains | equals
-- name: create_agency_rules
CREATE TEMPORARY TABLE agency_rules (
  rule_id INT NOT NULL PRIMARY KEY,
  source VARCHAR(32) NOT NULL,
  match_type VARCHAR(32) NOT NULL,
  match_mode VARCHAR(32) NOT NULL,
  pattern VARCHAR(255) NOT NULL,
  agency TEXT NOT NULL
);

-- name: insert_agency_rules
INSERT INTO agency_rules (rule_id, source, match_type, match_mode, pattern, agency)
SELECT 10, 'engagementhq', 'url',       'contains', 'engageagric.engagementhq.com',    'Department of Primary Industries and Regional Development'
UNION ALL SELECT 11,  'engagementhq', 'url',       'contains', 'yoursay.dpird.wa.gov.au',          'Department of Primary Industries and Regional Development'
UNION ALL SELECT 20,  'engagementhq', 'url',       'contains', 'haveyoursaywa.engagementhq.com',   'Department of Planning, Lands and Heritage'
UNION ALL SELECT 30,  'engagementhq', 'parent_id', 'equals',   '38135',                            'Department of Transport'
UNION ALL SELECT 31,  'engagementhq', 'tag',       'contains', 'dot',                              'Department of Transport'
UNION ALL SELECT 40,  'engagementhq', 'parent_id', 'equals',   '37726',                            'Main Roads Western Australia'
UNION ALL SELECT 41,  'engagementhq', 'tag',       'contains', 'mrwa',                             'Main Roads Western Australia'
UNION ALL SELECT 42,  'engagementhq', 'tag',       'contains', 'main roads',                       'Main Roads Western Australia'
UNION ALL SELECT 50,  'engagementhq', 'parent_id', 'equals',   '38267',                            'METRONET'
UNION ALL SELECT 51,  'engagementhq', 'tag',       'contains', 'metronet',                         'METRONET'
UNION ALL SELECT 60,  'engagementhq', 'parent_id', 'equals',   '37724',                            'Westport'
UNION ALL SELECT 61,  'engagementhq', 'tag',       'contains', 'westport',                         'Westport'
UNION ALL SELECT 70,  'engagementhq', 'parent_id', 'equals',   '37725',                            'Transperth'
UNION ALL SELECT 71,  'engagementhq', 'tag',       'contains', 'transperth',                       'Transperth'
UNION ALL SELECT 80,  'engagementhq', 'tag',       'contains', 'pta',                              'Public Transport Authority'
UNION ALL SELECT 100, 'citizenspace', 'url',       'contains', 'consultation.health.wa.gov.au',    'Department of Health'
UNION ALL SELECT 110, 'citizenspace', 'url',       'contains', 'consult.dwer.wa.gov.au',           'Department of Water and Environmental Regulation'
UNION ALL SELECT 120, 'citizenspace', 'url',       'contains', 'consultation.dmirs.wa.gov.au',     'Department of Energy, Mines, Industry Regulation and Safety';

-- name: drop_normalized_stage
DROP TEMPORARY TABLE IF EXISTS consultations_normalized;

-- name: create_normalized_stage
CREATE TEMPORARY TABLE consultations_normalized AS
WITH
clean AS (
  SELECT
    stage_row_id,
    source,
    id,
    name,
    description,
    NULLIF(tags, '') AS tags,
    NULLIF(parent_id, '') AS parent_id,
    NULLIF(department, '') AS department,
    url,
    publishdate_text,
    expirydate_text,
    LOWER(COALESCE(raw_status, 'unknown')) AS raw_status_l,
    LOWER(COALESCE(tags, '')) AS tags_l,
    LOWER(COALESCE(url, '')) AS url_l
  FROM consultations_stage
),
status_normalized AS (
  SELECT
    clean.*,
    CASE
      WHEN source = 'engagementhq' AND tags_l LIKE '%close%' THEN 'closed'
      WHEN source = 'engagementhq' AND raw_status_l = 'published' THEN 'open'
      WHEN source = 'engagementhq' AND raw_status_l = 'archived' THEN 'closed'
      ELSE raw_status_l
    END AS status
  FROM clean
),
agency_match_input AS (
  SELECT stage_row_id, source, 'url' AS match_type, url_l AS match_text FROM clean
  UNION ALL
  SELECT stage_row_id, source, 'tag', tags_l FROM clean
  UNION ALL
  SELECT stage_row_id, source, 'parent_id', parent_id FROM clean
),
first_agency_match AS (
  SELECT match_input.stage_row_id, MIN(rule.rule_id) AS rule_id
  FROM agency_match_input match_input
  JOIN agency_rules rule
    ON rule.source = match_input.source
   AND rule.match_type = match_input.match_type
   AND (
     (rule.match_mode = 'contains' AND match_input.match_text LIKE CONCAT('%', rule.pattern, '%'))
     OR (rule.match_mode = 'equals' AND match_input.match_text = rule.pattern)
   )
  GROUP BY match_input.stage_row_id
),
agency_normalized AS (
  SELECT
    normalized.*,
    COALESCE(rule.agency, normalized.department, 'Government of Western Australia') AS agency
  FROM status_normalized normalized
  LEFT JOIN first_agency_match match_row ON match_row.stage_row_id = normalized.stage_row_id
  LEFT JOIN agency_rules rule ON rule.rule_id = match_row.rule_id
),
final_rows AS (
  SELECT
    source,
    id,
    name,
    description,
    status,
    tags,
    agency,
    'Western Australia' AS region,
    url,
    CASE
      WHEN COALESCE(publishdate_text, '') REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
        THEN STR_TO_DATE(LEFT(publishdate_text, 10), '%Y-%m-%d')
      ELSE NULL
    END AS publishdate,
    CASE
      WHEN COALESCE(expirydate_text, '') REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
        THEN STR_TO_DATE(LEFT(expirydate_text, 10), '%Y-%m-%d')
      ELSE NULL
    END AS expirydate
  FROM agency_normalized
)
SELECT *
FROM final_rows;

-- name: stage_valid_rows
SELECT COUNT(*) FROM consultations_normalized WHERE status IN ('open', 'closed');

-- name: stage_null_required_rows
SELECT COUNT(*)
FROM consultations_normalized
WHERE status IN ('open', 'closed')
  AND (source IS NULL OR id IS NULL OR id = '' OR name IS NULL OR status IS NULL OR url IS NULL);

-- name: stage_duplicate_source_id_rows
SELECT COUNT(*)
FROM (
  SELECT source, id
  FROM consultations_normalized
  WHERE status IN ('open', 'closed')
  GROUP BY source, id
  HAVING COUNT(*) > 1
) duplicates;

-- name: table_exists
SELECT COUNT(*)
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_name = :table;

-- name: drop_table_if_exists
DROP TABLE IF EXISTS {{table}};

-- name: drop_table
DROP TABLE {{table}};

-- name: create_final
CREATE TABLE {{table}} (
  source VARCHAR(32) NOT NULL,
  id VARCHAR(255) NOT NULL,
  name TEXT NOT NULL,
  description TEXT NULL,
  status VARCHAR(32) NOT NULL,
  tags TEXT NULL,
  agency TEXT NULL,
  region TEXT NULL,
  url TEXT NOT NULL,
  publishdate DATE NULL,
  expirydate DATE NULL,
  loaded_at TIMESTAMP NOT NULL,
  UNIQUE KEY source_id (source, id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- name: insert_final
INSERT INTO {{table}}
SELECT source, id, name, description, status, tags, agency, region, url, publishdate, expirydate, CURRENT_TIMESTAMP
FROM consultations_normalized
WHERE status IN ('open', 'closed');

-- name: count_table
SELECT COUNT(*) FROM {{table}};

-- name: rename_replace_export
RENAME TABLE {{table}} TO {{old_table}}, {{new_table}} TO {{table}};

-- name: rename_first_export
RENAME TABLE {{new_table}} TO {{table}};
