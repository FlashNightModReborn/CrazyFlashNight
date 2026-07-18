[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$QueueRoot,
    [Parameter(Mandatory=$true)][string]$RequestId,
    [Parameter(Mandatory=$true)][string]$PolicyReceiptPath,
    [string]$CandidateRoot,
    [string[]]$ExternalAttestationPath = @()
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

function Get-Cf7PromotionSignerIdentity {
    param([Parameter(Mandatory=$true)][object]$Payload)
    if ([string]$Payload.schema -eq 'cf7-runtime-build-attestation-payload.v2') {
        return 'x509:' + ([string]$Payload.builderKeyId).ToUpperInvariant()
    }
    if ([string]$Payload.schema -eq 'cf7-runtime-github-build-attestation-payload.v2') {
        return 'github-oidc:' + ([string]$Payload.builderIdentityHash).ToUpperInvariant()
    }
    throw "Unsupported verified producer payload schema: $($Payload.schema)"
}

function Get-Cf7PromotionProofFingerprint {
    param([Parameter(Mandatory=$true)][object]$Proof)
    $fingerprint = if ([string]$Proof.schema -eq 'cf7-runtime-build-attestation.v2') {
        [string]$Proof.signature.canonicalPayloadSha256
    } else {
        [string]$Proof.canonicalPayloadSha256
    }
    $fingerprint = $fingerprint.ToUpperInvariant()
    if ($fingerprint -notmatch '^[0-9A-F]{64}$') { throw 'Verified producer proof has no canonical SHA-256 fingerprint.' }
    $representation = $Proof | ConvertTo-Json -Depth 30 -Compress
    $representationHash = Get-Cf7BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($representation))
    return "$fingerprint`:$representationHash"
}

function Select-Cf7PromotionUniqueEntries {
    param([Parameter(Mandatory=$true)][object[]]$Entries)
    $selected = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Entries) {
        $signerIdentity = Get-Cf7PromotionSignerIdentity -Payload $entry.payload
        $agreement = [string]::Join("`n", @(
            [string]$entry.payload.schema,
            [string]$entry.payload.faultDomain,
            ([string]$entry.payload.artifactSourceHash).ToUpperInvariant(),
            ([string]$entry.payload.producerRecipeHash).ToUpperInvariant(),
            ([string]$entry.payload.toolchainLockHash).ToUpperInvariant(),
            ([string]$entry.payload.buildIdentityHash).ToUpperInvariant(),
            ([string]$entry.payload.payloadClosureHash).ToUpperInvariant(),
            [string]$entry.payload.sourceCommitOid,
            [string]$entry.payload.releaseTreeOid
        ))
        $fingerprint = Get-Cf7PromotionProofFingerprint -Proof $entry.proof
        if ($selected.ContainsKey($signerIdentity)) {
            $existing = $selected[$signerIdentity]
            if ([string]$existing.agreement -cne $agreement) {
                throw "Runtime builder equivocation for release request: $signerIdentity"
            }
            if ([StringComparer]::Ordinal.Compare($fingerprint, [string]$existing.fingerprint) -lt 0) {
                $selected[$signerIdentity] = [pscustomobject]@{
                    signerIdentity=$signerIdentity; agreement=$agreement; fingerprint=$fingerprint; entry=$entry
                }
            }
            continue
        }
        $selected.Add($signerIdentity, [pscustomobject]@{
            signerIdentity=$signerIdentity; agreement=$agreement; fingerprint=$fingerprint; entry=$entry
        })
    }
    $rows = @($selected.Values)
    [Array]::Sort($rows, [Comparison[object]]{
        param($left,$right)
        return [StringComparer]::Ordinal.Compare([string]$left.signerIdentity,[string]$right.signerIdentity)
    })
    foreach ($row in $rows) { Write-Output $row.entry }
}

$QueueRoot = Get-Cf7RuntimeQueueRoot -ProjectRoot $ProjectRoot -QueueRoot $QueueRoot
$request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $RequestId
$registryPath = Join-Path $ProjectRoot 'config\build\runtime-builders.v2.json'
$identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode Worktree
foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
    if (([string]$identity.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) {
        throw "Current worktree does not materialize the immutable build request: $field"
    }
}

& git -C $ProjectRoot diff --quiet --no-ext-diff ([string]$request.releaseTreeOid) --
if ($LASTEXITCODE -eq 1) {
    throw 'Tracked worktree bytes no longer materialize the immutable request tree.'
}
if ($LASTEXITCODE -ne 0) { throw 'Cannot compare the worktree with the immutable request tree.' }

$PolicyReceiptPath = (Resolve-Path -LiteralPath $PolicyReceiptPath).Path
$receiptBytes = [IO.File]::ReadAllBytes($PolicyReceiptPath)
$receipt = [Text.Encoding]::UTF8.GetString($receiptBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
if ([string]$receipt.schema -ne 'cf7-runtime-policy-validation.v2' -or
        [string]$receipt.profile -ne 'production' -or $receipt.passed -ne $true) {
    throw 'Promotion requires a passed production cf7-runtime-policy-validation.v2 receipt.'
}
if ([string]$receipt.releaseTreeOid -ne ([string]$request.releaseTreeOid).ToLowerInvariant()) {
    throw 'Policy receipt does not bind the immutable request releaseTreeOid.'
}
foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
    if (([string]$receipt.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) {
        throw "Policy receipt does not match the immutable request: $field"
    }
}
foreach ($requiredCheck in @('release-tree-materialized','tracked-tree-readonly','candidate-payload-readonly')) {
    $matches = @($receipt.checks | Where-Object { [string]$_.name -eq $requiredCheck -and $_.passed -eq $true })
    if ($matches.Count -ne 1) { throw "Policy receipt lacks passed invariant: $requiredCheck" }
}

$verifiedEntries = @()
$githubWrapperInputs = @()
$identityResultsRoot = Join-Path (Join-Path $QueueRoot 'results') ([string]$request.buildIdentityHash).ToUpperInvariant()
if (Test-Path -LiteralPath $identityResultsRoot -PathType Container) {
    foreach ($resultFile in @(Get-ChildItem -LiteralPath $identityResultsRoot -Filter result.json -File -Recurse)) {
        try {
            $result = Get-Content -LiteralPath $resultFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $payload = Test-Cf7RuntimeBuildAttestationV2 -Attestation $result.attestation -RegistryPath $registryPath
            $matches = $true
            foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
                if (([string]$payload.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) { $matches = $false }
            }
            if ($matches) {
                $verifiedEntries += [pscustomobject]@{ proof=$result.attestation; payload=$payload }
            }
        } catch {
            Write-Warning "Ignoring invalid queue producer result $($resultFile.FullName): $($_.Exception.Message)"
        }
    }
}
foreach ($path in @($ExternalAttestationPath)) {
    $external = Get-Content -LiteralPath (Resolve-Path -LiteralPath $path).Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$external.schema -eq 'cf7-runtime-build-attestation.v2') {
        $payload = Test-Cf7RuntimeBuildAttestationV2 -Attestation $external -RegistryPath $registryPath
        foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
            if (([string]$payload.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) {
                throw "External attestation does not match request: $field ($path)"
            }
        }
        $verifiedEntries += [pscustomobject]@{ proof=$external; payload=$payload }
    } elseif ([string]$external.schema -eq 'cf7-runtime-github-build-attestation.v2') {
        $githubWrapperInputs += [pscustomobject]@{ path=$path; wrapper=$external }
    } else {
        throw "Unsupported external attestation schema: $path"
    }
}

if ($CandidateRoot) {
    $CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
} else {
    if ($verifiedEntries.Count -eq 0) {
        throw 'CandidateRoot is required when no verified local/X509 producer proof is available.'
    }
    $selectedClosure = @($verifiedEntries | Group-Object { ([string]$_.payload.payloadClosureHash).ToUpperInvariant() } |
        Sort-Object @{Expression={$_.Count};Descending=$true}, @{Expression={$_.Name};Descending=$false} |
        Select-Object -First 1)[0].Name
    $CandidateRoot = Join-Path `
        (Join-Path (Join-Path $QueueRoot 'cas\candidates') ([string]$request.buildIdentityHash).ToUpperInvariant()) `
        $selectedClosure
    $CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
}
if ($CandidateRoot -eq $ProjectRoot) { throw 'CandidateRoot cannot be the live project deployment root.' }
if ([string]::IsNullOrWhiteSpace([string]$receipt.candidateRoot)) {
    throw 'Promotion requires a policy receipt bound to the selected runtime candidate.'
}
try { $receiptCandidateRoot = [IO.Path]::GetFullPath([string]$receipt.candidateRoot).TrimEnd('\') }
catch { throw 'Policy receipt candidateRoot is invalid.' }
if ($receiptCandidateRoot -ne $CandidateRoot) {
    throw "Policy receipt candidateRoot does not match the selected candidate: receipt=$receiptCandidateRoot selected=$CandidateRoot"
}

$verifyBundle = Join-Path $ProjectRoot 'tools\verify-runtime-bundle-v2.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyBundle `
    -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
if ($LASTEXITCODE -ne 0) { throw 'Candidate runtime bundle v2 verification failed.' }
$candidateClosure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
$candidatePayloadHash = ([string]$candidateClosure.payloadClosureHash).ToUpperInvariant()
if ([string]$receipt.candidatePayloadClosureHash -notmatch '^[0-9A-Fa-f]{64}$' -or
        ([string]$receipt.candidatePayloadClosureHash).ToUpperInvariant() -ne $candidatePayloadHash) {
    throw 'Policy receipt candidatePayloadClosureHash does not match the selected candidate bytes.'
}
$verifiedEntries = @($verifiedEntries | Where-Object {
    ([string]$_.payload.payloadClosureHash).ToUpperInvariant() -eq $candidatePayloadHash
})

foreach ($input in $githubWrapperInputs) {
    $temporaryBase = Join-Path $ProjectRoot 'tmp\runtime-github-replay'
    New-Item -ItemType Directory -Path $temporaryBase -Force | Out-Null
    $temporaryRoot = Join-Path $temporaryBase ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    try {
        $envelopePath = Join-Path $temporaryRoot 'envelope.json'
        $bundlePath = Join-Path $temporaryRoot 'bundle.json'
        try {
            [IO.File]::WriteAllBytes($envelopePath, [Convert]::FromBase64String([string]$input.wrapper.envelopeBase64))
            [IO.File]::WriteAllBytes($bundlePath, [Convert]::FromBase64String([string]$input.wrapper.bundleBase64))
        } catch { throw "Invalid embedded GitHub attestation bytes: $($input.path)" }
        $verifiedWrapper = & (Join-Path $ProjectRoot 'tools\verify-runtime-github-attestation.ps1') `
            -ProjectRoot $ProjectRoot `
            -CandidateRoot $CandidateRoot `
            -EnvelopePath $envelopePath `
            -BundlePath $bundlePath `
            -ExpectedSourceCommitOid ([string]$request.sourceCommitOid) `
            -ReplayFromReleaseRecord
        if ($null -eq $verifiedWrapper -or [string]$verifiedWrapper.schema -ne 'cf7-runtime-github-build-attestation.v2') {
            throw "GitHub attestation verifier returned no normalized proof: $($input.path)"
        }
        Assert-Cf7RuntimeGitHubProofEquivalentV2 -Expected $input.wrapper -Actual $verifiedWrapper | Out-Null
        if ([string]$verifiedWrapper.payload.releaseTreeOid -ne ([string]$request.releaseTreeOid).ToLowerInvariant()) {
            throw "GitHub proof releaseTreeOid does not match the immutable request: $($input.path)"
        }
        foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
            if (([string]$verifiedWrapper.payload.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) {
                throw "GitHub proof does not match request: $field ($($input.path))"
            }
        }
        $verifiedEntries += [pscustomobject]@{ proof=$verifiedWrapper; payload=$verifiedWrapper.payload }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
    }
}

$verifiedEntries = @(Select-Cf7PromotionUniqueEntries -Entries $verifiedEntries)
$consensus = Test-Cf7RuntimeVerifiedPayloadConsensusV2 `
    -Payloads @($verifiedEntries | ForEach-Object { $_.payload }) `
    -MinimumConsensus 2
if ($candidatePayloadHash -ne ([string]$consensus.payloadClosureHash).ToUpperInvariant()) {
    throw 'Candidate payload does not match the independent builder consensus.'
}
$attestations = @($verifiedEntries | ForEach-Object { $_.proof })

$deploymentChanges = @(& git -C $ProjectRoot status --porcelain -- `
    'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json')
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect current runtime deployment state.' }
if ($deploymentChanges.Count -gt 0) {
    throw "Live runtime deployment is dirty; promotion refused:`n$($deploymentChanges -join "`n")"
}

$transactionBase = [IO.Path]::GetFullPath((Join-Path $ProjectRoot 'tmp\runtime-promotions')).TrimEnd('\')
New-Item -ItemType Directory -Path $transactionBase -Force | Out-Null
$transactionRoot = Join-Path $transactionBase ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N'))
$stageRoot = Join-Path $transactionRoot 'next'
$backupRoot = Join-Path $transactionRoot 'previous'
New-Item -ItemType Directory -Path $stageRoot,$backupRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $CandidateRoot 'runtime') -Destination $stageRoot -Recurse
Copy-Item -LiteralPath (Join-Path $CandidateRoot 'CRAZYFLASHER7MercenaryEmpire.exe') `
    -Destination (Join-Path $stageRoot 'CRAZYFLASHER7MercenaryEmpire.exe')

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyBundle `
    -ProjectRoot $ProjectRoot -DeploymentRoot $stageRoot
if ($LASTEXITCODE -ne 0) { throw 'Staged promotion copy failed bundle verification.' }

$manifestPath = Join-Path $stageRoot 'runtime\cf7-runtime-manifest.tsv'
$manifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash.ToUpperInvariant()
$orderedAttestations = @($attestations)
$releaseRecord = [pscustomobject][ordered]@{
    schema = 'cf7-runtime-release-consensus.v2'
    requestId = ([string]$request.requestId).ToUpperInvariant()
    releaseTreeOid = ([string]$request.releaseTreeOid).ToLowerInvariant()
    artifactSourceHash = ([string]$identity.artifactSourceHash).ToUpperInvariant()
    producerRecipeHash = ([string]$identity.producerRecipeHash).ToUpperInvariant()
    toolchainLockHash = ([string]$identity.toolchainLockHash).ToUpperInvariant()
    policyHash = ([string]$identity.policyHash).ToUpperInvariant()
    buildIdentityHash = ([string]$identity.buildIdentityHash).ToUpperInvariant()
    payloadClosureHash = ([string]$candidateClosure.payloadClosureHash).ToUpperInvariant()
    manifestSha256 = $manifestSha256
    policyReceiptSha256 = (Get-Cf7BytesSha256 -Bytes $receiptBytes)
    policyReceiptBase64 = [Convert]::ToBase64String($receiptBytes)
    attestations = $orderedAttestations
    promotedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$nextConsensusRecord = Join-Path $stageRoot 'runtime-release-consensus.json'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($nextConsensusRecord, (($releaseRecord | ConvertTo-Json -Depth 30) + "`n"), $utf8NoBom)

$liveRuntime = Join-Path $ProjectRoot 'runtime'
$liveBootstrap = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$consensusRecordPath = Join-Path $ProjectRoot 'config\build\runtime-release-consensus.json'
$backupRuntime = Join-Path $backupRoot 'runtime'
$backupBootstrap = Join-Path $backupRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$backupConsensusRecord = Join-Path $backupRoot 'runtime-release-consensus.json'
$hadConsensusRecord = Test-Path -LiteralPath $consensusRecordPath -PathType Leaf
$installedRuntime = $false
$installedBootstrap = $false
$installedConsensusRecord = $false
try {
    Move-Item -LiteralPath $liveRuntime -Destination $backupRuntime
    Move-Item -LiteralPath $liveBootstrap -Destination $backupBootstrap
    if ($hadConsensusRecord) { Move-Item -LiteralPath $consensusRecordPath -Destination $backupConsensusRecord }
    Move-Item -LiteralPath (Join-Path $stageRoot 'runtime') -Destination $liveRuntime
    $installedRuntime = $true
    Move-Item -LiteralPath (Join-Path $stageRoot 'CRAZYFLASHER7MercenaryEmpire.exe') -Destination $liveBootstrap
    $installedBootstrap = $true
    Move-Item -LiteralPath $nextConsensusRecord -Destination $consensusRecordPath
    $installedConsensusRecord = $true

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyBundle -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw 'Promoted runtime bundle failed final verification.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $ProjectRoot 'tools\verify-runtime-consensus.ps1') -ProjectRoot $ProjectRoot
    if ($LASTEXITCODE -ne 0) { throw 'Promoted runtime consensus record failed final verification.' }
    # CRAZYFLASHER7MercenaryEmpire.exe is a GUI-subsystem executable. Wait on the
    # process handle explicitly; the PowerShell call operator may otherwise return
    # before verification finishes and expose a stale $LASTEXITCODE.
    $verifyStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $verifyStartInfo.FileName = $liveBootstrap
    $verifyStartInfo.Arguments = '--verify-only'
    $verifyStartInfo.WorkingDirectory = $ProjectRoot
    $verifyStartInfo.UseShellExecute = $false
    $verifyStartInfo.CreateNoWindow = $true
    $verifyProcess = [System.Diagnostics.Process]::Start($verifyStartInfo)
    if ($null -eq $verifyProcess) { throw 'Promoted bootstrap verification process did not start.' }
    try {
        $verifyTimedOut = -not $verifyProcess.WaitForExit(120000)
        if ($verifyTimedOut) {
            try { $verifyProcess.Kill() } catch { }
            [void]$verifyProcess.WaitForExit(10000)
            $verifyExitCode = $null
        } else {
            $verifyExitCode = $verifyProcess.ExitCode
        }
    } finally {
        $verifyProcess.Dispose()
    }
    if ($verifyTimedOut) { throw 'Promoted bootstrap verification timed out after 120 seconds.' }
    if ($verifyExitCode -ne 0) { throw "Promoted bootstrap rejected the runtime bundle (exitCode=$verifyExitCode)." }
} catch {
    $failure = $_
    $rollbackErrors = New-Object 'System.Collections.Generic.List[string]'
    $rollbackStep = {
        param([string]$Label,[scriptblock]$Action)
        try { & $Action }
        catch { $rollbackErrors.Add("$Label`: $($_.Exception.Message)") }
    }
    if ($installedConsensusRecord -and (Test-Path -LiteralPath $consensusRecordPath)) {
        & $rollbackStep 'remove new consensus record' { Remove-Item -LiteralPath $consensusRecordPath -Force }
    }
    if ($installedBootstrap -and (Test-Path -LiteralPath $liveBootstrap)) {
        & $rollbackStep 'remove new bootstrap' { Remove-Item -LiteralPath $liveBootstrap -Force }
    }
    if ($installedRuntime -and (Test-Path -LiteralPath $liveRuntime)) {
        & $rollbackStep 'remove new runtime' { Remove-Item -LiteralPath $liveRuntime -Recurse -Force }
    }
    if (Test-Path -LiteralPath $backupBootstrap) {
        & $rollbackStep 'restore previous bootstrap' { Move-Item -LiteralPath $backupBootstrap -Destination $liveBootstrap }
    }
    if (Test-Path -LiteralPath $backupRuntime) {
        & $rollbackStep 'restore previous runtime' { Move-Item -LiteralPath $backupRuntime -Destination $liveRuntime }
    }
    if ($hadConsensusRecord -and (Test-Path -LiteralPath $backupConsensusRecord)) {
        & $rollbackStep 'restore previous consensus record' { Move-Item -LiteralPath $backupConsensusRecord -Destination $consensusRecordPath }
    }
    $rollbackSuffix = if ($rollbackErrors.Count -eq 0) { '' } else { " Rollback errors: $([string]::Join(' | ', $rollbackErrors.ToArray()))" }
    throw "Runtime promotion rolled back: $($failure.Exception.Message)$rollbackSuffix"
}

Write-Host "[RuntimePromotion] OK request=$($request.requestId) signers=$($consensus.signerIdentities.Count) payload=$($consensus.payloadClosureHash)" -ForegroundColor Green
Write-Host "[RuntimePromotion] Recoverable previous bundle: $backupRoot" -ForegroundColor DarkGray
