MODEL (
  name mysay.view,
  kind VIEW
);

SELECT
  id AS ConsultationIdentifier,
  CAST(attributes ->> '$.name' AS TEXT) AS ConsultationTitle,
  CAST(links ->> '$.self' AS TEXT) AS ConsultationUrl,
  CAST(attributes ->> '$.description' AS TEXT) AS ConsultationShortDescription,
  'Current' AS syncstate
FROM mysay.api