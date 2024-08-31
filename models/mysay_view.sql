MODEL (
  name mysay.view,
  kind VIEW
);

SELECT
  id AS ConsultationIdentifier,
  attributes ->> '$.name' AS ConsultationTitle,
  links ->> '$.self' AS ConsultationUrl,
  attributes ->> '$.description' AS ConsultationShortDescription,
  'Current' AS syncstate
FROM mysay.api