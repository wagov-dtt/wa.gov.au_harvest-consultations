MODEL (
  name consultations.tbl,
  kind FULL
);

SELECT
  *
FROM (
  SELECT
    *
  FROM citizenspace.view
  UNION ALL BY NAME
  SELECT
    *
  FROM engagementhq.view
)
WHERE
  status IN ('open', 'closed');

CREATE OR REPLACE TABLE mysqldb.sqlmesh.consultations AS
SELECT
  *
FROM consultations.tbl