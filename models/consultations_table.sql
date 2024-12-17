MODEL (
  name consultations.table,
  kind FULL
);

SELECT
  *
FROM citizenspace.view;

CREATE OR REPLACE TABLE mysqldb.sqlmesh.consultations AS SELECT * FROM consultations.table;
