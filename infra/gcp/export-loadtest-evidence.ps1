[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')]
    [string]$Project,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z]+-[a-z]+[0-9]$')]
    [string]$Region,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string]$RunId,

    [string]$OutputDirectory,

    [datetime]$SinceUtc = (Get-Date).ToUniversalTime().AddHours(-3),

    [datetime]$UntilUtc = (Get-Date).ToUniversalTime()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $root "results\gcp\$RunId"
}
if (Test-Path -LiteralPath $OutputDirectory) {
    throw "Evidence directory already exists: $OutputDirectory"
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$SinceUtc = $SinceUtc.ToUniversalTime()
$UntilUtc = $UntilUtc.ToUniversalTime()
if ($UntilUtc -le $SinceUtc) { throw 'UntilUtc must be after SinceUtc.' }

$directories = @(
    $OutputDirectory,
    (Join-Path $OutputDirectory 'prometheus'),
    (Join-Path $OutputDirectory 'cloud-monitoring'),
    (Join-Path $OutputDirectory 'cloud-logging'),
    (Join-Path $OutputDirectory 'cloud-run'),
    (Join-Path $OutputDirectory 'grafana')
)
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

function Write-Json([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-GcloudJson([string[]]$Arguments) {
    $result = & gcloud @Arguments
    if ($LASTEXITCODE -ne 0) { throw "gcloud $($Arguments -join ' ') failed." }
    return ($result | ConvertFrom-Json)
}

function Get-ServiceUrl([string]$Service) {
    $url = (& gcloud run services describe $Service --project $Project --region $Region --format='value(status.url)').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $url) { throw "Could not read URL for $Service." }
    return $url.TrimEnd('/')
}

function Invoke-Prometheus([string]$BaseUrl, [string]$Path, [hashtable]$Query) {
    $parts = foreach ($key in $Query.Keys) {
        "$( [uri]::EscapeDataString($key) )=$( [uri]::EscapeDataString([string]$Query[$key]) )"
    }
    $uri = "$BaseUrl$Path`?$($parts -join '&')"
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $uri -UseBasicParsing
        } catch {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Seconds $attempt
        }
    }
}

function Escape-OpenMetricsLabel([string]$Value) {
    return $Value.Replace('\', '\\').Replace("`n", '\n').Replace('"', '\"')
}

function Add-OpenMetrics([System.IO.StreamWriter]$Writer, $Result) {
    $name = $Result.metric.__name__
    $labels = @($Result.metric.PSObject.Properties | Where-Object { $_.Name -ne '__name__' } | Sort-Object Name)
    $labelText = if ($labels.Count) {
        '{' + (($labels | ForEach-Object { "$($_.Name)=`"$(Escape-OpenMetricsLabel ([string]$_.Value))`"" }) -join ',') + '}'
    } else { '' }
    foreach ($sample in @($Result.values)) {
        $timestamp = ([double]$sample[0]).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $Writer.WriteLine("$name$labelText $($sample[1]) $timestamp")
    }
}

function Get-MonitoringSeries([string]$Token, [string]$MetricType, [string]$Service) {
    $filter = "metric.type=`"$MetricType`" AND resource.type=`"cloud_run_revision`" AND resource.labels.`"service_name`"=`"$Service`""
    $base = "https://monitoring.googleapis.com/v3/projects/$Project/timeSeries?filter=$([uri]::EscapeDataString($filter))&interval.startTime=$([uri]::EscapeDataString($SinceUtc.ToString('o')))&interval.endTime=$([uri]::EscapeDataString($UntilUtc.ToString('o')))&view=FULL"
    $headers = @{ Authorization = "Bearer $Token" }
    $series = @()
    $url = $base
    do {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing
        $series += @($response.timeSeries)
        $nextPageToken = $response.PSObject.Properties['nextPageToken']
        $url = if ($nextPageToken -and $nextPageToken.Value) { "$base&pageToken=$([uri]::EscapeDataString($nextPageToken.Value))" } else { $null }
    } while ($url)
    return $series
}

$prometheusUrl = Get-ServiceUrl 'ride-matching-loadtest-prometheus'
$grafanaUrl = Get-ServiceUrl 'ride-matching-loadtest-grafana'
$start = $SinceUtc.ToString('o')
$end = $UntilUtc.ToString('o')
$selector = "{testid=`"$RunId`"}"
$seriesResponse = Invoke-Prometheus $prometheusUrl '/api/v1/series' @{
    'match[]' = $selector
    start     = $start
    end       = $end
}
if ($seriesResponse.status -ne 'success' -or -not @($seriesResponse.data).Count) {
    throw "Prometheus has no series for $RunId in the requested time window."
}

$metricNames = @($seriesResponse.data | ForEach-Object { $_.__name__ } | Sort-Object -Unique)
Write-Json (Join-Path $OutputDirectory 'prometheus\series.json') $seriesResponse
Set-Content -LiteralPath (Join-Path $OutputDirectory 'prometheus\metric-names.txt') -Value $metricNames -Encoding utf8

$openMetricsPath = Join-Path $OutputDirectory 'prometheus\metrics.prom'
$writer = [System.IO.StreamWriter]::new($openMetricsPath, $false, [System.Text.UTF8Encoding]::new($false))
$writer.NewLine = "`n"
try {
    foreach ($metricName in $metricNames) {
        $query = "$metricName$selector"
        $response = Invoke-Prometheus $prometheusUrl '/api/v1/query_range' @{
            query = $query
            start = $start
            end   = $end
            step  = '5s'
        }
        if ($response.status -ne 'success') { throw "Prometheus query failed for $metricName." }
        Write-Json (Join-Path $OutputDirectory "prometheus\$metricName.json") $response
        foreach ($result in @($response.data.result)) { Add-OpenMetrics $writer $result }
    }
    $writer.WriteLine('# EOF')
} finally {
    $writer.Dispose()
}

$tsdbDirectory = Join-Path $OutputDirectory 'prometheus\tsdb'
$tsdbContainer = "ride-matching-tsdb-$([guid]::NewGuid().ToString('N'))"
try {
    & docker create --name $tsdbContainer --entrypoint promtool -v "${OutputDirectory}:/archive:ro" prom/prometheus:v3.5.0 tsdb create-blocks-from openmetrics /archive/prometheus/metrics.prom /tmp/tsdb | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the offline Prometheus importer container.' }
    & docker start -a $tsdbContainer | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not import the Prometheus time series.' }
    & docker cp "${tsdbContainer}:/tmp/tsdb" $tsdbDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Could not copy the offline Prometheus TSDB from the importer container.' }
} finally {
    & docker rm -f $tsdbContainer 2>$null | Out-Null
}
if (-not (Test-Path -LiteralPath $tsdbDirectory)) {
    throw 'Could not create the offline Prometheus TSDB.'
}

$token = (& gcloud auth print-access-token).Trim()
if ($LASTEXITCODE -ne 0 -or -not $token) { throw 'Could not obtain a Google Cloud access token.' }
$cells = @('spring-jvm-1cpu', 'spring-jvm-2cpu', 'quarkus-jvm-1cpu', 'quarkus-jvm-2cpu')
$monitoringMetrics = @(
    'run.googleapis.com/container/cpu/utilizations',
    'run.googleapis.com/container/memory/utilizations',
    'run.googleapis.com/request_count',
    'run.googleapis.com/request_latencies',
    'run.googleapis.com/container/instance_count'
)
$resourceRows = @()
foreach ($cell in $cells) {
    $service = "ride-matching-loadtest-$cell"
    foreach ($metricType in $monitoringMetrics) {
        $series = Get-MonitoringSeries $token $metricType $service
        $safeMetric = $metricType.Replace('/', '_')
        Write-Json (Join-Path $OutputDirectory "cloud-monitoring\$cell-$safeMetric.json") $series
        if ($metricType -match 'container/(cpu|memory)/utilizations') {
            $values = @($series | ForEach-Object { $_.points } | ForEach-Object {
                $distribution = $_.value.PSObject.Properties['distributionValue']
                $mean = if ($distribution) { $distribution.Value.PSObject.Properties['mean'] } else { $null }
                if ($mean) { $mean.Value }
            } | Where-Object { $null -ne $_ })
            if ($values.Count) {
                $resourceRows += [PSCustomObject]@{
                    implementation = $cell
                    metric         = $metricType
                    samples        = $values.Count
                    mean           = [math]::Round((($values | Measure-Object -Average).Average), 6)
                    peak           = [math]::Round((($values | Measure-Object -Maximum).Maximum), 6)
                }
            }
        }
    }
}
$resourceRows | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'resource-summary.csv') -NoTypeInformation -Encoding utf8

$requestSeries = Get-Content -LiteralPath (Join-Path $OutputDirectory 'prometheus\k6_http_reqs_total.json') -Raw | ConvertFrom-Json
$scorecard = @{}
$endpointRows = @()
foreach ($result in @($requestSeries.data.result)) {
    $labels = $result.metric
    if ($labels.flow -ne 'population-ramp') { continue }
    $values = @($result.values | ForEach-Object { [double]$_[1] })
    if (-not $values.Count) { continue }
    $value = ($values | Measure-Object -Maximum).Maximum
    $implementation = $labels.implementation
    if (-not $scorecard.ContainsKey($implementation)) {
        $scorecard[$implementation] = [ordered]@{
            implementation        = $implementation
            application_requests  = 0
            unexpected_requests   = 0
            completed_lifecycles  = 0
            aborted_lifecycles    = 0
        }
    }
    $scorecard[$implementation].application_requests += $value
    if ($labels.expected_response -eq 'false') { $scorecard[$implementation].unexpected_requests += $value }
    $endpointRows += [PSCustomObject]@{
        implementation     = $implementation
        endpoint           = $labels.name
        status             = $labels.status
        expected_response  = $labels.expected_response
        requests           = $value
    }
}
foreach ($metric in @('k6_ride_lifecycles_completed_total', 'k6_ride_lifecycles_aborted_total')) {
    $path = Join-Path $OutputDirectory "prometheus\$metric.json"
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    foreach ($result in @($data.data.result)) {
        if ($result.metric.flow -ne 'population-ramp') { continue }
        $implementation = $result.metric.implementation
        if (-not $scorecard.ContainsKey($implementation)) { continue }
        $value = (@($result.values | ForEach-Object { [double]$_[1] }) | Measure-Object -Maximum).Maximum
        $key = if ($metric -match 'completed') { 'completed_lifecycles' } else { 'aborted_lifecycles' }
        $scorecard[$implementation][$key] += $value
    }
}
@($scorecard.Values | ForEach-Object { [PSCustomObject]$_ }) | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'scorecard.csv') -NoTypeInformation -Encoding utf8
$endpointRows | Export-Csv -LiteralPath (Join-Path $OutputDirectory 'endpoint-summary.csv') -NoTypeInformation -Encoding utf8

foreach ($cell in $cells) {
    $service = "ride-matching-loadtest-$cell"
    $job = "$service-k6"
    $serviceDescription = Invoke-GcloudJson @('run', 'services', 'describe', $service, '--project', $Project, '--region', $Region, '--format=json')
    $jobDescription = Invoke-GcloudJson @('run', 'jobs', 'describe', $job, '--project', $Project, '--region', $Region, '--format=json')
    $executions = Invoke-GcloudJson @('run', 'jobs', 'executions', 'list', '--job', $job, '--project', $Project, '--region', $Region, '--format=json')
    Write-Json (Join-Path $OutputDirectory "cloud-run\$cell-service.json") $serviceDescription
    Write-Json (Join-Path $OutputDirectory "cloud-run\$cell-job.json") $jobDescription
    Write-Json (Join-Path $OutputDirectory "cloud-run\$cell-executions.json") $executions
    & gcloud run services logs read $service --project $Project --region $Region --freshness=3h --limit 10000 --format=json | Set-Content -LiteralPath (Join-Path $OutputDirectory "cloud-logging\$cell-service.json") -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "Could not export logs for $service." }
    & gcloud run jobs logs read $job --project $Project --region $Region --freshness=3h --limit 10000 --format=json | Set-Content -LiteralPath (Join-Path $OutputDirectory "cloud-logging\$cell-job.json") -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw "Could not export logs for $job." }
}

$dashboard = Invoke-RestMethod -Uri "$grafanaUrl/api/dashboards/uid/ride-gcp-load-test" -UseBasicParsing
Write-Json (Join-Path $OutputDirectory 'grafana\ride-gcp-load-test.json') $dashboard

$files = @(Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' })
$manifest = [PSCustomObject]@{
    run_id          = $RunId
    project         = $Project
    region          = $Region
    since_utc       = $SinceUtc.ToString('o')
    until_utc       = $UntilUtc.ToString('o')
    prometheus_url  = $prometheusUrl
    grafana_url     = $grafanaUrl
    exported_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    files           = @($files | ForEach-Object {
        [PSCustomObject]@{
            path   = $_.FullName.Substring($OutputDirectory.Length + 1)
            bytes  = $_.Length
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    })
}
Write-Json (Join-Path $OutputDirectory 'manifest.json') $manifest
Write-Host "Evidence exported to $OutputDirectory"
