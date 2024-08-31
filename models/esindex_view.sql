MODEL (
  name esindex.view,
  kind VIEW
);

SELECT
  *,
  'Previous' AS syncstate
FROM esindex.api