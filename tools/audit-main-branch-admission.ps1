param(
    [string]$ProjectRoot,
    [string]$GitHubCliPath,
    [ValidateSet('ConfigOnly','Prepared','Layered','Active')]
    [string]$ExpectedState = 'Active',
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Resolve-Cf7GitHubCli([string]$ExplicitPath) {
    if ($ExplicitPath) {
        $resolved = (Resolve-Path -LiteralPath $ExplicitPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "gh executable is not a file: $resolved" }
        return $resolved
    }
    $command = Get-Command gh.exe, gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $standard = Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'
    if (Test-Path -LiteralPath $standard -PathType Leaf) { return $standard }
    throw 'GitHub CLI is required for remote admission audit. Install gh or pass -GitHubCliPath.'
}

function Invoke-Cf7AdmissionApi([string]$Endpoint, [switch]$AllowNotFound) {
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $script:GitHubCli api -H 'X-GitHub-Api-Version: 2026-03-10' $Endpoint 2>&1 | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    $text = ($lines -join "`n").Trim()
    if ($exitCode -ne 0) {
        if ($AllowNotFound -and $text -match '(?i)\(HTTP 404\)') {
            return [pscustomobject]@{ Found=$false; Value=$null }
        }
        throw "gh api failed for $Endpoint (exit=$exitCode): $text"
    }
    try { $value = $text | ConvertFrom-Json }
    catch { throw "GitHub returned invalid JSON for $Endpoint`: $($_.Exception.Message)" }
    return [pscustomobject]@{ Found=$true; Value=$value }
}

function Add-Cf7AdmissionIssue([string]$Message) {
    [void]$script:Issues.Add($Message)
}

function Get-Cf7SortedKey([object[]]$Values) {
    return [string]::Join(',', [string[]]@($Values | ForEach-Object { [string]$_ } | Sort-Object))
}

function Test-Cf7ExactFields($Value, [string[]]$ExpectedFields) {
    if ($null -eq $Value) { return $false }
    [string[]]$actualFields = @($Value.PSObject.Properties.Name)
    return $actualFields.Count -eq $ExpectedFields.Count -and
        @($actualFields | Where-Object { $ExpectedFields -notcontains $_ }).Count -eq 0
}

function Test-Cf7RulesetTarget($Ruleset, $TargetConfig) {
    if ([string]$Ruleset.target -cne [string]$TargetConfig.type) { return $false }
    if ($null -eq $Ruleset.conditions -or $null -eq $Ruleset.conditions.ref_name) { return $false }
    return (Get-Cf7SortedKey @($Ruleset.conditions.ref_name.include)) -ceq (Get-Cf7SortedKey @($TargetConfig.include)) -and
        (Get-Cf7SortedKey @($Ruleset.conditions.ref_name.exclude)) -ceq (Get-Cf7SortedKey @($TargetConfig.exclude))
}

function Test-Cf7RepositoryRulesetSource($Ruleset, [string]$Repository) {
    if ($null -eq $Ruleset -or
            $null -eq $Ruleset.PSObject.Properties['source_type'] -or
            $null -eq $Ruleset.PSObject.Properties['source']) {
        return $false
    }
    return [string]$Ruleset.source_type -ceq 'Repository' -and [string]$Ruleset.source -ieq $Repository
}

function Test-Cf7ClassicFlag($Protection, [string]$Name, [bool]$ExpectedEnabled) {
    $property = $Protection.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value -or
            $null -eq $property.Value.PSObject.Properties['enabled']) { return $false }
    return [bool]$property.Value.enabled -eq $ExpectedEnabled
}

function Test-Cf7MinimalClassicProtection($Protection) {
    if ($null -eq $Protection) { return $false }
    if ($null -ne $Protection.required_status_checks -or
            $null -ne $Protection.required_pull_request_reviews -or
            $null -ne $Protection.restrictions) { return $false }
    if (-not (Test-Cf7ClassicFlag $Protection 'enforce_admins' $true) -or
            -not (Test-Cf7ClassicFlag $Protection 'allow_force_pushes' $false) -or
            -not (Test-Cf7ClassicFlag $Protection 'allow_deletions' $false)) { return $false }
    foreach ($disabledFlag in @(
        'required_signatures',
        'required_linear_history',
        'block_creations',
        'required_conversation_resolution',
        'lock_branch',
        'allow_fork_syncing'
    )) {
        if (-not (Test-Cf7ClassicFlag $Protection $disabledFlag $false)) { return $false }
    }
    return $true
}

try {
    if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    $root = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path.TrimEnd('\')
    $configPath = Join-Path $root 'config\build\main-branch-admission.v2.json'
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    $raw = [IO.File]::ReadAllText($configPath, $strictUtf8).TrimStart([char]0xFEFF)
    $config = $raw | ConvertFrom-Json

    $topFields = @('schema','repository','mainAdmission','target','runtimeSourceTag','codeOwners','runtimeTagCreators','rulesets')
    if (-not (Test-Cf7ExactFields $config $topFields) -or [string]$config.schema -cne 'cf7-main-branch-admission.v2') {
        throw 'Admission config does not have the exact cf7-main-branch-admission.v2 top-level shape.'
    }
    if ([string]$config.repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Admission repository is invalid.' }

    $mainAdmissionFields = @('directPush','unlistedCollaborators','requirePullRequest','requiredStatusChecks','requireCodeOwnerReview')
    if (-not (Test-Cf7ExactFields $config.mainAdmission $mainAdmissionFields) -or
            [string]$config.mainAdmission.directPush -cne 'allCollaboratorsWithPushPermission' -or
            [string]$config.mainAdmission.unlistedCollaborators -cne 'allowed' -or
            $config.mainAdmission.requirePullRequest -ne $false -or
            @($config.mainAdmission.requiredStatusChecks).Count -ne 0 -or
            $config.mainAdmission.requireCodeOwnerReview -ne $false) {
        throw 'Main admission must allow every push-capable collaborator without a PR, status check, or CODEOWNER gate.'
    }
    if ([string]$config.target.type -cne 'branch' -or
            (Get-Cf7SortedKey @($config.target.include)) -cne 'refs/heads/main' -or
            @($config.target.exclude).Count -ne 0) {
        throw 'Admission target must be exactly refs/heads/main.'
    }
    if ([string]$config.runtimeSourceTag.type -cne 'tag' -or
            (Get-Cf7SortedKey @($config.runtimeSourceTag.include)) -cne 'refs/tags/runtime-build-v2/*' -or
            @($config.runtimeSourceTag.exclude).Count -ne 0) {
        throw 'Runtime source-tag target must be exactly refs/tags/runtime-build-v2/*.'
    }
    $cloudBuilderConfigPath = Join-Path $root 'config\build\runtime-github-builder.v2.json'
    $cloudBuilderRaw = [IO.File]::ReadAllText($cloudBuilderConfigPath, $strictUtf8).TrimStart([char]0xFEFF)
    $cloudBuilderConfig = $cloudBuilderRaw | ConvertFrom-Json
    if ([string]$cloudBuilderConfig.schema -cne 'cf7-runtime-github-builder.v2' -or
            [string]$cloudBuilderConfig.sourceRef -cnotmatch '^refs/tags/runtime-build-v2/[a-z0-9][a-z0-9._-]{1,80}$') {
        throw 'Cloud builder sourceRef must be one canonical tag covered by the runtime source-tag rulesets.'
    }

    $codeOwnerFields = @('path','mode')
    if (-not (Test-Cf7ExactFields $config.codeOwners $codeOwnerFields) -or
            [string]$config.codeOwners.path -cne '.github/CODEOWNERS' -or
            [string]$config.codeOwners.mode -cne 'advisory') {
        throw 'Admission CODEOWNERS advisory contract is invalid.'
    }
    $localCodeOwnersPath = Join-Path $root ([string]$config.codeOwners.path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $localCodeOwnersPath -PathType Leaf)) { throw 'Configured CODEOWNERS file is missing.' }

    if ($config.runtimeTagCreators -isnot [Array] -or @($config.runtimeTagCreators).Count -ne 2) {
        throw 'Runtime source-tag creators must contain exactly two immutable identities.'
    }
    $creatorKey = Get-Cf7SortedKey @($config.runtimeTagCreators | ForEach-Object {
        if (-not (Test-Cf7ExactFields $_ @('databaseId','login')) -or [int64]$_.databaseId -le 0 -or
                [string]$_.login -cnotmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$') {
            throw 'Runtime source-tag creator identity is invalid.'
        }
        "$([int64]$_.databaseId):$([string]$_.login)"
    })
    $expectedCreatorKey = Get-Cf7SortedKey @('91271520:Crazyfs','138298913:Flash-Night')
    if ($creatorKey -cne $expectedCreatorKey) {
        throw 'Runtime source-tag creators must be exactly Crazyfs and Flash-Night by immutable database ID.'
    }

    if (-not (Test-Cf7ExactFields $config.rulesets @('globalRefIntegrity','runtimeTagCreation','runtimeTagImmutability'))) {
        throw 'Admission rulesets must contain exactly the three direct-push release gates.'
    }
    $historyConfig = $config.rulesets.globalRefIntegrity
    $tagCreationConfig = $config.rulesets.runtimeTagCreation
    $tagImmutabilityConfig = $config.rulesets.runtimeTagImmutability
    if (-not (Test-Cf7ExactFields $historyConfig @('name','bypassActors','rules')) -or
            [string]$historyConfig.name -cne 'main-global-ref-integrity-v1' -or
            @($historyConfig.bypassActors).Count -ne 0 -or
            (Get-Cf7SortedKey @($historyConfig.rules)) -cne 'deletion,non_fast_forward') {
        throw 'Global ref-integrity ruleset desired state is invalid.'
    }
    if (-not (Test-Cf7ExactFields $tagCreationConfig @('name','bypassSource','bypassMode','rules')) -or
            [string]$tagCreationConfig.name -cne 'runtime-source-tag-creation-v1' -or
            [string]$tagCreationConfig.bypassSource -cne 'runtimeTagCreators' -or
            [string]$tagCreationConfig.bypassMode -cne 'always' -or
            (Get-Cf7SortedKey @($tagCreationConfig.rules)) -cne 'creation') {
        throw 'Runtime source-tag creation ruleset desired state is invalid.'
    }
    if (-not (Test-Cf7ExactFields $tagImmutabilityConfig @('name','bypassActors','updateAllowsFetchAndMerge','rules')) -or
            [string]$tagImmutabilityConfig.name -cne 'runtime-source-tag-immutability-v1' -or
            @($tagImmutabilityConfig.bypassActors).Count -ne 0 -or
            $tagImmutabilityConfig.updateAllowsFetchAndMerge -ne $false -or
            (Get-Cf7SortedKey @($tagImmutabilityConfig.rules)) -cne 'deletion,update') {
        throw 'Runtime source-tag immutability ruleset desired state is invalid.'
    }

    $script:Issues = New-Object 'Collections.Generic.List[string]'
    $remoteSummary = $null
    if ($ExpectedState -ne 'ConfigOnly') {
        $script:GitHubCli = Resolve-Cf7GitHubCli $GitHubCliPath
        $repoApi = 'repos/' + [string]$config.repository
        $user = (Invoke-Cf7AdmissionApi 'user').Value
        $repository = (Invoke-Cf7AdmissionApi $repoApi).Value
        if ([string]$repository.default_branch -cne 'main') {
            Add-Cf7AdmissionIssue 'Repository default branch must remain main.'
        }

        $collaborators = @((Invoke-Cf7AdmissionApi ($repoApi + '/collaborators?affiliation=all&per_page=100')).Value)
        if ($collaborators.Count -ge 100) { Add-Cf7AdmissionIssue 'Collaborator audit reached the 100-row safety limit; pagination support is required.' }
        foreach ($creator in @($config.runtimeTagCreators)) {
            $matches = @($collaborators | Where-Object {
                [int64]$_.id -eq [int64]$creator.databaseId -and [string]$_.login -ieq [string]$creator.login
            })
            if ($matches.Count -ne 1 -or
                    $null -eq $matches[0].PSObject.Properties['permissions'] -or
                    $null -eq $matches[0].permissions.PSObject.Properties['push'] -or
                    $matches[0].permissions.push -ne $true) {
                Add-Cf7AdmissionIssue "Runtime source-tag creator $($creator.login) is missing or lacks push permission."
            }
        }

        $rulesetSummaries = @((Invoke-Cf7AdmissionApi ($repoApi + '/rulesets?includes_parents=true&per_page=100')).Value)
        if ($rulesetSummaries.Count -ge 100) { Add-Cf7AdmissionIssue 'Ruleset audit reached the 100-row safety limit; pagination support is required.' }
        $expectedNames = @(
            [string]$historyConfig.name,
            [string]$tagCreationConfig.name,
            [string]$tagImmutabilityConfig.name
        )
        $unexpectedRulesets = @($rulesetSummaries | Where-Object { $expectedNames -notcontains [string]$_.name })
        if ($unexpectedRulesets.Count -gt 0) {
            Add-Cf7AdmissionIssue ('Unexpected repository or parent rulesets exist: ' + (($unexpectedRulesets | ForEach-Object name) -join ','))
        }

        $resolvedRulesets = @{}
        foreach ($name in $expectedNames) {
            $matches = @($rulesetSummaries | Where-Object { [string]$_.name -ceq $name })
            if ($matches.Count -ne 1) {
                Add-Cf7AdmissionIssue "Expected exactly one ruleset named $name; found $($matches.Count)."
                continue
            }
            if (-not (Test-Cf7RepositoryRulesetSource $matches[0] ([string]$config.repository))) {
                Add-Cf7AdmissionIssue "Ruleset $name is not sourced by the configured repository."
                continue
            }
            $resolved = (Invoke-Cf7AdmissionApi ($repoApi + '/rulesets/' + [string]$matches[0].id)).Value
            if ([string]$resolved.name -cne $name -or
                    -not (Test-Cf7RepositoryRulesetSource $resolved ([string]$config.repository))) {
                Add-Cf7AdmissionIssue "Resolved ruleset $name changed identity or is not sourced by the configured repository."
                continue
            }
            $resolvedRulesets[$name] = $resolved
        }

        $expectedEnforcement = if ($ExpectedState -eq 'Prepared') { 'disabled' } else { 'active' }
        $history = $resolvedRulesets[[string]$historyConfig.name]
        if ($history) {
            if (-not (Test-Cf7RulesetTarget $history $config.target) -or [string]$history.enforcement -cne $expectedEnforcement) {
                Add-Cf7AdmissionIssue 'Global ref-integrity ruleset target or enforcement differs from expected state.'
            }
            if ($null -eq $history.PSObject.Properties['bypass_actors'] -or @($history.bypass_actors).Count -ne 0 -or
                    (Get-Cf7SortedKey @($history.rules | ForEach-Object type)) -cne 'deletion,non_fast_forward') {
                Add-Cf7AdmissionIssue 'Global ref-integrity ruleset must have no bypass and only deletion/non_fast_forward.'
            }
        }

        $tagCreation = $resolvedRulesets[[string]$tagCreationConfig.name]
        if ($tagCreation) {
            if (-not (Test-Cf7RulesetTarget $tagCreation $config.runtimeSourceTag) -or
                    [string]$tagCreation.enforcement -cne $expectedEnforcement) {
                Add-Cf7AdmissionIssue 'Runtime source-tag creation ruleset target or enforcement differs from expected state.'
            }
            [object[]]$tagCreationBypass = @($tagCreation.bypass_actors)
            $expectedTagCreatorIds = Get-Cf7SortedKey @($config.runtimeTagCreators | ForEach-Object { [int64]$_.databaseId })
            $actualTagCreatorIds = Get-Cf7SortedKey @($tagCreationBypass | ForEach-Object { [int64]$_.actor_id })
            if ($null -eq $tagCreation.PSObject.Properties['bypass_actors'] -or
                    $actualTagCreatorIds -cne $expectedTagCreatorIds -or
                    @($tagCreationBypass | Where-Object {
                        [string]$_.actor_type -cne 'User' -or [string]$_.bypass_mode -cne 'always'
                    }).Count -gt 0 -or
                    (Get-Cf7SortedKey @($tagCreation.rules | ForEach-Object type)) -cne 'creation') {
                Add-Cf7AdmissionIssue 'Runtime source-tag creation ruleset must allow only Crazyfs and Flash-Night as User/always creators.'
            }
        }

        $tagImmutability = $resolvedRulesets[[string]$tagImmutabilityConfig.name]
        if ($tagImmutability) {
            if (-not (Test-Cf7RulesetTarget $tagImmutability $config.runtimeSourceTag) -or
                    [string]$tagImmutability.enforcement -cne $expectedEnforcement) {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability ruleset target or enforcement differs from expected state.'
            }
            [object[]]$tagUpdateRules = @($tagImmutability.rules | Where-Object { [string]$_.type -eq 'update' })
            $tagUpdateRuleRejectsAll = $false
            if ($tagUpdateRules.Count -eq 1) {
                $parametersProperty = $tagUpdateRules[0].PSObject.Properties['parameters']
                if ($null -eq $parametersProperty) {
                    # GitHub normalizes an explicit false update exception by omitting the
                    # parameters object.  A bare update rule therefore rejects every update.
                    $tagUpdateRuleRejectsAll = $true
                } elseif ($null -ne $parametersProperty.Value -and
                        (Test-Cf7ExactFields $parametersProperty.Value @('update_allows_fetch_and_merge')) -and
                        $parametersProperty.Value.update_allows_fetch_and_merge -eq $false) {
                    $tagUpdateRuleRejectsAll = $true
                }
            }
            if ($null -eq $tagImmutability.PSObject.Properties['bypass_actors'] -or @($tagImmutability.bypass_actors).Count -ne 0 -or
                    (Get-Cf7SortedKey @($tagImmutability.rules | ForEach-Object type)) -cne 'deletion,update' -or
                    -not $tagUpdateRuleRejectsAll) {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability ruleset must reject every update/deletion without bypass.'
            }
        }

        $classic = Invoke-Cf7AdmissionApi ($repoApi + '/branches/main/protection') -AllowNotFound
        if ($ExpectedState -eq 'Active') {
            if ($classic.Found) { Add-Cf7AdmissionIssue 'Classic branch protection still exists after active ruleset migration.' }
        } else {
            if (-not $classic.Found) {
                Add-Cf7AdmissionIssue "Classic branch protection is missing during $ExpectedState migration state."
            } elseif (-not (Test-Cf7MinimalClassicProtection $classic.Value)) {
                Add-Cf7AdmissionIssue 'Classic protection must only forbid force-push and deletion, including for admins.'
            }
        }

        if ($ExpectedState -in @('Layered','Active')) {
            $effectiveRules = @((Invoke-Cf7AdmissionApi ($repoApi + '/rules/branches/main')).Value)
            $effectiveTypes = Get-Cf7SortedKey @($effectiveRules | ForEach-Object type | Sort-Object -Unique)
            if ($effectiveTypes -cne 'deletion,non_fast_forward') {
                Add-Cf7AdmissionIssue 'Effective main rules must contain only deletion and non_fast_forward; PR/status/CODEOWNER gates are forbidden.'
            }
        }

        $remoteSummary = [ordered]@{
            authenticatedLogin=[string]$user.login
            collaboratorCount=$collaborators.Count
            runtimeTagCreators=@($config.runtimeTagCreators | ForEach-Object login)
            rulesetCount=$rulesetSummaries.Count
        }
    }

    $result = [pscustomobject][ordered]@{
        schema = 'cf7-main-branch-admission-audit.v2'
        passed = $script:Issues.Count -eq 0
        expectedState = $ExpectedState
        repository = [string]$config.repository
        mainDirectPush = $true
        runtimeTagCreators = @($config.runtimeTagCreators | ForEach-Object login)
        remote = $remoteSummary
        issues = @($script:Issues)
    }
    if ($Json) { $result | ConvertTo-Json -Depth 8 -Compress }
    else {
        $status = if ($result.passed) { 'OK' } else { 'FAIL' }
        Write-Host "[MainAdmissionAudit] $status state=$ExpectedState mainDirectPush=true tagCreators=$($result.runtimeTagCreators -join ',')"
        foreach ($issue in @($result.issues)) { Write-Host "[MainAdmissionAudit] ISSUE $issue" -ForegroundColor Red }
    }
    if (-not $result.passed) { exit 1 }
} catch {
    Write-Host "[MainAdmissionAudit] FAIL $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
