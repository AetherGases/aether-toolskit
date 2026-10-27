$ErrorActionPreference = "Stop"

$infraEnv = Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) "aether-infra\.env"
if (-not (Test-Path $infraEnv)) {
    $infraEnv = "C:\Users\eduardomacal-ieg\OneDrive - Instituto J&F\germinare\2026\aether\aether-infra\.env"
}

function Get-EnvValue($key) {
    foreach ($line in Get-Content $infraEnv) {
        if ($line -match "^\s*$key=(.+)$") { return $Matches[1].Trim() }
    }
    throw "Missing $key in $infraEnv"
}

$hostPooler = Get-EnvValue "POSTGRES_HOST"
$hostDirect = $hostPooler -replace "-pooler", ""
$user = Get-EnvValue "POSTGRES_USER"
$pass = Get-EnvValue "POSTGRES_PASSWORD"
$db1 = Get-EnvValue "POSTGRES_DB_FIRST_YEAR"
$db2 = Get-EnvValue "POSTGRES_DB_SECOND_YEAR"
$ssl = Get-EnvValue "POSTGRES_SSLMODE"
$port = Get-EnvValue "POSTGRES_PORT"

$sqlDir = Join-Path (Split-Path $PSScriptRoot -Parent) "init-postgres"
$sqlDirDocker = $sqlDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1' -replace ':', ''

function Invoke-NeonSql([string]$HostName, [string]$DbName, [string]$Sql) {
    docker run --rm -e PGPASSWORD=$pass postgres:16.10 `
        psql "host=$HostName port=$port user=$user dbname=$DbName sslmode=$ssl" `
        -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql failed (exit $LASTEXITCODE)" }
}

function Invoke-NeonFile([string]$HostName, [string]$DbName, [string]$FileName) {
    Write-Host ">> $FileName (db=$DbName)"
    docker run --rm -e PGPASSWORD=$pass -v "${sqlDir}:/sql:ro" -v "${PSScriptRoot}:/scripts:ro" postgres:16.10 `
        psql "host=$HostName port=$port user=$user dbname=$DbName sslmode=$ssl" `
        -v ON_ERROR_STOP=1 -f "/scripts/$FileName"
    if ($LASTEXITCODE -ne 0) { throw "psql failed on $FileName (exit $LASTEXITCODE)" }
}

function Invoke-NeonInitFile([string]$HostName, [string]$DbName, [string]$FileName) {
    Write-Host ">> $FileName (db=$DbName)"
    docker run --rm -e PGPASSWORD=$pass -v "${sqlDir}:/sql:ro" postgres:16.10 `
        psql "host=$HostName port=$port user=$user dbname=$DbName sslmode=$ssl" `
        -v ON_ERROR_STOP=1 -f "/sql/$FileName"
    if ($LASTEXITCODE -ne 0) { throw "psql failed on $FileName (exit $LASTEXITCODE)" }
}

Write-Host "=== Drop and recreate $db1 / $db2 on $hostDirect ==="
Invoke-NeonFile $hostDirect "neondb" "00-neon-drop-and-create.sql"

$secondYearScripts = @(
    "02-creating-initial-tables-second-year.sql",
    "03-second-year-audit-and-logs.sql",
    "04-second-year-functions-and-procedures.sql",
    "05-second-year-analytical-layer.sql",
    "06-second-year-indexes.sql",
    "07-second-year-metadata-catalog.sql"
)

foreach ($f in $secondYearScripts) {
    Invoke-NeonInitFile $hostPooler "neondb" $f
}

$firstYearScripts = @(
    "08-first-year-creating-initial-tables.sql",
    "09-creating-dataload-first-year.sql"
)

foreach ($f in $firstYearScripts) {
    Invoke-NeonInitFile $hostPooler $db1 $f
}

Invoke-NeonInitFile $hostPooler "neondb" "200-adding-users-initial.sql"

Write-Host "=== Verify ==="
Invoke-NeonSql $hostPooler "neondb" "SELECT datname FROM pg_database WHERE datname IN ('$db1', '$db2') ORDER BY 1;"
Invoke-NeonSql $hostPooler $db2 "SELECT COUNT(*) AS tables_2y FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';"
Invoke-NeonSql $hostPooler $db1 "SELECT COUNT(*) AS tables_1y FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';"

Write-Host "=== Done ==="
