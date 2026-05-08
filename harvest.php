<?php

declare(strict_types=1);

const DEFAULT_DB_NAME = 'harvest_consultations';
const DEFAULT_DB_TABLE = 'consultations';
const SQL_FILE = __DIR__ . '/sql/harvest.sql';

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
    $value = $_ENV[$key] ?? $_SERVER[$key] ?? getenv($key);
    return trim($value === false || $value === null ? $default : (string)$value, "'\"");
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

function sql(string $name, array $vars = []): string
{
    static $statements = null;
    $statements ??= load_sql(SQL_FILE);

    if (!isset($statements[$name])) {
        throw new RuntimeException("SQL statement not found: $name");
    }

    $query = $statements[$name];
    foreach ($vars as $key => $value) {
        $query = str_replace('{{' . $key . '}}', (string)$value, $query);
    }
    if (preg_match('/{{[A-Za-z0-9_]+}}/', $query, $matches)) {
        throw new RuntimeException("SQL statement $name has unset placeholder {$matches[0]}");
    }

    return $query;
}

function load_sql(string $path): array
{
    $contents = @file_get_contents($path);
    if ($contents === false) {
        throw new RuntimeException("SQL file not readable: $path");
    }

    $parts = preg_split('/^--\s*name:\s*([A-Za-z][A-Za-z0-9_]*)\s*$/m', $contents, -1, PREG_SPLIT_DELIM_CAPTURE);
    if ($parts === false || count($parts) < 3) {
        throw new RuntimeException("SQL file has no named statements: $path");
    }

    $statements = [];
    for ($i = 1; $i < count($parts); $i += 2) {
        $name = trim($parts[$i]);
        $query = trim($parts[$i + 1] ?? '');
        if ($query === '') {
            throw new RuntimeException("SQL statement is empty: $name");
        }
        $statements[$name] = $query;
    }

    return $statements;
}

function http_get(string $url, array $headers = []): string
{
    $headerLines = ['User-Agent: harvest-consultations/1.0'];
    foreach ($headers as $name => $value) {
        $headerLines[] = $name . ': ' . $value;
    }

    $context = stream_context_create([
        'http' => [
            'method' => 'GET',
            'header' => implode("\r\n", $headerLines),
            'timeout' => 30,
            'ignore_errors' => true,
        ],
    ]);
    $body = @file_get_contents($url, false, $context);
    if ($body === false) {
        $error = error_get_last()['message'] ?? 'unknown error';
        throw new RuntimeException("GET failed: $url ($error)");
    }

    $status = http_status($http_response_header ?? []);
    if ($status < 200 || $status >= 300) {
        throw new RuntimeException("GET failed: $url (HTTP $status)");
    }

    return $body;
}

function http_status(array $headers): int
{
    foreach ($headers as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d{3})\b/', $header, $matches)) {
            return (int)$matches[1];
        }
    }
    return 0;
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

function create_stage(PDO $pdo): void
{
    $pdo->exec(sql('create_stage'));
}

function insert_statement(PDO $pdo): PDOStatement
{
    return $pdo->prepare(sql('insert_stage'));
}

function normalize_stage(PDO $pdo): void
{
    $pdo->exec(sql('drop_normalized_stage'));
    $pdo->exec(sql('drop_agency_rules'));
    $pdo->exec(sql('create_agency_rules'));
    $pdo->exec(sql('insert_agency_rules'));
    $pdo->exec(sql('create_normalized_stage'));
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

            $payload = http_json($url . '/api/v2/projects?per_page=10000', ['Authorization' => "Bearer $token"]);
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
                    'raw_status' => text_or_null($attrs['state'] ?? $row['state'] ?? null),
                    'tags' => $tags === '' ? null : $tags,
                    'parent_id' => $parentId,
                    'department' => null,
                    'url' => $recordUrl,
                    'publishdate_text' => text_or_null($attrs['published-at'] ?? $row['published-at'] ?? null),
                    'expirydate_text' => null,
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
                    'raw_status' => text_or_null($row['status'] ?? 'unknown'),
                    'tags' => null,
                    'parent_id' => null,
                    'department' => text_or_null($row['department'] ?? null),
                    'url' => $recordUrl,
                    'publishdate_text' => text_or_null($row['startdate'] ?? null),
                    'expirydate_text' => text_or_null($row['enddate'] ?? null),
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
    $valid = scalar($pdo, sql('stage_valid_rows'));
    if ($valid === 0) {
        throw new RuntimeException('consultations_normalized has no open/closed rows; refusing to export');
    }

    if (scalar($pdo, sql('stage_null_required_rows')) > 0) {
        throw new RuntimeException('consultations_normalized contains null required values');
    }

    if (scalar($pdo, sql('stage_duplicate_source_id_rows')) > 0) {
        throw new RuntimeException('consultations_normalized contains duplicate source/id keys');
    }

    return $valid;
}

function table_exists(PDO $pdo, string $table): bool
{
    $stmt = $pdo->prepare(sql('table_exists'));
    $stmt->execute(['table' => $table]);
    return (int)$stmt->fetchColumn() > 0;
}

function export_final(PDO $pdo, string $table): int
{
    $new = mysql_identifier('DB_TABLE', $table . '_new');
    $old = mysql_identifier('DB_TABLE', $table . '_old');
    $ids = [
        'table' => qid($table),
        'new_table' => qid($new),
        'old_table' => qid($old),
    ];

    $pdo->exec(sql('drop_table_if_exists', ['table' => $ids['new_table']]));
    $pdo->exec(sql('create_final', ['table' => $ids['new_table']]));
    $pdo->exec(sql('insert_final', ['table' => $ids['new_table']]));

    $count = scalar($pdo, sql('count_table', ['table' => $ids['new_table']]));
    if ($count === 0) {
        throw new RuntimeException('final table has no rows; refusing to export');
    }

    $pdo->exec(sql('drop_table_if_exists', ['table' => $ids['old_table']]));
    if (table_exists($pdo, $table)) {
        $pdo->exec(sql('rename_replace_export', $ids));
        $pdo->exec(sql('drop_table', ['table' => $ids['old_table']]));
    } else {
        $pdo->exec(sql('rename_first_export', $ids));
    }

    return $count;
}

function init_db(array $cfg): void
{
    $pdo = connect_mysql($cfg);
    $pdo->exec(sql('create_database', ['database' => qid($cfg['db_name'])]));
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

    echo "Normalizing...\n";
    normalize_stage($pdo);

    echo "Validating...\n";
    validate_stage($pdo);

    echo "Exporting to MySQL ({$cfg['db_name']}.{$cfg['db_table']})...\n";
    $count = export_final($pdo, $cfg['db_table']);
    echo "  Done: $count rows\n";
}

try {
    $cfg = config();
    $command = $argv[1] ?? 'run';
    match ($command) {
        'run' => run_harvest($cfg),
        'init' => init_db($cfg),
        default => run_harvest($cfg),
    };
} catch (Throwable $exc) {
    fwrite(STDERR, 'Error: ' . $exc->getMessage() . "\n");
    exit(1);
}
