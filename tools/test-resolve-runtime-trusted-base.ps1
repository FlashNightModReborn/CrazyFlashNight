param([string]$TestNamePattern)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$resolver = Join-Path $repoRoot 'tools\resolve-runtime-trusted-base.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-trusted-base-tests-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$passed = 0
$failed = 0

function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-TestGit([string[]]$Arguments) {
    $output = @(& git -C $script:testRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join ' ')" }
    return @($output)
}

function Set-TestFile([string]$RelativePath, [string]$Content) {
    $path = Join-Path $script:testRoot ($RelativePath -replace '/','\')
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [IO.File]::WriteAllText($path, $Content, $script:utf8)
}

function Add-TestCommit([string]$RelativePath, [string]$Content, [string]$Message) {
    Set-TestFile $RelativePath $Content
    [void](Invoke-TestGit @('add','--',$RelativePath))
    [void](Invoke-TestGit @('commit','-m',$Message))
    $headLines = @(Invoke-TestGit @('rev-parse','HEAD'))
    return ([string]$headLines[0]).Trim().ToLowerInvariant()
}

function Run-Test([string]$Name, [scriptblock]$Body) {
    if ($TestNamePattern -and $Name -notmatch $TestNamePattern) { return }
    try {
        & $Body
        $script:passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-MockRun(
        [string]$Sha,
        [long]$RunId = 9001,
        [long]$SuiteId = 7001,
        [long]$WorkflowId = 314853607,
        [string]$Path = '.github/workflows/runtime-bundle-integrity.yml',
        [string]$Event = 'push',
        [string]$Status = 'completed',
        [string]$Conclusion = 'success',
        [string]$Branch = 'main',
        [string]$Repository = 'FlashNightModReborn/CrazyFlashNight',
        [string]$HeadRepository = 'FlashNightModReborn/CrazyFlashNight') {
    return [pscustomobject]@{
        id=$RunId
        check_suite_id=$SuiteId
        workflow_id=$WorkflowId
        path=$Path
        event=$Event
        status=$Status
        conclusion=$Conclusion
        head_branch=$Branch
        head_sha=$Sha
        repository=[pscustomobject]@{ full_name=$Repository }
        head_repository=[pscustomobject]@{ full_name=$HeadRepository }
    }
}

function New-MockCheck(
        [string]$Sha,
        [long]$RunId = 9001,
        [long]$CheckId = 8001,
        [long]$SuiteId = 7001,
        [long]$AppId = 15368,
        [string]$Name = 'verify-staged-bundle',
        [string]$Status = 'completed',
        [string]$Conclusion = 'success',
        [long]$JobId = 0) {
    if ($JobId -le 0) { $JobId = $CheckId }
    return [pscustomobject]@{
        id=$CheckId
        name=$Name
        head_sha=$Sha
        status=$Status
        conclusion=$Conclusion
        app=[pscustomobject]@{ id=$AppId }
        check_suite=[pscustomobject]@{ id=$SuiteId }
        details_url="https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/$RunId/job/$JobId"
    }
}

function Set-StandardMock([string]$Sha) {
    $run = New-MockRun -Sha $Sha
    $check = New-MockCheck -Sha $Sha
    $global:CF7MockWorkflowRuns = @($run)
    $global:CF7MockChecksBySha = @{ $Sha = @($check) }
    $global:CF7MockRunDetails = @{ '9001' = $run }
    $global:CF7MockWorkflowTotalCountOverride = $null
    $global:CF7MockCalls.Clear()
}

function Invoke-TestResolver([string]$Start, [string]$Head) {
    return @(& $script:resolver `
        -ProjectRoot $script:testRoot `
        -Repository 'FlashNightModReborn/CrazyFlashNight' `
        -StartRevision $Start `
        -HeadRevision $Head `
        -WorkflowId 314853607 `
        -WorkflowPath '.github/workflows/runtime-bundle-integrity.yml' `
        -CheckName 'verify-staged-bundle' `
        -CheckAppId 15368)
}

try {
    [void](New-Item -ItemType Directory -Path $testRoot -Force)
    [void](Invoke-TestGit @('init'))
    [void](Invoke-TestGit @('config','user.name','CF7 Trusted Base Test'))
    [void](Invoke-TestGit @('config','user.email','trusted-base@example.invalid'))
    [void](Invoke-TestGit @('config','core.autocrlf','false'))
    $good = Add-TestCommit 'docs/base.md' 'green' 'green anchor'
    $redCommits = New-Object 'Collections.Generic.List[string]'
    for ($index = 1; $index -le 130; $index++) {
        $red = Add-TestCommit 'launcher/src/Drift.cs' "native drift $index" "unverified native drift $index"
        [void]$redCommits.Add($red)
    }
    $bad = $redCommits[$redCommits.Count - 1]
    $head = Add-TestCommit 'docs/after.md' 'content' 'content after drift'

    $global:CF7MockWorkflowRuns = @()
    $global:CF7MockChecksBySha = @{}
    $global:CF7MockRunDetails = @{}
    $global:CF7MockCalls = New-Object 'Collections.Generic.List[string]'
    function global:Invoke-RestMethod {
        param([string]$Method, [string]$Uri, $Headers)
        [void]$global:CF7MockCalls.Add($Uri)
        $page = 1
        if ($Uri -match '[?&]page=([0-9]+)') { $page = [int]$Matches[1] }
        $perPage = 100
        if ($Uri -match '[?&]per_page=([0-9]+)') { $perPage = [int]$Matches[1] }

        if ($Uri -match '/actions/workflows/314853607/runs\?') {
            [object[]]$allRuns = @($global:CF7MockWorkflowRuns)
            $offset = ($page - 1) * $perPage
            $items = if ($offset -ge $allRuns.Count) { @() } else {
                @($allRuns | Select-Object -Skip $offset -First $perPage)
            }
            $totalCount = if ($null -eq $global:CF7MockWorkflowTotalCountOverride) {
                @($allRuns).Count
            } else { [long]$global:CF7MockWorkflowTotalCountOverride }
            return [pscustomobject]@{ total_count=$totalCount; workflow_runs=@($items) }
        }
        if ($Uri -match '/commits/([0-9a-f]{40,64})/check-runs\?') {
            $sha = [string]$Matches[1]
            [object[]]$allChecks = if ($global:CF7MockChecksBySha.ContainsKey($sha)) {
                @($global:CF7MockChecksBySha[$sha])
            } else { @() }
            $offset = ($page - 1) * $perPage
            $items = if ($offset -ge $allChecks.Count) { @() } else {
                @($allChecks | Select-Object -Skip $offset -First $perPage)
            }
            return [pscustomobject]@{ total_count=@($allChecks).Count; check_runs=@($items) }
        }
        if ($Uri -match '/actions/runs/([0-9]+)$') {
            $runKey = [string][long]$Matches[1]
            if ($global:CF7MockRunDetails.ContainsKey($runKey)) { return $global:CF7MockRunDetails[$runKey] }
            throw "Unknown mock workflow run: $runKey"
        }
        throw "Unexpected mock API URI: $Uri"
    }

    $previousToken = [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
    $env:GITHUB_TOKEN = 'unit-test-secret'

    Run-Test 'Finds an old trusted green ancestor across more than 128 red first-parent commits' {
        Set-StandardMock -Sha $good
        $result = @(Invoke-TestResolver -Start $bad -Head $head)
        Assert-Test (@($result | Where-Object { [string]$_ -ceq "CF7_TRUSTED_BASE=$good" }).Count -eq 1) ($result -join ' | ')
        Assert-Test ($global:CF7MockCalls.Count -eq 3) "expected workflow-runs, check-runs, run-detail; calls=$($global:CF7MockCalls.Count)"
        Assert-Test (($result -join "`n") -notmatch 'unit-test-secret') 'resolver output leaked GITHUB_TOKEN'
    }

    Run-Test 'Paginates successful workflow runs before selecting the nearest first-parent candidate' {
        Set-StandardMock -Sha $good
        $decoys = New-Object 'Collections.Generic.List[object]'
        for ($index = 1; $index -le 100; $index++) {
            $decoySha = [Convert]::ToString($index,16).PadLeft(40,'0')
            [void]$decoys.Add((New-MockRun -Sha $decoySha -RunId (10000 + $index) -SuiteId (20000 + $index)))
        }
        [void]$decoys.Add((New-MockRun -Sha $good))
        $global:CF7MockWorkflowRuns = @($decoys | ForEach-Object { $_ })
        $global:CF7MockCalls.Clear()
        $result = @(Invoke-TestResolver -Start $bad -Head $head)
        Assert-Test (@($result | Where-Object { [string]$_ -ceq "CF7_TRUSTED_BASE=$good" }).Count -eq 1) ($result -join ' | ')
        Assert-Test (@($global:CF7MockCalls | Where-Object { $_ -match '/actions/workflows/314853607/runs\?.*&page=2$' }).Count -eq 1) 'resolver did not request workflow-runs page 2'
    }

    Run-Test 'Accepts a bound anchor within the documented 1000-result workflow search window' {
        Set-StandardMock -Sha $good
        $runs = New-Object 'Collections.Generic.List[object]'
        [void]$runs.Add((New-MockRun -Sha $good))
        for ($index = 1; $index -lt 1000; $index++) {
            $decoySha = [Convert]::ToString($index,16).PadLeft(40,'0')
            [void]$runs.Add((New-MockRun -Sha $decoySha -RunId (10000 + $index) -SuiteId (20000 + $index)))
        }
        $global:CF7MockWorkflowRuns = @($runs | ForEach-Object { $_ })
        $global:CF7MockWorkflowTotalCountOverride = 1200
        $global:CF7MockCalls.Clear()
        $result = @(Invoke-TestResolver -Start $bad -Head $head)
        Assert-Test (@($result | Where-Object { [string]$_ -ceq "CF7_TRUSTED_BASE=$good" }).Count -eq 1) ($result -join ' | ')
        Assert-Test (@($global:CF7MockCalls | Where-Object { $_ -match '/actions/workflows/314853607/runs\?' }).Count -eq 10) 'resolver did not exhaust the exposed 1000-result workflow search window'
    }

    Run-Test 'Rejects a success produced by the wrong GitHub App' {
        Set-StandardMock -Sha $good
        $global:CF7MockChecksBySha[$good] = @((New-MockCheck -Sha $good -AppId 99999))
        $threw = $false
        try { [void](Invoke-TestResolver -Start $good -Head $head) } catch { $threw = $true }
        Assert-Test $threw 'wrong-app check unexpectedly became a trusted anchor'
    }

    Run-Test 'Rejects a workflow-list run with the wrong immutable workflow identity' {
        Set-StandardMock -Sha $good
        $global:CF7MockWorkflowRuns = @((New-MockRun -Sha $good -WorkflowId 314853608))
        $threw = $false
        try { [void](Invoke-TestResolver -Start $good -Head $head) } catch { $threw = $true }
        Assert-Test $threw 'wrong-workflow run unexpectedly became a trusted anchor'
    }

    Run-Test 'Rejects run-detail event and suite identity mismatches' {
        foreach ($mutation in @('pull-request','suite')) {
            Set-StandardMock -Sha $good
            if ($mutation -eq 'pull-request') {
                $global:CF7MockRunDetails['9001'] = New-MockRun -Sha $good -Event 'pull_request'
            } else {
                $global:CF7MockRunDetails['9001'] = New-MockRun -Sha $good -SuiteId 7002
            }
            $threw = $false
            try { [void](Invoke-TestResolver -Start $good -Head $head) } catch { $threw = $true }
            Assert-Test $threw "$mutation run-detail mismatch unexpectedly became a trusted anchor"
        }
    }

    Run-Test 'Rejects check job mismatch and ambiguous exact check bindings' {
        Set-StandardMock -Sha $good
        $global:CF7MockChecksBySha[$good] = @((New-MockCheck -Sha $good -JobId 8002))
        $threw = $false
        try { [void](Invoke-TestResolver -Start $good -Head $head) } catch { $threw = $true }
        Assert-Test $threw 'job mismatch unexpectedly became a trusted anchor'

        Set-StandardMock -Sha $good
        $global:CF7MockChecksBySha[$good] = @(
            (New-MockCheck -Sha $good -CheckId 8001),
            (New-MockCheck -Sha $good -CheckId 8002)
        )
        $threw = $false
        try { [void](Invoke-TestResolver -Start $good -Head $head) } catch { $threw = $true }
        Assert-Test $threw 'ambiguous exact checks unexpectedly became a trusted anchor'
    }

    Run-Test 'Rejects incomplete workflow pagination instead of using the immediate base' {
        Set-StandardMock -Sha $good
        $global:CF7MockWorkflowRuns = @(New-MockRun -Sha $good)
        $originalFunction = ${function:global:Invoke-RestMethod}
        function global:Invoke-RestMethod {
            param([string]$Method, [string]$Uri, $Headers)
            if ($Uri -match '/actions/workflows/314853607/runs\?') {
                return [pscustomobject]@{ total_count=101; workflow_runs=@() }
            }
            throw "Unexpected mock API URI: $Uri"
        }
        try {
            $threw = $false
            try { [void](Invoke-TestResolver -Start $bad -Head $head) } catch { $threw = $true }
            Assert-Test $threw 'incomplete pagination unexpectedly fell back to an untrusted base'
        } finally {
            ${function:global:Invoke-RestMethod} = $originalFunction
        }
    }

    Run-Test 'Rejects a search start outside the classified head ancestry' {
        Set-StandardMock -Sha $good
        [void](Invoke-TestGit @('checkout','-q','-b','sibling',$good))
        $sibling = Add-TestCommit 'docs/sibling.md' 'sibling' 'sibling'
        [void](Invoke-TestGit @('checkout','-q','--detach',$head))
        $threw = $false
        try { [void](Invoke-TestResolver -Start $sibling -Head $head) } catch { $threw = $true }
        Assert-Test $threw 'non-ancestor trusted-base search unexpectedly passed'
    }
} finally {
    if ($null -eq $previousToken) { Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue }
    else { $env:GITHUB_TOKEN = $previousToken }
    Remove-Item Function:\Invoke-RestMethod -Force -ErrorAction SilentlyContinue
    foreach ($name in @(
        'CF7MockWorkflowRuns','CF7MockChecksBySha','CF7MockRunDetails',
        'CF7MockWorkflowTotalCountOverride','CF7MockCalls'
    )) {
        Remove-Item ("Variable:\global:$name") -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host "[TrustedBaseTests] passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
