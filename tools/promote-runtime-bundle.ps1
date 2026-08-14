[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string]$QueueRoot,
    [Parameter(Mandatory=$true)][string]$RequestId,
    [Parameter(Mandatory=$true)][string]$PolicyReceiptPath,
    [string]$CandidateRoot,
    [string[]]$ExternalAttestationPath = @(),
    [switch]$VerifyOnly,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
if ($VerifyOnly -and [string]::IsNullOrWhiteSpace($ReportPath)) {
    throw 'VerifyOnly requires ReportPath.'
}
if (-not $VerifyOnly -and -not [string]::IsNullOrWhiteSpace($ReportPath)) {
    throw 'ReportPath is valid only with VerifyOnly.'
}
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

function Get-Cf7PromotionNormalizedPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $volumeRoot.Length) { return $fullPath.TrimEnd('\') }
    return $fullPath
}

function Test-Cf7PromotionPathWithin {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Root
    )
    $fullPath = Get-Cf7PromotionNormalizedPath -Path $Path
    $fullRoot = Get-Cf7PromotionNormalizedPath -Path $Root
    return $fullPath.Equals($fullRoot,[StringComparison]::OrdinalIgnoreCase) -or
        $fullPath.StartsWith($fullRoot + '\',[StringComparison]::OrdinalIgnoreCase)
}

function Resolve-Cf7PromotionPreflightReportPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string[]]$ProtectedRoots,
        [Parameter(Mandatory=$true)][string[]]$ProtectedPaths
    )
    if (-not [IO.Path]::IsPathRooted($Path)) {
        throw 'Promotion preflight ReportPath must be absolute.'
    }
    try { $fullPath = [IO.Path]::GetFullPath($Path) }
    catch { throw 'Promotion preflight ReportPath is invalid.' }
    $fileName = [IO.Path]::GetFileName($fullPath)
    if ([string]::IsNullOrWhiteSpace($fileName) -or $fileName.Contains(':')) {
        throw 'Promotion preflight ReportPath must name a regular file.'
    }
    $parent = [IO.Path]::GetDirectoryName($fullPath)
    if ([string]::IsNullOrWhiteSpace($parent) -or
            -not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw 'Promotion preflight ReportPath parent directory must already exist.'
    }
    $resolvedParent = Get-Cf7PromotionNormalizedPath -Path (Resolve-Path -LiteralPath $parent).Path
    $fullPath = Join-Path $resolvedParent $fileName
    $projectPath = Get-Cf7PromotionNormalizedPath -Path $ProjectRoot
    $projectLongPath = Get-Cf7PromotionNormalizedPath -Path (Get-Item -LiteralPath $projectPath -Force).FullName
    if (-not $projectPath.Equals($projectLongPath,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Promotion preflight ProjectRoot cannot use a short-path alias.'
    }
    if (-not (Test-Cf7PromotionPathWithin -Path $fullPath -Root $projectPath)) {
        throw 'Promotion preflight ReportPath must be inside ProjectRoot.'
    }
    $ancestor = $resolvedParent
    while ($true) {
        if (-not (Test-Cf7PromotionPathWithin -Path $ancestor -Root $projectPath)) {
            throw 'Promotion preflight ReportPath parent escaped ProjectRoot.'
        }
        $ancestorItem = Get-Item -LiteralPath $ancestor -Force
        $ancestorLongPath = Get-Cf7PromotionNormalizedPath -Path $ancestorItem.FullName
        if (-not $ancestor.Equals($ancestorLongPath,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Promotion preflight ReportPath ancestors cannot use short-path aliases.'
        }
        if (($ancestorItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Promotion preflight ReportPath ancestors cannot contain reparse points.'
        }
        if ($ancestor.Equals($projectPath,[StringComparison]::OrdinalIgnoreCase)) { break }
        $nextAncestor = [IO.Path]::GetDirectoryName($ancestor)
        if ([string]::IsNullOrWhiteSpace($nextAncestor) -or $nextAncestor -eq $ancestor) {
            throw 'Promotion preflight ReportPath parent cannot be anchored to ProjectRoot.'
        }
        $ancestor = Get-Cf7PromotionNormalizedPath -Path $nextAncestor
    }
    if (Test-Path -LiteralPath $fullPath) {
        throw 'Promotion preflight ReportPath already exists; CreateNew is required.'
    }
    foreach ($root in $ProtectedRoots) {
        if (-not [string]::IsNullOrWhiteSpace($root) -and
                (Test-Cf7PromotionPathWithin -Path $fullPath -Root $root)) {
            throw 'Promotion preflight ReportPath targets a protected runtime root.'
        }
    }
    foreach ($pathValue in $ProtectedPaths) {
        if (-not [string]::IsNullOrWhiteSpace($pathValue) -and
                $fullPath.Equals([IO.Path]::GetFullPath($pathValue),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Promotion preflight ReportPath targets a protected runtime input.'
        }
    }
    return $fullPath
}

function Write-Cf7PromotionPreflightReport {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][object]$Value,
        [string[]]$ForbiddenText = @()
    )
    $json = $Value | ConvertTo-Json -Depth 30
    $text = $json.Replace("`r`n","`n").Replace("`r","`n").TrimEnd([char]10,[char]13) + "`n"
    foreach ($forbidden in $ForbiddenText) {
        if ([string]::IsNullOrWhiteSpace($forbidden)) { continue }
        foreach ($form in @($forbidden,$forbidden.Replace('\','/'))) {
            if ($text.IndexOf($form,[StringComparison]::OrdinalIgnoreCase) -ge 0) {
                throw 'Promotion preflight report would disclose a local path or machine identity.'
            }
        }
    }
    if ($text -match '(?i)"[^"]*(AtUtc|timestamp)[^"]*"\s*:' -or
            $text -match '\d{4}-\d{2}-\d{2}T\d{2}:' -or
            $text -match '(?i)[A-Z]:\\\\') {
        throw 'Promotion preflight report would disclose a timestamp or absolute path.'
    }
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($text)
    $created = $false
    try {
        $stream = New-Object IO.FileStream(
            $Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $created = $true
        try {
            $stream.Write($bytes,0,$bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }
        $written = [IO.File]::ReadAllBytes($Path)
        if ($written.Length -ne $bytes.Length -or $written.Length -lt 2 -or
                $written[0] -eq 0xEF -or $written[$written.Length - 1] -ne 0x0A -or
                $written -contains [byte]0x0D) {
            throw 'Promotion preflight report is not canonical UTF-8 without BOM using LF.'
        }
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($written[$index] -ne $bytes[$index]) {
                throw 'Promotion preflight report bytes changed during CreateNew write.'
            }
        }
    } catch {
        if ($created -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            [IO.File]::Delete($Path)
        }
        throw
    }
}

function Assert-Cf7PromotionClosureUnchanged {
    param(
        [Parameter(Mandatory=$true)][object]$Expected,
        [Parameter(Mandatory=$true)][object]$Actual
    )
    if (([string]$Expected.payloadClosureHash).ToUpperInvariant() -ne
            ([string]$Actual.payloadClosureHash).ToUpperInvariant()) {
        throw 'Runtime candidate payload closure changed during promotion verification.'
    }
    $expectedFiles = @($Expected.files)
    $actualFiles = @($Actual.files)
    if ($expectedFiles.Count -ne $actualFiles.Count) {
        throw 'Runtime candidate file inventory changed during promotion verification.'
    }
    for ($index = 0; $index -lt $expectedFiles.Count; $index++) {
        foreach ($field in @('path','size','sha256')) {
            if ([string]$expectedFiles[$index].$field -cne [string]$actualFiles[$index].$field) {
                throw "Runtime candidate file inventory changed during promotion verification: index=$index field=$field"
            }
        }
    }
}

function Assert-Cf7PromotionVerificationWindowStable {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)][string]$RequestId,
        [Parameter(Mandatory=$true)][string]$WorktreeTreeish,
        [Parameter(Mandatory=$true)][object]$ExpectedIdentity,
        [Parameter(Mandatory=$true)][string]$RequestPath,
        [Parameter(Mandatory=$true)][string]$RequestSha256,
        [Parameter(Mandatory=$true)][string]$BundlePath,
        [Parameter(Mandatory=$true)][string]$BundleSha256,
        [Parameter(Mandatory=$true)][string]$RegistryPath,
        [Parameter(Mandatory=$true)][string]$RegistrySha256,
        [Parameter(Mandatory=$true)][string]$ReceiptPath,
        [Parameter(Mandatory=$true)][string]$ReceiptSha256,
        [Parameter(Mandatory=$true)][string]$CandidateRoot,
        [Parameter(Mandatory=$true)][object]$ExpectedCandidateClosure,
        [Parameter(Mandatory=$true)][string]$CandidateManifestPath,
        [Parameter(Mandatory=$true)][string]$CandidateManifestSha256,
        [object]$AudioV2H2RequestLinkSnapshot,
        [object[]]$ProofInputs = @()
    )
    [void](Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $RequestId)
    foreach ($snapshot in @(
        [pscustomobject]@{ label='request'; path=$RequestPath; sha256=$RequestSha256 },
        [pscustomobject]@{ label='request bundle'; path=$BundlePath; sha256=$BundleSha256 },
        [pscustomobject]@{ label='builder registry'; path=$RegistryPath; sha256=$RegistrySha256 },
        [pscustomobject]@{ label='policy receipt'; path=$ReceiptPath; sha256=$ReceiptSha256 }
    ) + @($ProofInputs)) {
        $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath ([string]$snapshot.path)).Hash.ToUpperInvariant()
        if ($currentHash -ne ([string]$snapshot.sha256).ToUpperInvariant()) {
            throw "Promotion verification input changed during validation: $($snapshot.label)"
        }
    }
    $currentIdentity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode Worktree
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        if (([string]$currentIdentity.$field).ToUpperInvariant() -ne
                ([string]$ExpectedIdentity.$field).ToUpperInvariant()) {
            throw "Current worktree changed during promotion verification: $field"
        }
    }
    & git -C $ProjectRoot diff --quiet --no-ext-diff $WorktreeTreeish --
    if ($LASTEXITCODE -eq 1) {
        throw 'Tracked worktree bytes changed during promotion verification.'
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot recheck the frozen promotion worktree treeish during promotion verification.'
    }
    $deploymentChanges = @(& git -C $ProjectRoot status --porcelain -- `
        'CRAZYFLASHER7MercenaryEmpire.exe' 'runtime' 'config/build/runtime-release-consensus.json')
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot recheck the live runtime deployment during promotion verification.'
    }
    if ($deploymentChanges.Count -gt 0) {
        throw "Live runtime deployment changed during promotion verification:`n$($deploymentChanges -join "`n")"
    }
    $currentClosure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
    Assert-Cf7PromotionClosureUnchanged -Expected $ExpectedCandidateClosure -Actual $currentClosure
    $currentManifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $CandidateManifestPath).Hash.ToUpperInvariant()
    if ($currentManifestHash -ne $CandidateManifestSha256.ToUpperInvariant()) {
        throw 'Runtime candidate manifest changed during promotion verification.'
    }
    if ($null -ne $AudioV2H2RequestLinkSnapshot) {
        Assert-Cf7AudioV2H2RequestLinkWindowStable -Required $true `
            -ProjectRoot $ProjectRoot -Snapshot $AudioV2H2RequestLinkSnapshot
    }
}

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

function Test-Cf7AudioV2H2RequestLinkRequired {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$SourceCommitOid
    )
    $manifestPath = 'docs/contracts/audio-v2/h1-decision-manifest.v4.json'
    $rows = @(& git -C $ProjectRoot -c core.quotepath=false ls-tree $SourceCommitOid -- $manifestPath)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the immutable request source for the Audio v2 R4 marker.' }
    if ($rows.Count -eq 0) { return $false }
    if ($rows.Count -ne 1 -or [string]$rows[0] -notmatch '^100644 blob [0-9a-f]{40,64}\tdocs/contracts/audio-v2/h1-decision-manifest\.v4\.json$') {
        throw 'The Audio v2 R4 marker is not one exact regular Git blob.'
    }
    return $true
}

function Get-Cf7AudioV2H2RequestLinkSnapshot {
    param(
        [Parameter(Mandatory=$true)][bool]$Required,
        [Parameter(Mandatory=$true)][string]$ProjectRoot
    )
    if (-not $Required) { return $null }
    $headRows = @(& git -C $ProjectRoot rev-parse --verify 'HEAD^{commit}')
    if ($LASTEXITCODE -ne 0 -or $headRows.Count -ne 1 -or [string]$headRows[0] -notmatch '^[0-9a-f]{40,64}$') {
        throw 'Cannot freeze the Audio v2 E3 HEAD commit.'
    }
    $headCommit = ([string]$headRows[0]).ToLowerInvariant()
    $validatorRows = @(& git -C $ProjectRoot rev-parse --verify "${headCommit}:tools/audio-v2/validate-h2-request-link.js")
    if ($LASTEXITCODE -ne 0 -or $validatorRows.Count -ne 1 -or [string]$validatorRows[0] -notmatch '^[0-9a-f]{40,64}$') {
        throw 'Cannot freeze the Audio v2 E3 validator blob.'
    }
    $validatorBlobOid = ([string]$validatorRows[0]).ToLowerInvariant()
    $validatorType = @(& git -C $ProjectRoot cat-file -t $validatorBlobOid)
    if ($LASTEXITCODE -ne 0 -or $validatorType.Count -ne 1 -or [string]$validatorType[0] -cne 'blob') {
        throw 'The Audio v2 E3 validator trust root is not one Git blob.'
    }
    return [pscustomobject]@{
        headCommit = $headCommit
        validatorBlobOid = $validatorBlobOid
    }
}

function Assert-Cf7AudioV2H2RequestLinkWindowStable {
    param(
        [Parameter(Mandatory=$true)][bool]$Required,
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [object]$Snapshot
    )
    if (-not $Required) { return }
    if ($null -eq $Snapshot) { throw 'Audio v2 R4 promotion lacks its early E3 trust-root snapshot.' }
    $current = Get-Cf7AudioV2H2RequestLinkSnapshot -Required $true -ProjectRoot $ProjectRoot
    if ([string]$current.headCommit -cne [string]$Snapshot.headCommit) {
        throw 'Audio v2 E3 HEAD changed after the early promotion gate.'
    }
    if ([string]$current.validatorBlobOid -cne [string]$Snapshot.validatorBlobOid) {
        throw 'Audio v2 E3 validator blob changed after the early promotion gate.'
    }
    & git -C $ProjectRoot diff --quiet --no-ext-diff HEAD --
    if ($LASTEXITCODE -eq 1) { throw 'Tracked worktree bytes changed after the Audio v2 E3 validation.' }
    if ($LASTEXITCODE -ne 0) { throw 'Cannot recheck the tracked worktree against the frozen Audio v2 E3 commit.' }
}

function Assert-Cf7AudioV2H2RequestLink {
    param(
        [Parameter(Mandatory=$true)][bool]$Required,
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$RequestPath,
        [Parameter(Mandatory=$true)][string]$RequestId,
        [Parameter(Mandatory=$true)][string]$RequestSha256
    )
    if (-not $Required) { return }
    $validatorPath = Join-Path $ProjectRoot 'tools\audio-v2\validate-h2-request-link.js'
    if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
        throw 'Audio v2 R4 promotion requires the H2 request-link validator.'
    }
    $node = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $node) { throw 'Audio v2 R4 promotion requires node.exe for the H2 request-link validator.' }
    & $node.Source $validatorPath --verify-link --request-file $RequestPath `
        --request-id $RequestId.ToUpperInvariant() --request-sha256 $RequestSha256.ToUpperInvariant()
    if ($LASTEXITCODE -ne 0) { throw 'Audio v2 R4 H2 request-link validation failed closed.' }
}

$QueueRoot = Get-Cf7RuntimeQueueRoot -ProjectRoot $ProjectRoot -QueueRoot $QueueRoot
$requestDirectory = Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId $RequestId
$requestPath = Join-Path $requestDirectory 'request.json'
$requestBundlePath = Join-Path $requestDirectory 'source.bundle'
$requestSha256Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $requestPath).Hash.ToUpperInvariant()
$requestBundleSha256Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $requestBundlePath).Hash.ToUpperInvariant()
$request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $RequestId
$requestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $requestPath).Hash.ToUpperInvariant()
$requestBundleSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $requestBundlePath).Hash.ToUpperInvariant()
if ($requestSha256 -ne $requestSha256Before -or $requestBundleSha256 -ne $requestBundleSha256Before) {
    throw 'Runtime build request changed while it was being read.'
}
$registryPath = Join-Path $ProjectRoot 'config\build\runtime-builders.v2.json'
$registrySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $registryPath).Hash.ToUpperInvariant()
$identity = Get-Cf7RuntimeBuildIdentityV2 -ProjectRoot $ProjectRoot -Mode Worktree
foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
    if (([string]$identity.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) {
        throw "Current worktree does not materialize the immutable build request: $field"
    }
}

$audioV2H2RequestLinkRequired = Test-Cf7AudioV2H2RequestLinkRequired `
    -ProjectRoot $ProjectRoot -SourceCommitOid ([string]$request.sourceCommitOid)
$audioV2H2RequestLinkSnapshot = Get-Cf7AudioV2H2RequestLinkSnapshot `
    -Required $audioV2H2RequestLinkRequired -ProjectRoot $ProjectRoot
# audio-v2-h2-link: early
Assert-Cf7AudioV2H2RequestLink -Required $audioV2H2RequestLinkRequired `
    -ProjectRoot $ProjectRoot -RequestPath $requestPath -RequestId ([string]$request.requestId) `
    -RequestSha256 $requestSha256
if ($audioV2H2RequestLinkRequired) {
    Assert-Cf7AudioV2H2RequestLinkWindowStable -Required $true `
        -ProjectRoot $ProjectRoot -Snapshot $audioV2H2RequestLinkSnapshot
    $promotionWorktreeTreeish = [string]$audioV2H2RequestLinkSnapshot.headCommit
} else {
    & git -C $ProjectRoot diff --quiet --no-ext-diff ([string]$request.releaseTreeOid) --
    if ($LASTEXITCODE -eq 1) {
        throw 'Tracked worktree bytes no longer materialize the immutable request tree.'
    }
    if ($LASTEXITCODE -ne 0) { throw 'Cannot compare the worktree with the immutable request tree.' }
    $promotionWorktreeTreeish = [string]$request.releaseTreeOid
}

$PolicyReceiptPath = (Resolve-Path -LiteralPath $PolicyReceiptPath).Path
$receiptBytes = [IO.File]::ReadAllBytes($PolicyReceiptPath)
$policyReceiptSha256 = Get-Cf7BytesSha256 -Bytes $receiptBytes
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
$proofInputSnapshots = New-Object 'System.Collections.Generic.List[object]'
$identityResultsRoot = Join-Path (Join-Path $QueueRoot 'results') ([string]$request.buildIdentityHash).ToUpperInvariant()
if (Test-Path -LiteralPath $identityResultsRoot -PathType Container) {
    foreach ($resultFile in @(Get-ChildItem -LiteralPath $identityResultsRoot -Filter result.json -File -Recurse)) {
        try {
            $resultSha256Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultFile.FullName).Hash.ToUpperInvariant()
            $result = Get-Content -LiteralPath $resultFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $resultSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultFile.FullName).Hash.ToUpperInvariant()
            if ($resultSha256 -ne $resultSha256Before) {
                throw 'Queue producer result changed while it was being read.'
            }
            $payload = Test-Cf7RuntimeBuildAttestationV2 -Attestation $result.attestation -RegistryPath $registryPath
            $matches = $true
            foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
                if (([string]$payload.$field).ToUpperInvariant() -ne ([string]$request.$field).ToUpperInvariant()) { $matches = $false }
            }
            if ($matches) {
                $verifiedEntries += [pscustomobject]@{ proof=$result.attestation; payload=$payload }
                $proofInputSnapshots.Add([pscustomobject]@{
                    label='queue producer result';path=$resultFile.FullName;sha256=$resultSha256
                })
            }
        } catch {
            Write-Warning "Ignoring invalid queue producer result $($resultFile.FullName): $($_.Exception.Message)"
        }
    }
}
foreach ($path in @($ExternalAttestationPath)) {
    $externalPath = (Resolve-Path -LiteralPath $path).Path
    $externalSha256Before = (Get-FileHash -Algorithm SHA256 -LiteralPath $externalPath).Hash.ToUpperInvariant()
    $external = Get-Content -LiteralPath $externalPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $externalSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $externalPath).Hash.ToUpperInvariant()
    if ($externalSha256 -ne $externalSha256Before) {
        throw "External attestation changed while it was being read: $path"
    }
    $proofInputSnapshots.Add([pscustomobject]@{
        label='external producer proof';path=$externalPath;sha256=$externalSha256
    })
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
$resolvedReportPath = $null
if ($VerifyOnly) {
    $runtimeInputConfig = Read-Cf7RuntimeV2Config -ProjectRoot $ProjectRoot -Mode Worktree
    $protectedReportRoots = New-Object 'System.Collections.Generic.List[string]'
    $protectedReportPaths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in @(
        $QueueRoot,
        $CandidateRoot,
        (Join-Path $ProjectRoot '.git'),
        (Join-Path $ProjectRoot 'config\build')
    )) {
        $protectedReportRoots.Add([IO.Path]::GetFullPath($root))
    }
    foreach ($domainName in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        $domain = $runtimeInputConfig.domains.PSObject.Properties[$domainName].Value
        foreach ($fixedFile in @($domain.fixedFiles)) {
            $protectedReportPaths.Add((Join-Path $ProjectRoot (([string]$fixedFile) -replace '/','\')))
        }
        foreach ($tree in @($domain.trees)) {
            $protectedReportRoots.Add((Join-Path $ProjectRoot (([string]$tree.path) -replace '/','\')))
        }
    }
    foreach ($fixedRoot in @($runtimeInputConfig.payload.fixedRoots)) {
        $protectedReportPaths.Add((Join-Path $ProjectRoot (([string]$fixedRoot) -replace '/','\')))
    }
    foreach ($treeRoot in @($runtimeInputConfig.payload.trees)) {
        $protectedReportRoots.Add((Join-Path $ProjectRoot (([string]$treeRoot) -replace '/','\')))
    }
    $protectedReportPaths.Add((Join-Path $ProjectRoot 'config\build\runtime-release-consensus.json'))
    $resolvedReportPath = Resolve-Cf7PromotionPreflightReportPath -Path $ReportPath -ProjectRoot $ProjectRoot `
        -ProtectedRoots $protectedReportRoots.ToArray() `
        -ProtectedPaths $protectedReportPaths.ToArray()
}

$verifyBundle = Join-Path $ProjectRoot 'tools\verify-runtime-bundle-v2.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifyBundle `
    -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
if ($LASTEXITCODE -ne 0) { throw 'Candidate runtime bundle v2 verification failed.' }
$candidateClosure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
$candidatePayloadHash = ([string]$candidateClosure.payloadClosureHash).ToUpperInvariant()
$candidateManifestPath = Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv'
$candidateManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $candidateManifestPath).Hash.ToUpperInvariant()
if ([string]$receipt.candidatePayloadClosureHash -notmatch '^[0-9A-Fa-f]{64}$' -or
        ([string]$receipt.candidatePayloadClosureHash).ToUpperInvariant() -ne $candidatePayloadHash) {
    throw 'Policy receipt candidatePayloadClosureHash does not match the selected candidate bytes.'
}
$verifiedEntries = @($verifiedEntries | Where-Object {
    ([string]$_.payload.payloadClosureHash).ToUpperInvariant() -eq $candidatePayloadHash
})

foreach ($input in $githubWrapperInputs) {
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $temporaryRoot = Join-Path $temporaryBase ('cf7-runtime-github-replay-' + [Guid]::NewGuid().ToString('N'))
    if ((Test-Cf7PromotionPathWithin -Path $temporaryRoot -Root $ProjectRoot) -or
            (Test-Cf7PromotionPathWithin -Path $temporaryRoot -Root $QueueRoot) -or
            (Test-Cf7PromotionPathWithin -Path $temporaryRoot -Root $CandidateRoot)) {
        throw 'GitHub replay scratch must be outside project, queue, and candidate roots.'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
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

if ($VerifyOnly) {
    $verificationWindow = @{
        ProjectRoot = $ProjectRoot
        QueueRoot = $QueueRoot
        RequestId = $RequestId
        WorktreeTreeish = $promotionWorktreeTreeish
        ExpectedIdentity = $identity
        RequestPath = $requestPath
        RequestSha256 = $requestSha256
        BundlePath = $requestBundlePath
        BundleSha256 = $requestBundleSha256
        RegistryPath = $registryPath
        RegistrySha256 = $registrySha256
        ReceiptPath = $PolicyReceiptPath
        ReceiptSha256 = $policyReceiptSha256
        CandidateRoot = $CandidateRoot
        ExpectedCandidateClosure = $candidateClosure
        CandidateManifestPath = $candidateManifestPath
        CandidateManifestSha256 = $candidateManifestSha256
        AudioV2H2RequestLinkSnapshot = $audioV2H2RequestLinkSnapshot
        ProofInputs = $proofInputSnapshots.ToArray()
    }
    Assert-Cf7PromotionVerificationWindowStable @verificationWindow
    $proofSummaries = @(
        foreach ($entry in $verifiedEntries) {
            $proofSchema = [string]$entry.proof.schema
            $proofKind = if ($proofSchema -eq 'cf7-runtime-build-attestation.v2') { 'x509' } else { 'github-oidc' }
            $canonicalPayloadSha256 = if ($proofKind -eq 'x509') {
                [string]$entry.proof.signature.canonicalPayloadSha256
            } else {
                [string]$entry.proof.canonicalPayloadSha256
            }
            [pscustomobject][ordered]@{
                schema = $proofSchema
                kind = $proofKind
                signerIdentity = Get-Cf7PromotionSignerIdentity -Payload $entry.payload
                faultDomain = [string]$entry.payload.faultDomain
                canonicalPayloadSha256 = $canonicalPayloadSha256.ToUpperInvariant()
            }
        }
    )
    $signerIdentities = [string[]]@($proofSummaries | ForEach-Object { [string]$_.signerIdentity })
    $faultDomains = [string[]]@($proofSummaries | ForEach-Object { [string]$_.faultDomain })
    [Array]::Sort($signerIdentities,[StringComparer]::Ordinal)
    [Array]::Sort($faultDomains,[StringComparer]::Ordinal)
    $candidateFiles = @(
        foreach ($file in @($candidateClosure.files)) {
            [pscustomobject][ordered]@{
                path = [string]$file.path
                size = [Int64]$file.size
                sha256 = ([string]$file.sha256).ToUpperInvariant()
            }
        }
    )
    $preflightReport = [pscustomobject][ordered]@{
        schema = 'cf7-runtime-promotion-preflight.v2'
        status = 'preflight-passed'
        scope = 'promotion-preflight'
        runtimeMutationPerformed = $false
        releaseStateMutationPerformed = $false
        reportCreated = $true
        promotionPerformed = $false
        deploymentPerformed = $false
        reusableAsPromotionInput = $false
        request = [pscustomobject][ordered]@{
            requestId = ([string]$request.requestId).ToUpperInvariant()
            sourceCommitOid = ([string]$request.sourceCommitOid).ToLowerInvariant()
            requestCommitOid = ([string]$request.requestCommitOid).ToLowerInvariant()
            releaseTreeOid = ([string]$request.releaseTreeOid).ToLowerInvariant()
            artifactSourceHash = ([string]$identity.artifactSourceHash).ToUpperInvariant()
            producerRecipeHash = ([string]$identity.producerRecipeHash).ToUpperInvariant()
            toolchainLockHash = ([string]$identity.toolchainLockHash).ToUpperInvariant()
            policyHash = ([string]$identity.policyHash).ToUpperInvariant()
            buildIdentityHash = ([string]$identity.buildIdentityHash).ToUpperInvariant()
        }
        candidate = [pscustomobject][ordered]@{
            payloadClosureHash = $candidatePayloadHash
            manifestSha256 = $candidateManifestSha256
            fileCount = $candidateFiles.Count
            files = $candidateFiles
        }
        policy = [pscustomobject][ordered]@{
            receiptSha256 = $policyReceiptSha256
        }
        consensus = [pscustomobject][ordered]@{
            schema = [string]$consensus.schema
            minimumConsensus = 2
            proofCount = $proofSummaries.Count
            signerIdentities = $signerIdentities
            faultDomains = $faultDomains
            proofs = $proofSummaries
        }
        limitations = @(
            'This report is not a promotion input.',
            'No promotion or deployment was performed.',
            'Formal promotion must rerun every validation and execute its transaction checks.'
        )
    }
    $forbiddenReportText = New-Object 'System.Collections.Generic.List[string]'
    foreach ($value in @(
        $ProjectRoot,
        $QueueRoot,
        $CandidateRoot,
        $PolicyReceiptPath,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile),
        $env:USERPROFILE
    ) + @($proofInputSnapshots | ForEach-Object { [string]$_.path })) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            $forbiddenReportText.Add([string]$value)
        }
    }
    foreach ($toolName in @('git.exe','gh.exe','git','gh')) {
        $toolCommand = Get-Command $toolName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $toolCommand -and -not [string]::IsNullOrWhiteSpace([string]$toolCommand.Source)) {
            $forbiddenReportText.Add([string]$toolCommand.Source)
        }
    }
    # audio-v2-h2-link: verify-only-final
    Assert-Cf7AudioV2H2RequestLink -Required $audioV2H2RequestLinkRequired `
        -ProjectRoot $ProjectRoot -RequestPath $requestPath -RequestId ([string]$request.requestId) `
        -RequestSha256 $requestSha256
    Assert-Cf7AudioV2H2RequestLinkWindowStable -Required $audioV2H2RequestLinkRequired `
        -ProjectRoot $ProjectRoot -Snapshot $audioV2H2RequestLinkSnapshot
    Write-Cf7PromotionPreflightReport -Path $resolvedReportPath -Value $preflightReport `
        -ForbiddenText $forbiddenReportText.ToArray()
    try {
        Assert-Cf7PromotionVerificationWindowStable @verificationWindow
    } catch {
        if (Test-Path -LiteralPath $resolvedReportPath -PathType Leaf) {
            [IO.File]::Delete($resolvedReportPath)
        }
        throw
    }
    Write-Host "[RuntimePromotionPreflight] OK request=$($request.requestId) signers=$($proofSummaries.Count) payload=$candidatePayloadHash" -ForegroundColor Green
    return
}

# audio-v2-h2-link: promotion-final
Assert-Cf7AudioV2H2RequestLink -Required $audioV2H2RequestLinkRequired `
    -ProjectRoot $ProjectRoot -RequestPath $requestPath -RequestId ([string]$request.requestId) `
    -RequestSha256 $requestSha256
Assert-Cf7AudioV2H2RequestLinkWindowStable -Required $audioV2H2RequestLinkRequired `
    -ProjectRoot $ProjectRoot -Snapshot $audioV2H2RequestLinkSnapshot
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
    policyReceiptSha256 = $policyReceiptSha256
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
