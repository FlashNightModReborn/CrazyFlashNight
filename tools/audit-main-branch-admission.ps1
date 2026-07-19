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

function Get-Cf7SortedKey([object[]]$Values) {
    return [string]::Join(',', [string[]]@($Values | ForEach-Object { [string]$_ } | Sort-Object))
}

function Add-Cf7AdmissionIssue([string]$Message) {
    [void]$script:Issues.Add($Message)
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
    return [string]$Ruleset.source_type -ceq 'Repository' -and
        [string]$Ruleset.source -ieq $Repository
}

function Get-Cf7AdmissionRunLink([string]$DetailsUrl, [string]$Repository) {
    if ([string]::IsNullOrWhiteSpace($DetailsUrl)) { return $null }
    $match = [regex]::Match(
        $DetailsUrl,
        '^https://github\.com/' + [regex]::Escape($Repository) + '/actions/runs/([0-9]+)/job/([0-9]+)(?:\?.*)?$'
    )
    if (-not $match.Success) { return $null }
    $runId = [long]0
    $jobId = [long]0
    if (-not [long]::TryParse($match.Groups[1].Value, [ref]$runId) -or $runId -le 0 -or
            -not [long]::TryParse($match.Groups[2].Value, [ref]$jobId) -or $jobId -le 0) { return $null }
    return [pscustomobject]@{ RunId=$runId; JobId=$jobId }
}

function Get-Cf7CodeOwnersContract([byte[]]$Bytes, [string]$Label) {
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $strictUtf8.GetString($Bytes) }
    catch { throw "$Label is not strict UTF-8." }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { throw "$Label must not contain a UTF-8 BOM." }
    $normalized = $text.Replace("`r`n", "`n")
    if ($normalized.Contains("`r")) { throw "$Label contains a bare carriage return." }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = [BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($normalized))).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }

    $entries = @{}
    foreach ($line in $normalized.Split([char]10)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        [string[]]$tokens = @($trimmed -split '[\t ]+')
        $pattern = [string]$tokens[0]
        if ($entries.ContainsKey($pattern)) { throw "$Label contains duplicate pattern $pattern." }
        [string[]]$owners = @()
        if ($tokens.Count -gt 1) { $owners = [string[]]$tokens[1..($tokens.Count - 1)] }
        $entries[$pattern] = $owners
    }
    return [pscustomobject]@{ Digest=$digest; Entries=$entries }
}

function Test-Cf7CodeOwnersRoutes($Contract, [string[]]$RequiredOwners, $NativeGate) {
    $ownerKey = Get-Cf7SortedKey @($RequiredOwners | ForEach-Object { '@' + $_ })
    if (-not $Contract.Entries.ContainsKey('*') -or @($Contract.Entries['*']).Count -ne 0) { return $false }
    if ($null -eq $NativeGate -or [string]$NativeGate.schema -cne 'cf7-native-change-gate.v1' -or
            $NativeGate.protectedExtensions -isnot [Array] -or $NativeGate.protectedBasenames -isnot [Array]) {
        return $false
    }
    $requiredPatterns = @(
        @($NativeGate.protectedExtensions | ForEach-Object { '*' + [string]$_ }) +
        @($NativeGate.protectedBasenames | ForEach-Object { [string]$_ }) +
        @('/.github/','/.gitattributes',
        '/config/build/','/global.json','/launcher/CRAZYFLASHER7MercenaryEmpire.csproj',
        '/launcher/Directory.Packages.props','/launcher/packages.lock.json','/launcher/app.ico',
        '/launcher/app.manifest','/launcher/build*.ps1','/launcher/native/','/launcher/scripts/',
        '/launcher/src/','/runtime/','/tools/')
    )
    foreach ($pattern in $requiredPatterns) {
        if (-not $Contract.Entries.ContainsKey($pattern) -or
                (Get-Cf7SortedKey @($Contract.Entries[$pattern])) -cne $ownerKey) { return $false }
    }
    return $true
}

try {
    if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
    $root = (Resolve-Path -LiteralPath $ProjectRoot -ErrorAction Stop).Path.TrimEnd('\')
    $configPath = Join-Path $root 'config\build\main-branch-admission.v1.json'
    $raw = [IO.File]::ReadAllText($configPath, (New-Object Text.UTF8Encoding($false, $true))).TrimStart([char]0xFEFF)
    $config = $raw | ConvertFrom-Json
    $topFields = @('schema','repository','unknownCollaboratorPolicy','target','runtimeSourceTag','codeOwners','requiredStatusCheck','actors','rulesets')
    $actualTopFields = @($config.PSObject.Properties.Name)
    if ($null -eq $config -or $actualTopFields.Count -ne $topFields.Count -or
            @($actualTopFields | Where-Object { $topFields -notcontains $_ }).Count -gt 0 -or
            [string]$config.schema -cne 'cf7-main-branch-admission.v1') {
        throw 'Admission config does not have the exact cf7-main-branch-admission.v1 top-level shape.'
    }
    if ([string]$config.repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Admission repository is invalid.' }
    if ([string]$config.unknownCollaboratorPolicy -cne 'restricted') { throw 'Unknown collaborators must default to restricted.' }
    if ([string]$config.target.type -cne 'branch' -or
            (Get-Cf7SortedKey @($config.target.include)) -cne 'refs/heads/main' -or @($config.target.exclude).Count -ne 0) {
        throw 'Admission target must be exactly refs/heads/main.'
    }
    if ([string]$config.runtimeSourceTag.type -cne 'tag' -or
            (Get-Cf7SortedKey @($config.runtimeSourceTag.include)) -cne 'refs/tags/runtime-build-v2/*' -or
            @($config.runtimeSourceTag.exclude).Count -ne 0) {
        throw 'Runtime source-tag target must be exactly refs/tags/runtime-build-v2/*.'
    }
    $codeOwnerFields = @('path','normalizedLfSha256','requiredOwners')
    $actualCodeOwnerFields = @($config.codeOwners.PSObject.Properties.Name)
    if ($actualCodeOwnerFields.Count -ne $codeOwnerFields.Count -or
            @($actualCodeOwnerFields | Where-Object { $codeOwnerFields -notcontains $_ }).Count -gt 0 -or
            [string]$config.codeOwners.path -cne '.github/CODEOWNERS' -or
            [string]$config.codeOwners.normalizedLfSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            (Get-Cf7SortedKey @($config.codeOwners.requiredOwners)) -cne 'Crazyfs,Flash-Night') {
        throw 'Admission CODEOWNERS contract is invalid.'
    }
    $localCodeOwnersPath = Join-Path $root ([string]$config.codeOwners.path -replace '/', '\')
    if (-not (Test-Path -LiteralPath $localCodeOwnersPath -PathType Leaf)) { throw 'Configured CODEOWNERS file is missing.' }
    $nativeGatePath = Join-Path $root 'config\build\native-change-gate.v1.json'
    $nativeGateRaw = [IO.File]::ReadAllText($nativeGatePath, (New-Object Text.UTF8Encoding($false, $true))).TrimStart([char]0xFEFF)
    try { $nativeGate = $nativeGateRaw | ConvertFrom-Json }
    catch { throw "Native change gate cannot drive CODEOWNERS audit: $($_.Exception.Message)" }
    $localCodeOwners = Get-Cf7CodeOwnersContract ([IO.File]::ReadAllBytes($localCodeOwnersPath)) 'Local CODEOWNERS'
    if ([string]$localCodeOwners.Digest -cne [string]$config.codeOwners.normalizedLfSha256 -or
            -not (Test-Cf7CodeOwnersRoutes $localCodeOwners ([string[]]@($config.codeOwners.requiredOwners)) $nativeGate)) {
        throw 'Local CODEOWNERS does not match the frozen digest and trust-root/native owner routes.'
    }
    $requiredCheckFields = @('context','integrationId','workflowId','workflowPath','strict')
    $actualRequiredCheckFields = @($config.requiredStatusCheck.PSObject.Properties.Name)
    if ($actualRequiredCheckFields.Count -ne $requiredCheckFields.Count -or
            @($actualRequiredCheckFields | Where-Object { $requiredCheckFields -notcontains $_ }).Count -gt 0 -or
            [string]$config.requiredStatusCheck.context -cne 'verify-staged-bundle' -or
            [int64]$config.requiredStatusCheck.integrationId -ne 15368 -or
            [int64]$config.requiredStatusCheck.workflowId -ne 314853607 -or
            [string]$config.requiredStatusCheck.workflowPath -cne '.github/workflows/runtime-bundle-integrity.yml' -or
            $config.requiredStatusCheck.strict -ne $true) {
        throw 'Admission required status check contract is invalid.'
    }
    if ($config.actors -isnot [Array] -or @($config.actors).Count -eq 0) { throw 'Admission actors must be a non-empty array.' }

    $actorIds = New-Object 'Collections.Generic.HashSet[long]'
    $actorLogins = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $restricted = New-Object 'Collections.Generic.List[object]'
    $direct = New-Object 'Collections.Generic.List[object]'
    foreach ($actor in @($config.actors)) {
        $id = [int64]$actor.databaseId
        $login = [string]$actor.login
        $admission = [string]$actor.admission
        if ($id -le 0 -or -not $actorIds.Add($id)) { throw "Admission actor has an invalid or duplicate databaseId: $id" }
        if ($login -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$' -or -not $actorLogins.Add($login)) {
            throw "Admission actor has an invalid or duplicate login: $login"
        }
        if ($admission -eq 'restricted') { [void]$restricted.Add($actor) }
        elseif ($admission -eq 'directPushBypass') { [void]$direct.Add($actor) }
        else { throw "Admission actor $login has an unsupported admission: $admission" }
    }
    if ($restricted.Count -eq 0 -or $direct.Count -eq 0) { throw 'Admission config requires both restricted and directPushBypass actors.' }
    # PowerShell 5.1 can throw "Argument types do not match" when a generic List[object]
    # is wrapped in @(...). Freeze both collections as ordinary arrays before remote audit.
    $restricted = [object[]]$restricted.ToArray()
    $direct = [object[]]$direct.ToArray()

    $identityConfig = $config.rulesets.identityGate
    $historyConfig = $config.rulesets.globalRefIntegrity
    $tagCreationConfig = $config.rulesets.runtimeTagCreation
    $tagImmutabilityConfig = $config.rulesets.runtimeTagImmutability
    if ([string]$identityConfig.name -cne 'main-native-identity-gate-v1' -or
            [string]$identityConfig.bypassAdmission -cne 'directPushBypass' -or
            [string]$identityConfig.bypassMode -cne 'always' -or
            $identityConfig.requirePullRequest -ne $true -or
            (Get-Cf7SortedKey @($identityConfig.allowedMergeMethods)) -cne 'merge' -or
            @($identityConfig.requiredReviewers).Count -ne 0 -or
            [int]$identityConfig.requiredApprovingReviewCount -ne 0 -or
            $identityConfig.requireCodeOwnerReview -ne $true -or
            $identityConfig.dismissStaleReviewsOnPush -ne $true -or
            $identityConfig.requireLastPushApproval -ne $false -or
            $identityConfig.requiredReviewThreadResolution -ne $false) {
        throw 'Identity ruleset desired state is invalid or does not require trust-root CODEOWNER review.'
    }
    if ([string]$historyConfig.name -cne 'main-global-ref-integrity-v1' -or
            @($historyConfig.bypassActors).Count -ne 0 -or
            (Get-Cf7SortedKey @($historyConfig.rules)) -cne 'deletion,non_fast_forward') {
        throw 'Global ref-integrity ruleset desired state is invalid.'
    }
    if ([string]$tagCreationConfig.name -cne 'runtime-source-tag-creation-v1' -or
            [string]$tagCreationConfig.bypassAdmission -cne 'restricted' -or
            [string]$tagCreationConfig.bypassMode -cne 'always' -or
            (Get-Cf7SortedKey @($tagCreationConfig.rules)) -cne 'creation') {
        throw 'Runtime source-tag creation ruleset desired state is invalid.'
    }
    if ([string]$tagImmutabilityConfig.name -cne 'runtime-source-tag-immutability-v1' -or
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
        if ([string]$repository.default_branch -cne 'main' -or
                $repository.allow_merge_commit -ne $true -or $repository.allow_auto_merge -ne $true) {
            Add-Cf7AdmissionIssue 'Repository must keep main as default and enable merge commits plus auto-merge for the restricted contribution path.'
        }
        $workflow = (Invoke-Cf7AdmissionApi ($repoApi + '/actions/workflows/' + [string]$config.requiredStatusCheck.workflowId)).Value
        if ([int64]$workflow.id -ne [int64]$config.requiredStatusCheck.workflowId -or
                [string]$workflow.path -cne [string]$config.requiredStatusCheck.workflowPath -or
                [string]$workflow.state -cne 'active') {
            Add-Cf7AdmissionIssue 'Required status-check workflow ID/path is not live in the active state.'
        }
        $remoteCodeOwnersResponse = (Invoke-Cf7AdmissionApi (
            $repoApi + '/contents/' + [string]$config.codeOwners.path + '?ref=main'
        )).Value
        if ([string]$remoteCodeOwnersResponse.type -cne 'file' -or
                [string]$remoteCodeOwnersResponse.path -cne [string]$config.codeOwners.path -or
                [string]$remoteCodeOwnersResponse.encoding -cne 'base64') {
            Add-Cf7AdmissionIssue 'Remote main CODEOWNERS is missing or not a regular base64 file response.'
        } else {
            try {
                $remoteCodeOwnersBytes = [Convert]::FromBase64String(([string]$remoteCodeOwnersResponse.content -replace '\s',''))
                $remoteCodeOwners = Get-Cf7CodeOwnersContract $remoteCodeOwnersBytes 'Remote main CODEOWNERS'
                if ([string]$remoteCodeOwners.Digest -cne [string]$config.codeOwners.normalizedLfSha256) {
                    Add-Cf7AdmissionIssue 'Remote main CODEOWNERS differs from the frozen normalized-LF digest.'
                }
            } catch { Add-Cf7AdmissionIssue ('Remote main CODEOWNERS could not be decoded or validated: ' + $_.Exception.Message) }
        }
        $codeOwnersErrors = (Invoke-Cf7AdmissionApi ($repoApi + '/codeowners/errors?ref=main')).Value
        if ($null -eq $codeOwnersErrors.PSObject.Properties['errors'] -or @($codeOwnersErrors.errors).Count -ne 0) {
            Add-Cf7AdmissionIssue 'GitHub reports CODEOWNERS syntax or ownership errors on main.'
        }
        $collaborators = @((Invoke-Cf7AdmissionApi ($repoApi + '/collaborators?affiliation=all&per_page=100')).Value)
        if ($collaborators.Count -ge 100) { Add-Cf7AdmissionIssue 'Collaborator audit reached the 100-row safety limit; pagination support is required.' }
        $expectedActorKey = Get-Cf7SortedKey @($config.actors | ForEach-Object { "$($_.databaseId):$($_.login.ToLowerInvariant())" })
        $actualActorKey = Get-Cf7SortedKey @($collaborators | ForEach-Object { "$($_.id):$(([string]$_.login).ToLowerInvariant())" })
        if ($actualActorKey -cne $expectedActorKey) { Add-Cf7AdmissionIssue 'Direct collaborator set or ID/login mapping differs from versioned admission config.' }
        foreach ($actor in @($config.actors)) {
            $matchingCollaborators = @($collaborators | Where-Object { [int64]$_.id -eq [int64]$actor.databaseId })
            if ($matchingCollaborators.Count -ne 1 -or
                    $null -eq $matchingCollaborators[0].PSObject.Properties['permissions'] -or
                    $null -eq $matchingCollaborators[0].permissions.PSObject.Properties['push'] -or
                    $matchingCollaborators[0].permissions.push -ne $true) {
                Add-Cf7AdmissionIssue "Admission actor $($actor.login) does not have effective push permission for direct push or same-repository contrib branches."
            }
        }

        $rulesetSummaries = @((Invoke-Cf7AdmissionApi ($repoApi + '/rulesets?includes_parents=true&per_page=100')).Value)
        if ($rulesetSummaries.Count -ge 100) { Add-Cf7AdmissionIssue 'Ruleset audit reached the 100-row safety limit; pagination support is required.' }
        $expectedNames = @(
            [string]$identityConfig.name,
            [string]$historyConfig.name,
            [string]$tagCreationConfig.name,
            [string]$tagImmutabilityConfig.name
        )
        $unexpectedRulesets = @($rulesetSummaries | Where-Object { $expectedNames -notcontains [string]$_.name })
        if ($unexpectedRulesets.Count -gt 0) { Add-Cf7AdmissionIssue ('Unexpected repository/parent rulesets exist: ' + (($unexpectedRulesets | ForEach-Object name) -join ',')) }

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
            if (-not (Test-Cf7RepositoryRulesetSource $resolved ([string]$config.repository))) {
                Add-Cf7AdmissionIssue "Resolved ruleset $name is not sourced by the configured repository."
                continue
            }
            $resolvedRulesets[$name] = $resolved
        }

        $expectedEnforcement = if ($ExpectedState -eq 'Prepared') { 'disabled' } else { 'active' }
        $identity = $resolvedRulesets[[string]$identityConfig.name]
        if ($identity) {
            if (-not (Test-Cf7RulesetTarget $identity $config.target) -or [string]$identity.enforcement -cne $expectedEnforcement) {
                Add-Cf7AdmissionIssue 'Identity ruleset target or enforcement differs from expected state.'
            }
            if ($null -eq $identity.PSObject.Properties['bypass_actors']) {
                Add-Cf7AdmissionIssue 'Identity ruleset response omits bypass_actors.'
            }
            $bypass = @($identity.bypass_actors)
            $expectedBypassIds = Get-Cf7SortedKey @($direct | ForEach-Object { [int64]$_.databaseId })
            $actualBypassIds = Get-Cf7SortedKey @($bypass | ForEach-Object { [int64]$_.actor_id })
            if ($actualBypassIds -cne $expectedBypassIds -or
                    @($bypass | Where-Object { [string]$_.actor_type -cne 'User' -or [string]$_.bypass_mode -cne 'always' }).Count -gt 0) {
                Add-Cf7AdmissionIssue 'Identity ruleset bypass actors are not the exact directPushBypass User/always set.'
            }
            if (@($bypass | Where-Object { $actorIds.Contains([int64]$_.actor_id) -and
                    @($restricted | ForEach-Object { [int64]$_.databaseId }) -contains [int64]$_.actor_id }).Count -gt 0) {
                Add-Cf7AdmissionIssue 'A restricted actor appears in the identity ruleset bypass list.'
            }
            $pullRule = @($identity.rules | Where-Object { [string]$_.type -eq 'pull_request' })
            $statusRule = @($identity.rules | Where-Object { [string]$_.type -eq 'required_status_checks' })
            if ((Get-Cf7SortedKey @($identity.rules | ForEach-Object type)) -cne 'pull_request,required_status_checks') {
                Add-Cf7AdmissionIssue 'Identity ruleset contains missing or extra rule types.'
            }
            if ($pullRule.Count -ne 1 -or [int]$pullRule[0].parameters.required_approving_review_count -ne 0 -or
                    (Get-Cf7SortedKey @($pullRule[0].parameters.allowed_merge_methods)) -cne 'merge' -or
                    @($pullRule[0].parameters.required_reviewers).Count -ne 0 -or
                    $pullRule[0].parameters.require_code_owner_review -ne $true -or
                    $pullRule[0].parameters.dismiss_stale_reviews_on_push -ne $true -or
                    $pullRule[0].parameters.require_last_push_approval -ne $false -or
                    $pullRule[0].parameters.required_review_thread_resolution -ne $false) {
                Add-Cf7AdmissionIssue 'Identity pull-request rule differs from the frozen zero-general-approval plus trust-root CODEOWNER contract.'
            }
            [object[]]$checks = @(if ($statusRule.Count -eq 1) { $statusRule[0].parameters.required_status_checks })
            if ($statusRule.Count -ne 1 -or $statusRule[0].parameters.strict_required_status_checks_policy -ne $true -or
                    $checks.Count -ne 1 -or [string]$checks[0].context -cne [string]$config.requiredStatusCheck.context -or
                    [int64]$checks[0].integration_id -ne [int64]$config.requiredStatusCheck.integrationId) {
                Add-Cf7AdmissionIssue 'Identity required-status-check rule differs from the versioned contract.'
            }
            $currentActor = @($config.actors | Where-Object { [string]$_.login -ieq [string]$user.login })
            if ($currentActor.Count -eq 1 -and $null -ne $identity.PSObject.Properties['current_user_can_bypass']) {
                $expectedCanBypass = [string]$currentActor[0].admission -eq 'directPushBypass'
                if ([bool]$identity.current_user_can_bypass -ne $expectedCanBypass) {
                    Add-Cf7AdmissionIssue 'current_user_can_bypass disagrees with the authenticated actor admission.'
                }
            }
        }

        $history = $resolvedRulesets[[string]$historyConfig.name]
        if ($history) {
            if (-not (Test-Cf7RulesetTarget $history $config.target) -or [string]$history.enforcement -cne $expectedEnforcement) {
                Add-Cf7AdmissionIssue 'Global ref-integrity ruleset target or enforcement differs from expected state.'
            }
            if ($null -eq $history.PSObject.Properties['bypass_actors']) {
                Add-Cf7AdmissionIssue 'Global ref-integrity ruleset response omits bypass_actors.'
            }
            if (@($history.bypass_actors).Count -ne 0 -or
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
            if ($null -eq $tagCreation.PSObject.Properties['bypass_actors']) {
                Add-Cf7AdmissionIssue 'Runtime source-tag creation ruleset response omits bypass_actors.'
            }
            [object[]]$tagCreationBypass = @($tagCreation.bypass_actors)
            $expectedTagCreatorIds = Get-Cf7SortedKey @($restricted | ForEach-Object { [int64]$_.databaseId })
            $actualTagCreatorIds = Get-Cf7SortedKey @($tagCreationBypass | ForEach-Object { [int64]$_.actor_id })
            if ($actualTagCreatorIds -cne $expectedTagCreatorIds -or
                    @($tagCreationBypass | Where-Object {
                        [string]$_.actor_type -cne 'User' -or [string]$_.bypass_mode -cne 'always'
                    }).Count -gt 0 -or
                    (Get-Cf7SortedKey @($tagCreation.rules | ForEach-Object type)) -cne 'creation') {
                Add-Cf7AdmissionIssue 'Runtime source-tag creation ruleset must allow only the restricted User/always creators and only the creation rule.'
            }
        }

        $tagImmutability = $resolvedRulesets[[string]$tagImmutabilityConfig.name]
        if ($tagImmutability) {
            if (-not (Test-Cf7RulesetTarget $tagImmutability $config.runtimeSourceTag) -or
                    [string]$tagImmutability.enforcement -cne $expectedEnforcement) {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability ruleset target or enforcement differs from expected state.'
            }
            if ($null -eq $tagImmutability.PSObject.Properties['bypass_actors']) {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability ruleset response omits bypass_actors.'
            }
            [object[]]$tagUpdateRules = @($tagImmutability.rules | Where-Object { [string]$_.type -eq 'update' })
            if (@($tagImmutability.bypass_actors).Count -ne 0) {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability ruleset must have no bypass.'
            }
            if ((Get-Cf7SortedKey @($tagImmutability.rules | ForEach-Object type)) -cne 'deletion,update') {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability ruleset must contain only deletion and update rules.'
            }
            if ($tagUpdateRules.Count -ne 1 -or
                    $tagUpdateRules[0].parameters.update_allows_fetch_and_merge -ne $false) {
                Add-Cf7AdmissionIssue 'Runtime source-tag immutability update rule is missing or weakened.'
            }
        }

        $classic = Invoke-Cf7AdmissionApi ($repoApi + '/branches/main/protection') -AllowNotFound
        if ($ExpectedState -eq 'Active' -and $classic.Found) { Add-Cf7AdmissionIssue 'Classic branch protection still exists after active ruleset migration.' }
        if ($ExpectedState -in @('Prepared','Layered')) {
            if (-not $classic.Found) { Add-Cf7AdmissionIssue "Classic branch protection is missing during $ExpectedState fail-closed state." }
            else {
                $classicChecks = @($classic.Value.required_status_checks.checks)
                $classicContext = @($classicChecks | Where-Object {
                    [string]$_.context -ceq [string]$config.requiredStatusCheck.context -and
                    [int64]$_.app_id -eq [int64]$config.requiredStatusCheck.integrationId
                })
                if ($classic.Value.required_status_checks.strict -ne $true -or
                        $classicChecks.Count -ne 1 -or $classicContext.Count -ne 1 -or
                        $classic.Value.enforce_admins.enabled -ne $true -or
                        $null -eq $classic.Value.required_pull_request_reviews -or
                        $classic.Value.required_pull_request_reviews.require_code_owner_reviews -ne $true -or
                        $classic.Value.required_pull_request_reviews.dismiss_stale_reviews -ne $true -or
                        [int]$classic.Value.required_pull_request_reviews.required_approving_review_count -ne 0 -or
                        $classic.Value.required_pull_request_reviews.require_last_push_approval -ne $false -or
                        $classic.Value.required_conversation_resolution.enabled -ne $false -or
                        $null -ne $classic.Value.restrictions -or
                        $classic.Value.allow_force_pushes.enabled -ne $false -or
                        $classic.Value.allow_deletions.enabled -ne $false) {
                    Add-Cf7AdmissionIssue 'Classic protection is present but weaker than the frozen migration baseline.'
                }
            }
        }
        if ($ExpectedState -in @('Layered','Active')) {
            $effectiveRules = @((Invoke-Cf7AdmissionApi ($repoApi + '/rules/branches/main')).Value)
            $effectiveTypes = @($effectiveRules | ForEach-Object type | Sort-Object -Unique)
            foreach ($requiredType in @('deletion','non_fast_forward','pull_request','required_status_checks')) {
                if ($effectiveTypes -notcontains $requiredType) { Add-Cf7AdmissionIssue "Effective main rules lack $requiredType." }
            }

            $mainCommit = (Invoke-Cf7AdmissionApi ($repoApi + '/commits/main')).Value
            $mainSha = ([string]$mainCommit.sha).ToLowerInvariant()
            if ($mainSha -notmatch '^[0-9a-f]{40,64}$' -or [string]$mainCommit.sha -cne $mainSha) {
                Add-Cf7AdmissionIssue 'Current main ref did not resolve to one canonical full commit OID.'
            } else {
                $encodedContext = [Uri]::EscapeDataString([string]$config.requiredStatusCheck.context)
                $checkResponse = (Invoke-Cf7AdmissionApi (
                    $repoApi + '/commits/' + $mainSha + '/check-runs?check_name=' + $encodedContext
                )).Value
                if ($null -eq $checkResponse.PSObject.Properties['total_count'] -or
                        $null -eq $checkResponse.PSObject.Properties['check_runs']) {
                    Add-Cf7AdmissionIssue 'Current main check-runs response lacks total_count or check_runs.'
                } else {
                    [object[]]$headChecks = @($checkResponse.check_runs)
                    if ([long]$checkResponse.total_count -ne $headChecks.Count) {
                        Add-Cf7AdmissionIssue 'Current main check-runs response is incomplete or requires pagination.'
                    }
                    $validHeadChecks = New-Object 'Collections.Generic.List[object]'
                    foreach ($headCheck in $headChecks) {
                        $runLink = Get-Cf7AdmissionRunLink ([string]$headCheck.details_url) ([string]$config.repository)
                        if ([long]$headCheck.id -le 0 -or
                                [string]$headCheck.name -cne [string]$config.requiredStatusCheck.context -or
                                [string]$headCheck.head_sha -cne $mainSha -or
                                [string]$headCheck.status -cne 'completed' -or
                                [string]$headCheck.conclusion -cne 'success' -or
                                $null -eq $headCheck.app -or
                                [long]$headCheck.app.id -ne [long]$config.requiredStatusCheck.integrationId -or
                                $null -eq $headCheck.check_suite -or [long]$headCheck.check_suite.id -le 0 -or
                                $null -eq $runLink -or [long]$runLink.JobId -ne [long]$headCheck.id) {
                            continue
                        }
                        $headRun = (Invoke-Cf7AdmissionApi ($repoApi + '/actions/runs/' + [long]$runLink.RunId)).Value
                        if ([long]$headRun.id -eq [long]$runLink.RunId -and
                                [long]$headRun.check_suite_id -eq [long]$headCheck.check_suite.id -and
                                [long]$headRun.workflow_id -eq [long]$config.requiredStatusCheck.workflowId -and
                                [string]$headRun.path -ceq [string]$config.requiredStatusCheck.workflowPath -and
                                [string]$headRun.event -ceq 'push' -and
                                [string]$headRun.status -ceq 'completed' -and
                                [string]$headRun.conclusion -ceq 'success' -and
                                [string]$headRun.head_branch -ceq 'main' -and
                                [string]$headRun.head_sha -ceq $mainSha -and
                                [string]$headRun.repository.full_name -ieq [string]$config.repository -and
                                [string]$headRun.head_repository.full_name -ieq [string]$config.repository) {
                            [void]$validHeadChecks.Add([pscustomobject]@{
                                CheckId=[long]$headCheck.id
                                RunId=[long]$headRun.id
                            })
                        }
                    }
                    if ($validHeadChecks.Count -ne 1) {
                        Add-Cf7AdmissionIssue "Current main HEAD requires exactly one latest successful push/main check bound to the frozen workflow; found $($validHeadChecks.Count)."
                    } else {
                        $remoteSummary = [ordered]@{
                            authenticatedLogin=[string]$user.login
                            collaboratorCount=$collaborators.Count
                            rulesetCount=$rulesetSummaries.Count
                            mainSha=$mainSha
                            mainCheckId=[long]$validHeadChecks[0].CheckId
                            mainRunId=[long]$validHeadChecks[0].RunId
                        }
                    }
                }
            }
        }
        if ($null -eq $remoteSummary) {
            $remoteSummary = [ordered]@{ authenticatedLogin=[string]$user.login; collaboratorCount=$collaborators.Count; rulesetCount=$rulesetSummaries.Count }
        }
    }

    $result = [pscustomobject][ordered]@{
        schema = 'cf7-main-branch-admission-audit.v1'
        passed = $script:Issues.Count -eq 0
        expectedState = $ExpectedState
        repository = [string]$config.repository
        actorCount = @($config.actors).Count
        restrictedUsers = @($restricted | ForEach-Object login)
        directPushBypassUsers = @($direct | ForEach-Object login)
        remote = $remoteSummary
        issues = @($script:Issues)
    }
    if ($Json) { $result | ConvertTo-Json -Depth 8 -Compress }
    else {
        $status = if ($result.passed) { 'OK' } else { 'FAIL' }
        Write-Host "[MainAdmissionAudit] $status state=$ExpectedState actors=$($result.actorCount) restricted=$($result.restrictedUsers -join ',')"
        foreach ($issue in @($result.issues)) { Write-Host "[MainAdmissionAudit] ISSUE $issue" -ForegroundColor Red }
    }
    if (-not $result.passed) { exit 1 }
} catch {
    Write-Host "[MainAdmissionAudit] FAIL $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
