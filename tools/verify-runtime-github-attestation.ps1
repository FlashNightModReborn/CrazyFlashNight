param(
    [Parameter(Mandatory=$true)][string]$EnvelopePath,
    [Parameter(Mandatory=$true)][string]$BundlePath,
    [string]$CandidateRoot,
    [string]$ProjectRoot,
    [string]$ConfigPath,
    [string]$GitHubCliPath = 'gh',
    [ValidatePattern('^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$')][string]$ExpectedSourceCommitOid,
    [ValidateSet('Worktree','Index')][string]$SourceMode = 'Worktree',
    [switch]$ReplayFromReleaseRecord,
    [switch]$WithoutCandidateArchive,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
if ($WithoutCandidateArchive) {
    if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) { throw '-WithoutCandidateArchive forbids CandidateRoot.' }
    if ($SourceMode -eq 'Index') { throw '-WithoutCandidateArchive cannot bind Index-mode candidate bytes.' }
    if ($ReplayFromReleaseRecord) { throw '-WithoutCandidateArchive is not a release-record replay mode; promotion replays against real candidate bytes.' }
} else {
    if ([string]::IsNullOrWhiteSpace($CandidateRoot)) { throw 'CandidateRoot is required unless -WithoutCandidateArchive is selected.' }
    $CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
}
$EnvelopePath = (Resolve-Path -LiteralPath $EnvelopePath).Path
$BundlePath = (Resolve-Path -LiteralPath $BundlePath).Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $ProjectRoot 'config\build\runtime-github-builder.v2.json' }
if (-not [IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $ProjectRoot $ConfigPath }
$ConfigPath = if ($SourceMode -eq 'Index') { [IO.Path]::GetFullPath($ConfigPath) } else { (Resolve-Path -LiteralPath $ConfigPath).Path }
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')

function Read-Cf7GitHubBuilderConfig {
    if ($SourceMode -eq 'Index') {
        $relativeConfig = Get-Cf7RuntimeV2RelativePath -ProjectRoot $ProjectRoot -Path $ConfigPath
        $configText = [Text.Encoding]::UTF8.GetString((Get-Cf7RuntimeV2GitIndexBlobBytes -ProjectRoot $ProjectRoot -RelativePath $relativeConfig))
    } else {
        $configText = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8)
    }
    $config = $configText.TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ($null -eq $config -or [string]$config.schema -ne 'cf7-runtime-github-builder.v2') { throw 'Unsupported GitHub runtime builder config schema.' }
    if ($config.enabled -isnot [bool] -or -not [bool]$config.enabled) { throw 'GitHub runtime builder is disabled.' }
    if ([string]$config.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub runtime builder repository.' }
    if ([string]$config.signerWorkflow -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$') { throw 'Invalid GitHub runtime signer workflow.' }
    if ([string]$config.sourceRef -cnotmatch '^refs/tags/runtime-build-v2/[a-z0-9][a-z0-9._-]{1,80}$') {
        throw 'GitHub runtime sourceRef must be one canonical protected runtime-build-v2 tag.'
    }
    foreach ($field in @('faultDomain','runnerClass')) {
        if ([string]$config.$field -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') { throw "Invalid GitHub runtime builder field: $field" }
    }
    if ([string]$config.identityProvider -ne 'github-oidc-sigstore' -or $config.longLivedPrivateKey -isnot [bool] -or [bool]$config.longLivedPrivateKey) {
        throw 'GitHub runtime builder must use keyless GitHub OIDC/Sigstore identity.'
    }
    return $config
}

function Invoke-Cf7GitText {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $result = @(& git -C $ProjectRoot @Arguments)
    if ($LASTEXITCODE -ne 0 -or $result.Count -ne 1) { throw "Git command failed: git $([string]::Join(' ', $Arguments))" }
    return ([string]$result[0]).Trim()
}

function Read-Cf7CandidateManifestV2 {
    if ($SourceMode -eq 'Index') {
        $manifestText = [Text.Encoding]::UTF8.GetString((Get-Cf7RuntimeV2GitIndexBlobBytes -ProjectRoot $ProjectRoot -RelativePath 'runtime/cf7-runtime-manifest.tsv'))
    } else {
        $path = Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv'
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Candidate manifest is missing: $path" }
        $manifestText = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    }
    $lines = @($manifestText -split "`r?`n" | Where-Object { $_ -ne '' })
    if ($lines.Count -lt 9 -or $lines[0] -ne 'cf7-runtime-manifest-v2') { throw 'Candidate manifest is not cf7-runtime-manifest-v2.' }
    $allowed = @('publishMode','artifactSourceHash','producerRecipeHash','toolchainLockHash','toolchainBaseline','buildIdentityHash','payloadClosureHash')
    $metadata = @{}
    $files = New-Object 'System.Collections.Generic.List[object]'
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($line in $lines | Select-Object -Skip 1) {
        $parts = @($line -split "`t")
        if ($parts.Count -eq 4 -and $parts[0] -eq 'file') {
            if (-not $parts[1] -or $parts[1].Contains('\') -or $parts[1] -match '(^|/)\.\.(/|$)' -or -not $paths.Add($parts[1])) { throw "Invalid or duplicate candidate manifest path: $($parts[1])" }
            $size = 0L
            if (-not [Int64]::TryParse($parts[2], [Globalization.NumberStyles]::None, [Globalization.CultureInfo]::InvariantCulture, [ref]$size) -or $size -lt 0) { throw "Invalid candidate manifest size: $line" }
            if ($parts[3] -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid candidate manifest SHA-256: $line" }
            $files.Add([pscustomobject][ordered]@{ path=$parts[1]; size=$size; sha256=$parts[3].ToUpperInvariant() })
            continue
        }
        if ($parts.Count -ne 2 -or $parts[0] -notin $allowed -or $metadata.ContainsKey($parts[0])) { throw "Invalid candidate manifest row: $line" }
        $metadata[$parts[0]] = $parts[1]
    }
    foreach ($field in $allowed) { if (-not $metadata.ContainsKey($field) -or [string]::IsNullOrWhiteSpace([string]$metadata[$field])) { throw "Candidate manifest lacks metadata: $field" } }
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        if ([string]$metadata[$field] -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid candidate manifest hash: $field" }
        $metadata[$field] = ([string]$metadata[$field]).ToUpperInvariant()
    }
    if ([string]$metadata.publishMode -ne 'framework-dependent') { throw 'Candidate manifest has an unsupported publish mode.' }
    return [pscustomobject]@{ metadata=$metadata; files=$files.ToArray() }
}

function Assert-Cf7FileInventoriesEqual {
    param([Parameter(Mandatory=$true)][object[]]$Expected, [Parameter(Mandatory=$true)][object[]]$Actual)
    $left = @($Expected); $right = @($Actual)
    [Array]::Sort($left, [Comparison[object]]{ param($a,$b) [StringComparer]::Ordinal.Compare([string]$a.path,[string]$b.path) })
    [Array]::Sort($right, [Comparison[object]]{ param($a,$b) [StringComparer]::Ordinal.Compare([string]$a.path,[string]$b.path) })
    if ($left.Count -ne $right.Count) { throw "Runtime file inventory count mismatch: expected=$($left.Count) actual=$($right.Count)" }
    for ($i=0; $i -lt $left.Count; $i++) {
        foreach ($field in @('path','size','sha256')) {
            if ([string]$left[$i].$field -cne [string]$right[$i].$field) { throw "Runtime file inventory mismatch: $field row=$i" }
        }
    }
}

function ConvertTo-Cf7GitHubEnvelopeText {
    param([Parameter(Mandatory=$true)][object]$Envelope)
    if ([string]$Envelope.schema -ne 'cf7-runtime-github-build-envelope.v2') { throw 'Unsupported GitHub runtime envelope schema.' }
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $parts.Add('{"schema":"cf7-runtime-github-build-envelope.v2"')
    foreach ($field in @('repository','signerWorkflow','sourceRef','faultDomain','runnerClass','sourceCommitOid','releaseTreeOid','artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        if ($null -eq $Envelope.PSObject.Properties[$field]) { throw "GitHub runtime envelope lacks field: $field" }
        $parts.Add(',"' + $field + '":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$Envelope.$field)))
    }
    if ($null -eq $Envelope.PSObject.Properties['files']) { throw 'GitHub runtime envelope lacks files.' }
    $parts.Add(',"files":[')
    $files = @($Envelope.files)
    [Array]::Sort($files, [Comparison[object]]{ param($a,$b) [StringComparer]::Ordinal.Compare([string]$a.path,[string]$b.path) })
    for ($i=0; $i -lt $files.Count; $i++) {
        if ($i -gt 0) { $parts.Add(',') }
        $row = $files[$i]
        $parts.Add('{"path":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$row.path)) +
            ',"size":' + ([Int64]$row.size).ToString([Globalization.CultureInfo]::InvariantCulture) +
            ',"sha256":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$row.sha256).ToUpperInvariant()) + '}')
    }
    $parts.Add(']}')
    return [string]::Join('', $parts.ToArray())
}

function ConvertTo-Cf7GitHubNormalizedPayloadText {
    param([Parameter(Mandatory=$true)][object]$Payload)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $parts.Add('{"schema":"cf7-runtime-github-build-attestation-payload.v2"')
    foreach ($field in @('builderKind','builderIdentityHash','faultDomain','repository','signerWorkflow','sourceRef','runnerClass','sourceCommitOid','releaseTreeOid','artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash','envelopeSha256','bundleSha256')) {
        $parts.Add(',"' + $field + '":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$Payload.$field)))
    }
    $parts.Add(',"files":[')
    $files = @($Payload.files)
    [Array]::Sort($files, [Comparison[object]]{ param($a,$b) [StringComparer]::Ordinal.Compare([string]$a.path,[string]$b.path) })
    for ($i=0; $i -lt $files.Count; $i++) {
        if ($i -gt 0) { $parts.Add(',') }
        $row = $files[$i]
        $parts.Add('{"path":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$row.path)) +
            ',"size":' + ([Int64]$row.size).ToString([Globalization.CultureInfo]::InvariantCulture) +
            ',"sha256":' + (ConvertTo-Cf7RuntimeV2JsonString ([string]$row.sha256).ToUpperInvariant()) + '}')
    }
    $parts.Add(']}')
    return [string]::Join('', $parts.ToArray())
}

if ($SourceMode -eq 'Index' -and -not $WithoutCandidateArchive -and $CandidateRoot -ne $ProjectRoot) {
    throw 'Index source mode requires CandidateRoot to equal ProjectRoot.'
}
$config = Read-Cf7GitHubBuilderConfig
$envelopeBytes = [IO.File]::ReadAllBytes($EnvelopePath)
if ($envelopeBytes.Length -ge 3 -and $envelopeBytes[0] -eq 0xEF -and $envelopeBytes[1] -eq 0xBB -and $envelopeBytes[2] -eq 0xBF) { throw 'GitHub runtime envelope must be UTF-8 without BOM.' }
$envelopeRaw = [Text.Encoding]::UTF8.GetString($envelopeBytes)
if ($envelopeRaw.Contains("`r")) { throw 'GitHub runtime envelope must use LF line endings.' }
try { $envelope = $envelopeRaw | ConvertFrom-Json }
catch { throw "GitHub runtime envelope is not valid JSON: $($_.Exception.Message)" }
$canonicalEnvelope = ConvertTo-Cf7GitHubEnvelopeText -Envelope $envelope
if ($envelopeRaw -cne $canonicalEnvelope + "`n") { throw 'GitHub runtime envelope is not in canonical deterministic form.' }

foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
    if ([string]$envelope.$field -cnotmatch '^[0-9A-F]{64}$') { throw "Invalid GitHub runtime envelope hash: $field" }
}
if ([string]$envelope.sourceCommitOid -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or [string]$envelope.releaseTreeOid -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw 'GitHub runtime envelope has an invalid source Git identity.'
}
foreach ($field in @('repository','signerWorkflow','sourceRef','faultDomain','runnerClass')) {
    if ([string]$envelope.$field -cne [string]$config.$field) { throw "GitHub runtime envelope/config mismatch: $field" }
}
$expectedBuildIdentity = Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $envelope.artifactSourceHash -ProducerRecipeHash $envelope.producerRecipeHash -ToolchainLockHash $envelope.toolchainLockHash
if ($expectedBuildIdentity -cne [string]$envelope.buildIdentityHash) { throw 'GitHub runtime envelope build identity is internally inconsistent.' }
$expectedEnvelopeClosure = Get-Cf7RuntimeV2CanonicalClosureHash -Files @($envelope.files)
if ($expectedEnvelopeClosure -cne [string]$envelope.payloadClosureHash) { throw 'GitHub runtime envelope file inventory does not match payload closure.' }

if (-not $ExpectedSourceCommitOid) {
    $ExpectedSourceCommitOid = if ($ReplayFromReleaseRecord) { [string]$envelope.sourceCommitOid } else { Invoke-Cf7GitText -Arguments @('rev-parse','HEAD^{commit}') }
}
$ExpectedSourceCommitOid = $ExpectedSourceCommitOid.ToLowerInvariant()
if ([string]$envelope.sourceCommitOid -cne $ExpectedSourceCommitOid) { throw "GitHub runtime source commit mismatch: expected=$ExpectedSourceCommitOid actual=$($envelope.sourceCommitOid)" }
$headCommit = (Invoke-Cf7GitText -Arguments @('rev-parse','HEAD^{commit}')).ToLowerInvariant()
if ($ReplayFromReleaseRecord) {
    & git -C $ProjectRoot merge-base --is-ancestor $ExpectedSourceCommitOid $headCommit
    if ($LASTEXITCODE -ne 0) { throw "Release replay HEAD is not a descendant of the attested source commit: source=$ExpectedSourceCommitOid head=$headCommit" }
} else {
    if ($headCommit -cne $ExpectedSourceCommitOid) { throw "Verification checkout does not match expected source commit: expected=$ExpectedSourceCommitOid actual=$headCommit" }
    & git -C $ProjectRoot diff --cached --quiet --exit-code
    if ($LASTEXITCODE -ne 0) { throw 'Staged changes are forbidden while verifying a cloud build.' }
    if ($SourceMode -eq 'Worktree') {
        & git -C $ProjectRoot diff --quiet --exit-code
        if ($LASTEXITCODE -ne 0) { throw 'Tracked worktree changes are forbidden while verifying a cloud build.' }
    }
}
$expectedTree = (Invoke-Cf7GitText -Arguments @('rev-parse',"$ExpectedSourceCommitOid^{tree}")).ToLowerInvariant()
if ([string]$envelope.releaseTreeOid -cne $expectedTree) { throw "GitHub runtime release tree mismatch: expected=$expectedTree actual=$($envelope.releaseTreeOid)" }

$identity = Get-Cf7RuntimeV2Identity -ProjectRoot $ProjectRoot -Mode $SourceMode
foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
    if ([string]$envelope.$field -cne [string]$identity.$field) { throw "GitHub runtime envelope/source identity mismatch: $field" }
}
if (-not $WithoutCandidateArchive) {
    $closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot -Mode $SourceMode
    if ([string]$closure.payloadClosureHash -cne [string]$envelope.payloadClosureHash) { throw 'GitHub runtime candidate bytes do not match the attested payload closure.' }
    Assert-Cf7FileInventoriesEqual -Expected @($envelope.files) -Actual @($closure.files)
    $manifest = Read-Cf7CandidateManifestV2
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        if ([string]$manifest.metadata[$field] -cne [string]$envelope.$field) { throw "GitHub runtime candidate manifest/envelope mismatch: $field" }
    }
    Assert-Cf7FileInventoriesEqual -Expected @($envelope.files) -Actual @($manifest.files)
}
# Trust-root boundary for -WithoutCandidateArchive: the Sigstore provenance signs the
# deterministic envelope (with its per-file SHA-256 inventory), and the pinned cloud workflow
# asserts archive bytes == envelope before signing, so a successful run binds the archive to
# this envelope. Local candidate byte equality is deferred to the promotion path, which
# replays this proof against the real candidate root with full per-file hashing. The archive
# byte assertion is intentionally not repeated here; every other check (canonical envelope,
# config/source/tree binding, local source identity, gh attestation verify) is unchanged.

$bundleBytes = [IO.File]::ReadAllBytes($BundlePath)
if ($bundleBytes.Length -eq 0) { throw 'GitHub runtime attestation bundle is empty.' }
try { [void]([Text.Encoding]::UTF8.GetString($bundleBytes) | ConvertFrom-Json) }
catch { throw "GitHub runtime attestation bundle is not valid JSON: $($_.Exception.Message)" }

if ([IO.Path]::IsPathRooted($GitHubCliPath) -or $GitHubCliPath.Contains('\') -or $GitHubCliPath.Contains('/')) {
    if (-not (Test-Path -LiteralPath $GitHubCliPath -PathType Leaf)) { throw "GitHub CLI is missing: $GitHubCliPath" }
    $ghCommand = (Resolve-Path -LiteralPath $GitHubCliPath).Path
} else {
    $resolvedGh = Get-Command $GitHubCliPath -ErrorAction SilentlyContinue
    if (-not $resolvedGh -and $GitHubCliPath -eq 'gh') {
        $fallbacks = @(
            (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe')
        )
        $fallback = $fallbacks | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        if ($fallback) { $resolvedGh = Get-Item -LiteralPath $fallback }
    }
    if (-not $resolvedGh) { throw "GitHub CLI is unavailable: $GitHubCliPath" }
    $ghCommand = if ($resolvedGh.PSObject.Properties['Source']) { $resolvedGh.Source } else { $resolvedGh.FullName }
}
$ghArguments = @(
    'attestation','verify',$EnvelopePath,
    '--repo',[string]$config.repository,
    '--signer-workflow',[string]$config.signerWorkflow,
    '--source-ref',[string]$config.sourceRef,
    '--deny-self-hosted-runners',
    '--bundle',$BundlePath,
    '--predicate-type','https://slsa.dev/provenance/v1',
    '--format','json'
)
$stderrPath = Join-Path ([IO.Path]::GetTempPath()) ('cf7-gh-attestation-' + [Guid]::NewGuid().ToString('N') + '.stderr')
try {
    $ghOutput = @(& $ghCommand @ghArguments 2> $stderrPath)
    $ghExitCode = $LASTEXITCODE
    $ghError = if (Test-Path -LiteralPath $stderrPath) { [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::Default) } else { '' }
} finally {
    if (Test-Path -LiteralPath $stderrPath) { Remove-Item -LiteralPath $stderrPath -Force }
}
if ($ghExitCode -ne 0) { throw "GitHub provenance verification failed (exit=$ghExitCode): $ghError" }
try { $ghVerification = ([string]::Join("`n", [string[]]$ghOutput)) | ConvertFrom-Json }
catch { throw "GitHub provenance verifier returned invalid JSON: $($_.Exception.Message)" }
$verifiedAttestations = @($ghVerification)
if ($verifiedAttestations.Count -lt 1) { throw 'GitHub provenance verifier returned no verified attestations.' }
foreach ($verified in $verifiedAttestations) {
    if ($null -eq $verified.PSObject.Properties['attestation'] -or
            $null -eq $verified.PSObject.Properties['verificationResult'] -or
            $null -eq $verified.verificationResult.PSObject.Properties['signature'] -or
            $null -eq $verified.verificationResult.signature.PSObject.Properties['certificate'] -or
            $null -eq $verified.verificationResult.PSObject.Properties['verifiedTimestamps'] -or
            [string]$verified.verificationResult.statement.predicateType -cne 'https://slsa.dev/provenance/v1') {
        throw 'GitHub provenance verifier returned an unexpected verification result.'
    }
}

$envelopeSha256 = Get-Cf7RuntimeV2BytesSha256 -Bytes $envelopeBytes
$bundleSha256 = Get-Cf7RuntimeV2BytesSha256 -Bytes $bundleBytes
$builderIdentityText = "builderKind`tgithub-oidc`nrepository`t$($config.repository)`nsignerWorkflow`t$($config.signerWorkflow)`nsourceRef`t$($config.sourceRef)`nrunnerClass`t$($config.runnerClass)`nfaultDomain`t$($config.faultDomain)`n"
$builderIdentityHash = Get-Cf7RuntimeV2BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($builderIdentityText))
$payload = [pscustomobject][ordered]@{
    schema = 'cf7-runtime-github-build-attestation-payload.v2'
    builderKind = 'github-oidc'
    builderIdentityHash = $builderIdentityHash
    faultDomain = [string]$config.faultDomain
    repository = [string]$config.repository
    signerWorkflow = [string]$config.signerWorkflow
    sourceRef = [string]$config.sourceRef
    runnerClass = [string]$config.runnerClass
    sourceCommitOid = [string]$envelope.sourceCommitOid
    releaseTreeOid = [string]$envelope.releaseTreeOid
    artifactSourceHash = [string]$envelope.artifactSourceHash
    producerRecipeHash = [string]$envelope.producerRecipeHash
    toolchainLockHash = [string]$envelope.toolchainLockHash
    buildIdentityHash = [string]$envelope.buildIdentityHash
    payloadClosureHash = [string]$envelope.payloadClosureHash
    envelopeSha256 = $envelopeSha256
    bundleSha256 = $bundleSha256
    files = @($envelope.files)
}
$canonicalPayload = ConvertTo-Cf7GitHubNormalizedPayloadText -Payload $payload
$wrapper = [pscustomobject][ordered]@{
    schema = 'cf7-runtime-github-build-attestation.v2'
    payload = $payload
    canonicalPayloadSha256 = Get-Cf7RuntimeV2BytesSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($canonicalPayload))
    envelopeBase64 = [Convert]::ToBase64String($envelopeBytes)
    bundleBase64 = [Convert]::ToBase64String($bundleBytes)
}
if ($OutputPath) {
    $outputCandidate = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $ProjectRoot $OutputPath }
    $fullOutput = [IO.Path]::GetFullPath($outputCandidate)
    $outputParent = Split-Path -Parent $fullOutput
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) { New-Item -ItemType Directory -Path $outputParent -Force | Out-Null }
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($fullOutput, (($wrapper | ConvertTo-Json -Depth 12) + "`n"), $utf8NoBom)
}
Write-Host "[RuntimeGitHubAttestation] OK source=$($payload.sourceCommitOid) payload=$($payload.payloadClosureHash) builder=$builderIdentityHash" -ForegroundColor Green
return $wrapper
