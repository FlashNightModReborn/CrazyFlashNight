[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$')]
    [string]$SourceCommitOid,
    [string]$ProjectRoot,
    [string]$OutputRoot,
    [string]$ConfigPath,
    [string]$GitHubCliPath = 'gh',
    [ValidateRange(1,600)][int]$DiscoveryTimeoutSeconds = 120,
    [ValidateRange(30,86400)][int]$RunTimeoutSeconds = 21600,
    [ValidateRange(1,300)][int]$PollSeconds = 10,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$SourceCommitOid = $SourceCommitOid.ToLowerInvariant()
if (-not $ConfigPath) { $ConfigPath = Join-Path $ProjectRoot 'config\build\runtime-github-builder.v2.json' }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path

function Read-Cf7CloudBuilderConfig {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config -or [string]$config.schema -ne 'cf7-runtime-github-builder.v2') {
        throw 'Unsupported GitHub runtime builder config schema.'
    }
    if ($config.enabled -isnot [bool] -or -not [bool]$config.enabled) { throw 'GitHub runtime builder is disabled.' }
    if ([string]$config.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid GitHub runtime repository.' }
    if ([string]$config.signerWorkflow -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$') {
        throw 'Invalid GitHub runtime signer workflow.'
    }
    if ([string]$config.sourceRef -notmatch '^refs/(?:heads|tags)/[A-Za-z0-9._/-]+$' -or
            [string]$config.sourceRef -match '(?:^|/)\.\.(?:/|$)|//|/$') { throw 'Invalid GitHub runtime source ref.' }
    if ([string]$config.identityProvider -ne 'github-oidc-sigstore' -or
            $config.longLivedPrivateKey -isnot [bool] -or [bool]$config.longLivedPrivateKey) {
        throw 'GitHub runtime builder must use keyless OIDC/Sigstore identity.'
    }
    return $config
}

function Resolve-Cf7GitHubCli {
    if ([IO.Path]::IsPathRooted($GitHubCliPath) -or $GitHubCliPath.Contains('\') -or $GitHubCliPath.Contains('/')) {
        if (-not (Test-Path -LiteralPath $GitHubCliPath -PathType Leaf)) { throw "GitHub CLI is missing: $GitHubCliPath" }
        return (Resolve-Path -LiteralPath $GitHubCliPath).Path
    }
    $command = Get-Command $GitHubCliPath -ErrorAction SilentlyContinue
    if (-not $command -and $GitHubCliPath -eq 'gh') {
        $fallbacks = @(
            (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe')
        )
        $fallback = $fallbacks | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        if ($fallback) { return (Resolve-Path -LiteralPath $fallback).Path }
    }
    if (-not $command) { throw "GitHub CLI is unavailable: $GitHubCliPath" }
    return $command.Source
}

function Invoke-Cf7GitText([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $ProjectRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return ($output -join "`n").Trim()
}

function Invoke-Cf7Gh([string[]]$Arguments, [switch]$AllowEmpty) {
    Write-Host "[RuntimeGitHubBuild] gh $($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' ') ..." -ForegroundColor DarkGray
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $script:GitHubCli @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw "GitHub CLI failed (exit=$exitCode): gh $($Arguments -join ' ')`n$($output -join "`n")"
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) { throw 'GitHub CLI returned empty output.' }
    return $text
}

function Invoke-Cf7GhJson([string[]]$Arguments) {
    $text = Invoke-Cf7Gh -Arguments $Arguments
    try { return $text | ConvertFrom-Json }
    catch { throw "GitHub CLI returned invalid JSON: $($_.Exception.Message)" }
}

function Get-Cf7CloudRuns([string]$Repository, [string]$WorkflowFile) {
    $runs = Invoke-Cf7GhJson -Arguments @(
        'run','list','--repo',$Repository,'--workflow',$WorkflowFile,'--event','workflow_dispatch',
        '--limit','100','--json','databaseId,displayTitle,headBranch,headSha,status,conclusion,createdAt,event,url'
    )
    return @($runs)
}

function Assert-Cf7RunIdentity($Run, [Int64]$ExpectedId, [string]$ExpectedTitle, [string]$ExpectedBranch) {
    if ([Int64]$Run.databaseId -ne $ExpectedId) { throw 'GitHub run databaseId changed while waiting.' }
    if ([string]$Run.displayTitle -cne $ExpectedTitle) { throw 'GitHub run title no longer identifies the requested source commit.' }
    if ([string]$Run.headBranch -cne $ExpectedBranch) { throw 'GitHub runtime run came from an unexpected workflow source branch.' }
    if ([string]$Run.event -ne 'workflow_dispatch') { throw 'GitHub runtime run has an unexpected event kind.' }
}

function Test-Cf7ArtifactFile([string]$Root, [string]$Name, [Int64]$MaximumBytes) {
    $path = Join-Path $Root $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Signed cloud artifact lacks file: $Name" }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Cloud artifact file is a reparse point: $Name" }
    if ($item.Length -le 0 -or $item.Length -gt $MaximumBytes) { throw "Cloud artifact file has an unsafe size: $Name ($($item.Length))" }
    return $item.FullName
}

function Expand-Cf7CandidateArchiveSafely([string]$ArchivePath, [string]$DestinationRoot) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $DestinationRoot) { throw "Candidate extraction destination already exists: $DestinationRoot" }
    New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
    $root = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -lt 2 -or $archive.Entries.Count -gt 512) { throw 'Candidate archive has an unsafe entry count.' }
        [Int64]$totalLength = 0
        foreach ($entry in $archive.Entries) {
            $raw = ([string]$entry.FullName).Replace('\','/')
            if ([string]::IsNullOrWhiteSpace($raw) -or $raw.StartsWith('/') -or $raw.StartsWith('//') -or
                    $raw -match '^[A-Za-z]:' -or $raw.Contains('//') -or $raw.IndexOf([char]0) -ge 0) {
                throw "Unsafe candidate archive path: $raw"
            }
            $isDirectory = $raw.EndsWith('/')
            $normalized = $raw.TrimEnd('/')
            $segments = @($normalized.Split('/'))
            if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw "Unsafe candidate archive path segments: $raw"
            }
            foreach ($segment in $segments) {
                if ($segment -notmatch '^[A-Za-z0-9_.() -]+$') { throw "Unsupported candidate archive path segment: $segment" }
            }
            if ($normalized -ne 'CRAZYFLASHER7MercenaryEmpire.exe' -and
                    $normalized -ne 'runtime-build-metadata.v2.json' -and
                    $normalized -ne 'runtime' -and
                    -not $normalized.StartsWith('runtime/', [StringComparison]::Ordinal)) {
                throw "Candidate archive path is outside the payload allowlist: $normalized"
            }
            if (-not $seen.Add($normalized)) { throw "Duplicate/case-colliding candidate archive path: $normalized" }

            [uint32]$attributes = [uint32]$entry.ExternalAttributes
            $unixType = (($attributes -shr 16) -band 0xF000)
            if ($unixType -eq 0xA000 -or ($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Candidate archive contains a link/reparse entry: $normalized"
            }

            if (-not $isDirectory) {
                if ($entry.Length -lt 0 -or $entry.Length -gt 268435456) { throw "Candidate archive entry is too large: $normalized" }
                $totalLength += [Int64]$entry.Length
                if ($totalLength -gt 536870912) { throw 'Candidate archive expands beyond the 512 MiB safety limit.' }
            }

            $destination = [IO.Path]::GetFullPath((Join-Path $root ($normalized -replace '/','\')))
            if (-not $destination.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Candidate archive path escapes extraction root: $normalized"
            }
            if ($isDirectory) {
                New-Item -ItemType Directory -Path $destination -Force | Out-Null
                continue
            }
            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $input = $entry.Open()
            try {
                $output = New-Object IO.FileStream($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
        }
    } finally { $archive.Dispose() }

    foreach ($required in @('CRAZYFLASHER7MercenaryEmpire.exe','runtime\cf7-runtime-manifest.tsv')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $required) -PathType Leaf)) {
            throw "Extracted candidate lacks required file: $required"
        }
    }
    return $root
}

function Invoke-Cf7ProofVerifier(
    [string]$CandidateRoot,
    [string]$EnvelopePath,
    [string]$BundlePath,
    [string]$ProofPath
) {
    $verifier = Join-Path $ProjectRoot 'tools\verify-runtime-github-attestation.ps1'
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw "GitHub runtime verifier is missing: $verifier" }
    $powerShell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$verifier,
        '-ProjectRoot',$ProjectRoot,'-CandidateRoot',$CandidateRoot,
        '-EnvelopePath',$EnvelopePath,'-BundlePath',$BundlePath,
        '-ExpectedSourceCommitOid',$SourceCommitOid,'-GitHubCliPath',$script:GitHubCli,
        '-OutputPath',$ProofPath
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powerShell @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    foreach ($line in $output) { Write-Host ([string]$line) }
    if ($exitCode -ne 0) { throw "GitHub runtime attestation verification failed with exit code $exitCode." }
    if (-not (Test-Path -LiteralPath $ProofPath -PathType Leaf)) { throw 'GitHub runtime verifier did not write the normalized proof.' }
    $proof = Get-Content -LiteralPath $ProofPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$proof.schema -ne 'cf7-runtime-github-build-attestation.v2' -or
            [string]$proof.payload.sourceCommitOid -cne $SourceCommitOid) {
        throw 'Normalized GitHub runtime proof does not bind the requested source commit.'
    }
    return $proof
}

$config = Read-Cf7CloudBuilderConfig
$script:GitHubCli = Resolve-Cf7GitHubCli
$workflowFile = [IO.Path]::GetFileName([string]$config.signerWorkflow)
$sourceRefName = ([string]$config.sourceRef) -replace '^refs/(?:heads|tags)/', ''
$expectedRunTitle = "Runtime cloud builder $SourceCommitOid"
$artifactName = "runtime-cloud-builder-$SourceCommitOid"

$head = Invoke-Cf7GitText @('rev-parse','HEAD^{commit}')
if ($head.ToLowerInvariant() -cne $SourceCommitOid) {
    throw "Current checkout must equal SourceCommitOid for proof verification: expected=$SourceCommitOid actual=$head"
}
Invoke-Cf7GitText @('diff','--quiet','--exit-code') | Out-Null
Invoke-Cf7GitText @('diff','--cached','--quiet','--exit-code') | Out-Null

if (-not $OutputRoot) { $OutputRoot = Join-Path $ProjectRoot ("tmp\runtime-cloud-results\$SourceCommitOid") }
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot).TrimEnd('\')
if ([IO.Path]::GetPathRoot($OutputRoot) -eq $OutputRoot) { throw 'OutputRoot must be a dedicated directory, not a filesystem root.' }
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) { New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null }
$outputRootItem = Get-Item -LiteralPath $OutputRoot -Force
if (($outputRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OutputRoot cannot be a reparse point.' }

$beforeRuns = @(Get-Cf7CloudRuns -Repository ([string]$config.repository) -WorkflowFile $workflowFile)
$beforeIds = New-Object 'System.Collections.Generic.HashSet[long]'
foreach ($run in $beforeRuns) { [void]$beforeIds.Add([Int64]$run.databaseId) }

Write-Host "[RuntimeGitHubBuild] Dispatch source=$SourceCommitOid workflow=$workflowFile ref=$sourceRefName" -ForegroundColor Cyan
Invoke-Cf7Gh -Arguments @(
    'workflow','run',$workflowFile,'--repo',[string]$config.repository,
    '--ref',$sourceRefName,'-f',"source_commit=$SourceCommitOid"
) -AllowEmpty | Out-Null

$discoveryDeadline = [DateTime]::UtcNow.AddSeconds($DiscoveryTimeoutSeconds)
$run = $null
do {
    $candidates = @(Get-Cf7CloudRuns -Repository ([string]$config.repository) -WorkflowFile $workflowFile | Where-Object {
        [string]$_.displayTitle -ceq $expectedRunTitle -and
        [string]$_.headBranch -ceq $sourceRefName -and
        [string]$_.event -eq 'workflow_dispatch' -and
        -not $beforeIds.Contains([Int64]$_.databaseId)
    })
    if ($candidates.Count -gt 0) {
        $run = @($candidates | Sort-Object {[Int64]$_.databaseId} | Select-Object -First 1)[0]
        break
    }
    if ([DateTime]::UtcNow -ge $discoveryDeadline) { break }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
if ($null -eq $run) { throw "Timed out locating dispatched GitHub run with title: $expectedRunTitle" }

$runId = [Int64]$run.databaseId
Assert-Cf7RunIdentity -Run $run -ExpectedId $runId -ExpectedTitle $expectedRunTitle -ExpectedBranch $sourceRefName
Write-Host "[RuntimeGitHubBuild] Located run=$runId url=$($run.url)" -ForegroundColor Cyan

$runDeadline = [DateTime]::UtcNow.AddSeconds($RunTimeoutSeconds)
do {
    $run = Invoke-Cf7GhJson -Arguments @(
        'run','view',[string]$runId,'--repo',[string]$config.repository,
        '--json','databaseId,displayTitle,headBranch,headSha,status,conclusion,createdAt,event,url'
    )
    Assert-Cf7RunIdentity -Run $run -ExpectedId $runId -ExpectedTitle $expectedRunTitle -ExpectedBranch $sourceRefName
    if ([string]$run.status -eq 'completed') { break }
    if ([DateTime]::UtcNow -ge $runDeadline) { throw "Timed out waiting for GitHub runtime run: $runId" }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
if ([string]$run.conclusion -ne 'success') {
    throw "GitHub runtime run failed: run=$runId conclusion=$($run.conclusion) url=$($run.url)"
}

$resultRoot = Join-Path $OutputRoot ("run-$runId")
if (Test-Path -LiteralPath $resultRoot) { throw "Cloud result directory already exists; refusing overwrite: $resultRoot" }
$downloadRoot = Join-Path $resultRoot 'signed-artifact'
$candidateRoot = Join-Path $resultRoot 'candidate'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

Write-Host "[RuntimeGitHubBuild] Download signed artifact=$artifactName" -ForegroundColor Cyan
Invoke-Cf7Gh -Arguments @(
    'run','download',[string]$runId,'--repo',[string]$config.repository,
    '--name',$artifactName,'--dir',$downloadRoot
) -AllowEmpty | Out-Null

$expectedArtifactFiles = @(
    'runtime-candidate.v2.zip',
    'runtime-build-envelope.v2.json',
    'runtime-build-envelope.v2.sigstore.json'
)
$actualArtifactFiles = @(Get-ChildItem -LiteralPath $downloadRoot -File -Recurse | ForEach-Object {
    $_.FullName.Substring($downloadRoot.Length + 1).Replace('\','/')
})
if ($actualArtifactFiles.Count -ne $expectedArtifactFiles.Count -or
        @($actualArtifactFiles | Where-Object { $expectedArtifactFiles -notcontains $_ }).Count -gt 0) {
    throw "Signed cloud artifact file set is unexpected: $($actualArtifactFiles -join ',')"
}

$archivePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-candidate.v2.zip' -MaximumBytes 536870912
$envelopePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-build-envelope.v2.json' -MaximumBytes 16777216
$bundlePath = Test-Cf7ArtifactFile -Root $downloadRoot -Name 'runtime-build-envelope.v2.sigstore.json' -MaximumBytes 16777216
$candidateRoot = Expand-Cf7CandidateArchiveSafely -ArchivePath $archivePath -DestinationRoot $candidateRoot
$proofPath = Join-Path $resultRoot 'verified-github-proof.v2.json'
$proof = Invoke-Cf7ProofVerifier -CandidateRoot $candidateRoot -EnvelopePath $envelopePath -BundlePath $bundlePath -ProofPath $proofPath

$result = [pscustomobject][ordered]@{
    schema = 'cf7-runtime-github-build-invocation.v2'
    sourceCommitOid = $SourceCommitOid
    repository = [string]$config.repository
    workflow = $workflowFile
    runId = $runId
    runUrl = [string]$run.url
    artifactName = $artifactName
    resultRoot = $resultRoot
    candidateRoot = $candidateRoot
    envelopePath = $envelopePath
    bundlePath = $bundlePath
    proofPath = $proofPath
    buildIdentityHash = [string]$proof.payload.buildIdentityHash
    payloadClosureHash = [string]$proof.payload.payloadClosureHash
    completedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$resultPath = Join-Path $resultRoot 'runtime-github-build-result.v2.json'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($resultPath, (($result | ConvertTo-Json -Depth 8) + "`n"), $utf8NoBom)
Write-Host "[RuntimeGitHubBuild] OK run=$runId proof=$proofPath candidate=$candidateRoot" -ForegroundColor Green
if ($Json) { $result | ConvertTo-Json -Depth 8 } else { $result }
