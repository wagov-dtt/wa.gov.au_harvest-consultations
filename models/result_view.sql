MODEL (
  name result.view,
  kind VIEW
);

SELECT
  *
FROM mysay.view
UNION ALL BY NAME
SELECT
  *
FROM citizenspace.view