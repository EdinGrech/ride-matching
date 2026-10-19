[CmdletBinding()]
param(
    [ValidateSet('spring', 'quarkus')]
    [string]$Backend = 'spring',
    [ValidateSet(1, 2)]
    [int]$Cpu = 1,
    [switch]$Quick,
    [string]$BaseUrl
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$compose = @('-f', (Join-Path $root 'compose.yaml'), '-f', (Join-Path $root 'compose.observability.yaml'), '-f', (Join-Path $root 'compose.benchmark.yaml'))

$env:RUN_ID = Get-Date -Format 'yyyyMMdd-HHmmss'
$env:BENCHMARK_PROFILE = if ($Quick) { 'quick' } else { 'full' }

if ($BaseUrl) {
    $target = [Uri]$BaseUrl
    if (-not $target.IsAbsoluteUri -or $target.Scheme -ne 'https') {
        throw '-BaseUrl must be an absolute HTTPS URL.'
    }
    $env:BASE_URL = $target.AbsoluteUri.TrimEnd('/')
    $env:IMPLEMENTATION = 'gcp-cloud-run'

    $hasTokens = -not [string]::IsNullOrWhiteSpace($env:RIDER_TOKENS) -and -not [string]::IsNullOrWhiteSpace($env:DRIVER_TOKENS)
    if (-not $hasTokens -and [string]::IsNullOrWhiteSpace($env:TOKEN_ISSUER)) {
        throw 'Set RIDER_TOKENS and DRIVER_TOKENS, or set TOKEN_ISSUER for the deployed test identity provider.'
    }
    if ($env:TOKEN_ISSUER -and [string]::IsNullOrWhiteSpace($env:TOKEN_ISSUER_HOST)) {
        $env:TOKEN_ISSUER_HOST = ([Uri]$env:TOKEN_ISSUER).Authority
    }

    & docker compose @compose up -d cadvisor prometheus grafana
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $apiUrl = "$($env:BASE_URL)/drivers/me/state"
} else {
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

    & docker compose @compose up -d --build --force-recreate mock-idp cadvisor prometheus grafana api
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $apiAddress = (& docker compose @compose port api 8080).Trim()
    $apiUrl = "http://$apiAddress/drivers/me/state"
}

$apiReady = $false
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $apiUrl -ErrorAction Stop | Out-Null
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
if (-not $apiReady) { throw "API did not become reachable at $apiUrl" }

$started = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$k6Command = @('--profile', 'load-test', 'run', '--rm')
if ($BaseUrl) { $k6Command += '--no-deps' }
$k6Command += 'k6'
& docker compose @compose @k6Command
$result = $LASTEXITCODE
$finished = [DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds()
$query = "from=$started&to=$finished&timezone=browser&var-implementation=$($env:IMPLEMENTATION)&var-testid=$($env:RUN_ID)"
Write-Host "Grafana: http://localhost:3000/d/ride-benchmark/ride-benchmark?$query"
exit $result
