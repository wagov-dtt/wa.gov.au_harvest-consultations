CREATE TABLE citizenspace_raw (
    id VARCHAR, title VARCHAR, overview VARCHAR, status VARCHAR,
    department VARCHAR, url VARCHAR, startdate VARCHAR, enddate VARCHAR
);

INSERT INTO citizenspace_raw VALUES
    ('cs-health', 'Health consultation', 'Overview', 'OPEN', NULL,
     'https://consultation.health.wa.gov.au/example', '2026-01-02', '2026-02-03'),
    ('cs-ignored', 'Draft', 'Overview', 'draft', 'Example Agency',
     'https://example.wa.gov.au/draft', '', '');

CREATE TABLE engagementhq_raw (
    id VARCHAR, name VARCHAR, description VARCHAR, state VARCHAR, url VARCHAR,
    "published-at" VARCHAR, "project-tag-list" VARCHAR[], "parent-id" VARCHAR, portal VARCHAR
);

INSERT INTO engagementhq_raw VALUES
    ('ehq-url', 'DPIRD', 'Description', 'published',
     'https://yoursay.dpird.wa.gov.au/project', '2026-03-04', ['mrwa'], NULL, 'https://yoursay.dpird.wa.gov.au'),
    ('ehq-parent', 'Main Roads', 'Description', 'published',
     'https://example.com/project', '2026-03-04', [], '37726', 'https://example.com'),
    ('ehq-tag', 'Transport', 'Description', 'published',
     'https://example.com/transport', '2026-03-04', ['passenger transport'], NULL, 'https://example.com'),
    ('ehq-closed', 'Closed', 'Description', 'published',
     'https://example.com/closed', '2026-03-04', ['consultation closed'], NULL, 'https://example.com');

.read chart/transform.sql

SELECT CASE WHEN count(*) = 5 THEN true ELSE error('expected 5 final rows') END
FROM consultations_final;

SELECT CASE WHEN agency = 'Department of Primary Industries and Regional Development'
    THEN true ELSE error('URL rule must take precedence') END
FROM engagementhq_std WHERE id = 'ehq-url';

SELECT CASE WHEN agency = 'Main Roads Western Australia'
    THEN true ELSE error('parent-id mapping failed') END
FROM engagementhq_std WHERE id = 'ehq-parent';

SELECT CASE WHEN agency = 'Department of Transport and Major Infrastructure'
    THEN true ELSE error('tag mapping failed') END
FROM engagementhq_std WHERE id = 'ehq-tag';

SELECT CASE WHEN status = 'closed'
    THEN true ELSE error('closed tag status failed') END
FROM engagementhq_std WHERE id = 'ehq-closed';

SELECT CASE WHEN agency = 'Department of Health'
                 AND publishdate = DATE '2026-01-02'
                 AND expirydate = DATE '2026-02-03'
    THEN true ELSE error('CitizenSpace transform failed') END
FROM citizenspace_std WHERE id = 'cs-health';

SELECT CASE WHEN columns = ['source', 'name', 'description', 'status', 'agency', 'tags', 'region', 'url', 'publishdate', 'expirydate']
    THEN true ELSE error('output schema mismatch') END
FROM (
    SELECT array_agg(column_name ORDER BY ordinal_position) AS columns
    FROM information_schema.columns WHERE table_name = 'consultations_final'
);
