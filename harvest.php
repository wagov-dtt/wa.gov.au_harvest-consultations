<?php

declare(strict_types=1);

const DEFAULT_DB_NAME = 'harvest_consultations';
const DEFAULT_DB_TABLE = 'consultations';
const DEFAULT_REGION = 'Western Australia';
const DEFAULT_AGENCY = 'Government of Western Australia';

function config(): array
{
    return [
        'portals' => parse_portals(env_value('PORTALS_JSON', '{}')),
        'db_host' => env_value('DB_HOST', 'localhost'),
        'db_port' => env_value('DB_PORT', '3306'),
        'db_user' => env_value('DB_USER', 'root'),
        'db_password' => env_value('DB_PASSWORD'),
        'db_name' => mysql_identifier('DB_NAME', env_value('DB_NAME', DEFAULT_DB_NAME)),
        'db_table' => mysql_identifier('DB_TABLE', env_value('DB_TABLE', DEFAULT_DB_TABLE)),
    ];
}

function env_value(string $key, string $default = ''): string
{
    $value = getenv($key);
    return trim($value === false ? $default : $value, "'\"");
}

function mysql_identifier(string $key, string $value): string
{
    if (!preg_match('/^[A-Za-z_][A-Za-z0-9_]*$/', $value)) {
        throw new RuntimeException("$key must be a MySQL identifier: letters, numbers, underscores; not starting with a number");
    }
    return $value;
}

function parse_portals(string $value): array
{
    $data = json_decode($value, true);
    if (!is_array($data)) {
        $data = json_decode(str_replace('\\"', '"', $value), true);
    }
    if (!is_array($data)) {
        throw new RuntimeException('PORTALS_JSON must be a JSON object');
    }

    $portals = [];
    foreach ($data as $source => $urls) {
        if (!in_array($source, ['citizenspace', 'engagementhq'], true)) {
            throw new RuntimeException('PORTALS_JSON source names must be one of: citizenspace, engagementhq');
        }
        if (!is_array($urls)) {
            throw new RuntimeException('PORTALS_JSON must map source names to URL lists');
        }
        foreach ($urls as $url) {
            if (!is_string($url) || !is_https_url($url)) {
                throw new RuntimeException('PORTALS_JSON URL lists must contain HTTPS URL strings');
            }
            $portals[$source][] = rtrim($url, '/');
        }
    }
    return $portals;
}

function is_https_url(string $value): bool
{
    $parts = parse_url($value);
    return ($parts['scheme'] ?? '') === 'https' && !empty($parts['host']);
}

function connect_mysql(array $cfg, ?string $database = null): PDO
{
    $dsn = sprintf(
        'mysql:host=%s;port=%s;charset=utf8mb4%s',
        $cfg['db_host'],
        $cfg['db_port'],
        $database === null ? '' : ';dbname=' . $database,
    );
    return new PDO($dsn, $cfg['db_user'], $cfg['db_password'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
}

function qid(string $identifier): string
{
    return '`' . str_replace('`', '``', $identifier) . '`';
}

function http_get(string $url, array $headers = []): string
{
    $headers[] = 'User-Agent: harvest-consultations/1.0';
    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'header' => implode("\r\n", $headers),
            'timeout' => 30,
            'ignore_errors' => true,
        ],
    ]);

    $body = @file_get_contents($url, false, $context);
    if ($body === false) {
        throw new RuntimeException("GET failed: $url");
    }

    $status = 0;
    foreach (($http_response_header ?? []) as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d{3})\b/', $header, $matches)) {
            $status = (int)$matches[1];
        }
    }
    if ($status < 200 || $status >= 300) {
        throw new RuntimeException("GET $url returned HTTP $status");
    }

    return $body;
}

function http_json(string $url, array $headers = []): mixed
{
    return json_decode(http_get($url, $headers), true, flags: JSON_THROW_ON_ERROR);
}

function first_auth_token(string $page): ?string
{
    if (preg_match('/eyJ[A-Za-z0-9._-]+/', $page, $matches)) {
        return $matches[0];
    }
    if (preg_match('/data-thunder="([^"]*)"/', $page, $matches)) {
        return $matches[1];
    }
    return null;
}

function text_or_null(mixed $value): ?string
{
    if ($value === null || $value === '') {
        return null;
    }
    return is_scalar($value) ? (string)$value : json_encode($value, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
}

function parse_date(?string $value): ?string
{
    if ($value === null || trim($value) === '') {
        return null;
    }
    $timestamp = strtotime($value);
    return $timestamp === false ? null : gmdate('Y-m-d', $timestamp);
}

function engagementhq_status(?string $state, string $tags): string
{
    $tags = strtolower($tags);
    $state = strtolower($state ?? 'unknown');
    if (str_contains($tags, 'close')) {
        return 'closed';
    }
    if ($state === 'published') {
        return 'open';
    }
    if ($state === 'archived') {
        return 'closed';
    }
    return $state;
}

function engagementhq_agency(string $url, ?string $parentId, string $tags): string
{
    $url = strtolower($url);
    $tags = strtolower($tags);
    if (str_contains($url, 'engageagric.engagementhq.com') || str_contains($url, 'yoursay.dpird.wa.gov.au')) {
        return 'Department of Primary Industries and Regional Development';
    }
    if (str_contains($url, 'haveyoursaywa.engagementhq.com')) {
        return 'Department of Planning, Lands and Heritage';
    }
    if ($parentId === '38135' || str_contains($tags, 'dot')) {
        return 'Department of Transport';
    }
    if ($parentId === '37726' || str_contains($tags, 'mrwa') || str_contains($tags, 'main roads')) {
        return 'Main Roads Western Australia';
    }
    if ($parentId === '38267' || str_contains($tags, 'metronet')) {
        return 'METRONET';
    }
    if ($parentId === '37724' || str_contains($tags, 'westport')) {
        return 'Westport';
    }
    if ($parentId === '37725' || str_contains($tags, 'transperth')) {
        return 'Transperth';
    }
    if (str_contains($tags, 'pta')) {
        return 'Public Transport Authority';
    }
    return DEFAULT_AGENCY;
}

function citizenspace_agency(?string $url, ?string $department): string
{
    $url = strtolower($url ?? '');
    if (str_contains($url, 'consultation.health.wa.gov.au')) {
        return 'Department of Health';
    }
    if (str_contains($url, 'consult.dwer.wa.gov.au')) {
        return 'Department of Water and Environmental Regulation';
    }
    if (str_contains($url, 'consultation.dmirs.wa.gov.au')) {
        return 'Department of Energy, Mines, Industry Regulation and Safety';
    }
    return $department ?: DEFAULT_AGENCY;
}

function create_stage(PDO $pdo): void
{
    $pdo->exec(<<<'SQL'
CREATE TEMPORARY TABLE consultations_stage (
  source VARCHAR(32) NOT NULL,
  id VARCHAR(255) NOT NULL,
  name TEXT NULL,
  description TEXT NULL,
  status VARCHAR(32) NULL,
  tags TEXT NULL,
  agency TEXT NULL,
  region TEXT NULL,
  url TEXT NULL,
  publishdate DATE NULL,
  expirydate DATE NULL
)
SQL);
}

function insert_statement(PDO $pdo): PDOStatement
{
    return $pdo->prepare(<<<'SQL'
INSERT INTO consultations_stage
(source, id, name, description, status, tags, agency, region, url, publishdate, expirydate)
VALUES
(:source, :id, :name, :description, :status, :tags, :agency, :region, :url, :publishdate, :expirydate)
SQL);
}

function harvest_engagementhq(array $cfg, PDOStatement $insert): int
{
    $count = 0;
    foreach (($cfg['portals']['engagementhq'] ?? []) as $url) {
        try {
            $token = first_auth_token(http_get($url));
            if ($token === null || $token === '') {
                fwrite(STDERR, "  No auth token: $url\n");
                continue;
            }

            $payload = http_json($url . '/api/v2/projects?per_page=10000', ["Authorization: Bearer $token"]);
            $rows = is_array($payload) && is_array($payload['data'] ?? null) ? $payload['data'] : [];
            foreach ($rows as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $attrs = is_array($row['attributes'] ?? null) ? $row['attributes'] : [];
                $links = is_array($row['links'] ?? null) ? $row['links'] : [];
                $tagsValue = $attrs['project-tag-list'] ?? $row['project-tag-list'] ?? [];
                $tags = is_array($tagsValue) ? implode(',', array_map('strval', $tagsValue)) : (string)$tagsValue;
                $recordUrl = text_or_null($links['self'] ?? $row['url'] ?? $url) ?? $url;
                $parentId = text_or_null($attrs['parent-id'] ?? $row['parent-id'] ?? null);

                $insert->execute([
                    'source' => 'engagementhq',
                    'id' => text_or_null($row['id'] ?? '') ?? '',
                    'name' => text_or_null($attrs['name'] ?? $row['name'] ?? null),
                    'description' => text_or_null($attrs['description'] ?? $row['description'] ?? null),
                    'status' => engagementhq_status(text_or_null($attrs['state'] ?? $row['state'] ?? null), $tags),
                    'tags' => $tags === '' ? null : $tags,
                    'agency' => engagementhq_agency($recordUrl, $parentId, $tags),
                    'region' => DEFAULT_REGION,
                    'url' => $recordUrl,
                    'publishdate' => parse_date(text_or_null($attrs['published-at'] ?? $row['published-at'] ?? null)),
                    'expirydate' => null,
                ]);
                $count++;
            }
        } catch (Throwable $exc) {
            fwrite(STDERR, "  Error $url: {$exc->getMessage()}\n");
        }
    }
    return $count;
}

function harvest_citizenspace(array $cfg, PDOStatement $insert): int
{
    $count = 0;
    foreach (($cfg['portals']['citizenspace'] ?? []) as $url) {
        try {
            $rows = http_json($url . '/api/2.3/json_search_results?fields=extended');
            if (!is_array($rows)) {
                continue;
            }
            foreach ($rows as $row) {
                if (!is_array($row)) {
                    continue;
                }
                $recordUrl = text_or_null($row['url'] ?? null);
                $insert->execute([
                    'source' => 'citizenspace',
                    'id' => text_or_null($row['id'] ?? '') ?? '',
                    'name' => text_or_null($row['title'] ?? null),
                    'description' => text_or_null($row['overview'] ?? null),
                    'status' => strtolower(text_or_null($row['status'] ?? 'unknown') ?? 'unknown'),
                    'tags' => null,
                    'agency' => citizenspace_agency($recordUrl, text_or_null($row['department'] ?? null)),
                    'region' => DEFAULT_REGION,
                    'url' => $recordUrl,
                    'publishdate' => parse_date(text_or_null($row['startdate'] ?? null)),
                    'expirydate' => parse_date(text_or_null($row['enddate'] ?? null)),
                ]);
                $count++;
            }
        } catch (Throwable $exc) {
            fwrite(STDERR, "  Error $url: {$exc->getMessage()}\n");
        }
    }
    return $count;
}

function scalar(PDO $pdo, string $sql): int
{
    return (int)$pdo->query($sql)->fetchColumn();
}

function validate_stage(PDO $pdo): int
{
    $valid = scalar($pdo, "SELECT COUNT(*) FROM consultations_stage WHERE status IN ('open', 'closed')");
    if ($valid === 0) {
        throw new RuntimeException('consultations_stage has no open/closed rows; refusing to export');
    }

    if (scalar($pdo, "SELECT COUNT(*) FROM consultations_stage WHERE status IN ('open', 'closed') AND (source IS NULL OR id IS NULL OR id = '' OR name IS NULL OR status IS NULL OR url IS NULL)") > 0) {
        throw new RuntimeException('consultations_stage contains null required values');
    }

    if (scalar($pdo, "SELECT COUNT(*) FROM (SELECT source, id FROM consultations_stage WHERE status IN ('open', 'closed') GROUP BY source, id HAVING COUNT(*) > 1) duplicates") > 0) {
        throw new RuntimeException('consultations_stage contains duplicate source/id keys');
    }

    return $valid;
}

function table_exists(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = :table');
    $stmt->execute(['table' => $table]);
    return (int)$stmt->fetchColumn() > 0;
}

function export_final(PDO $pdo, string $table): int
{
    $new = mysql_identifier('DB_TABLE', $table . '_new');
    $old = mysql_identifier('DB_TABLE', $table . '_old');

    $pdo->exec('DROP TABLE IF EXISTS ' . qid($new));
    $pdo->exec('CREATE TABLE ' . qid($new) . " (
  source VARCHAR(32) NOT NULL,
  id VARCHAR(255) NOT NULL,
  name TEXT NOT NULL,
  description TEXT NULL,
  status VARCHAR(32) NOT NULL,
  tags TEXT NULL,
  agency TEXT NULL,
  region TEXT NULL,
  url TEXT NOT NULL,
  publishdate DATE NULL,
  expirydate DATE NULL,
  loaded_at TIMESTAMP NOT NULL,
  UNIQUE KEY source_id (source, id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");

    $pdo->exec('INSERT INTO ' . qid($new) . "
SELECT source, id, name, description, status, tags, agency, region, url, publishdate, expirydate, CURRENT_TIMESTAMP
FROM consultations_stage
WHERE status IN ('open', 'closed')");

    $count = scalar($pdo, 'SELECT COUNT(*) FROM ' . qid($new));
    if ($count === 0) {
        throw new RuntimeException('final table has no rows; refusing to export');
    }

    $pdo->exec('DROP TABLE IF EXISTS ' . qid($old));
    if (table_exists($pdo, $table)) {
        $pdo->exec('RENAME TABLE ' . qid($table) . ' TO ' . qid($old) . ', ' . qid($new) . ' TO ' . qid($table));
        $pdo->exec('DROP TABLE ' . qid($old));
    } else {
        $pdo->exec('RENAME TABLE ' . qid($new) . ' TO ' . qid($table));
    }

    return $count;
}

function init_db(array $cfg): void
{
    $pdo = connect_mysql($cfg);
    $pdo->exec('CREATE DATABASE IF NOT EXISTS ' . qid($cfg['db_name']) . ' DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    echo "Database '{$cfg['db_name']}' ready\n";
}

function run_harvest(array $cfg): void
{
    if (empty($cfg['portals']['engagementhq']) && empty($cfg['portals']['citizenspace'])) {
        throw new RuntimeException('PORTALS_JSON must configure at least one portal for run');
    }

    init_db($cfg);
    $pdo = connect_mysql($cfg, $cfg['db_name']);
    create_stage($pdo);
    $insert = insert_statement($pdo);

    echo "Harvesting APIs...\n";
    $ehq = harvest_engagementhq($cfg, $insert);
    echo "  EngagementHQ: $ehq records\n";
    $cs = harvest_citizenspace($cfg, $insert);
    echo "  CitizenSpace: $cs records\n";

    echo "Validating...\n";
    validate_stage($pdo);

    echo "Exporting to MySQL ({$cfg['db_name']}.{$cfg['db_table']})...\n";
    $count = export_final($pdo, $cfg['db_table']);
    echo "  Done: $count rows\n";
}

function stats(array $cfg): void
{
    $pdo = connect_mysql($cfg, $cfg['db_name']);
    $table = qid($cfg['db_table']);
    echo "\n=== {$cfg['db_name']}.{$cfg['db_table']} ===\n";
    echo 'Total rows: ' . scalar($pdo, "SELECT COUNT(*) FROM $table") . "\n\n";

    echo "By source/status:\n";
    foreach ($pdo->query("SELECT source, status, COUNT(*) AS count FROM $table GROUP BY source, status") as $row) {
        printf("  %-15s %-10s %s\n", $row['source'], $row['status'], $row['count']);
    }

    echo "\nSample rows:\n";
    foreach ($pdo->query("SELECT source, id, LEFT(name, 50) AS name, status FROM $table LIMIT 5") as $row) {
        printf("  %-15s %-10s %-50s %s\n", $row['source'], $row['id'], $row['name'], $row['status']);
    }
}

try {
    $cfg = config();
    $command = $argv[1] ?? 'run';
    match ($command) {
        'run' => run_harvest($cfg),
        'init' => init_db($cfg),
        'stats' => stats($cfg),
        default => run_harvest($cfg),
    };
} catch (Throwable $exc) {
    fwrite(STDERR, 'Error: ' . $exc->getMessage() . "\n");
    exit(1);
}
