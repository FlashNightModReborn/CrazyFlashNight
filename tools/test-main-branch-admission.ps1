param([string]$TestNamePattern)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$auditScript = Join-Path $repoRoot 'tools\audit-main-branch-admission.ps1'
$configPath = Join-Path $repoRoot 'config\build\main-branch-admission.v2.json'
$cloudBuilderConfigPath = Join-Path $repoRoot 'config\build\runtime-github-builder.v2.json'
$legacyConfigPath = Join-Path $repoRoot 'config\build\main-branch-admission.v1.json'
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

function Invoke-TestAudit(
    [ValidateSet('ConfigOnly','Prepared','Layered','Active')][string]$ExpectedState,
    [string]$MockMode = 'normal'
) {
    $env:CF7_ADMISSION_TEST_STATE = $ExpectedState
    $env:CF7_ADMISSION_TEST_MODE = $MockMode
    $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:auditScript `
        -ProjectRoot $script:repoRoot -GitHubCliPath $script:fakeGh -ExpectedState $ExpectedState -Json 2>&1 |
        ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $jsonLine = @($output | Where-Object { $_ -match '^\{"schema":"cf7-main-branch-admission-audit\.v2"' } | Select-Object -Last 1)
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
    $sourceType = if ($mode -eq 'parent-source' -and $Id -eq 201) { 'Organization' } else { 'Repository' }
    $source = if ($sourceType -eq 'Organization') { 'FlashNightModReborn' } else { [string]$config.repository }
    return [ordered]@{ id=$Id; name=$Name; source_type=$sourceType; source=$source }
}

function Get-Enforcement {
    if ($mode -eq 'wrong-enforcement') {
        return $(if ($state -eq 'Prepared') { 'active' } else { 'disabled' })
    }
    return $(if ($state -eq 'Prepared') { 'disabled' } else { 'active' })
}

function New-HistoryRuleset {
    $result = [ordered]@{
        id=201
        name=[string]$config.rulesets.globalRefIntegrity.name
        source_type='Repository'
        source=[string]$config.repository
        target='branch'
        enforcement=(Get-Enforcement)
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/heads/main'); exclude=@() } }
        bypass_actors=@()
        rules=@([ordered]@{ type='deletion' },[ordered]@{ type='non_fast_forward' })
    }
    if ($mode -eq 'missing-bypass') { [void]$result.Remove('bypass_actors') }
    if ($mode -eq 'history-extra-rule') { $result.rules += [ordered]@{ type='pull_request' } }
    return $result
}

function New-TagCreationRuleset {
    [object[]]$bypass = @($config.runtimeTagCreators | ForEach-Object {
        [ordered]@{ actor_id=[long]$_.databaseId; actor_type='User'; bypass_mode='always' }
    })
    if ($mode -eq 'tower-tag-creator-missing') {
        $bypass = @($bypass | Where-Object { $_.actor_id -ne 328609522 })
    }
    if ($mode -eq 'aka-tag-creator-missing') { $bypass = @($bypass | Where-Object { $_.actor_id -ne 182913479 }) }
    $akaBypass = @($bypass | Where-Object { $_.actor_id -eq 182913479 })
    if ($mode -eq 'aka-tag-creator-wrong-id') { $akaBypass[0].actor_id = 182913480 }
    if ($mode -eq 'aka-tag-creator-wrong-type') { $akaBypass[0].actor_type = 'RepositoryRole' }
    if ($mode -eq 'aka-tag-creator-wrong-mode') { $akaBypass[0].bypass_mode = 'pull_request' }
    if ($mode -eq 'tag-creator-extra') {
        $bypass += [ordered]@{ actor_id=999999999; actor_type='User'; bypass_mode='always' }
    }
    return [ordered]@{
        id=202
        name=[string]$config.rulesets.runtimeTagCreation.name
        source_type='Repository'
        source=[string]$config.repository
        target='tag'
        enforcement=(Get-Enforcement)
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/tags/runtime-build-v2/*'); exclude=@() } }
        bypass_actors=$bypass
        rules=@([ordered]@{ type='creation' })
    }
}

function New-TagImmutabilityRuleset {
    [object[]]$bypass = @(if ($mode -eq 'tag-immutability-bypass') {
        [ordered]@{ actor_id=91271520; actor_type='User'; bypass_mode='always' }
    })
    $updateRule = if ($mode -eq 'tag-weak-update') {
        [ordered]@{ type='update'; parameters=[ordered]@{ update_allows_fetch_and_merge=$true } }
    } else {
        # Real GitHub responses omit parameters when the false exception was persisted.
        [ordered]@{ type='update' }
    }
    return [ordered]@{
        id=203
        name=[string]$config.rulesets.runtimeTagImmutability.name
        source_type='Repository'
        source=[string]$config.repository
        target='tag'
        enforcement=(Get-Enforcement)
        conditions=[ordered]@{ ref_name=[ordered]@{ include=@('refs/tags/runtime-build-v2/*'); exclude=@() } }
        bypass_actors=$bypass
        rules=@(
            [ordered]@{ type='deletion' },
            $updateRule
        )
    }
}

switch -Regex ($endpoint) {
    '^user$' {
        if ($mode -eq 'aka-publisher') { Emit ([ordered]@{ login='aka-flashNight'; id=182913479 }) }
        Emit ([ordered]@{ login='Crazyfs'; id=91271520 })
    }
    '^repos/FlashNightModReborn/CrazyFlashNight$' {
        Emit ([ordered]@{ default_branch='main' })
    }
    '/collaborators\?' {
        [object[]]$collaborators = @($config.runtimeTagCreators | ForEach-Object {
            [ordered]@{ id=[long]$_.databaseId; login=[string]$_.login; permissions=[ordered]@{ push=$true } }
        })
        if ($mode -eq 'creator-missing') { $collaborators = @($collaborators | Where-Object id -ne 91271520) }
        if ($mode -eq 'tower-creator-missing') { $collaborators = @($collaborators | Where-Object id -ne 328609522) }
        if ($mode -eq 'aka-creator-missing') { $collaborators = @($collaborators | Where-Object id -ne 182913479) }
        $akaCreator = @($collaborators | Where-Object id -eq 182913479)
        if ($mode -eq 'aka-creator-wrong-id') { $akaCreator[0].id = 182913480 }
        if ($mode -eq 'aka-creator-no-push') { $akaCreator[0].permissions.push = $false }
        $collaborators += [ordered]@{
            id=777777777
            login='UnlistedArtist'
            permissions=[ordered]@{ push=($mode -ne 'unlisted-no-push') }
        }
        Emit $collaborators
    }
    '/rulesets\?includes_parents' {
        [object[]]$summaries = @(
            (New-RulesetSummary 201 ([string]$config.rulesets.globalRefIntegrity.name)),
            (New-RulesetSummary 202 ([string]$config.rulesets.runtimeTagCreation.name)),
            (New-RulesetSummary 203 ([string]$config.rulesets.runtimeTagImmutability.name))
        )
        if ($mode -eq 'unexpected-ruleset') {
            $summaries += New-RulesetSummary 204 'main-native-identity-gate-v1'
        }
        Emit $summaries
    }
    '/rulesets/201$' { Emit (New-HistoryRuleset) }
    '/rulesets/202$' { Emit (New-TagCreationRuleset) }
    '/rulesets/203$' { Emit (New-TagImmutabilityRuleset) }
    '/branches/main/protection$' {
        if (($state -eq 'Active' -and $mode -ne 'active-classic') -or $mode -eq 'classic-missing') {
            [Console]::Error.WriteLine('gh: Not Found (HTTP 404)')
            exit 1
        }
        $requiredChecks = $null
        if ($mode -eq 'classic-status') {
            $requiredChecks = [ordered]@{ strict=$true; checks=@([ordered]@{ context='verify-staged-bundle'; app_id=15368 }) }
        }
        $requiredReviews = $null
        if ($mode -eq 'classic-pr') {
            $requiredReviews = [ordered]@{ require_code_owner_reviews=$true; required_approving_review_count=0 }
        }
        Emit ([ordered]@{
            required_status_checks=$requiredChecks
            required_pull_request_reviews=$requiredReviews
            restrictions=$null
            required_signatures=[ordered]@{ enabled=$false }
            enforce_admins=[ordered]@{ enabled=$true }
            required_linear_history=[ordered]@{ enabled=$false }
            allow_force_pushes=[ordered]@{ enabled=($mode -eq 'classic-force') }
            allow_deletions=[ordered]@{ enabled=$false }
            block_creations=[ordered]@{ enabled=$false }
            required_conversation_resolution=[ordered]@{ enabled=$false }
            lock_branch=[ordered]@{ enabled=$false }
            allow_fork_syncing=[ordered]@{ enabled=$false }
        })
    }
    '/rules/branches/main$' {
        [object[]]$rules = @([ordered]@{ type='deletion' },[ordered]@{ type='non_fast_forward' })
        if ($mode -eq 'effective-pr') { $rules += [ordered]@{ type='pull_request' } }
        if ($mode -eq 'effective-status') { $rules += [ordered]@{ type='required_status_checks' } }
        Emit $rules
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

# Windows PowerShell can expose the query '&' to cmd.exe when invoking a .cmd.
# Absorb the per_page tail while preserving the fake implementation's status.
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

    Run-Test 'v2 config removes every identity PR and required-check contract' {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Test ([string]$config.schema -ceq 'cf7-main-branch-admission.v2') 'wrong v2 schema'
        Assert-Test (-not (Test-Path -LiteralPath $legacyConfigPath)) 'legacy v1 admission config still exists'
        Assert-Test ($null -eq $config.PSObject.Properties['actors']) 'legacy actor allowlist remains'
        Assert-Test ($null -eq $config.PSObject.Properties['requiredStatusCheck']) 'required status check remains'
        Assert-Test ($null -eq $config.rulesets.PSObject.Properties['identityGate']) 'identity ruleset remains'
        Assert-Test (@($config.mainAdmission.requiredStatusChecks).Count -eq 0) 'status-check list is not empty'
        Assert-Test ([string]$config.codeOwners.mode -ceq 'advisory') 'CODEOWNERS is not advisory'
        Assert-Test ($null -eq $config.codeOwners.PSObject.Properties['normalizedLfSha256']) 'CODEOWNERS is still hash-bound'
        $cloudBuilder = Get-Content -LiteralPath $cloudBuilderConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Test ([string]$cloudBuilder.sourceRef -cmatch '^refs/tags/runtime-build-v2/[a-z0-9][a-z0-9._-]{1,80}$') `
            'formal cloud builder sourceRef escapes the protected single-segment runtime tag namespace'
    }

    Run-Test 'ConfigOnly validates the local direct-push contract' {
        $result = Invoke-TestAudit -ExpectedState ConfigOnly
        Assert-Test ($result.ExitCode -eq 0) $result.Output
        Assert-Test ($null -ne $result.Result -and $result.Result.passed -eq $true -and $result.Result.mainDirectPush -eq $true) $result.Output
        Assert-Test (@($result.Result.runtimeTagCreators).Count -eq 4 -and
            @($result.Result.runtimeTagCreators) -contains 'towerofsorcerer' -and
            @($result.Result.runtimeTagCreators) -contains 'aka-flashNight') 'new publisher was not admitted'
    }

    Run-Test 'Publisher identity rejects wrong immutable IDs missing duplicate or unauthorized creators' {
        $invalidRoot = Join-Path $testRoot 'invalid-config'
        [void](New-Item -ItemType Directory -Path (Join-Path $invalidRoot 'config\build'),(Join-Path $invalidRoot '.github') -Force)
        Copy-Item -LiteralPath $cloudBuilderConfigPath -Destination (Join-Path $invalidRoot 'config\build\runtime-github-builder.v2.json')
        Copy-Item -LiteralPath (Join-Path $repoRoot '.github\CODEOWNERS') -Destination (Join-Path $invalidRoot '.github\CODEOWNERS')
        foreach ($mutation in @('wrong-id','aka-wrong-id','aka-missing','aka-duplicate','aka-replaced','extra-creator')) {
            $invalidConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            switch ($mutation) {
                'wrong-id' { ($invalidConfig.runtimeTagCreators | Where-Object login -eq 'towerofsorcerer').databaseId = 999999999 }
                'aka-wrong-id' { ($invalidConfig.runtimeTagCreators | Where-Object login -ceq 'aka-flashNight').databaseId = 182913480 }
                'aka-missing' { $invalidConfig.runtimeTagCreators = @($invalidConfig.runtimeTagCreators | Where-Object login -cne 'aka-flashNight') }
                'aka-duplicate' { $invalidConfig.runtimeTagCreators[-1] = $invalidConfig.runtimeTagCreators[0] }
                'aka-replaced' { $invalidConfig.runtimeTagCreators[-1] = [pscustomobject]@{ databaseId=999999999; login='OtherPublisher' } }
                'extra-creator' { $invalidConfig.runtimeTagCreators += [pscustomobject]@{ databaseId=999999999; login='OtherPublisher' } }
            }
            [IO.File]::WriteAllText((Join-Path $invalidRoot 'config\build\main-branch-admission.v2.json'),
                ($invalidConfig | ConvertTo-Json -Depth 20), $utf8)
            $output = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $auditScript `
                -ProjectRoot $invalidRoot -ExpectedState ConfigOnly -Json 2>&1 | ForEach-Object { [string]$_ })
            Assert-Test ($LASTEXITCODE -ne 0) "$mutation config passed"
            Assert-Test (($output -join "`n") -match 'Runtime source-tag creators') ($output -join "`n")
        }
    }

    Run-Test 'Every release workflow job pins exactly the four publisher IDs before runner allocation' {
        $actorClause = "github.actor_id == '91271520' || github.actor_id == '138298913' || github.actor_id == '328609522' || github.actor_id == '182913479'"
        $contracts = @(
            @{ Path='.github\workflows\runtime-cloud-builder.yml'; Job='build'; Guard="github.event_name == 'workflow_dispatch' && github.run_attempt == 1 && ($actorClause)" },
            @{ Path='.github\workflows\runtime-cloud-builder.yml'; Job='attest'; Guard="needs.build.result == 'success' && github.event_name == 'workflow_dispatch' && github.run_attempt == 1 && ($actorClause)" },
            @{ Path='.github\workflows\runtime-bundle-integrity.yml'; Job='audit-native-runtime'; Guard="github.run_attempt == 1 && (github.event_name != 'workflow_dispatch' || $actorClause)" },
            @{ Path='.github\workflows\runtime-bundle-integrity.yml'; Job='generated-path-regressions'; Guard="github.run_attempt == 1 && (github.event_name != 'workflow_dispatch' || $actorClause)" }
        )
        foreach ($contract in $contracts) {
            $workflow = [IO.File]::ReadAllText((Join-Path $repoRoot $contract.Path), [Text.Encoding]::UTF8)
            $job = [regex]::Match($workflow, ('(?ms)^  ' + [regex]::Escape($contract.Job) + ':\s*\r?\n.*?(?=^  [a-z][a-z0-9-]*:|\z)')).Value
            $condition = [regex]::Match($job, '(?m)^    if: >-\r?\n(?<guard>(?:^      [^\r\n]*\r?\n)+)')
            Assert-Test $condition.Success "missing job-level condition: $($contract.Job)"
            $normalized = [regex]::Replace($condition.Groups['guard'].Value.Trim(), '\s+', ' ')
            Assert-Test ($normalized -ceq $contract.Guard) "publisher, event, attempt or success gate drifted: $($contract.Job): $normalized"
            Assert-Test ($job.IndexOf('if: >-', [StringComparison]::Ordinal) -lt
                $job.IndexOf('runs-on:', [StringComparison]::Ordinal)) "late authorization: $($contract.Job)"
        }
    }

    foreach ($state in @('Prepared','Layered','Active')) {
        Run-Test "$state remote state parses and passes the three-ruleset contract" {
            $result = Invoke-TestAudit -ExpectedState $state
            Assert-Test ($result.ExitCode -eq 0) $result.Output
            Assert-Test ($null -ne $result.Result -and $result.Result.passed -eq $true) $result.Output
        }
    }

    Run-Test 'Unlisted collaborators never participate in the main admission decision' {
        $result = Invoke-TestAudit -ExpectedState Active -MockMode 'unlisted-no-push'
        Assert-Test ($result.ExitCode -eq 0) $result.Output
    }

    Run-Test 'A legacy identity gate or any other extra ruleset fails closed' {
        $result = Invoke-TestAudit -ExpectedState Active -MockMode 'unexpected-ruleset'
        Assert-Test ($result.ExitCode -ne 0) 'unexpected ruleset passed'
        Assert-Test ($result.Output -match 'Unexpected repository or parent rulesets') $result.Output
    }

    Run-Test 'Parent organization ruleset cannot impersonate a repository ruleset' {
        $result = Invoke-TestAudit -ExpectedState Prepared -MockMode 'parent-source'
        Assert-Test ($result.ExitCode -ne 0) 'parent-source ruleset passed'
        Assert-Test ($result.Output -match 'not sourced by the configured repository') $result.Output
    }

    Run-Test 'aka-flashNight passes Active audit with all four immutable publisher identities in the offline fixture' {
        $result = Invoke-TestAudit -ExpectedState Active -MockMode 'aka-publisher'
        Assert-Test ($result.ExitCode -eq 0 -and $result.Result.passed -eq $true) $result.Output
        Assert-Test ($result.Result.remote.authenticatedLogin -ceq 'aka-flashNight') $result.Output
        Assert-Test (@($result.Result.remote.runtimeTagCreators).Count -eq 4 -and
            @($result.Result.remote.runtimeTagCreators) -contains 'aka-flashNight') $result.Output
    }

    Run-Test 'Runtime tag creators remain the exact four immutable identities' {
        foreach ($mode in @(
            'creator-missing','tower-creator-missing','tower-tag-creator-missing','tag-creator-extra',
            'aka-creator-missing','aka-creator-wrong-id','aka-creator-no-push',
            'aka-tag-creator-missing','aka-tag-creator-wrong-id','aka-tag-creator-wrong-type','aka-tag-creator-wrong-mode'
        )) {
            $result = Invoke-TestAudit -ExpectedState Active -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode passed"
            Assert-Test ($result.Output -match 'source-tag creator|source-tag creation') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Runtime source tags reject every update deletion bypass or weakened update rule' {
        foreach ($mode in @('tag-immutability-bypass','tag-weak-update')) {
            $result = Invoke-TestAudit -ExpectedState Layered -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode passed"
            Assert-Test ($result.Output -match 'source-tag immutability') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Rulesets require an explicit bypass array and the exact migration enforcement' {
        foreach ($mode in @('missing-bypass','wrong-enforcement','history-extra-rule')) {
            $result = Invoke-TestAudit -ExpectedState Layered -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode passed"
            Assert-Test ($result.Output -match 'Global ref-integrity') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Prepared and Layered classic protection contains only ref-integrity safety' {
        foreach ($mode in @('classic-pr','classic-status','classic-force','classic-missing')) {
            $result = Invoke-TestAudit -ExpectedState Layered -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode passed"
            Assert-Test ($result.Output -match 'Classic') "$mode`: $($result.Output)"
        }
    }

    Run-Test 'Active removes classic protection and rejects PR or status rules on main' {
        foreach ($mode in @('active-classic','effective-pr','effective-status')) {
            $result = Invoke-TestAudit -ExpectedState Active -MockMode $mode
            Assert-Test ($result.ExitCode -ne 0) "$mode passed"
            Assert-Test ($result.Output -match 'Classic branch protection|Effective main rules') "$mode`: $($result.Output)"
        }
    }
} finally {
    $env:PATH = $originalPath
    foreach ($name in @('CF7_ADMISSION_TEST_CONFIG','CF7_ADMISSION_TEST_STATE','CF7_ADMISSION_TEST_MODE')) {
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
