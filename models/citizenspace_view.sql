MODEL (
  name citizenspace.view,
  kind VIEW
);

SELECT
  url AS ConsultationUrl,
  'Current' AS syncstate
FROM citizenspace.api