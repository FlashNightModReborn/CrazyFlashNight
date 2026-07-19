param([string]$TestNamePattern)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$auditScript = Join-Path $repoRoot 'tools\audit-main-branch-admission.ps1'
$configPath = Join-Path $repoRoot 'config\build\main-branch-admission.v1.json'
$codeOwnersPath = Join-Path $repoRoot '.github\CODEOWNERS'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-main-admission-tests-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$originalPath = $env:PATH
$passed = 0
$failed = 0

function Assert-Test([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
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

function Invoke-TestAudit([ValidateSet('Prepared','Layered','Active')][string]$ExpectedState, [string]$MockMode = 'normal') {
    $env:CF7_ADMISSION_TEST_STATE = $ExpectedState
    $env:CF7_ADMISSION_TEST_MODE = $MockMode
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:auditScript `
        -ProjectRoot $script:repoRoot -GitHubCliPath $script:fakeGh -ExpectedState $ExpectedState -Json 2>&1 |
        ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $jsonLine = @($output | Where-Object { $_ -match '^\{"schema":"cf7-main-branch-admission-audit\.v1"' } | Select-Object -Last 1)
    $result = if ($jsonLine.Count -eq 1) { $jsonLine[0] | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ ExitCode=$exitCode; Output=($output -join "`n"); Result=$result }
}

$fakeGhImplSource = @'
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath $env:CF7_ADMISSION_TEST_CONFIG -Raw -Encoding UTF8 | ConvertFrom-Json
$endpoint = [string]$Arguments[$Arguments.Count - 1]
$state = [string]$env:CF7_ADMISSION_TEST_STATE
$mode = [string]$env:CF7_ADMISSION_TEST_MODE

function Emit($Value) {
    Write-Output ($Value | ConvertTo-Json -Depth 30 -Compress)
    exit 0
}

function New-RulesetSummary([long]$Id, [string]$Name) {
    $sourceType = if ($mode -eq 'parent-source') { 'Organization' } else { 'Repository' }
    $source = if ($mode -eq 'parent-source') { 'FlashNightModReborn' } else { [string]$config.repository }
    return [ordered]@{ id=$Id; name=$Name; source_type=$sourceType; source=$source }
}

function New-IdentityRuleset {
    $enforcement = if ($state -eq 'Prepared') { 'disabled' } else { 'active' }
    $result = [ordered]@{
        id=101
        name=[string]$config.rulesets.identityGate.name
        source_type='Repository'
        source=[string]$config.repository
        target='branch'
        enforcement=$enforcement
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/heads/main'); exclude=@() } }
        rules=@(
            [ordered]@{
                type='pull_request'
                parameters=[ordered]@{
                    allowed_merge_methods=@('merge')
                    required_reviewers=@()
                    dismiss_stale_reviews_on_push=$true
                    require_code_owner_review=$true
                    require_last_push_approval=$false
                    required_approving_review_count=0
                    required_review_thread_resolution=$false
                }
            },
            [ordered]@{
                type='required_status_checks'
                parameters=[ordered]@{
                    strict_required_status_checks_policy=$true
                    required_status_checks=@([ordered]@{
                        context=[string]$config.requiredStatusCheck.context
                        integration_id=[long]$config.requiredStatusCheck.integrationId
                    })
                }
            }
        )
        current_user_can_bypass=$false
    }
    if ($mode -ne 'missing-bypass') {
        $result.bypass_actors = @($config.actors | Where-Object admission -eq 'directPushBypass' | ForEach-Object {
            [ordered]@{ actor_id=[long]$_.databaseId; actor_type='User'; bypass_mode='always' }
        })
    }
    return $result
}

function New-HistoryRuleset {
    $enforcement = if ($state -eq 'Prepared') { 'disabled' } else { 'active' }
    return [ordered]@{
        id=102
        name=[string]$config.rulesets.globalRefIntegrity.name
        source_type='Repository'
        source=[string]$config.repository
        target='branch'
        enforcement=$enforcement
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/heads/main'); exclude=@() } }
        bypass_actors=@()
        rules=@([ordered]@{ type='deletion' },[ordered]@{ type='non_fast_forward' })
        current_user_can_bypass=$false
    }
}

function New-TagCreationRuleset {
    $enforcement = if ($state -eq 'Prepared') { 'disabled' } else { 'active' }
    return [ordered]@{
        id=103
        name=[string]$config.rulesets.runtimeTagCreation.name
        source_type='Repository'
        source=[string]$config.repository
        target='tag'
        enforcement=$enforcement
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/tags/runtime-build-v2/*'); exclude=@() } }
        bypass_actors=@($config.actors | Where-Object admission -eq 'restricted' | ForEach-Object {
            [ordered]@{ actor_id=[long]$_.databaseId; actor_type='User'; bypass_mode='always' }
        })
        rules=@([ordered]@{ type='creation' })
    }
}

function New-TagImmutabilityRuleset {
    $enforcement = if ($state -eq 'Prepared') { 'disabled' } else { 'active' }
    [object[]]$bypass = @(if ($mode -eq 'tag-immutability-bypass') {
        [ordered]@{ actor_id=91271520; actor_type='User'; bypass_mode='always' }
    })
    return [ordered]@{
        id=104
        name=[string]$config.rulesets.runtimeTagImmutability.name
        source_type='Repository'
        source=[string]$config.repository
        target='tag'
        enforcement=$enforcement
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/tags/runtime-build-v2/*'); exclude=@() } }
        bypass_actors=$bypass
        rules=@(
            [ordered]@{ type='deletion' },
            [ordered]@{
                type='update'
                parameters=[ordered]@{ update_allows_fetch_and_merge=($mode -eq 'tag-weak-update') }
            }
        )
    }
}

switch -Regex ($endpoint) {
    '^user$' { Emit ([ordered]@{ login='Crazyfs'; id=91271520 }) }
    '^repos/FlashNightModReborn/CrazyFlashNight$' {
        Emit ([ordered]@{ default_branch='main'; allow_merge_commit=$true; allow_auto_merge=$true })
    }
    '/actions/workflows/314853607$' {
        if ($mode -eq 'workflow-missing') {
            [Console]::Error.WriteLine('gh: Not Found (HTTP 404)')
            exit 1
        }
        Emit ([ordered]@{
            id=[long]$config.requiredStatusCheck.workflowId
            path=if ($mode -eq 'workflow-wrong-path') { '.github/workflows/impersonator.yml' } else { [string]$config.requiredStatusCheck.workflowPath }
            state=if ($mode -eq 'workflow-disabled') { 'disabled_manually' } else { 'active' }
        })
    }
    '/contents/\.github/CODEOWNERS\?ref(?:=main)?$' {
        $bytes = [IO.File]::ReadAllBytes($env:CF7_ADMISSION_TEST_CODEOWNERS)
        if ($mode -eq 'codeowners-wrong-content') { $bytes = [Text.Encoding]::UTF8.GetBytes("*`n") }
        Emit ([ordered]@{
            type='file'
            path='.github/CODEOWNERS'
            encoding='base64'
            content=[Convert]::ToBase64String($bytes)
        })
    }
    '/codeowners/errors\?ref(?:=main)?$' {
        [object[]]$errors = @(if ($mode -eq 'codeowners-error') {
            [ordered]@{ kind='Invalid owner'; line=2; column=1; message='owner not found'; path='.github/CODEOWNERS' }
        })
        Emit ([ordered]@{ errors=$errors })
    }
    '/collaborators\?' {
        Emit @($config.actors | ForEach-Object {
            [ordered]@{ id=[long]$_.databaseId; login=[string]$_.login; permissions=[ordered]@{ push=$true } }
        })
    }
    '/rulesets\?includes_parents' {
        Emit @(
            (New-RulesetSummary 101 ([string]$config.rulesets.identityGate.name)),
            (New-RulesetSummary 102 ([string]$config.rulesets.globalRefIntegrity.name)),
            (New-RulesetSummary 103 ([string]$config.rulesets.runtimeTagCreation.name)),
            (New-RulesetSummary 104 ([string]$config.rulesets.runtimeTagImmutability.name))
        )
    }
    '/rulesets/101$' { Emit (New-IdentityRuleset) }
    '/rulesets/102$' { Emit (New-HistoryRuleset) }
    '/rulesets/103$' { Emit (New-TagCreationRuleset) }
    '/rulesets/104$' { Emit (New-TagImmutabilityRuleset) }
    '/branches/main/protection$' {
        if ($state -eq 'Active') {
            [Console]::Error.WriteLine('gh: Not Found (HTTP 404)')
            exit 1
        }
        Emit ([ordered]@{
            required_status_checks=[ordered]@{
                strict=$true
                checks=@([ordered]@{ context=[string]$config.requiredStatusCheck.context; app_id=[long]$config.requiredStatusCheck.integrationId })
            }
            enforce_admins=[ordered]@{ enabled=$true }
            required_pull_request_reviews=[ordered]@{
                require_code_owner_reviews=$true
                dismiss_stale_reviews=$true
                required_approving_review_count=0
                require_last_push_approval=$false
            }
            required_conversation_resolution=[ordered]@{ enabled=$false }
            restrictions=$null
            allow_force_pushes=[ordered]@{ enabled=$false }
            allow_deletions=[ordered]@{ enabled=$false }
        })
    }
    '/rules/branches/main$' {
        Emit @(
            [ordered]@{ type='deletion' },
            [ordered]@{ type='non_fast_forward' },
            [ordered]@{ type='pull_request' },
            [ordered]@{ type='required_status_checks' }
        )
    }
    '/commits/main$' {
        Emit ([ordered]@{ sha='1111111111111111111111111111111111111111' })
    }
    '/commits/1111111111111111111111111111111111111111/check-runs\?check_name(?:=verify-staged-bundle)?$' {
        if ($mode -eq 'head-check-missing') {
            Emit ([ordered]@{ total_count=0; check_runs=@() })
        }
        $headSha = if ($mode -eq 'head-check-wrong-sha') { '2222222222222222222222222222222222222222' } else { '1111111111111111111111111111111111111111' }
        Emit ([ordered]@{
            total_count=1
            check_runs=@([ordered]@{
                id=88089620865
                name=[string]$config.requiredStatusCheck.context
                head_sha=$headSha
                status='completed'
                conclusion=if ($mode -eq 'head-check-failed') { 'failure' } else { 'success' }
                details_url='https://github.com/FlashNightModReborn/CrazyFlashNight/actions/runs/29648091574/job/88089620865'
                app=[ordered]@{ id=if ($mode -eq 'head-check-wrong-app') { 1 } else { [long]$config.requiredStatusCheck.integrationId } }
                check_suite=[ordered]@{ id=80290321861 }
            })
        })
    }
    '/actions/runs/29648091574$' {
        Emit ([ordered]@{
            id=29648091574
            check_suite_id=80290321861
            workflow_id=[long]$config.requiredStatusCheck.workflowId
            path=[string]$config.requiredStatusCheck.workflowPath
            event=if ($mode -eq 'head-run-wrong-event') { 'pull_request' } else { 'push' }
            status='completed'
            conclusion='success'
            head_branch='main'
            head_sha='1111111111111111111111111111111111111111'
            repository=[ordered]@{ full_name=[string]$config.repository }
            head_repository=[ordered]@{ full_name=[string]$config.repository }
        })
    }
    default {
        [Console]::Error.WriteLine("unexpected fake gh endpoint: $endpoint")
        exit 2
    }
}
'@

$fakeGhCmdSource = @'
@echo off
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0fake-gh-impl.ps1" "%~1" "%~2" "%~3" "%~4"
set "CF7_FAKE_GH_EXIT_CODE=%ERRORLEVEL%"
exit /b %CF7_FAKE_GH_EXIT_CODE%
'@

# Windows PowerShell invokes .cmd through cmd.exe without quoting '&' in a native
# argument. Absorb the one query tail used by this audit and preserve the wrapper's
# exit status; the fake implementation still runs in its own PowerShell process.
$fakeGhQueryTailSource = @'
@echo off
if defined CF7_FAKE_GH_EXIT_CODE exit /b %CF7_FAKE_GH_EXIT_CODE%
exit /b 2
'@

try {
    [void](New-Item -ItemType Directory -Path $testRoot -Force)
    $fakeGhImpl = Join-Path $testRoot 'fake-gh-impl.ps1'
    $fakeGh = Join-Path $testRoot 'fake-gh.cmd'
    $fakeGhQueryTail = Join-Path $testRoot 'per_page.cmd'
    [IO.File]::WriteAllText($fakeGhImpl, $fakeGhImplSource, $utf8)
    [IO.File]::WriteAllText($fakeGh, $fakeGhCmdSource, $utf8)
    [IO.File]::WriteAllText($fakeGhQueryTail, $fakeGhQueryTailSource, $utf8)
    $env:PATH = $testRoot + [IO.Path]::PathSeparator + $originalPath
    $env:CF7_ADMISSION_TEST_CONFIG = $configPath
    $env:CF7_ADMISSION_TEST_CODEOWNERS = $codeOwnersPath

    foreach ($state in @('Prepared','Layered','Active')) {
        Run-Test "$state remote state parses and passes exact contract" {
            $result = Invoke-TestAudit -ExpectedState $state
            Assert-Test ($result.ExitCode -eq 0) $result.Output
            Assert-Test ($null -ne $result.Result -and $result.Result.passed -eq $true) $result.Output
        }
    }

    Run-Test 'Missing bypass_actors fails closed instead of becoming an empty bypass list' {
        $result = Invoke-TestAudit -ExpectedState Layered -MockMode 'missing-bypass'
        Assert-Test ($result.ExitCode -ne 0) 'missing bypass_actors unexpectedly passed'
        Assert-Test ($result.Output -match 'omits bypass_actors') $result.Output
    }

    Run-Test 'Parent organization ruleset cannot impersonate the repository ruleset' {
        $result = Invoke-TestAudit -ExpectedState Prepared -MockMode 'parent-source'
        Assert-Test ($result.ExitCode -ne 0) 'parent-source ruleset unexpectedly passed'
        Assert-Test ($result.Output -match 'not sourced by the configured repository') $result.Output
    }

    Run-Test 'Required workflow must exist at the frozen path and remain active' {
        foreach ($mode in @('workflow-disabled','workflow-wrong-path','workflow-missing')) {
            $result = Invoke-TestAudit -ExpectedState Layered -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode unexpectedly passed"
            Assert-Test ($result.Output -match 'workflow ID/path is not live|gh api failed') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Remote main CODEOWNERS must match the frozen valid owner map' {
        foreach ($mode in @('codeowners-wrong-content','codeowners-error')) {
            $result = Invoke-TestAudit -ExpectedState Prepared -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode unexpectedly passed"
            Assert-Test ($result.Output -match 'CODEOWNERS') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Runtime source tags reject every update deletion bypass or weakened update rule' {
        foreach ($mode in @('tag-immutability-bypass','tag-weak-update')) {
            $result = Invoke-TestAudit -ExpectedState Layered -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode unexpectedly passed"
            Assert-Test ($result.Output -match 'source-tag immutability') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Layered and Active require the current main HEAD exact successful push workflow check' {
        foreach ($mode in @('head-check-missing','head-check-failed','head-check-wrong-sha','head-check-wrong-app','head-run-wrong-event')) {
            $result = Invoke-TestAudit -ExpectedState Layered -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode unexpectedly passed"
            Assert-Test ($result.Output -match 'Current main HEAD requires exactly one latest successful push/main check') "$mode`: $($result.Output)"
        }
    }
} finally {
    $env:PATH = $originalPath
    foreach ($name in @('CF7_ADMISSION_TEST_CONFIG','CF7_ADMISSION_TEST_CODEOWNERS','CF7_ADMISSION_TEST_STATE','CF7_ADMISSION_TEST_MODE')) {
        Remove-Item ("Env:$name") -ErrorAction SilentlyContinue
    }
    $resolved = [IO.Path]::GetFullPath($testRoot).TrimEnd('\')
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ($resolved.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolved).StartsWith('cf7-main-admission-tests-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[MainAdmissionTests] passed=$passed failed=$failed"
if ($failed -gt 0) { exit 1 }
