[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z][a-z0-9-]{4,28}[a-z0-9]$')]
    [string]$Project,

    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z]+-[a-z]+[0-9]$')]
    [string]$Region,

    [ValidateSet('quick', 'full')]
    [string]$Profile = 'quick',

    [switch]$Full,

    [switch]$Reset,

    [switch]$Destroy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($Full -and $PSBoundParameters.ContainsKey('Profile')) {
    throw 'Use either -Full or -Profile, not both.'
}
if ($Full) {
    $Profile = 'full'
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$terraformDirectory = Join-Path $root 'infra\gcp'
$repository = 'ride-matching-loadtest'
$serviceName = 'ride-matching-loadtest'
$buildId = "loadtest-$(Get-Date -Format 'yyyyMMddHHmmss')"
$runId = "run-$(Get-Date -Format 'yyyyMMddHHmmss')"
$builder = "$serviceName-builder@$Project.iam.gserviceaccount.com"

function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File failed with exit code $LASTEXITCODE."
    }
}

function Terraform([string[]]$Arguments) {
    Invoke-Native 'terraform.exe' (@("-chdir=$terraformDirectory") + $Arguments)
}

function Get-StateRepository {
    $state = & terraform.exe "-chdir=$terraformDirectory" state show google_artifact_registry_repository.images 2>$null
    if ($LASTEXITCODE -eq 0) {
        $repositoryId = (($state | Select-String '^\s*repository_id\s*=') -replace '.*"([^"]+)".*', '$1').Trim()
        if ($repositoryId) {
            return $repositoryId
        }
    }
    return $repository
}

function Remove-ArtifactPackages([string]$Repository) {
    $packages = & gcloud artifacts packages list --project $Project --location $Region --repository $Repository --format='value(name)'
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not list Artifact Registry packages.'
    }

    foreach ($package in $packages) {
        if ($package) {
            Invoke-Native 'gcloud' @('artifacts', 'packages', 'delete', $package, '--project', $Project, '--quiet')
        }
    }
}

$variables = @(
    "-var=gcp_project=$Project",
    "-var=region=$Region",
    "-var=build_id=$buildId",
    "-var=test_run_id=$runId",
    "-var=benchmark_profile=$Profile",
    "-var=artifact_repository_id=$repository"
)
$bootstrapVariables = @(
    "-var=gcp_project=$Project",
    "-var=region=$Region",
    "-var=artifact_repository_id=$repository"
)

Terraform @('init', '-input=false')

if ($Reset -and $Destroy) {
    throw 'Use either -Reset or -Destroy, not both.'
}

if ($Reset -or $Destroy) {
    try {
        Terraform (@('destroy', '-auto-approve') + $variables)
    } catch {
        Write-Host 'Removing published images before retrying Terraform destroy.'
        Remove-ArtifactPackages (Get-StateRepository)
        Terraform (@('destroy', '-auto-approve') + $variables)
    }
}

if ($Destroy) {
    return
}

Terraform (@(
    'apply', '-auto-approve',
    '-target=google_project_service.required',
    '-target=google_artifact_registry_repository.images',
    '-target=google_service_account.builder',
    '-target=google_project_iam_member.builder'
) + $bootstrapVariables)

Write-Host 'Waiting for Cloud Build service-account permissions to propagate.'
Start-Sleep -Seconds 60
$buildOutput = & gcloud builds submit $root --async --format='value(id)' --project $Project --config (Join-Path $root 'cloudbuild.yaml') --substitutions "_REGION=$Region,_REPOSITORY=$repository,_TAG=$buildId" --service-account "projects/$Project/serviceAccounts/$builder"
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create the Cloud Build build.'
}
$build = ($buildOutput -join '').Trim()
if (-not $build) { throw 'Cloud Build did not return a build ID.' }

do {
    Start-Sleep -Seconds 5
    $buildStatus = (& gcloud builds describe $build --project $Project --format='value(status)').Trim()
    Write-Host "Cloud Build ${build}: $buildStatus"
} while ($buildStatus -in @('QUEUED', 'WORKING'))

if ($buildStatus -ne 'SUCCESS') {
    throw "Cloud Build $build ended with status $buildStatus."
}

Terraform (@('apply', '-auto-approve') + $variables)

Write-Host 'Waiting for Cloud Run invoker permissions to propagate.'
Start-Sleep -Seconds 60
$jobs = ((& terraform.exe "-chdir=$terraformDirectory" output -json loadtest_jobs) | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the load-test job outputs.'
}
$grafana = (& terraform.exe "-chdir=$terraformDirectory" output -raw grafana_url).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the Grafana URL.'
}

$launches = @{}
foreach ($property in $jobs.PSObject.Properties) {
    $launches[$property.Name] = Start-Job -ScriptBlock {
        param($JobName, $ProjectId, $JobRegion)
        $output = & gcloud run jobs execute $JobName --project $ProjectId --region $JobRegion --format='value(metadata.name)' 2>$null
        if ($LASTEXITCODE -ne 0) { throw "Could not start $JobName." }
        $executionName = ($output -join '').Trim()
        if (-not $executionName) { throw "$JobName did not return an execution name." }
        $executionName
    } -ArgumentList $property.Value, $Project, $Region
}

$executions = @{}
foreach ($cell in $launches.Keys) {
    $launch = $launches[$cell]
    $execution = (Receive-Job -Job $launch -Wait | Out-String).Trim()
    if ($launch.State -ne 'Completed') {
        $reason = $launch.ChildJobs[0].JobStateInfo.Reason
        Remove-Job -Job $launch -Force
        throw "Could not start the $cell load-test job. $reason"
    }
    Remove-Job -Job $launch
    if (-not $execution) { throw "Could not start the $cell load-test job." }
    $executions[$cell] = $execution
    Write-Host "Started ${cell}: $execution"
}

$pending = [System.Collections.Generic.HashSet[string]]::new([string[]]$executions.Keys)
$failures = @()
while ($pending.Count -gt 0) {
    Start-Sleep -Seconds 10
    foreach ($cell in @($pending)) {
        $execution = $executions[$cell]
        $details = (& gcloud run jobs executions describe $execution --project $Project --region $Region --format=json | ConvertFrom-Json)
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect the $cell execution: $execution"
        }

        $completed = @($details.status.conditions | Where-Object { $_.type -eq 'Completed' })
        if (-not $completed) {
            continue
        }
        if ($completed[0].status -eq 'Unknown') {
            continue
        }

        [void]$pending.Remove($cell)
        if ($completed[0].status -eq 'True') {
            Write-Host "Completed ${cell}: $execution"
        } else {
            $failures += [PSCustomObject]@{
                Cell    = $cell
                Message = $completed[0].message
                Logs    = $details.status.logUri
            }
        }
    }
}

$dashboard = "$grafana/d/ride-gcp-load-test/ride-gcp-load-test?var-testid=$runId"
Write-Host "Grafana: $dashboard"
if ($failures.Count -gt 0) {
    $failures | Format-List | Out-String | Write-Host
    throw "$($failures.Count) load-test cell(s) failed."
}
