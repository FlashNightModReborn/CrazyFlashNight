[CmdletBinding()]
param(
    [switch]$ForceBuild,
    [switch]$BuildOnly,
    [switch]$ReuseOnly,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

if ($Status -and ($ForceBuild -or $BuildOnly -or $ReuseOnly)) {
    throw '-Status cannot be combined with -ForceBuild, -BuildOnly, or -ReuseOnly.'
}
if ($ForceBuild -and $ReuseOnly) {
    throw '-ForceBuild and -ReuseOnly are mutually exclusive.'
}

$scriptDirectory = if ($PSScriptRoot) {
    $PSScriptRoot
} else {
    Split-Path -Parent -Path $MyInvocation.MyCommand.Path
}
$scriptDirectory = (Resolve-Path -LiteralPath $scriptDirectory).Path.TrimEnd('\')
$projectRoot = (Split-Path -Parent $scriptDirectory).TrimEnd('\')
$candidateBase = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\runtime-candidates\v2')).TrimEnd('\')
$devStateDirectory = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\runtime-dev')).TrimEnd('\')
$activePointerPath = Join-Path $devStateDirectory 'active.v1.json'
$runtimeCommonPath = Join-Path $projectRoot 'tools\runtime-build-v2-common.ps1'
$buildPath = Join-Path $projectRoot 'launcher\build.ps1'
$startPath = Join-Path $projectRoot 'automation\start.ps1'
$bundleVerifierPath = Join-Path $projectRoot 'tools\verify-runtime-bundle-v2.ps1'

foreach ($requiredPath in @($runtimeCommonPath, $buildPath, $startPath, $bundleVerifierPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Local development runtime dependency is missing: $requiredPath"
    }
}

. $runtimeCommonPath

function Test-Cf7DevSha256 {
    param([string]$Value)
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9A-Fa-f]{64}$'
}

function Assert-Cf7DevPlainPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Description
    )
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must not be a reparse point: $Path"
    }
}

function Assert-Cf7DevCandidateBase {
    foreach ($pathSegment in @(
        (Join-Path $projectRoot 'tmp'),
        (Join-Path $projectRoot 'tmp\runtime-candidates'),
        $candidateBase
    )) {
        if (Test-Path -LiteralPath $pathSegment) {
            Assert-Cf7DevPlainPath -Path $pathSegment -Description 'Local development candidate path segment'
        }
    }
}

function Get-Cf7DevCandidateRelativePath {
    param([Parameter(Mandatory=$true)][string]$CandidateRoot)
    $candidatePath = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
    $candidateParent = [IO.Path]::GetDirectoryName($candidatePath).TrimEnd('\')
    if (-not $candidateParent.Equals($candidateBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Local development candidates must be direct children of $candidateBase"
    }
    return $candidatePath.Substring($projectRoot.Length + 1).Replace('\', '/')
}

function Resolve-Cf7DevCandidateRelativePath {
    param([Parameter(Mandatory=$true)][string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or [IO.Path]::IsPathRooted($RelativePath)) {
        throw 'The active local development candidate path must be repository-relative.'
    }
    $candidatePath = [IO.Path]::GetFullPath((Join-Path $projectRoot ($RelativePath.Replace('/', '\')))).TrimEnd('\')
    [void](Get-Cf7DevCandidateRelativePath -CandidateRoot $candidatePath)
    return $candidatePath
}

function Get-Cf7DevCandidateInfo {
    param(
        [Parameter(Mandatory=$true)][string]$CandidateRoot,
        [Parameter(Mandatory=$true)]$ExpectedIdentity
    )

    try {
        $candidatePath = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
        [void](Get-Cf7DevCandidateRelativePath -CandidateRoot $candidatePath)
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Container)) { return $null }
        Assert-Cf7DevPlainPath -Path $candidatePath -Description 'Local development candidate root'

        $metadataPath = Join-Path $candidatePath 'runtime-build-metadata.v2.json'
        $runtimePath = Join-Path $candidatePath 'runtime'
        $manifestPath = Join-Path $runtimePath 'cf7-runtime-manifest.tsv'
        $corePath = Join-Path $runtimePath 'CRAZYFLASHER7MercenaryEmpire.Core.dll'
        foreach ($requiredPath in @($metadataPath, $manifestPath, $corePath)) {
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { return $null }
            Assert-Cf7DevPlainPath -Path $requiredPath -Description 'Local development candidate file'
        }
        Assert-Cf7DevPlainPath -Path $runtimePath -Description 'Local development candidate runtime directory'

        $metadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$metadata.schema -cne 'cf7-runtime-candidate-metadata.v2') { return $null }
        foreach ($field in @(
            'artifactSourceHash',
            'producerRecipeHash',
            'toolchainLockHash',
            'buildIdentityHash',
            'payloadClosureHash'
        )) {
            if (-not (Test-Cf7DevSha256 -Value ([string]$metadata.$field))) { return $null }
        }
        foreach ($field in @(
            'artifactSourceHash',
            'producerRecipeHash',
            'toolchainLockHash',
            'buildIdentityHash'
        )) {
            if (([string]$metadata.$field).ToUpperInvariant() -cne
                    ([string]$ExpectedIdentity.$field).ToUpperInvariant()) {
                return $null
            }
        }

        return [pscustomobject][ordered]@{
            root = $candidatePath
            relativePath = Get-Cf7DevCandidateRelativePath -CandidateRoot $candidatePath
            artifactSourceHash = ([string]$metadata.artifactSourceHash).ToUpperInvariant()
            producerRecipeHash = ([string]$metadata.producerRecipeHash).ToUpperInvariant()
            toolchainLockHash = ([string]$metadata.toolchainLockHash).ToUpperInvariant()
            buildIdentityHash = ([string]$metadata.buildIdentityHash).ToUpperInvariant()
            payloadClosureHash = ([string]$metadata.payloadClosureHash).ToUpperInvariant()
            corePath = $corePath
            coreSha256 = (Get-FileHash -LiteralPath $corePath -Algorithm SHA256).Hash.ToUpperInvariant()
            createdAtUtc = [string]$metadata.createdAtUtc
            metadataLastWriteTimeUtc = (Get-Item -LiteralPath $metadataPath).LastWriteTimeUtc
        }
    } catch {
        Write-Verbose "Ignoring invalid local development candidate '$CandidateRoot': $($_.Exception.Message)"
        return $null
    }
}

function Get-Cf7DevPointerProbe {
    param([Parameter(Mandatory=$true)]$ExpectedIdentity)

    if (-not (Test-Path -LiteralPath $activePointerPath -PathType Leaf)) {
        return [pscustomobject]@{ state = 'missing'; reason = $null; info = $null }
    }
    try {
        Assert-Cf7DevPlainPath -Path $activePointerPath -Description 'Local development active pointer'
        $pointer = Get-Content -LiteralPath $activePointerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$pointer.schema -cne 'cf7-local-dev-runtime-selection.v1') {
            throw "unexpected schema '$($pointer.schema)'"
        }
        $candidatePath = Resolve-Cf7DevCandidateRelativePath -RelativePath ([string]$pointer.candidateRelativePath)
        $info = Get-Cf7DevCandidateInfo -CandidateRoot $candidatePath -ExpectedIdentity $ExpectedIdentity
        if ($null -eq $info) { throw 'candidate is missing, invalid, or does not match the current Worktree identity' }
        foreach ($field in @(
            'artifactSourceHash',
            'producerRecipeHash',
            'toolchainLockHash',
            'buildIdentityHash',
            'payloadClosureHash',
            'coreSha256'
        )) {
            if (([string]$pointer.$field).ToUpperInvariant() -cne ([string]$info.$field).ToUpperInvariant()) {
                throw "pointer/candidate mismatch: $field"
            }
        }
        return [pscustomobject]@{ state = 'ready'; reason = $null; info = $info }
    } catch {
        return [pscustomobject]@{ state = 'invalid_or_stale'; reason = $_.Exception.Message; info = $null }
    }
}

function Find-Cf7DevMatchingCandidates {
    param([Parameter(Mandatory=$true)]$ExpectedIdentity)

    if (-not (Test-Path -LiteralPath $candidateBase -PathType Container)) { return @() }
    Assert-Cf7DevCandidateBase
    $matches = New-Object 'System.Collections.Generic.List[object]'
    foreach ($directory in @(Get-ChildItem -LiteralPath $candidateBase -Directory -Force)) {
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $info = Get-Cf7DevCandidateInfo -CandidateRoot $directory.FullName -ExpectedIdentity $ExpectedIdentity
        if ($null -ne $info) { [void]$matches.Add($info) }
    }
    return @($matches | Sort-Object metadataLastWriteTimeUtc -Descending)
}

function Select-Cf7DevReusableCandidate {
    param(
        [Parameter(Mandatory=$true)]$ExpectedIdentity,
        [Parameter(Mandatory=$true)]$PointerProbe,
        [Parameter(Mandatory=$true)][object[]]$Matches
    )

    $closures = @($Matches | ForEach-Object { $_.payloadClosureHash } | Sort-Object -Unique)
    if ($closures.Count -gt 1) {
        throw "Multiple payload closures exist for the current build identity. Refusing to guess; inspect reproducibility or use -ForceBuild. closures=$($closures -join ',')"
    }
    if ($PointerProbe.state -eq 'ready') { return $PointerProbe.info }
    if ($Matches.Count -gt 0) { return $Matches[0] }
    return $null
}

function Write-Cf7DevActivePointer {
    param([Parameter(Mandatory=$true)]$CandidateInfo)

    if (-not (Test-Path -LiteralPath $devStateDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $devStateDirectory -Force | Out-Null
    }
    Assert-Cf7DevPlainPath -Path $devStateDirectory -Description 'Local development state directory'
    if (Test-Path -LiteralPath $activePointerPath) {
        Assert-Cf7DevPlainPath -Path $activePointerPath -Description 'Local development active pointer'
    }

    $pointer = [ordered]@{
        schema = 'cf7-local-dev-runtime-selection.v1'
        candidateRelativePath = [string]$CandidateInfo.relativePath
        artifactSourceHash = [string]$CandidateInfo.artifactSourceHash
        producerRecipeHash = [string]$CandidateInfo.producerRecipeHash
        toolchainLockHash = [string]$CandidateInfo.toolchainLockHash
        buildIdentityHash = [string]$CandidateInfo.buildIdentityHash
        payloadClosureHash = [string]$CandidateInfo.payloadClosureHash
        coreSha256 = [string]$CandidateInfo.coreSha256
        activatedAtUtc = [DateTime]::UtcNow.ToString('o')
        trust = 'INDEX_ONLY_REVERIFY_BEFORE_EXECUTION'
    }
    $temporaryPointer = Join-Path $devStateDirectory (
        'active.v1.next-{0}-{1}.json' -f $PID, [Guid]::NewGuid().ToString('N'))
    $backupPointer = Join-Path $devStateDirectory (
        'active.v1.backup-{0}-{1}.json' -f $PID, [Guid]::NewGuid().ToString('N'))
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    try {
        [IO.File]::WriteAllText($temporaryPointer, (($pointer | ConvertTo-Json -Depth 5) + "`n"), $utf8NoBom)
        if (Test-Path -LiteralPath $activePointerPath -PathType Leaf) {
            # Windows PowerShell 5.1/.NET Framework rejects a null backup path for
            # File.Replace. A same-directory backup keeps the swap atomic across both
            # Windows PowerShell and modern PowerShell; the index itself remains ignored.
            [IO.File]::Replace($temporaryPointer, $activePointerPath, $backupPointer, $true)
        } else {
            [IO.File]::Move($temporaryPointer, $activePointerPath)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPointer) {
            Remove-Item -LiteralPath $temporaryPointer -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPointer) {
            Remove-Item -LiteralPath $backupPointer -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Cf7DevChildPowerShell {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory=$true)][string]$Description
    )
    $windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Description failed (exitCode=$exitCode)."
    }
}

function Write-Cf7DevStatus {
    param(
        [Parameter(Mandatory=$true)]$Identity,
        [Parameter(Mandatory=$true)]$PointerProbe,
        [Parameter(Mandatory=$true)][object[]]$Matches
    )
    $closures = @($Matches | ForEach-Object { $_.payloadClosureHash } | Sort-Object -Unique)
    $selectionState = if ($closures.Count -gt 1) {
        'equivocation'
    } elseif ($PointerProbe.state -eq 'ready') {
        'ready'
    } elseif ($Matches.Count -gt 0) {
        'matching_candidate_available'
    } elseif ($PointerProbe.state -eq 'missing') {
        'missing'
    } else {
        'invalid_or_stale'
    }
    $candidateInfo = if ($closures.Count -gt 1) {
        $null
    } elseif ($PointerProbe.state -eq 'ready') {
        $PointerProbe.info
    } elseif ($Matches.Count -gt 0) {
        $Matches[0]
    } else {
        $null
    }

    Write-Host '=== CF7 Local Development Runtime Status ===' -ForegroundColor Cyan
    Write-Host "  Selection state : $selectionState"
    Write-Host "  Worktree build  : $($Identity.buildIdentityHash)"
    Write-Host "  Active pointer  : $activePointerPath"
    Write-Host "  Candidate       : $(if ($null -ne $candidateInfo) { $candidateInfo.root } else { '<none>' })"
    if ($selectionState -eq 'equivocation') {
        Write-Host "  Closure conflict: $($closures -join ', ')" -ForegroundColor Red
    }
    Write-Host '  Formal runtime  : NOT SELECTED (local development status only)' -ForegroundColor Yellow

    return [pscustomobject][ordered]@{
        schema = 'cf7-local-dev-runtime-status.v1'
        selectionState = $selectionState
        pointerState = [string]$PointerProbe.state
        pointerReason = [string]$PointerProbe.reason
        pointerPath = $activePointerPath
        currentBuildIdentityHash = ([string]$Identity.buildIdentityHash).ToUpperInvariant()
        matchingCandidateCount = [int]$Matches.Count
        matchingPayloadClosureCount = [int]$closures.Count
        matchingPayloadClosureHashes = $closures
        candidateRoot = if ($null -ne $candidateInfo) { [string]$candidateInfo.root } else { $null }
        candidateCorePath = if ($null -ne $candidateInfo) { [string]$candidateInfo.corePath } else { $null }
        candidateCoreSha256 = if ($null -ne $candidateInfo) { [string]$candidateInfo.coreSha256 } else { $null }
        payloadClosureHash = if ($null -ne $candidateInfo) { [string]$candidateInfo.payloadClosureHash } else { $null }
        deploymentStatus = 'NOT_DEPLOYED'
    }
}

$identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $projectRoot -Mode Worktree
Assert-Cf7DevCandidateBase
$pointerProbe = Get-Cf7DevPointerProbe -ExpectedIdentity $identity
$matchingCandidates = @(Find-Cf7DevMatchingCandidates -ExpectedIdentity $identity)

if ($Status) {
    Write-Cf7DevStatus -Identity $identity -PointerProbe $pointerProbe -Matches $matchingCandidates
    return
}

$mutexHash = Get-Cf7RuntimeV2TextSha256 -Text $projectRoot.ToUpperInvariant()
$mutex = New-Object Threading.Mutex($false, ('Local\CF7_RuntimeDev_' + $mutexHash.Substring(0, 24)))
$mutexAcquired = $false
try {
    try {
        $mutexAcquired = $mutex.WaitOne([TimeSpan]::FromMinutes(30))
    } catch [Threading.AbandonedMutexException] {
        $mutexAcquired = $true
    }
    if (-not $mutexAcquired) { throw 'Timed out waiting for another local development runtime operation.' }

    # Refresh the pointer and candidate list after acquiring the mutation lock.
    $pointerProbe = Get-Cf7DevPointerProbe -ExpectedIdentity $identity
    $matchingCandidates = @(Find-Cf7DevMatchingCandidates -ExpectedIdentity $identity)
    $selected = $null
    $candidateAction = 'reused'
    if (-not $ForceBuild) {
        $selected = Select-Cf7DevReusableCandidate `
            -ExpectedIdentity $identity -PointerProbe $pointerProbe -Matches $matchingCandidates
    }

    if ($null -eq $selected) {
        if ($ReuseOnly) {
            throw "No reusable candidate matches current Worktree build identity $($identity.buildIdentityHash)."
        }
        Write-Host '=== CF7 Local Development Candidate Build ===' -ForegroundColor Cyan
        Write-Host '  Network/cloud policy : skipped; using installed local toolchain and dependency caches.'
        Write-Host '  Formal deployment    : not selected and must remain unchanged.' -ForegroundColor Yellow
        $buildOutput = @(& $buildPath `
            -ProjectRoot $projectRoot `
            -BuilderId 'local-dev' `
            -SkipPrepare `
            -SkipPolicy)
        $buildRecords = @($buildOutput | Where-Object {
            $null -ne $_ -and [string]$_.schema -ceq 'cf7-runtime-release-candidate.v2'
        })
        if ($buildRecords.Count -ne 1) {
            throw "Local candidate build returned $($buildRecords.Count) structured candidate records; expected exactly one."
        }
        $buildRecord = $buildRecords[0]
        if ([string]$buildRecord.deploymentStatus -cne 'NOT_DEPLOYED' -or
                [string]$buildRecord.runtimeMode -cne 'isolated_candidate' -or
                [bool]$buildRecord.formalDeploymentModified) {
            throw 'Local candidate build did not preserve the NOT_DEPLOYED/formal-unchanged contract.'
        }
        $selected = Get-Cf7DevCandidateInfo `
            -CandidateRoot ([string]$buildRecord.candidateRoot) -ExpectedIdentity $identity
        if ($null -eq $selected) {
            throw 'Fresh local candidate does not match the current Worktree identity.'
        }
        if ([string]$buildRecord.buildIdentityHash -cne [string]$selected.buildIdentityHash -or
                [string]$buildRecord.payloadClosureHash -cne [string]$selected.payloadClosureHash -or
                [string]$buildRecord.candidateCoreSha256 -cne [string]$selected.coreSha256) {
            throw 'Fresh local candidate structured result does not match its on-disk identity.'
        }
        $conflictingClosures = @($matchingCandidates | Where-Object {
            [string]$_.payloadClosureHash -cne [string]$selected.payloadClosureHash
        } | ForEach-Object { $_.payloadClosureHash } | Sort-Object -Unique)
        if ($conflictingClosures.Count -gt 0) {
            throw "Fresh local candidate diverged from an existing payload closure for the same build identity. Refusing to activate it. fresh=$($selected.payloadClosureHash) existing=$($conflictingClosures -join ',')"
        }
        $candidateAction = 'built'
    }

    Write-Host '=== CF7 Local Development Candidate Selected ===' -ForegroundColor Cyan
    Write-Host "  Action          : $candidateAction"
    Write-Host "  Candidate       : $($selected.root)"
    Write-Host "  Core SHA256     : $($selected.coreSha256)"
    Write-Host "  Build identity  : $($selected.buildIdentityHash)"
    Write-Host "  Payload closure : $($selected.payloadClosureHash)"
    Write-Host '  Deployment      : NOT_DEPLOYED (isolated local development candidate)' -ForegroundColor Yellow

    if ($BuildOnly) {
        Invoke-Cf7DevChildPowerShell -ScriptPath $bundleVerifierPath -Arguments @(
            '-ProjectRoot', $projectRoot,
            '-DeploymentRoot', $selected.root,
            '-IntegrityOnly'
        ) -Description 'Local candidate integrity verification'
        Write-Cf7DevActivePointer -CandidateInfo $selected
        [pscustomobject][ordered]@{
            schema = 'cf7-local-dev-runtime-result.v1'
            lifecycleState = 'candidate_built'
            candidateAction = $candidateAction
            candidateRoot = [string]$selected.root
            candidateCorePath = [string]$selected.corePath
            candidateCoreSha256 = [string]$selected.coreSha256
            buildIdentityHash = [string]$selected.buildIdentityHash
            payloadClosureHash = [string]$selected.payloadClosureHash
            activePointerPath = $activePointerPath
            deploymentStatus = 'NOT_DEPLOYED'
        }
        return
    }

    Invoke-Cf7DevChildPowerShell -ScriptPath $startPath -Arguments @(
        '-CandidateRoot', $selected.root
    ) -Description 'Local candidate launch'
    Write-Cf7DevActivePointer -CandidateInfo $selected
    [pscustomobject][ordered]@{
        schema = 'cf7-local-dev-runtime-result.v1'
        lifecycleState = 'candidate_executed'
        candidateAction = $candidateAction
        candidateRoot = [string]$selected.root
        candidateCorePath = [string]$selected.corePath
        candidateCoreSha256 = [string]$selected.coreSha256
        buildIdentityHash = [string]$selected.buildIdentityHash
        payloadClosureHash = [string]$selected.payloadClosureHash
        activePointerPath = $activePointerPath
        deploymentStatus = 'NOT_DEPLOYED'
    }
} finally {
    if ($mutexAcquired) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    $mutex.Dispose()
}
