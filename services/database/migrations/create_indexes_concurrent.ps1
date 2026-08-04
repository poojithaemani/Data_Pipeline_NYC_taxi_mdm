<#
Create Indexes Concurrently Helper

Usage (PowerShell):
  $env:PGPASSWORD = '<your_password>'
  ./create_indexes_concurrent.ps1 -Host 'db.host' -Port 5432 -Database 'mydb' -User 'myuser' -DryRun:$false

Notes:
- This script requires psql in PATH.
- It executes CREATE INDEX CONCURRENTLY statements outside transactions.
- It checks for existing indexes using to_regclass; if index exists it is skipped.
- For production, run during low-traffic window and ensure no long-running transactions.
#>

param(
  [string]$Host = $env:PGHOST,
  [int]$Port = $(if ($env:PGPORT) { [int]$env:PGPORT } else { 5432 }),
  [string]$Database = $env:PGDATABASE,
  [string]$User = $env:PGUSER,
  [switch]$DryRun = $true
)

function Check-Psql {
  $psql = Get-Command psql -ErrorAction SilentlyContinue
  if (-not $psql) {
    Write-Error "psql not found in PATH. Install PostgreSQL client tools or ensure psql is available."
    exit 2
  }
}

function Exec-PSQL {
  param($sql)
  $cmd = @('psql', '-h', $Host, '-p', $Port.ToString(), '-U', $User, '-d', $Database, '-t', '-c', $sql)
  if ($DryRun) {
    Write-Output "DRY-RUN: psql $($cmd -join ' ')"
  } else {
    $proc = Start-Process -FilePath psql -ArgumentList @('-h', $Host, '-p', $Port.ToString(), '-U', $User, '-d', $Database, '-t', '-c', $sql) -NoNewWindow -Wait -PassThru -ErrorAction Stop
    return $proc.ExitCode
  }
}

# Index definitions
$indexes = @(
  @{ name = 'idx_vendors_vendorid_current'; sql = "CREATE UNIQUE INDEX CONCURRENTLY idx_vendors_vendorid_current ON vendors (vendor_id) WHERE is_current;" },
  @{ name = 'idx_vendors_vendorid_effective_date'; sql = "CREATE INDEX CONCURRENTLY idx_vendors_vendorid_effective_date ON vendors (vendor_id, effective_date);" },
  @{ name = 'idx_golden_locationid_current'; sql = "CREATE UNIQUE INDEX CONCURRENTLY idx_golden_locationid_current ON golden_zones (location_id) WHERE is_current AND location_id IS NOT NULL;" },
  @{ name = 'idx_golden_borough_zone_effective'; sql = "CREATE INDEX CONCURRENTLY idx_golden_borough_zone_effective ON golden_zones (borough, zone, effective_date);" },
  @{ name = 'idx_golden_effective_date'; sql = "CREATE INDEX CONCURRENTLY idx_golden_effective_date ON golden_zones (effective_date);" }
)

Check-Psql

if (-not $Host -or -not $Database -or -not $User) {
  Write-Error "Missing connection parameters. Set PGHOST/PGDATABASE/PGUSER env vars or provide -Host -Database -User parameters."
  exit 2
}

Write-Output "Connecting to $User@$Host:$Port/$Database"

foreach ($idx in $indexes) {
  $name = $idx.name
  $checkSql = "SELECT to_regclass('public.$name') IS NOT NULL;"
  if ($DryRun) {
    Write-Output "DRY-RUN: Would check existence of $name"
    Write-Output "DRY-RUN: Would run: $($idx.sql)"
    continue
  }

  try {
    $existsResult = & psql -h $Host -p $Port -U $User -d $Database -t -c $checkSql 2>&1
  } catch {
    Write-Error "psql check failed: $_"
    exit 3
  }

  $exists = $existsResult.Trim()
  if ($exists -eq 't') {
    Write-Output "Index $name already exists — skipping."
    continue
  }

  Write-Output "Creating index $name..."
  try {
    & psql -h $Host -p $Port -U $User -d $Database -c $($idx.sql)
    if ($LASTEXITCODE -ne 0) {
      Write-Error "Failed to create index $name (psql exit code $LASTEXITCODE)."
      exit $LASTEXITCODE
    }
    Write-Output "Created index $name."
  } catch {
    Write-Error "Exception while creating index $name: $_"
    exit 4
  }
}

Write-Output "All index operations completed."
