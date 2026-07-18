param(
    [string]$ProjectRoot,
    [string]$DeploymentRoot,
    [string]$RecordPath,
    [switch]$Staged,
    [switch]$IntegrityOnly
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$DeploymentRoot = if ($DeploymentRoot) { (Resolve-Path -LiteralPath $DeploymentRoot).Path.TrimEnd('\') } else { $ProjectRoot }
if ($Staged -and ($DeploymentRoot -ne $ProjectRoot -or $RecordPath)) {
    throw '-Staged uses the indexed project deployment and canonical consensus record.'
}

. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
$relativeRecord = 'config/build/runtime-release-consensus.json'
if ($Staged) {
    $recordBytes = Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath $relativeRecord
    $record = [Text.Encoding]::UTF8.GetString($recordBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $mode = 'Index'
} else {
    if (-not $RecordPath) { $RecordPath = Join-Path $ProjectRoot ($relativeRecord -replace '/', '\') }
    elseif (-not [IO.Path]::IsPathRooted($RecordPath)) { $RecordPath = Join-Path $ProjectRoot $RecordPath }
    $RecordPath = (Resolve-Path -LiteralPath $RecordPath).Path
    $record = Get-Content -LiteralPath $RecordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $mode = 'Worktree'
}

function Assert-Cf7ConsensusHash {
    param([string]$Name, [string]$Value)
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid release consensus field: $Name" }
}

function Get-Cf7LegacyManifestIdentity {
    $manifestBytes = if ($Staged) {
        Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'runtime/cf7-runtime-manifest.tsv'
    } else {
        [IO.File]::ReadAllBytes((Join-Path $DeploymentRoot 'runtime\cf7-runtime-manifest.tsv'))
    }
    $text = [Text.Encoding]::UTF8.GetString($manifestBytes).TrimStart([char]0xFEFF)
    $lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' })
    if ($lines.Count -lt 1 -or [string]$lines[0] -ne 'cf7-runtime-manifest-v1') {
        throw 'Legacy consensus integrity requires a v1 runtime manifest.'
    }
    $metadata = @{}
    foreach ($line in $lines | Select-Object -Skip 1) {
        $parts = @([string]$line -split "`t")
        if ($parts.Count -eq 2 -and $parts[0] -in @('sourceTreeHash','toolchainLockHash')) {
            if ($metadata.ContainsKey($parts[0])) { throw "Duplicate legacy manifest metadata: $($parts[0])" }
            $metadata[$parts[0]] = [string]$parts[1]
        }
    }
    foreach ($field in @('sourceTreeHash','toolchainLockHash')) {
        if (-not $metadata.ContainsKey($field) -or [string]$metadata[$field] -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "Legacy manifest lacks valid identity metadata: $field"
        }
    }
    return $metadata
}

function Test-Cf7LegacyConsensus {
    if ([string]$record.schema -ne 'cf7-runtime-release-consensus.v1') { return $false }
    $builders = @($record.builders)
    if ($builders.Count -lt 2) { throw 'Runtime release consensus v1 requires at least two builders.' }
    $builderSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($builder in $builders) {
        if ([string]$builder -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw "Invalid consensus builderId: $builder" }
        if (-not $builderSet.Add([string]$builder)) { throw "Duplicate consensus builderId: $builder" }
    }
    foreach ($field in @('sourceTreeHash','toolchainLockHash','buildRecipeHash','artifactClosureHash')) {
        Assert-Cf7ConsensusHash -Name $field -Value ([string]$record.$field)
    }

    $actualClosure = Get-Cf7RuntimeArtifactClosure -DeploymentRoot $DeploymentRoot -ProjectRoot $ProjectRoot -Mode $mode
    $errors = @()
    if ($IntegrityOnly) {
        $manifestIdentity = Get-Cf7LegacyManifestIdentity
        $manifestSource = [string]$manifestIdentity['sourceTreeHash']
        $manifestToolchain = [string]$manifestIdentity['toolchainLockHash']
        if ([string]$record.sourceTreeHash -ne $manifestSource) { $errors += "consensus sourceTreeHash does not match the v1 manifest: record=$($record.sourceTreeHash) manifest=$manifestSource" }
        if ([string]$record.toolchainLockHash -ne $manifestToolchain) { $errors += "consensus toolchainLockHash does not match the v1 manifest: record=$($record.toolchainLockHash) manifest=$manifestToolchain" }
    } else {
        $actualSource = Get-Cf7RuntimeSourceTreeHash -ProjectRoot $ProjectRoot -Mode $mode
        $actualToolchain = Get-Cf7ToolchainLockHash -ProjectRoot $ProjectRoot -Mode $mode
        $actualRecipe = Get-Cf7RuntimeBuildRecipeHash -ProjectRoot $ProjectRoot -Mode $mode
        if ([string]$record.sourceTreeHash -ne $actualSource) { $errors += "sourceTreeHash expected=$($record.sourceTreeHash) actual=$actualSource" }
        if ([string]$record.toolchainLockHash -ne $actualToolchain) { $errors += "toolchainLockHash expected=$($record.toolchainLockHash) actual=$actualToolchain" }
        if ([string]$record.buildRecipeHash -ne $actualRecipe) { $errors += "buildRecipeHash expected=$($record.buildRecipeHash) actual=$actualRecipe" }
    }
    if ([string]$record.artifactClosureHash -ne $actualClosure.artifactClosureHash) { $errors += "artifactClosureHash expected=$($record.artifactClosureHash) actual=$($actualClosure.artifactClosureHash)" }
    if ($errors.Count -gt 0) {
        foreach ($message in $errors) { Write-Host "[RuntimeConsensus] MISMATCH $message" -ForegroundColor Red }
        exit 2
    }
    Write-Host "[RuntimeConsensus] OK schema=v1 state=$(if ($IntegrityOnly) {'integrity-only'} else {'coherent'}) mode=$mode builders=$($builders -join ',') closure=$($actualClosure.artifactClosureHash)" -ForegroundColor Green
    return $true
}

if (Test-Cf7LegacyConsensus) { exit 0 }
if ($IntegrityOnly) { throw '-IntegrityOnly is limited to the one-time legacy v1 migration bootstrap.' }
if ([string]$record.schema -ne 'cf7-runtime-release-consensus.v2') {
    throw 'Unsupported runtime release consensus schema.'
}

. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

$allowedFields = @(
    'schema','requestId','releaseTreeOid','artifactSourceHash','producerRecipeHash',
    'toolchainLockHash','policyHash','buildIdentityHash','payloadClosureHash',
    'manifestSha256','policyReceiptSha256','policyReceiptBase64','attestations','promotedAtUtc'
)
foreach ($property in $record.PSObject.Properties.Name) {
    if ($allowedFields -notcontains $property) { throw "Unexpected v2 release consensus field: $property" }
}
foreach ($field in @(
    'requestId','artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash',
    'buildIdentityHash','payloadClosureHash','manifestSha256','policyReceiptSha256'
)) {
    Assert-Cf7ConsensusHash -Name $field -Value ([string]$record.$field)
}
if ([string]$record.releaseTreeOid -notmatch '^[0-9A-Fa-f]{40,64}$') { throw 'Invalid v2 releaseTreeOid.' }
$promotedAt = [DateTime]::MinValue
if (-not [DateTime]::TryParse([string]$record.promotedAtUtc, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind, [ref]$promotedAt)) {
    throw 'Invalid v2 promotedAtUtc.'
}
$expectedRequestId = Get-Cf7RuntimeRequestId `
    -ReleaseTreeOid ([string]$record.releaseTreeOid) `
    -PolicyHash ([string]$record.policyHash)
if ($expectedRequestId -ne ([string]$record.requestId).ToUpperInvariant()) {
    throw 'Release consensus requestId does not match releaseTreeOid + policyHash.'
}

$bundleVerifier = Join-Path $ProjectRoot 'tools\verify-runtime-bundle-v2.ps1'
if ($Staged) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bundleVerifier -ProjectRoot $ProjectRoot -Staged
} else {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bundleVerifier `
        -ProjectRoot $ProjectRoot -DeploymentRoot $DeploymentRoot
}
if ($LASTEXITCODE -ne 0) { throw 'Release consensus deployment failed runtime bundle v2 verification.' }

$temporaryRegistry = $null
try {
    $registryPath = Join-Path $ProjectRoot 'config\build\runtime-builders.v2.json'
    if ($Staged) {
        $temporaryBase = Join-Path $ProjectRoot 'tmp\runtime-consensus-verify'
        New-Item -ItemType Directory -Path $temporaryBase -Force | Out-Null
        $temporaryRegistry = Join-Path $temporaryBase ([Guid]::NewGuid().ToString('N') + '.json')
        [IO.File]::WriteAllBytes(
            $temporaryRegistry,
            (Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'config/build/runtime-builders.v2.json'))
        $registryPath = $temporaryRegistry
    }

    $attestations = @($record.attestations)
    $verifiedPayloads = @()
    $proofSignerKeys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($attestation in $attestations) {
        if ([string]$attestation.schema -eq 'cf7-runtime-build-attestation.v2') {
            $verifiedPayload = Test-Cf7RuntimeBuildAttestationV2 `
                -Attestation $attestation `
                -RegistryPath $registryPath
            $verifiedPayloads += $verifiedPayload
            $proofSignerKeys.Add('x509:' + ([string]$verifiedPayload.builderKeyId).ToUpperInvariant())
            continue
        }
        if ([string]$attestation.schema -ne 'cf7-runtime-github-build-attestation.v2') {
            throw "Unsupported producer proof in v2 release consensus: $($attestation.schema)"
        }

        $cloudTemporaryRoot = Join-Path (Join-Path $ProjectRoot 'tmp\runtime-consensus-verify') ([Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $cloudTemporaryRoot -Force | Out-Null
        try {
            $envelopePath = Join-Path $cloudTemporaryRoot 'envelope.json'
            $bundlePath = Join-Path $cloudTemporaryRoot 'bundle.json'
            try {
                [IO.File]::WriteAllBytes($envelopePath, [Convert]::FromBase64String([string]$attestation.envelopeBase64))
                [IO.File]::WriteAllBytes($bundlePath, [Convert]::FromBase64String([string]$attestation.bundleBase64))
            } catch { throw 'Release consensus contains invalid embedded GitHub proof bytes.' }
            $verifiedWrapper = & (Join-Path $ProjectRoot 'tools\verify-runtime-github-attestation.ps1') `
                -ProjectRoot $ProjectRoot `
                -CandidateRoot $DeploymentRoot `
                -EnvelopePath $envelopePath `
                -BundlePath $bundlePath `
                -ExpectedSourceCommitOid ([string]$attestation.payload.sourceCommitOid) `
                -SourceMode $mode `
                -ReplayFromReleaseRecord
            if ($null -eq $verifiedWrapper) { throw 'GitHub producer proof replay returned no normalized proof.' }
            Assert-Cf7RuntimeGitHubProofEquivalentV2 -Expected $attestation -Actual $verifiedWrapper | Out-Null
            if ([string]$verifiedWrapper.payload.releaseTreeOid -ne ([string]$record.releaseTreeOid).ToLowerInvariant()) {
                throw 'GitHub producer proof releaseTreeOid does not match the release consensus.'
            }
            $verifiedPayloads += $verifiedWrapper.payload
            $proofSignerKeys.Add('github-oidc:' + ([string]$verifiedWrapper.payload.builderIdentityHash).ToUpperInvariant())
        } finally {
            if (Test-Path -LiteralPath $cloudTemporaryRoot) {
                Remove-Item -LiteralPath $cloudTemporaryRoot -Recurse -Force
            }
        }
    }
    for ($index = 1; $index -lt $proofSignerKeys.Count; $index++) {
        if ([StringComparer]::Ordinal.Compare($proofSignerKeys[$index - 1],$proofSignerKeys[$index]) -ge 0) {
            throw 'Release consensus producer proofs are not in canonical signer order or contain a duplicate signer.'
        }
    }
    $consensus = Test-Cf7RuntimeVerifiedPayloadConsensusV2 -Payloads $verifiedPayloads -MinimumConsensus 2

    try { $receiptBytes = [Convert]::FromBase64String([string]$record.policyReceiptBase64) }
    catch { throw 'policyReceiptBase64 is not valid Base64.' }
    if ([Convert]::ToBase64String($receiptBytes) -cne [string]$record.policyReceiptBase64) {
        throw 'policyReceiptBase64 is not in canonical form.'
    }
    if ((Get-Cf7BytesSha256 -Bytes $receiptBytes) -ne ([string]$record.policyReceiptSha256).ToUpperInvariant()) {
        throw 'Embedded policy receipt SHA-256 mismatch.'
    }
    $receipt = [Text.Encoding]::UTF8.GetString($receiptBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ([string]$receipt.schema -ne 'cf7-runtime-policy-validation.v2' -or
            [string]$receipt.profile -ne 'production' -or $receipt.passed -ne $true) {
        throw 'Release consensus requires a passed production v2 policy receipt.'
    }
    if ([string]$receipt.releaseTreeOid -ne ([string]$record.releaseTreeOid).ToLowerInvariant()) {
        throw 'Policy receipt releaseTreeOid does not match consensus.'
    }
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        if (([string]$receipt.$field).ToUpperInvariant() -ne ([string]$record.$field).ToUpperInvariant()) {
            throw "Policy receipt does not match release consensus: $field"
        }
    }
    if (([string]$receipt.toolchainHash).ToUpperInvariant() -ne ([string]$record.toolchainLockHash).ToUpperInvariant()) {
        throw 'Policy receipt toolchainHash does not match release consensus toolchainLockHash.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$receipt.candidateRoot)) {
        throw 'Policy receipt is not bound to a runtime candidate.'
    }
    if ([string]$receipt.candidatePayloadClosureHash -notmatch '^[0-9A-Fa-f]{64}$' -or
            ([string]$receipt.candidatePayloadClosureHash).ToUpperInvariant() -ne ([string]$record.payloadClosureHash).ToUpperInvariant()) {
        throw 'Policy receipt candidatePayloadClosureHash does not match release consensus payloadClosureHash.'
    }
    foreach ($requiredCheck in @('release-tree-materialized','tracked-tree-readonly','candidate-payload-readonly')) {
        $matches = @($receipt.checks | Where-Object { [string]$_.name -eq $requiredCheck -and $_.passed -eq $true })
        if ($matches.Count -ne 1) { throw "Policy receipt lacks passed invariant: $requiredCheck" }
    }

    $identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode $mode
    $closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $DeploymentRoot -Mode $mode
    $manifestBytes = if ($Staged) {
        Get-Cf7GitBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'runtime/cf7-runtime-manifest.tsv'
    } else {
        [IO.File]::ReadAllBytes((Join-Path $DeploymentRoot 'runtime\cf7-runtime-manifest.tsv'))
    }
    $actualManifestHash = Get-Cf7BytesSha256 -Bytes $manifestBytes

    $errors = @()
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
        if (([string]$record.$field).ToUpperInvariant() -ne ([string]$identity.$field).ToUpperInvariant()) {
            $errors += "$field expected=$($record.$field) actual=$($identity.$field)"
        }
        if (([string]$record.$field).ToUpperInvariant() -ne ([string]$consensus.$field).ToUpperInvariant()) {
            $errors += "attestation $field expected=$($record.$field) actual=$($consensus.$field)"
        }
    }
    if (([string]$record.policyHash).ToUpperInvariant() -ne ([string]$identity.policyHash).ToUpperInvariant()) {
        $errors += "policyHash expected=$($record.policyHash) actual=$($identity.policyHash)"
    }
    if (([string]$record.payloadClosureHash).ToUpperInvariant() -ne ([string]$closure.payloadClosureHash).ToUpperInvariant()) {
        $errors += "payloadClosureHash expected=$($record.payloadClosureHash) actual=$($closure.payloadClosureHash)"
    }
    if (([string]$record.payloadClosureHash).ToUpperInvariant() -ne ([string]$consensus.payloadClosureHash).ToUpperInvariant()) {
        $errors += "attestation payloadClosureHash expected=$($record.payloadClosureHash) actual=$($consensus.payloadClosureHash)"
    }
    if (([string]$record.manifestSha256).ToUpperInvariant() -ne $actualManifestHash) {
        $errors += "manifestSha256 expected=$($record.manifestSha256) actual=$actualManifestHash"
    }
    if ($errors.Count -gt 0) {
        foreach ($message in $errors) { Write-Host "[RuntimeConsensus] MISMATCH $message" -ForegroundColor Red }
        exit 2
    }

    Write-Host "[RuntimeConsensus] OK schema=v2 mode=$mode signers=$($consensus.signerIdentities.Count) faultDomains=$($consensus.faultDomains.Count) payload=$($closure.payloadClosureHash)" -ForegroundColor Green
} finally {
    if ($temporaryRegistry -and (Test-Path -LiteralPath $temporaryRegistry)) {
        Remove-Item -LiteralPath $temporaryRegistry -Force
    }
}
