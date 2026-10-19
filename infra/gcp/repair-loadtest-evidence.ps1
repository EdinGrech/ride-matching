[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$EvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$manifestPath = Join-Path $EvidenceDirectory 'manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$cells = @('spring-jvm-1cpu', 'spring-jvm-2cpu', 'quarkus-jvm-1cpu', 'quarkus-jvm-2cpu')

function Get-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$scorecard = @{}
foreach ($cell in $cells) {
    $scorecard[$cell] = [ordered]@{
        implementation        = $cell
        application_requests  = 0
        unexpected_requests   = 0
        completed_lifecycles  = 0
        aborted_lifecycles    = 0
    }
}

$requests = Get-Json (Join-Path $EvidenceDirectory 'prometheus\k6_http_reqs_total.json')
foreach ($result in @($requests.data.result)) {
    if ($result.metric.flow -ne 'population-ramp') { continue }
    $cell = $result.metric.implementation
    if (-not $scorecard.ContainsKey($cell)) { continue }
    $value = (@($result.values | ForEach-Object { [double]$_[1] }) | Measure-Object -Maximum).Maximum
    $scorecard[$cell].application_requests += $value
    if ($result.metric.expected_response -eq 'false') { $scorecard[$cell].unexpected_requests += $value }
}
foreach ($metric in @('k6_ride_lifecycles_completed_total', 'k6_ride_lifecycles_aborted_total')) {
    $data = Get-Json (Join-Path $EvidenceDirectory "prometheus\$metric.json")
    foreach ($result in @($data.data.result)) {
        if ($result.metric.flow -ne 'population-ramp') { continue }
        $cell = $result.metric.implementation
        if (-not $scorecard.ContainsKey($cell)) { continue }
        $value = (@($result.values | ForEach-Object { [double]$_[1] }) | Measure-Object -Maximum).Maximum
        $field = if ($metric -match 'completed') { 'completed_lifecycles' } else { 'aborted_lifecycles' }
        $scorecard[$cell][$field] += $value
    }
}
@($scorecard.Values | ForEach-Object { [PSCustomObject]$_ }) |
    Export-Csv -LiteralPath (Join-Path $EvidenceDirectory 'scorecard.csv') -NoTypeInformation -Encoding utf8

$runStart = [datetime]::MaxValue
$runEnd = [datetime]::MinValue
foreach ($cell in $cells) {
    $executions = Get-Content -LiteralPath (Join-Path $EvidenceDirectory "cloud-run\$cell-executions.json") -Raw | ConvertFrom-Json
    $execution = @($executions | Where-Object {
        $_.spec.template.spec.containers[0].args -contains "testid=$($manifest.run_id)"
    })[0]
    if (-not $execution) { throw "No execution found for $cell." }
    $executionStart = [datetime]$execution.metadata.creationTimestamp
    $executionEnd = [datetime]$execution.status.completionTime
    if ($executionStart -lt $runStart) { $runStart = $executionStart }
    if ($executionEnd -gt $runEnd) { $runEnd = $executionEnd }
}

$resourceRows = @()
foreach ($cell in $cells) {
    foreach ($metric in @('cpu', 'memory')) {
        $path = Join-Path $EvidenceDirectory "cloud-monitoring\$cell-run.googleapis.com_container_${metric}_utilizations.json"
        $series = Get-Json $path
        $values = @($series | ForEach-Object { $_.points } | Where-Object {
            $end = [datetime]$_.interval.endTime
            $end -ge $runStart -and $end -le $runEnd
        } | ForEach-Object {
            $distribution = $_.value.PSObject.Properties['distributionValue']
            $mean = if ($distribution) { $distribution.Value.PSObject.Properties['mean'] }
            if ($mean) { $mean.Value }
        } | Where-Object { $null -ne $_ })
        if (-not $values.Count) { throw "No $metric utilization samples found for $cell in the run window." }
        $resourceRows += [PSCustomObject]@{
            implementation = $cell
            metric         = "run.googleapis.com/container/$($metric)/utilizations"
            samples        = $values.Count
            mean           = [math]::Round((($values | Measure-Object -Average).Average), 6)
            peak           = [math]::Round((($values | Measure-Object -Maximum).Maximum), 6)
        }
    }
}
$resourceRows | Export-Csv -LiteralPath (Join-Path $EvidenceDirectory 'resource-summary.csv') -NoTypeInformation -Encoding utf8

$files = @(Get-ChildItem -LiteralPath $EvidenceDirectory -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' })
$updatedManifest = [PSCustomObject]@{
    run_id          = $manifest.run_id
    project         = $manifest.project
    region          = $manifest.region
    since_utc       = $manifest.since_utc
    until_utc       = $manifest.until_utc
    prometheus_url  = $manifest.prometheus_url
    grafana_url     = $manifest.grafana_url
    exported_at_utc = $manifest.exported_at_utc
    repaired_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    run_start_utc   = $runStart.ToUniversalTime().ToString('o')
    run_end_utc     = $runEnd.ToUniversalTime().ToString('o')
    files           = @($files | ForEach-Object {
        [PSCustomObject]@{
            path   = $_.FullName.Substring($EvidenceDirectory.Length + 1)
            bytes  = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
}
$updatedManifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "Repaired evidence archive: $EvidenceDirectory"
