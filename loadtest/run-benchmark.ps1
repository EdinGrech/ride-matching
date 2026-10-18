[CmdletBinding()]
param(
    [ValidateSet('spring', 'quarkus')]
    [string]$Backend = 'spring',
    [ValidateSet(1, 2)]
    [int]$Cpu = 1,
    [switch]$Quick
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$compose = @('-f', (Join-Path $root 'compose.yaml'), '-f', (Join-Path $root 'compose.observability.yaml'), '-f', (Join-Path $root 'compose.benchmark.yaml'))

if ($Backend -eq 'spring') {
    & (Join-Path $root 'ride-matching-springboot\mvnw.cmd') -f (Join-Path $root 'ride-matching-springboot\pom.xml') package
    $env:API_CONTEXT = './ride-matching-springboot'
    Remove-Item Env:API_DOCKERFILE -ErrorAction SilentlyContinue
} else {
    & (Join-Path $root 'ride-matching-quarkus\mvnw.cmd') -f (Join-Path $root 'ride-matching-quarkus\pom.xml') package
    $env:API_CONTEXT = './ride-matching-quarkus'
    $env:API_DOCKERFILE = 'src/main/docker/Dockerfile.jvm'
}
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$env:API_CPUS = "$Cpu.0"
$env:API_MEMORY = '512m'
$env:IMPLEMENTATION = "$Backend-jvm-$Cpu`cpu"
$env:RUN_ID = Get-Date -Format 'yyyyMMdd-HHmmss'
$env:BENCHMARK_PROFILE = if ($Quick) { 'quick' } else { 'full' }

& docker compose @compose up -d --build --force-recreate mock-idp cadvisor prometheus grafana api
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apiAddress = (& docker compose @compose port api 8080).Trim()
$apiReady = $false
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "http://$apiAddress/drivers/me/state" -ErrorAction Stop | Out-Null
        $apiReady = $true
        break
    } catch {
        if ($_.Exception.Response) {
            $apiReady = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}
if (-not $apiReady) { throw "API did not become reachable at http://$apiAddress" }

$started = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
& docker compose @compose --profile load-test run --rm k6
$result = $LASTEXITCODE
$finished = [DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds()
$query = "from=$started&to=$finished&timezone=browser&var-implementation=$($env:IMPLEMENTATION)&var-testid=$($env:RUN_ID)"
Write-Host "Grafana: http://localhost:3000/d/ride-benchmark/ride-benchmark?$query"
exit $result
