param(
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][ValidatePattern('^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$')][string]$SourceCommitOid,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$ProjectRoot,
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
if (-not $ConfigPath) { $ConfigPath = Join-Path $ProjectRoot 'config\build\runtime-github-builder.v2.json' }
if (-not [IO.Path]::IsPathRooted($ConfigPath)) { $ConfigPath = Join-Path $ProjectRoot $ConfigPath }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')

function Read-Cf7GitHubBuilderConfig {
    $config = [IO.File]::ReadAllText($ConfigPath, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
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
    $path = Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Candidate manifest is missing: $path" }
    $lines = @([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) -split "`r?`n" | Where-Object { $_ -ne '' })
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
    if ($left.Count -ne $right.Count) { throw "Candidate file inventory count mismatch: manifest=$($left.Count) actual=$($right.Count)" }
    for ($i=0; $i -lt $left.Count; $i++) {
        foreach ($field in @('path','size','sha256')) {
            if ([string]$left[$i].$field -cne [string]$right[$i].$field) { throw "Candidate file inventory mismatch: $field row=$i" }
        }
    }
}

function ConvertTo-Cf7GitHubEnvelopeJsonString {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return 'null' }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int][char]$character
        switch ($code) {
            8  { [void]$builder.Append('\b'); continue }
            9  { [void]$builder.Append('\t'); continue }
            10 { [void]$builder.Append('\n'); continue }
            12 { [void]$builder.Append('\f'); continue }
            13 { [void]$builder.Append('\r'); continue }
            34 { [void]$builder.Append('\"'); continue }
            92 { [void]$builder.Append('\\'); continue }
        }
        if ($code -lt 0x20) { [void]$builder.Append(('\u{0:x4}' -f $code)) }
        else { [void]$builder.Append($character) }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-Cf7GitHubEnvelopeText {
    param([Parameter(Mandatory=$true)][object]$Envelope)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $parts.Add('{"schema":"cf7-runtime-github-build-envelope.v2"')
    foreach ($field in @('repository','signerWorkflow','sourceRef','faultDomain','runnerClass','sourceCommitOid','releaseTreeOid','artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash','payloadClosureHash')) {
        $parts.Add(',"' + $field + '":' + (ConvertTo-Cf7GitHubEnvelopeJsonString ([string]$Envelope.$field)))
    }
    $parts.Add(',"files":[')
    $files = @($Envelope.files)
    [Array]::Sort($files, [Comparison[object]]{ param($a,$b) [StringComparer]::Ordinal.Compare([string]$a.path,[string]$b.path) })
    for ($i=0; $i -lt $files.Count; $i++) {
        if ($i -gt 0) { $parts.Add(',') }
        $row = $files[$i]
        $parts.Add('{"path":' + (ConvertTo-Cf7GitHubEnvelopeJsonString ([string]$row.path)) +
            ',"size":' + ([Int64]$row.size).ToString([Globalization.CultureInfo]::InvariantCulture) +
            ',"sha256":' + (ConvertTo-Cf7GitHubEnvelopeJsonString ([string]$row.sha256).ToUpperInvariant()) + '}')
    }
    $parts.Add(']}')
    return [string]::Join('', $parts.ToArray())
}

$config = Read-Cf7GitHubBuilderConfig
$normalizedCommit = $SourceCommitOid.ToLowerInvariant()
$headCommit = (Invoke-Cf7GitText -Arguments @('rev-parse','HEAD^{commit}')).ToLowerInvariant()
if ($headCommit -ne $normalizedCommit) { throw "Checked-out HEAD does not match sourceCommitOid: expected=$normalizedCommit actual=$headCommit" }
& git -C $ProjectRoot diff --quiet --exit-code
if ($LASTEXITCODE -ne 0) { throw 'Tracked worktree changes are forbidden while creating a cloud build envelope.' }
& git -C $ProjectRoot diff --cached --quiet --exit-code
if ($LASTEXITCODE -ne 0) { throw 'Staged changes are forbidden while creating a cloud build envelope.' }
$releaseTreeOid = (Invoke-Cf7GitText -Arguments @('rev-parse',"$normalizedCommit^{tree}")).ToLowerInvariant()

$identity = Get-Cf7RuntimeV2Identity -ProjectRoot $ProjectRoot -Mode Worktree
$closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot -Mode Worktree
$manifest = Read-Cf7CandidateManifestV2
$expectedBuildIdentity = Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $manifest.metadata.artifactSourceHash -ProducerRecipeHash $manifest.metadata.producerRecipeHash -ToolchainLockHash $manifest.metadata.toolchainLockHash
if ($expectedBuildIdentity -ne $manifest.metadata.buildIdentityHash) { throw 'Candidate manifest build identity is internally inconsistent.' }
foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
    if ([string]$manifest.metadata[$field] -cne [string]$identity.$field) { throw "Candidate identity does not match checked-out source: $field" }
}
if ([string]$manifest.metadata.payloadClosureHash -cne [string]$closure.payloadClosureHash) { throw 'Candidate manifest payload closure does not match candidate bytes.' }
Assert-Cf7FileInventoriesEqual -Expected $manifest.files -Actual $closure.files

$envelope = [pscustomobject][ordered]@{
    schema = 'cf7-runtime-github-build-envelope.v2'
    repository = [string]$config.repository
    signerWorkflow = [string]$config.signerWorkflow
    sourceRef = [string]$config.sourceRef
    faultDomain = [string]$config.faultDomain
    runnerClass = [string]$config.runnerClass
    sourceCommitOid = $normalizedCommit
    releaseTreeOid = $releaseTreeOid
    artifactSourceHash = ([string]$identity.artifactSourceHash).ToUpperInvariant()
    producerRecipeHash = ([string]$identity.producerRecipeHash).ToUpperInvariant()
    toolchainLockHash = ([string]$identity.toolchainLockHash).ToUpperInvariant()
    buildIdentityHash = ([string]$identity.buildIdentityHash).ToUpperInvariant()
    payloadClosureHash = ([string]$closure.payloadClosureHash).ToUpperInvariant()
    files = @($closure.files)
}
$text = ConvertTo-Cf7GitHubEnvelopeText -Envelope $envelope
$outputCandidate = if ([IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $ProjectRoot $OutputPath }
$fullOutput = [IO.Path]::GetFullPath($outputCandidate)
$parent = Split-Path -Parent $fullOutput
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($fullOutput, $text + "`n", $utf8NoBom)
Write-Host "[RuntimeGitHubEnvelope] OK source=$normalizedCommit payload=$($envelope.payloadClosureHash) path=$fullOutput" -ForegroundColor Green
return $envelope
