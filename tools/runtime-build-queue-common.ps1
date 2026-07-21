# CF7 runtime build queue shared primitives. PowerShell 5.1 / 7 compatible.
# The queue is intentionally data-only: requests cannot carry commands or script text.

function Get-Cf7RuntimeQueueRoot {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [string]$QueueRoot
    )
    if ([string]::IsNullOrWhiteSpace($QueueRoot)) { $QueueRoot = $env:CF7_RUNTIME_QUEUE_ROOT }
    if ([string]::IsNullOrWhiteSpace($QueueRoot)) {
        $QueueRoot = Join-Path $ProjectRoot 'tmp\runtime-build-queue'
    }
    return [IO.Path]::GetFullPath($QueueRoot).TrimEnd('\')
}

function Remove-Cf7LocalDirectoryTree {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$AllowedRoot
    )
    $resolvedPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $resolvedRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')
    $filesystemRoot = [IO.Path]::GetPathRoot($resolvedRoot)
    if ($resolvedRoot.StartsWith('\\', [StringComparison]::Ordinal) -or
            $filesystemRoot -notmatch '^[A-Za-z]:\\$') {
        throw 'Long-path directory cleanup is restricted to a machine-local drive.'
    }
    if ($resolvedPath.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not $resolvedPath.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean a directory outside its allowed local root: $resolvedPath"
    }
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) { return }

    # Windows PowerShell 5.1 cannot recurse through a checkout containing paths beyond
    # MAX_PATH unless the provider receives the extended local-path form. The checkout
    # root itself remains short and is validated above before adding the prefix.
    Remove-Item -LiteralPath ('\\?\' + $resolvedPath) -Recurse -Force
}

function Initialize-Cf7RuntimeQueue {
    param([Parameter(Mandatory=$true)][string]$QueueRoot)
    foreach ($name in @('requests','leases','results','cas')) {
        New-Item -ItemType Directory -Path (Join-Path $QueueRoot $name) -Force | Out-Null
    }
    New-Item -ItemType Directory -Path (Join-Path $QueueRoot 'results\_failures') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $QueueRoot 'cas\candidates') -Force | Out-Null
}

function Get-Cf7QueueSha256Bytes {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-Cf7QueueSha256Text {
    param([Parameter(Mandatory=$true)][string]$Text)
    return Get-Cf7QueueSha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-Cf7QueueFileSha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToUpperInvariant()
}

function Write-Cf7QueueUtf8File {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-Cf7QueueJsonAtomic {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)]$Value,
        [int]$Depth = 12
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    $backup = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.bak')
    try {
        Write-Cf7QueueUtf8File -Path $temporary -Text (($Value | ConvertTo-Json -Depth $Depth) + "`n")
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporary, $Path, $backup)
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
    }
}

function Read-Cf7QueueJson {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Queue JSON missing: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Invalid queue JSON $Path`: $($_.Exception.Message)" }
}

function Assert-Cf7QueueHash {
    param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') { throw "Invalid $Name in runtime build queue record." }
}

function Assert-Cf7GitOid {
    param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[0-9a-fA-F]{40,64}$') { throw "Invalid $Name in runtime build request." }
}

function Assert-Cf7QueueName {
    param([Parameter(Mandatory=$true)][string]$Name, [Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '^[a-z0-9][a-z0-9._-]{1,63}$') {
        throw "$Name must be 2-64 lowercase ASCII letters, digits, dot, underscore, or hyphen."
    }
}

function Get-Cf7RuntimeRequestId {
    param(
        [Parameter(Mandatory=$true)][string]$ReleaseTreeOid,
        [Parameter(Mandatory=$true)][string]$PolicyHash
    )
    return Get-Cf7QueueSha256Text -Text ("cf7-runtime-build-request.v1`nreleaseTreeOid`t$($ReleaseTreeOid.ToLowerInvariant())`npolicyHash`t$($PolicyHash.ToUpperInvariant())`n")
}

function Assert-Cf7RuntimeBuildRequest {
    param([Parameter(Mandatory=$true)]$Request)
    if ($null -eq $Request -or @('cf7-runtime-build-request.v1','cf7-runtime-build-request.v2') -notcontains [string]$Request.schema) {
        throw 'Unsupported runtime build request schema.'
    }
    $commonFields = @(
        'schema','requestId','sourceKind','releaseTreeOid','sourceCommitOid','requestCommitOid','bundleTreeOid',
        'artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash',
        'bundleFile','bundleSha256','requiredQuorum','createdAtUtc'
    )
    # A short-lived development build emitted sparse v1 records with bundleTreeOid before the
    # schema bump landed. Accept that optional field for queue migration, while all new sparse
    # requests are v2 and legacy v1 records without it retain full-release-tree semantics.
    $allowed = @($commonFields)
    $required = if ([string]$Request.schema -eq 'cf7-runtime-build-request.v2') {
        @($commonFields)
    } else {
        @($commonFields | Where-Object { $_ -ne 'bundleTreeOid' })
    }
    foreach ($property in $Request.PSObject.Properties.Name) {
        if ($allowed -notcontains $property) { throw "Unexpected runtime build request field: $property" }
    }
    foreach ($field in $required) {
        if ($null -eq $Request.PSObject.Properties[$field]) { throw "Runtime build request lacks field: $field" }
    }
    Assert-Cf7QueueHash -Name requestId -Value ([string]$Request.requestId)
    Assert-Cf7GitOid -Name releaseTreeOid -Value ([string]$Request.releaseTreeOid)
    Assert-Cf7GitOid -Name sourceCommitOid -Value ([string]$Request.sourceCommitOid)
    Assert-Cf7GitOid -Name requestCommitOid -Value ([string]$Request.requestCommitOid)
    if ($null -ne $Request.PSObject.Properties['bundleTreeOid']) {
        Assert-Cf7GitOid -Name bundleTreeOid -Value ([string]$Request.bundleTreeOid)
    }
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash','bundleSha256')) {
        Assert-Cf7QueueHash -Name $field -Value ([string]$Request.$field)
    }
    if (@('Index','Treeish') -notcontains [string]$Request.sourceKind) { throw 'Invalid sourceKind in runtime build request.' }
    if ([string]$Request.bundleFile -ne 'source.bundle') { throw 'Runtime build request bundleFile must be source.bundle.' }
    if ([int]$Request.requiredQuorum -ne 2) { throw 'Runtime build request requiredQuorum must be 2.' }
    $createdAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Request.createdAtUtc, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind, [ref]$createdAt)) {
        throw 'Runtime build request createdAtUtc is invalid.'
    }
    $expected = Get-Cf7RuntimeRequestId -ReleaseTreeOid ([string]$Request.releaseTreeOid) -PolicyHash ([string]$Request.policyHash)
    if ($expected -ne ([string]$Request.requestId).ToUpperInvariant()) { throw 'Runtime build requestId does not match releaseTreeOid + policyHash.' }
    return $Request
}

function Get-Cf7RuntimeRequestDirectory {
    param([Parameter(Mandatory=$true)][string]$QueueRoot, [Parameter(Mandatory=$true)][string]$RequestId)
    Assert-Cf7QueueHash -Name requestId -Value $RequestId
    return Join-Path (Join-Path $QueueRoot 'requests') $RequestId.ToUpperInvariant()
}

function Read-Cf7RuntimeBuildRequest {
    param([Parameter(Mandatory=$true)][string]$QueueRoot, [Parameter(Mandatory=$true)][string]$RequestId)
    $directory = Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId $RequestId
    $request = Assert-Cf7RuntimeBuildRequest -Request (Read-Cf7QueueJson -Path (Join-Path $directory 'request.json'))
    $bundle = Join-Path $directory 'source.bundle'
    if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) { throw "Runtime request bundle missing: $bundle" }
    if ((Get-Cf7QueueFileSha256 -Path $bundle) -ne ([string]$request.bundleSha256).ToUpperInvariant()) {
        throw 'Runtime request bundle SHA-256 mismatch.'
    }
    return $request
}

function Publish-Cf7QueueDirectory {
    param(
        [Parameter(Mandatory=$true)][string]$TemporaryDirectory,
        [Parameter(Mandatory=$true)][string]$DestinationDirectory
    )
    try {
        [IO.Directory]::Move($TemporaryDirectory, $DestinationDirectory)
        return $true
    } catch [IO.IOException] {
        if (Test-Path -LiteralPath $DestinationDirectory -PathType Container) { return $false }
        throw
    }
}

function Set-Cf7RuntimeRequestSuperseded {
    param(
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)][string]$RequestId,
        [Parameter(Mandatory=$true)][string]$ByRequestId
    )
    Assert-Cf7QueueHash -Name requestId -Value $RequestId
    Assert-Cf7QueueHash -Name supersededByRequestId -Value $ByRequestId
    if ($RequestId -eq $ByRequestId) { throw 'A runtime request cannot supersede itself.' }
    $directory = Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId $RequestId
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Cannot supersede unknown request: $RequestId" }
    $replacement = Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId $ByRequestId
    if (-not (Test-Path -LiteralPath $replacement -PathType Container)) { throw "Cannot supersede with unknown request: $ByRequestId" }
    $marker = [pscustomobject]@{
        schema = 'cf7-runtime-build-request-superseded.v1'
        requestId = $RequestId.ToUpperInvariant()
        supersededByRequestId = $ByRequestId.ToUpperInvariant()
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    Write-Cf7QueueJsonAtomic -Path (Join-Path $directory 'superseded.json') -Value $marker
}

function Test-Cf7LeaseExpired {
    param([Parameter(Mandatory=$true)][string]$LeaseDirectory)
    try {
        $lease = Read-Cf7QueueJson -Path (Join-Path $LeaseDirectory 'lease.json')
        return ([DateTime]::Parse([string]$lease.expiresAtUtc).ToUniversalTime() -le [DateTime]::UtcNow)
    } catch { return $true }
}

function Try-EnterCf7RuntimeRequestLease {
    param(
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)][string]$RequestId,
        [Parameter(Mandatory=$true)][string]$WorkerId,
        [int]$LeaseTtlSeconds = 300
    )
    Assert-Cf7QueueName -Name WorkerId -Value $WorkerId
    if ($LeaseTtlSeconds -lt 5) { throw 'LeaseTtlSeconds must be at least 5.' }
    $leasesRoot = Join-Path $QueueRoot 'leases'
    $target = Join-Path $leasesRoot $RequestId.ToUpperInvariant()
    $token = [Guid]::NewGuid().ToString('N')
    $temporary = Join-Path $leasesRoot ('.' + $RequestId + '.' + $token + '.tmp')
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        $now = [DateTime]::UtcNow
        $record = [pscustomobject]@{
            schema = 'cf7-runtime-build-lease.v1'; requestId = $RequestId.ToUpperInvariant()
            workerId = $WorkerId; leaseToken = $token; pid = $PID
            acquiredAtUtc = $now.ToString('o'); heartbeatAtUtc = $now.ToString('o')
            expiresAtUtc = $now.AddSeconds($LeaseTtlSeconds).ToString('o')
        }
        Write-Cf7QueueUtf8File -Path (Join-Path $temporary 'lease.json') -Text (($record | ConvertTo-Json -Depth 4) + "`n")
        if (Publish-Cf7QueueDirectory -TemporaryDirectory $temporary -DestinationDirectory $target) {
            return [pscustomobject]@{ requestId=$RequestId.ToUpperInvariant(); workerId=$WorkerId; leaseToken=$token; directory=$target; ttl=$LeaseTtlSeconds }
        }
        if (-not (Test-Cf7LeaseExpired -LeaseDirectory $target)) { return $null }
        $expired = Join-Path $leasesRoot ('.expired.' + $RequestId + '.' + [Guid]::NewGuid().ToString('N'))
        try { [IO.Directory]::Move($target, $expired) } catch [IO.IOException] { return $null }
        try {
            if (Publish-Cf7QueueDirectory -TemporaryDirectory $temporary -DestinationDirectory $target) {
                return [pscustomobject]@{ requestId=$RequestId.ToUpperInvariant(); workerId=$WorkerId; leaseToken=$token; directory=$target; ttl=$LeaseTtlSeconds }
            }
            return $null
        } finally {
            if (Test-Path -LiteralPath $expired) { Remove-Item -LiteralPath $expired -Recurse -Force }
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

function Update-Cf7RuntimeRequestLease {
    param([Parameter(Mandatory=$true)]$Lease)
    $path = Join-Path ([string]$Lease.directory) 'lease.json'
    $record = Read-Cf7QueueJson -Path $path
    if ([string]$record.leaseToken -ne [string]$Lease.leaseToken) { throw 'Runtime request lease ownership was lost.' }
    $now = [DateTime]::UtcNow
    $record.heartbeatAtUtc = $now.ToString('o')
    $record.expiresAtUtc = $now.AddSeconds([int]$Lease.ttl).ToString('o')
    Write-Cf7QueueJsonAtomic -Path $path -Value $record
}

function Exit-Cf7RuntimeRequestLease {
    param([Parameter(Mandatory=$true)]$Lease)
    $directory = [string]$Lease.directory
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
    try {
        $record = Read-Cf7QueueJson -Path (Join-Path $directory 'lease.json')
        if ([string]$record.leaseToken -ne [string]$Lease.leaseToken) { return }
        $released = Join-Path (Split-Path -Parent $directory) ('.released.' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::Move($directory, $released)
        Remove-Item -LiteralPath $released -Recurse -Force
    } catch [IO.IOException] { return }
}

function Enter-Cf7RuntimeWorkerMutex {
    param([Parameter(Mandatory=$true)][string]$WorkerId)
    Assert-Cf7QueueName -Name WorkerId -Value $WorkerId
    $suffix = (Get-Cf7QueueSha256Text -Text $WorkerId).Substring(0, 24)
    $mutex = New-Object Threading.Mutex($false, ('Local\CF7RuntimeBuildWorker-' + $suffix))
    try {
        if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); return $null }
    } catch [Threading.AbandonedMutexException] { }
    return $mutex
}

function Exit-Cf7RuntimeWorkerMutex {
    param($Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch { }
    $Mutex.Dispose()
}

function Copy-Cf7CandidateIntoCas {
    param(
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$CandidateRoot,
        [Parameter(Mandatory=$true)][string]$BuildIdentityHash,
        [Parameter(Mandatory=$true)][string]$PayloadClosureHash,
        [Parameter(Mandatory=$true)][object[]]$PayloadFiles
    )
    Assert-Cf7QueueHash -Name buildIdentityHash -Value $BuildIdentityHash
    Assert-Cf7QueueHash -Name payloadClosureHash -Value $PayloadClosureHash
    $casRoot = Join-Path $QueueRoot 'cas\candidates'
    $identityCasRoot = Join-Path $casRoot $BuildIdentityHash.ToUpperInvariant()
    New-Item -ItemType Directory -Path $identityCasRoot -Force | Out-Null
    $destination = Join-Path $identityCasRoot $PayloadClosureHash.ToUpperInvariant()
    $verifier = Join-Path $ProjectRoot 'tools\verify-runtime-bundle-v2.ps1'
    if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) { throw "Runtime v2 integrity verifier missing: $verifier" }
    if (Test-Path -LiteralPath $destination -PathType Container) {
        $existingClosure = Get-Cf7QueuePayloadClosure -ProjectRoot $ProjectRoot -CandidateRoot $destination
        if ([string]$existingClosure.payloadClosureHash -ne $PayloadClosureHash) { throw 'Existing CAS candidate does not match its address.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -ProjectRoot $ProjectRoot -DeploymentRoot $destination -IntegrityOnly | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Existing CAS candidate failed runtime v2 integrity verification.' }
        return $destination
    }
    $temporary = Join-Path $identityCasRoot ('.' + $PayloadClosureHash + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        foreach ($row in $PayloadFiles) {
            $relative = ([string]$row.path).Replace('\','/')
            if (-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|/)\.\.(/|$)') { throw "Unsafe payload path: $relative" }
            $source = Join-Path $CandidateRoot ($relative -replace '/', '\')
            $target = Join-Path $temporary ($relative -replace '/', '\')
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
        }
        $manifestSource = Join-Path $CandidateRoot 'runtime\cf7-runtime-manifest.tsv'
        if (-not (Test-Path -LiteralPath $manifestSource -PathType Leaf)) { throw 'Runtime candidate lacks cf7-runtime-manifest.tsv.' }
        $manifestTarget = Join-Path $temporary 'runtime\cf7-runtime-manifest.tsv'
        New-Item -ItemType Directory -Path (Split-Path -Parent $manifestTarget) -Force | Out-Null
        Copy-Item -LiteralPath $manifestSource -Destination $manifestTarget -Force
        $copiedClosure = Get-Cf7QueuePayloadClosure -ProjectRoot $ProjectRoot -CandidateRoot $temporary
        if ([string]$copiedClosure.payloadClosureHash -ne $PayloadClosureHash) {
            throw 'CAS staging copy changed the payload closure.'
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -ProjectRoot $ProjectRoot -DeploymentRoot $temporary -IntegrityOnly | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'CAS staging candidate failed runtime v2 integrity verification.' }
        if (-not (Publish-Cf7QueueDirectory -TemporaryDirectory $temporary -DestinationDirectory $destination)) {
            if (-not (Test-Path -LiteralPath $destination -PathType Container)) { throw 'CAS publication race did not produce a candidate.' }
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
    return $destination
}

function Get-Cf7QueuePayloadClosure {
    param(
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)][string]$CandidateRoot
    )
    if (Get-Command Get-Cf7RuntimeV2PayloadClosure -ErrorAction SilentlyContinue) {
        return Get-Cf7RuntimeV2PayloadClosure -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
    }
    if (Get-Command Get-Cf7RuntimePayloadClosureV2 -ErrorAction SilentlyContinue) {
        return Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $ProjectRoot -DeploymentRoot $CandidateRoot
    }
    throw 'runtime-build-v2-common.ps1 lacks a v2 payload closure function.'
}

function Publish-Cf7RuntimeProducerResult {
    param(
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)][string]$ProjectRoot,
        [Parameter(Mandatory=$true)]$Request,
        [Parameter(Mandatory=$true)]$Attestation,
        [Parameter(Mandatory=$true)][string]$CandidateRoot,
        [Parameter(Mandatory=$true)][string]$RegistryPath,
        [scriptblock]$AttestationValidator
    )
    if ($AttestationValidator) { & $AttestationValidator $Attestation $RegistryPath }
    else { Test-Cf7RuntimeBuildAttestationV2 -Attestation $Attestation -RegistryPath $RegistryPath | Out-Null }
    $payload = $Attestation.payload
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
        if ([string]$payload.$field -ne [string]$Request.$field) { throw "Producer result does not match request: $field" }
    }
    Assert-Cf7QueueHash -Name builderKeyId -Value ([string]$payload.builderKeyId)
    Assert-Cf7QueueName -Name faultDomain -Value ([string]$payload.faultDomain)
    Assert-Cf7QueueHash -Name payloadClosureHash -Value ([string]$payload.payloadClosureHash)
    $actualClosure = Get-Cf7QueuePayloadClosure -ProjectRoot $ProjectRoot -CandidateRoot $CandidateRoot
    if ([string]$actualClosure.payloadClosureHash -ne [string]$payload.payloadClosureHash) {
        throw 'Producer attestation payload closure does not match candidate bytes.'
    }
    $casPath = Copy-Cf7CandidateIntoCas -QueueRoot $QueueRoot -ProjectRoot $ProjectRoot -CandidateRoot $CandidateRoot -BuildIdentityHash ([string]$payload.buildIdentityHash) -PayloadClosureHash ([string]$payload.payloadClosureHash) -PayloadFiles @($actualClosure.files)
    $identityRoot = Join-Path (Join-Path $QueueRoot 'results') ([string]$payload.buildIdentityHash).ToUpperInvariant()
    New-Item -ItemType Directory -Path $identityRoot -Force | Out-Null
    $destination = Join-Path $identityRoot ([string]$payload.builderKeyId).ToUpperInvariant()
    $temporary = Join-Path $identityRoot ('.' + [string]$payload.builderKeyId + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        $result = [pscustomobject]@{
            schema = 'cf7-runtime-build-result.v1'; requestId = [string]$Request.requestId
            buildIdentityHash = [string]$payload.buildIdentityHash; builderKeyId = [string]$payload.builderKeyId
            faultDomain = [string]$payload.faultDomain; payloadClosureHash = [string]$payload.payloadClosureHash
            casRelativePath = 'cas/candidates/' + ([string]$payload.buildIdentityHash).ToUpperInvariant() + '/' + ([string]$payload.payloadClosureHash).ToUpperInvariant()
            attestationFile = 'attestation.json'
            createdAtUtc = [DateTime]::UtcNow.ToString('o'); attestation = $Attestation
        }
        Write-Cf7QueueUtf8File -Path (Join-Path $temporary 'attestation.json') -Text (($Attestation | ConvertTo-Json -Depth 20) + "`n")
        Write-Cf7QueueUtf8File -Path (Join-Path $temporary 'result.json') -Text (($result | ConvertTo-Json -Depth 20) + "`n")
        if (-not (Publish-Cf7QueueDirectory -TemporaryDirectory $temporary -DestinationDirectory $destination)) {
            $existing = Read-Cf7QueueJson -Path (Join-Path $destination 'result.json')
            if ([string]$existing.payloadClosureHash -ne [string]$payload.payloadClosureHash -or
                [string]$existing.faultDomain -ne [string]$payload.faultDomain) {
                throw "Builder key equivocation for build identity: $($payload.builderKeyId)"
            }
            return $existing
        }
        return $result
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

function Copy-Cf7RuntimeFailureDiagnostics {
    param(
        [Parameter(Mandatory=$true)][string]$SourceRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot
    )
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { return @() }
    $sourceItem = Get-Item -LiteralPath $SourceRoot -Force
    if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Runtime failure diagnostics root must not be a reparse point.'
    }
    $files = @(Get-ChildItem -LiteralPath $SourceRoot -Force -File)
    if ($files.Count -gt 16) { throw 'Runtime failure diagnostics contains more than 16 files.' }
    $totalBytes = [Int64]0
    $accepted = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Runtime failure diagnostic is a reparse point: $($file.Name)"
        }
        if ($file.Length -gt 1MB) { throw "Runtime failure diagnostic exceeds 1 MiB: $($file.Name)" }
        $totalBytes += $file.Length
        if ($totalBytes -gt 2MB) { throw 'Runtime failure diagnostics exceed the 2 MiB total limit.' }
        if ($file.Name -notmatch '^[A-Za-z0-9_.-]{1,128}$') {
            throw "Runtime failure diagnostic has an unsafe file name: $($file.Name)"
        }
        if (-not (Test-Path -LiteralPath $DestinationRoot -PathType Container)) {
            New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
        }
        $destination = Join-Path $DestinationRoot $file.Name
        [IO.File]::Copy($file.FullName, $destination, $false)
        $accepted.Add($file.Name)
    }
    return $accepted.ToArray()
}

function Write-Cf7RuntimeBuildFailure {
    param(
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)]$Request,
        [Parameter(Mandatory=$true)][string]$WorkerId,
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$DiagnosticRoot
    )
    $directory = Join-Path (Join-Path (Join-Path $QueueRoot 'results\_failures') ([string]$Request.requestId)) ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $diagnosticFiles = @()
    $diagnosticCaptureError = $null
    if (-not [string]::IsNullOrWhiteSpace($DiagnosticRoot)) {
        try {
            $diagnosticFiles = @(Copy-Cf7RuntimeFailureDiagnostics -SourceRoot $DiagnosticRoot `
                -DestinationRoot (Join-Path $directory 'diagnostics'))
        } catch {
            # Diagnostic capture must never mask the original producer failure.
            $diagnosticCaptureError = $_.Exception.Message
        }
    }
    $record = [pscustomobject]@{
        schema='cf7-runtime-build-failure.v1'; requestId=[string]$Request.requestId
        buildIdentityHash=[string]$Request.buildIdentityHash; workerId=$WorkerId
        createdAtUtc=[DateTime]::UtcNow.ToString('o'); message=$Message
        diagnosticFiles=$diagnosticFiles; diagnosticCaptureError=$diagnosticCaptureError
    }
    Write-Cf7QueueJsonAtomic -Path (Join-Path $directory 'failure.json') -Value $record
}

function Get-Cf7RuntimeBuildRequestState {
    param(
        [Parameter(Mandatory=$true)][string]$QueueRoot,
        [Parameter(Mandatory=$true)]$Request,
        [Parameter(Mandatory=$true)][string]$RegistryPath,
        [scriptblock]$AttestationValidator
    )
    $requestDir = Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId ([string]$Request.requestId)
    $supersededPath = Join-Path $requestDir 'superseded.json'
    if (Test-Path -LiteralPath $supersededPath -PathType Leaf) {
        $marker = Read-Cf7QueueJson -Path $supersededPath
        return [pscustomobject]@{ requestId=[string]$Request.requestId; status='superseded'; quorum='0/2'; validResults=0; faultDomains=@(); supersededBy=[string]$marker.supersededByRequestId; failures=0 }
    }
    $valid = @()
    $identityRoot = Join-Path (Join-Path $QueueRoot 'results') ([string]$Request.buildIdentityHash).ToUpperInvariant()
    if (Test-Path -LiteralPath $identityRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $identityRoot -Filter result.json -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $result = Read-Cf7QueueJson -Path $file.FullName
                if ([string]$result.schema -ne 'cf7-runtime-build-result.v1') { continue }
                if ([string]$result.buildIdentityHash -ne [string]$Request.buildIdentityHash) { continue }
                if ($AttestationValidator) { & $AttestationValidator $result.attestation $RegistryPath }
                else { Test-Cf7RuntimeBuildAttestationV2 -Attestation $result.attestation -RegistryPath $RegistryPath | Out-Null }
                $payload = $result.attestation.payload
                if ([string]$result.builderKeyId -ne [string]$payload.builderKeyId -or
                    [string]$result.faultDomain -ne [string]$payload.faultDomain -or
                    [string]$result.payloadClosureHash -ne [string]$payload.payloadClosureHash) { continue }
                $matches = $true
                # Producer proofs are reusable across policy-only changes. The request itself is
                # policy-addressed; producer equality is intentionally buildIdentity + signer.
                foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','buildIdentityHash')) {
                    if ([string]$payload.$field -ne [string]$Request.$field) { $matches = $false }
                }
                if ($matches) {
                    $valid += [pscustomobject]@{
                        builderKeyId=[string]$payload.builderKeyId; faultDomain=[string]$payload.faultDomain
                        payloadClosureHash=[string]$payload.payloadClosureHash; result=$result
                    }
                }
            } catch { }
        }
    }
    $best = @()
    foreach ($group in @($valid | Group-Object payloadClosureHash)) {
        $groupDomains = @($group.Group | ForEach-Object { [string]$_.faultDomain } | Sort-Object -Unique)
        if ($groupDomains.Count -gt $best.Count) { $best = $groupDomains }
    }
    $domains = @($best)
    $failRoot = Join-Path (Join-Path $QueueRoot 'results\_failures') ([string]$Request.requestId)
    $failureCount = 0
    if (Test-Path -LiteralPath $failRoot -PathType Container) {
        $failureCount = @(Get-ChildItem -LiteralPath $failRoot -Filter failure.json -File -Recurse -ErrorAction SilentlyContinue).Count
    }
    $count = [Math]::Min(2, $domains.Count)
    $status = if ($count -ge 2) { 'ready' } elseif ($failureCount -gt 0 -and $count -eq 0) { 'failed' } else { "$count/2" }
    return [pscustomobject]@{
        requestId=[string]$Request.requestId; status=$status; quorum="$count/2"
        validResults=$valid.Count; faultDomains=$domains; supersededBy=$null; failures=$failureCount
    }
}
