[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EvidenceDirectory,

    [ValidateRange(1024, 65535)]
    [int]$GrafanaPort = 3101,

    [ValidateRange(1024, 65535)]
    [int]$PrometheusPort = 9091
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$archive = (Resolve-Path $EvidenceDirectory).Path
$manifestPath = Join-Path $archive 'manifest.json'
$tsdbPath = Join-Path $archive 'prometheus\tsdb'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Missing manifest: $manifestPath" }
if (-not (Test-Path -LiteralPath $tsdbPath)) { throw "Missing offline Prometheus data: $tsdbPath" }
foreach ($port in @($GrafanaPort, $PrometheusPort)) {
    if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
        throw "Port $port is already in use. The local benchmark stack remains untouched; choose another port."
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$projectName = "ride-matching-evidence-$($manifest.run_id)".ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
$composeFile = Join-Path $PSScriptRoot 'evidence\compose.yaml'
$env:EVIDENCE_DIR = $archive
$env:EVIDENCE_GRAFANA_PORT = $GrafanaPort
$env:EVIDENCE_PROMETHEUS_PORT = $PrometheusPort

& docker compose -p $projectName -f $composeFile up -d
if ($LASTEXITCODE -ne 0) { throw 'Could not start the isolated evidence viewer.' }

$from = [DateTimeOffset]::Parse($manifest.since_utc).ToUnixTimeMilliseconds()
$to = [DateTimeOffset]::Parse($manifest.until_utc).ToUnixTimeMilliseconds()
Write-Host "Grafana: http://127.0.0.1:$GrafanaPort/d/archived-gcp-load-test?from=$from&to=$to&var-testid=$($manifest.run_id)"
Write-Host "Prometheus: http://127.0.0.1:$PrometheusPort"
