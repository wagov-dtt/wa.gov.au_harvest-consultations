MODEL (
  name mysay.view,
  kind VIEW
);

SELECT
  id AS ConsultationIdentifier,
  FROM_JSON(attributes, '{ "name": "VARCHAR", "description": "VARCHAR" }') AS attributes,
  FROM_JSON(links, '{ "self": "VARCHAR" }') AS links,
  attributes.name AS ConsultationTitle,
  links.self AS ConsultationUrl,
  attributes.description AS ConsultationShortDescription,
  'Current' AS syncstate
FROM mysay.api