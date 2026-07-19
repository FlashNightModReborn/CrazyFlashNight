param(
    [string]$ProjectRoot,
    [Parameter(Mandatory=$true)]
    [string]$Repository,
    [Parameter(Mandatory=$true)]
    [string]$StartRevision,
    [string]$HeadRevision = 'HEAD',
    [Parameter(Mandatory=$true)]
    [long]$WorkflowId,
    [Parameter(Mandatory=$true)]
    [string]$WorkflowPath,
    [Parameter(Mandatory=$true)]
    [string]$CheckName,
    [Parameter(Mandatory=$true)]
    [long]$CheckAppId,
    [string]$TargetBranch = 'main'
)

$ErrorActionPreference = 'Stop'

function Test-Cf7SafeRevision([string]$Revision) {
    if ([string]::IsNullOrWhiteSpace($Revision) -or $Revision -match '^0+$') { return $false }
    if ($Revision.StartsWith('-') -or $Revision.Contains('..') -or $Revision.Contains(':') -or
            $Revision.Contains('\\') -or $Revision.Contains('@{')) { return $false }
    return $Revision -match '^[A-Za-z0-9][A-Za-z0-9._/^-]*$'
}

function Resolve-Cf7Commit([string]$Revision) {
    if (-not (Test-Cf7SafeRevision $Revision)) { throw "Unsafe or invalid Git revision: $Revision" }
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $ProjectRoot rev-parse --verify "$Revision^{commit}" 2>$null)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    if ($exitCode -ne 0 -or $output.Count -ne 1 -or [string]$output[0] -notmatch '^[0-9a-fA-F]{40,64}$') {
        throw "Cannot resolve Git commit: $Revision"
    }
    return ([string]$output[0]).Trim().ToLowerInvariant()
}

function Invoke-Cf7GitHubGet([string]$RelativePath) {
    $uri = 'https://api.github.com/' + $RelativePath.TrimStart('/')
    $headers = @{
        Accept = 'application/vnd.github+json'
        Authorization = 'Bearer ' + $script:GitHubToken
        'X-GitHub-Api-Version' = '2026-03-10'
        'User-Agent' = 'cf7-runtime-trusted-base'
    }
    try {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    } catch {
        $status = 'unknown'
        try { $status = [int]$_.Exception.Response.StatusCode } catch {}
        throw "GitHub API GET failed (HTTP $status): $RelativePath"
    }
}

function Get-Cf7WorkflowRunLink([string]$DetailsUrl) {
    if ([string]::IsNullOrWhiteSpace($DetailsUrl)) { return $null }
    $escapedRepository = [regex]::Escape($Repository)
    $match = [regex]::Match(
        $DetailsUrl,
        '^https://github\.com/' + $escapedRepository + '/actions/runs/([0-9]+)/job/([0-9]+)(?:\?.*)?$'
    )
    if (-not $match.Success) { return $null }
    $runId = [long]0
    $jobId = [long]0
    if (-not [long]::TryParse($match.Groups[1].Value, [ref]$runId) -or $runId -le 0 -or
            -not [long]::TryParse($match.Groups[2].Value, [ref]$jobId) -or $jobId -le 0) { return $null }
    return [pscustomobject]@{ RunId=$runId; JobId=$jobId }
}

function Test-Cf7WorkflowRun($Run, [long]$ExpectedRunId, [long]$ExpectedCheckSuiteId, [string]$ExpectedCommit) {
    if ($null -eq $Run) { return $false }
    return $ExpectedRunId -gt 0 -and $ExpectedCheckSuiteId -gt 0 -and
        [long]$Run.id -eq $ExpectedRunId -and
        [long]$Run.check_suite_id -eq $ExpectedCheckSuiteId -and
        [long]$Run.workflow_id -eq $WorkflowId -and
        [string]$Run.path -ceq $WorkflowPath -and
        [string]$Run.event -ceq 'push' -and
        [string]$Run.status -ceq 'completed' -and
        [string]$Run.conclusion -ceq 'success' -and
        [string]$Run.head_branch -ceq $TargetBranch -and
        [string]$Run.head_sha -ceq $ExpectedCommit -and
        [string]$Run.repository.full_name -ieq $Repository -and
        [string]$Run.head_repository.full_name -ieq $Repository
}

if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path.TrimEnd('\\')
if ($Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Repository must be owner/name.' }
if ($WorkflowId -le 0) { throw 'WorkflowId must be a positive GitHub database ID.' }
if ($WorkflowPath -cnotmatch '^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$') { throw 'WorkflowPath is invalid.' }
if ($CheckName -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_. -]{0,99}$') { throw 'CheckName is invalid.' }
if ($CheckAppId -le 0) { throw 'CheckAppId must be a positive GitHub App ID.' }
if ($TargetBranch -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$' -or $TargetBranch.Contains('..')) {
    throw 'TargetBranch is invalid.'
}
$script:GitHubToken = [string]$env:GITHUB_TOKEN
if ([string]::IsNullOrWhiteSpace($script:GitHubToken) -or
        $script:GitHubToken.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0) {
    throw 'GITHUB_TOKEN is required and must not contain control characters.'
}

$startCommit = Resolve-Cf7Commit $StartRevision
$headCommit = Resolve-Cf7Commit $HeadRevision
& git -C $ProjectRoot merge-base --is-ancestor $startCommit $headCommit *> $null
if ($LASTEXITCODE -ne 0) { throw 'Trusted-base search start must be an ancestor of the classified head.' }

$candidates = @(& git -C $ProjectRoot rev-list --first-parent $startCommit 2>$null)
if ($LASTEXITCODE -ne 0 -or $candidates.Count -eq 0) { throw 'Cannot enumerate trusted-base candidate history.' }
$candidateRanks = @{}
$rank = [long]0
foreach ($candidateValue in $candidates) {
    $candidate = ([string]$candidateValue).Trim().ToLowerInvariant()
    if ($candidate -notmatch '^[0-9a-f]{40,64}$') { throw 'Git returned an invalid trusted-base candidate OID.' }
    if ($candidateRanks.ContainsKey($candidate)) { throw "Git returned a duplicate trusted-base candidate OID: $candidate" }
    $candidateRanks[$candidate] = $rank
    $rank++
}

$pageSize = 100
$workflowSearchResultCap = 1000
$encodedBranch = [Uri]::EscapeDataString($TargetBranch)
$encodedCheckName = [Uri]::EscapeDataString($CheckName)
$candidateRuns = New-Object 'Collections.Generic.List[object]'
$seenRunIds = @{}
$expectedWorkflowRunCount = [long]-1
$receivedWorkflowRunCount = [long]0
$workflowPage = 1
$workflowSearchWasCapped = $false

while ($true) {
    $runsResponse = Invoke-Cf7GitHubGet (
        'repos/' + $Repository + '/actions/workflows/' + $WorkflowId +
        '/runs?branch=' + $encodedBranch + '&event=push&status=success&per_page=' + $pageSize + '&page=' + $workflowPage
    )
    if ($null -eq $runsResponse -or $null -eq $runsResponse.PSObject.Properties['workflow_runs'] -or
            $null -eq $runsResponse.PSObject.Properties['total_count']) {
        throw 'GitHub workflow-runs response lacks total_count or workflow_runs.'
    }
    $responseTotal = [long]0
    if (-not [long]::TryParse([string]$runsResponse.total_count, [ref]$responseTotal) -or $responseTotal -lt 0) {
        throw 'GitHub workflow-runs response has an invalid total_count.'
    }
    if ($expectedWorkflowRunCount -lt 0) { $expectedWorkflowRunCount = $responseTotal }
    elseif ($responseTotal -ne $expectedWorkflowRunCount) {
        throw 'GitHub workflow-runs pagination changed total_count while resolving the trusted base.'
    }

    $pageRuns = @($runsResponse.workflow_runs)
    if ($pageRuns.Count -gt $pageSize) { throw 'GitHub workflow-runs response exceeds the requested page size.' }
    if ($pageRuns.Count -eq 0 -and $receivedWorkflowRunCount -lt $expectedWorkflowRunCount) {
        throw 'GitHub workflow-runs pagination ended before total_count was satisfied.'
    }

    foreach ($run in $pageRuns) {
        $runId = [long]$run.id
        if ($runId -le 0) { throw 'GitHub workflow-runs response contains an invalid run ID.' }
        $runKey = [string]$runId
        if ($seenRunIds.ContainsKey($runKey)) { throw "GitHub workflow-runs pagination returned duplicate run ID $runId." }
        $seenRunIds[$runKey] = $true

        $runCommit = ([string]$run.head_sha).ToLowerInvariant()
        if ($runCommit -notmatch '^[0-9a-f]{40,64}$') { continue }
        if (-not $candidateRanks.ContainsKey($runCommit)) { continue }
        if ([string]$run.head_sha -cne $runCommit) { continue }
        if (Test-Cf7WorkflowRun -Run $run -ExpectedRunId $runId `
                -ExpectedCheckSuiteId ([long]$run.check_suite_id) -ExpectedCommit $runCommit) {
            [void]$candidateRuns.Add($run)
        }
    }

    $receivedWorkflowRunCount += $pageRuns.Count
    if ($receivedWorkflowRunCount -gt $expectedWorkflowRunCount) {
        throw 'GitHub workflow-runs pagination returned more runs than total_count.'
    }
    if ($receivedWorkflowRunCount -eq $expectedWorkflowRunCount) { break }
    # GitHub exposes at most 1,000 results for a workflow-run search that uses
    # branch/event/status filters. A strictly bound anchor inside that window is
    # conservative; finding none still fails closed below.
    if ($expectedWorkflowRunCount -gt $workflowSearchResultCap -and
            $receivedWorkflowRunCount -eq $workflowSearchResultCap) {
        $workflowSearchWasCapped = $true
        break
    }
    if ($pageRuns.Count -lt $pageSize) {
        throw 'GitHub workflow-runs pagination returned a short non-final page.'
    }
    $workflowPage++
}

$orderedCandidateRuns = @($candidateRuns | Sort-Object `
    @{ Expression={ [long]$candidateRanks[([string]$_.head_sha).ToLowerInvariant()] }; Ascending=$true }, `
    @{ Expression={ [long]$_.id }; Descending=$true })
$selected = $null
$checkPagesScanned = 0

foreach ($candidateRun in $orderedCandidateRuns) {
    $candidate = ([string]$candidateRun.head_sha).ToLowerInvariant()
    $matchingChecks = New-Object 'Collections.Generic.List[object]'
    $seenCheckIds = @{}
    $expectedCheckCount = [long]-1
    $receivedCheckCount = [long]0
    $checkPage = 1

    while ($true) {
        $checks = Invoke-Cf7GitHubGet (
            'repos/' + $Repository + '/commits/' + $candidate +
            '/check-runs?check_name=' + $encodedCheckName + '&filter=all&per_page=' + $pageSize + '&page=' + $checkPage
        )
        $checkPagesScanned++
        if ($null -eq $checks -or $null -eq $checks.PSObject.Properties['check_runs'] -or
                $null -eq $checks.PSObject.Properties['total_count']) {
            throw 'GitHub check-runs response lacks total_count or check_runs.'
        }
        $checkTotal = [long]0
        if (-not [long]::TryParse([string]$checks.total_count, [ref]$checkTotal) -or $checkTotal -lt 0) {
            throw "GitHub check-runs response has an invalid total_count: $([string]$checks.total_count)"
        }
        if ($expectedCheckCount -lt 0) { $expectedCheckCount = $checkTotal }
        elseif ($checkTotal -ne $expectedCheckCount) {
            throw "GitHub check-runs pagination changed total_count for $candidate."
        }

        $pageChecks = @($checks.check_runs)
        if ($pageChecks.Count -gt $pageSize) { throw 'GitHub check-runs response exceeds the requested page size.' }
        if ($pageChecks.Count -eq 0 -and $receivedCheckCount -lt $expectedCheckCount) {
            throw "GitHub check-runs pagination ended early for $candidate."
        }
        foreach ($check in $pageChecks) {
            $checkId = [long]$check.id
            if ($checkId -le 0) { throw 'GitHub check-runs response contains an invalid check ID.' }
            $checkKey = [string]$checkId
            if ($seenCheckIds.ContainsKey($checkKey)) { throw "GitHub check-runs pagination returned duplicate check ID $checkId." }
            $seenCheckIds[$checkKey] = $true

            $runLink = Get-Cf7WorkflowRunLink ([string]$check.details_url)
            if ([string]$check.name -ceq $CheckName -and
                    [string]$check.head_sha -ceq $candidate -and
                    [string]$check.status -ceq 'completed' -and
                    [string]$check.conclusion -ceq 'success' -and
                    $null -ne $check.app -and [long]$check.app.id -eq $CheckAppId -and
                    $null -ne $check.check_suite -and
                    [long]$check.check_suite.id -eq [long]$candidateRun.check_suite_id -and
                    $null -ne $runLink -and [long]$runLink.RunId -eq [long]$candidateRun.id -and
                    [long]$runLink.JobId -eq $checkId) {
                [void]$matchingChecks.Add($check)
            }
        }

        $receivedCheckCount += $pageChecks.Count
        if ($receivedCheckCount -gt $expectedCheckCount) {
            throw "GitHub check-runs pagination returned more checks than total_count for $candidate."
        }
        if ($receivedCheckCount -eq $expectedCheckCount) { break }
        if ($pageChecks.Count -lt $pageSize) { throw "GitHub check-runs pagination returned a short non-final page for $candidate." }
        $checkPage++
    }

    if ($matchingChecks.Count -gt 1) {
        throw "Ambiguous trusted-base check binding for workflow run $([long]$candidateRun.id)."
    }
    if ($matchingChecks.Count -eq 0) { continue }

    $check = $matchingChecks[0]
    $run = Invoke-Cf7GitHubGet ('repos/' + $Repository + '/actions/runs/' + [long]$candidateRun.id)
    if (Test-Cf7WorkflowRun -Run $run -ExpectedRunId ([long]$candidateRun.id) `
            -ExpectedCheckSuiteId ([long]$check.check_suite.id) -ExpectedCommit $candidate) {
        $selected = [pscustomobject]@{
            Commit=$candidate
            CheckId=[long]$check.id
            RunId=[long]$candidateRun.id
            Rank=[long]$candidateRanks[$candidate]
        }
        break
    }
}

if ($null -eq $selected) {
    throw "No trusted successful $CheckName anchor was found in $($candidateRanks.Count) first-parent commits from $startCommit."
}

Write-Host "[RuntimeTrustedBase] OK anchor=$($selected.Commit) checkId=$($selected.CheckId) runId=$($selected.RunId) rank=$($selected.Rank) candidates=$($candidateRanks.Count) workflowPages=$workflowPage workflowSearchCapped=$workflowSearchWasCapped checkPages=$checkPagesScanned start=$startCommit head=$headCommit" -ForegroundColor Green
Write-Output "CF7_TRUSTED_BASE=$($selected.Commit)"
