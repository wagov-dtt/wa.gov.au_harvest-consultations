MODEL (
  name consultations.table,
  kind FULL
);

SELECT
  *
FROM citizenspace.view;

@IF(
  @runtime_stage = 'evaluating',
  CREATE OR REPLACE TABLE mysql_db.consultations AS SELECT * FROM consultations.table
);