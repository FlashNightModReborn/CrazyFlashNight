param(
    [string]$ProjectRoot,
    [string]$QueueRoot,
    [ValidateSet('Index','Treeish')][string]$SourceKind = 'Index',
    [string]$Treeish = 'HEAD',
    [string[]]$SupersedeRequestId = @()
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

function Invoke-Cf7RequestGit {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& git -C $ProjectRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return @($output)
}

function Get-Cf7RequestV2Identity {
    param([ValidateSet('Worktree','Index')][string]$Mode, [string]$Root)
    if (Get-Command Get-Cf7RuntimeV2Identity -ErrorAction SilentlyContinue) {
        return Get-Cf7RuntimeV2Identity -ProjectRoot $Root -Mode $Mode
    }
    foreach ($name in @('Get-Cf7RuntimeArtifactSourceHash','Get-Cf7RuntimeProducerRecipeHash','Get-Cf7RuntimeToolchainLockHashV2','Get-Cf7RuntimePolicyHash','Get-Cf7RuntimeV2BuildIdentityHash')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "runtime-build-v2-common.ps1 lacks required function: $name" }
    }
    $artifact = Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $Root -Mode $Mode
    $recipe = Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $Root -Mode $Mode
    $toolchain = Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $Root -Mode $Mode
    $policy = Get-Cf7RuntimePolicyHash -ProjectRoot $Root -Mode $Mode
    $buildIdentity = Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $artifact -ProducerRecipeHash $recipe -ToolchainLockHash $toolchain
    return [pscustomobject]@{
        artifactSourceHash=$artifact; producerRecipeHash=$recipe; toolchainLockHash=$toolchain
        policyHash=$policy; buildIdentityHash=$buildIdentity
    }
}

function Get-Cf7RequestBundleEntries {
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($domain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        foreach ($path in Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain $domain -Mode Index) {
            [void]$paths.Add(([string]$path).Replace('\', '/'))
        }
    }
    $sorted = [string[]]$paths
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($path in $sorted) {
        $rows = @(Invoke-Cf7RequestGit -Arguments @('ls-files','-s','--',$path))
        $stageZero = @($rows | Where-Object { $_ -match '^[0-9]+\s+[0-9a-fA-F]+\s+0\t' })
        if ($stageZero.Count -ne 1 -or [string]$stageZero[0] -notmatch '^([0-9]+)\s+([0-9a-fA-F]+)\s+0\t(.+)$') {
            throw "Runtime request bundle input has no unique stage-0 entry: $path"
        }
        if ([string]$Matches[3] -cne $path) { throw "Runtime request bundle path mismatch: $path" }
        $entries.Add([pscustomobject]@{ mode=[string]$Matches[1]; oid=([string]$Matches[2]).ToLowerInvariant(); path=$path })
    }
    return $entries.ToArray()
}

function New-Cf7RequestBundleTree {
    param(
        [Parameter(Mandatory=$true)][object[]]$Entries,
        [Parameter(Mandatory=$true)][string]$IndexPath
    )
    $savedIndex = $env:GIT_INDEX_FILE
    try {
        $env:GIT_INDEX_FILE = $IndexPath
        Invoke-Cf7RequestGit -Arguments @('read-tree','--empty') | Out-Null
        foreach ($entry in $Entries) {
            Invoke-Cf7RequestGit -Arguments @(
                'update-index','--add','--cacheinfo',
                [string]$entry.mode,[string]$entry.oid,[string]$entry.path
            ) | Out-Null
        }
        return ([string](Invoke-Cf7RequestGit -Arguments @('write-tree') | Select-Object -First 1)).Trim().ToLowerInvariant()
    } finally {
        $env:GIT_INDEX_FILE = $savedIndex
        if (Test-Path -LiteralPath $IndexPath) { Remove-Item -LiteralPath $IndexPath -Force }
        if (Test-Path -LiteralPath ($IndexPath + '.lock')) { Remove-Item -LiteralPath ($IndexPath + '.lock') -Force }
    }
}

function New-Cf7RequestSnapshotCommit {
    param([Parameter(Mandatory=$true)][string]$TreeOid)
    $oldAuthorName = $env:GIT_AUTHOR_NAME; $oldAuthorEmail = $env:GIT_AUTHOR_EMAIL
    $oldCommitterName = $env:GIT_COMMITTER_NAME; $oldCommitterEmail = $env:GIT_COMMITTER_EMAIL
    try {
        $env:GIT_AUTHOR_NAME='CF7 Runtime Queue'; $env:GIT_AUTHOR_EMAIL='runtime-queue@invalid.local'
        $env:GIT_COMMITTER_NAME='CF7 Runtime Queue'; $env:GIT_COMMITTER_EMAIL='runtime-queue@invalid.local'
        $commitOutput = @('CF7 immutable runtime build request') | & git -C $ProjectRoot commit-tree $TreeOid 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git commit-tree failed: $($commitOutput -join "`n")" }
        return ([string]($commitOutput | Select-Object -First 1)).Trim().ToLowerInvariant()
    } finally {
        $env:GIT_AUTHOR_NAME=$oldAuthorName; $env:GIT_AUTHOR_EMAIL=$oldAuthorEmail
        $env:GIT_COMMITTER_NAME=$oldCommitterName; $env:GIT_COMMITTER_EMAIL=$oldCommitterEmail
    }
}

function Assert-Cf7ExistingRequestMatchesSnapshot {
    param(
        [Parameter(Mandatory=$true)]$Request,
        [Parameter(Mandatory=$true)]$Identity,
        [Parameter(Mandatory=$true)][string]$ReleaseTreeOid,
        [Parameter(Mandatory=$true)][string]$BundleTreeOid
    )
    if (([string]$Request.releaseTreeOid).ToLowerInvariant() -cne $ReleaseTreeOid.ToLowerInvariant()) {
        throw 'Existing runtime request directory has a different releaseTreeOid.'
    }
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        if (([string]$Request.$field).ToUpperInvariant() -cne ([string]$Identity.$field).ToUpperInvariant()) {
            throw "Existing runtime request directory has a different frozen identity: $field"
        }
    }
    if ($null -ne $Request.PSObject.Properties['bundleTreeOid'] -and
            ([string]$Request.bundleTreeOid).ToLowerInvariant() -cne $BundleTreeOid.ToLowerInvariant()) {
        throw 'Existing runtime request directory has a different synthetic bundle tree.'
    }
    return $Request
}

$QueueRoot = Get-Cf7RuntimeQueueRoot -ProjectRoot $ProjectRoot -QueueRoot $QueueRoot
Initialize-Cf7RuntimeQueue -QueueRoot $QueueRoot
$requestsRoot = Join-Path $QueueRoot 'requests'
$temporaryRef = 'refs/heads/cf7-runtime-request-' + [Guid]::NewGuid().ToString('N')
$temporaryIndex = $null
$bundleIndex = $null
$previousGitIndexFile = $env:GIT_INDEX_FILE
$temporaryRequest = $null
$refCreated = $false

try {
    $sourceCommitOid = ([string](Invoke-Cf7RequestGit -Arguments @('rev-parse', "$Treeish^{commit}") | Select-Object -First 1)).Trim().ToLowerInvariant()
    if ($SourceKind -eq 'Index') {
        $releaseTreeOid = ([string](Invoke-Cf7RequestGit -Arguments @('write-tree') | Select-Object -First 1)).Trim().ToLowerInvariant()
        $identity = Get-Cf7RequestV2Identity -Mode Index -Root $ProjectRoot
        $bundleEntries = Get-Cf7RequestBundleEntries
    } else {
        $releaseTreeOid = ([string](Invoke-Cf7RequestGit -Arguments @('rev-parse', "$sourceCommitOid^{tree}") | Select-Object -First 1)).Trim().ToLowerInvariant()
        # Compute a committed tree's identity through an isolated index.  A full temporary
        # worktree is both wasteful and unsafe for CF7's intentionally deep Flash asset paths
        # on Windows; v2 identity only needs Git blob identities, not materialized files.
        $temporaryIndex = Join-Path $requestsRoot ('.identity.' + [Guid]::NewGuid().ToString('N') + '.index')
        try {
            $env:GIT_INDEX_FILE = $temporaryIndex
            Invoke-Cf7RequestGit -Arguments @('read-tree',$sourceCommitOid) | Out-Null
            $identity = Get-Cf7RequestV2Identity -Mode Index -Root $ProjectRoot
            $bundleEntries = Get-Cf7RequestBundleEntries
        } finally {
            $env:GIT_INDEX_FILE = $previousGitIndexFile
            if (Test-Path -LiteralPath $temporaryIndex) { Remove-Item -LiteralPath $temporaryIndex -Force }
            if (Test-Path -LiteralPath ($temporaryIndex + '.lock')) { Remove-Item -LiteralPath ($temporaryIndex + '.lock') -Force }
            $temporaryIndex = $null
        }
    }
    $bundleIndex = Join-Path $requestsRoot ('.bundle.' + [Guid]::NewGuid().ToString('N') + '.index')
    $bundleTreeOid = New-Cf7RequestBundleTree -Entries $bundleEntries -IndexPath $bundleIndex
    $bundleIndex = $null
    $requestCommitOid = New-Cf7RequestSnapshotCommit -TreeOid $bundleTreeOid
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        Assert-Cf7QueueHash -Name $field -Value ([string]$identity.$field)
    }
    $requestId = Get-Cf7RuntimeRequestId -ReleaseTreeOid $releaseTreeOid -PolicyHash ([string]$identity.policyHash)
    $destination = Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId $requestId
    if (Test-Path -LiteralPath $destination -PathType Container) {
        $request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $requestId
        Assert-Cf7ExistingRequestMatchesSnapshot -Request $request -Identity $identity `
            -ReleaseTreeOid $releaseTreeOid -BundleTreeOid $bundleTreeOid | Out-Null
        foreach ($oldId in $SupersedeRequestId) { Set-Cf7RuntimeRequestSuperseded -QueueRoot $QueueRoot -RequestId $oldId -ByRequestId $requestId }
        Write-Output $request
        return
    }

    Invoke-Cf7RequestGit -Arguments @('update-ref',$temporaryRef,$requestCommitOid) | Out-Null
    $refCreated = $true
    $temporaryRequest = Join-Path $requestsRoot ('.request.' + $requestId + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    New-Item -ItemType Directory -Path $temporaryRequest -Force | Out-Null
    $bundlePath = Join-Path $temporaryRequest 'source.bundle'
    Invoke-Cf7RequestGit -Arguments @('bundle','create',$bundlePath,$temporaryRef) | Out-Null
    Invoke-Cf7RequestGit -Arguments @('bundle','verify',$bundlePath) | Out-Null
    $request = [pscustomobject]@{
        schema='cf7-runtime-build-request.v2'; requestId=$requestId; sourceKind=$SourceKind
        releaseTreeOid=$releaseTreeOid; sourceCommitOid=$sourceCommitOid; requestCommitOid=$requestCommitOid; bundleTreeOid=$bundleTreeOid
        artifactSourceHash=([string]$identity.artifactSourceHash).ToUpperInvariant()
        producerRecipeHash=([string]$identity.producerRecipeHash).ToUpperInvariant()
        toolchainLockHash=([string]$identity.toolchainLockHash).ToUpperInvariant()
        policyHash=([string]$identity.policyHash).ToUpperInvariant()
        buildIdentityHash=([string]$identity.buildIdentityHash).ToUpperInvariant()
        bundleFile='source.bundle'; bundleSha256=Get-Cf7QueueFileSha256 -Path $bundlePath
        requiredQuorum=2; createdAtUtc=[DateTime]::UtcNow.ToString('o')
    }
    Assert-Cf7RuntimeBuildRequest -Request $request | Out-Null
    Write-Cf7QueueUtf8File -Path (Join-Path $temporaryRequest 'request.json') -Text (($request | ConvertTo-Json -Depth 8) + "`n")
    if (-not (Publish-Cf7QueueDirectory -TemporaryDirectory $temporaryRequest -DestinationDirectory $destination)) {
        if (Test-Path -LiteralPath $temporaryRequest) { Remove-Item -LiteralPath $temporaryRequest -Recurse -Force }
        $request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $requestId
        Assert-Cf7ExistingRequestMatchesSnapshot -Request $request -Identity $identity `
            -ReleaseTreeOid $releaseTreeOid -BundleTreeOid $bundleTreeOid | Out-Null
    }
    $temporaryRequest = $null
    foreach ($oldId in $SupersedeRequestId) { Set-Cf7RuntimeRequestSuperseded -QueueRoot $QueueRoot -RequestId $oldId -ByRequestId $requestId }
    Write-Output $request
} finally {
    $env:GIT_INDEX_FILE = $previousGitIndexFile
    if ($refCreated) { & git -C $ProjectRoot update-ref -d $temporaryRef 2>$null | Out-Null }
    if ($temporaryIndex) {
        if (Test-Path -LiteralPath $temporaryIndex) { Remove-Item -LiteralPath $temporaryIndex -Force }
        if (Test-Path -LiteralPath ($temporaryIndex + '.lock')) { Remove-Item -LiteralPath ($temporaryIndex + '.lock') -Force }
    }
    if ($bundleIndex) {
        if (Test-Path -LiteralPath $bundleIndex) { Remove-Item -LiteralPath $bundleIndex -Force }
        if (Test-Path -LiteralPath ($bundleIndex + '.lock')) { Remove-Item -LiteralPath ($bundleIndex + '.lock') -Force }
    }
    if ($temporaryRequest -and (Test-Path -LiteralPath $temporaryRequest)) { Remove-Item -LiteralPath $temporaryRequest -Recurse -Force }
}
