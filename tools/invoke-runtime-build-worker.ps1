param(
    [string]$ProjectRoot,
    [string]$QueueRoot,
    [string]$CheckoutRoot = $env:CF7_RUNTIME_CHECKOUT_ROOT,
    [Parameter(Mandatory=$true)][string]$WorkerId,
    [string]$CertificateThumbprint,
    [string]$RegistryPath,
    [switch]$Once,
    [switch]$Watch,
    [switch]$DryRun,
    [string]$BuildCommand,
    [int]$LeaseTtlSeconds = 300,
    [int]$HeartbeatSeconds = 15,
    [int]$PollSeconds = 15
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-attestation-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

Assert-Cf7QueueName -Name WorkerId -Value $WorkerId
if ($Once -and $Watch) { throw '-Once and -Watch are mutually exclusive.' }
if (-not $Once -and -not $Watch) { $Once = $true }
if ($DryRun -and $Watch) { throw '-DryRun is only supported with -Once.' }
if (-not $DryRun -and [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    throw '-CertificateThumbprint is required unless -DryRun is used.'
}
if ($HeartbeatSeconds -lt 1 -or $HeartbeatSeconds -ge $LeaseTtlSeconds) {
    throw 'HeartbeatSeconds must be positive and smaller than LeaseTtlSeconds.'
}
if ($PollSeconds -lt 1) { throw 'PollSeconds must be positive.' }
if (-not $RegistryPath) { $RegistryPath = Join-Path $ProjectRoot 'config\build\runtime-builders.v2.json' }
if ($BuildCommand) { $BuildCommand = (Resolve-Path -LiteralPath $BuildCommand).Path }
$QueueRoot = Get-Cf7RuntimeQueueRoot -ProjectRoot $ProjectRoot -QueueRoot $QueueRoot
Assert-Cf7RuntimeQueuePathBudget -QueueRoot $QueueRoot
Initialize-Cf7RuntimeQueue -QueueRoot $QueueRoot
if ([string]::IsNullOrWhiteSpace($CheckoutRoot)) {
    $localRoot = if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $env:LOCALAPPDATA
    } else {
        [IO.Path]::GetTempPath()
    }
    $CheckoutRoot = Join-Path $localRoot 'CF7\runtime-build-checkouts'
}
$checkoutRootFull = [IO.Path]::GetFullPath($CheckoutRoot)
$checkoutFilesystemRoot = [IO.Path]::GetPathRoot($checkoutRootFull)
if ([string]::IsNullOrWhiteSpace($checkoutRootFull) -or
        $checkoutRootFull.TrimEnd('\') -eq $checkoutFilesystemRoot.TrimEnd('\')) {
    throw 'CheckoutRoot must be a dedicated directory, not a filesystem root.'
}
$CheckoutRoot = $checkoutRootFull.TrimEnd('\')
if ($CheckoutRoot.StartsWith('\\', [StringComparison]::Ordinal)) {
    throw 'CheckoutRoot must be machine-local; UNC/network paths are not allowed.'
}
if ($checkoutFilesystemRoot -match '^[A-Za-z]:\\$') {
    try {
        $checkoutDrive = New-Object IO.DriveInfo($checkoutFilesystemRoot)
        if ($checkoutDrive.DriveType -eq [IO.DriveType]::Network) {
            throw 'CheckoutRoot must be machine-local; mapped network drives are not allowed.'
        }
    } catch [IO.IOException] {
        throw "Cannot inspect CheckoutRoot drive: $($_.Exception.Message)"
    }
}
foreach ($restrictedRoot in @($ProjectRoot,$QueueRoot)) {
    $restricted = [IO.Path]::GetFullPath($restrictedRoot).TrimEnd('\')
    if ($CheckoutRoot.Equals($restricted, [StringComparison]::OrdinalIgnoreCase) -or
            $CheckoutRoot.StartsWith($restricted + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CheckoutRoot must remain outside the source repository and shared queue.'
    }
}
New-Item -ItemType Directory -Path $CheckoutRoot -Force | Out-Null
$workerHadFailure = $false
$workerKeyId = $null
if (-not $DryRun) {
    $workerCertificate = Get-Cf7RuntimeV2CurrentUserCertificate -CertificateThumbprint $CertificateThumbprint
    try { $workerKeyId = Get-Cf7RuntimeV2BuilderKeyId -Certificate $workerCertificate }
    finally { $workerCertificate.Dispose() }
    $workerRegistry = Read-Cf7RuntimeV2BuilderRegistry -RegistryPath $RegistryPath
    $workerEntry = Get-Cf7RuntimeV2RegistryEntry -Registry $workerRegistry -KeyId $workerKeyId -CertificateThumbprint $CertificateThumbprint
    if (-not [bool]$workerEntry.enabled) { throw "Runtime builder is disabled: $workerKeyId" }
}

function Get-Cf7WorkerV2Identity {
    param([Parameter(Mandatory=$true)][string]$Root)
    if (Get-Command Get-Cf7RuntimeV2Identity -ErrorAction SilentlyContinue) {
        return Get-Cf7RuntimeV2Identity -ProjectRoot $Root -Mode Worktree
    }
    foreach ($name in @('Get-Cf7RuntimeArtifactSourceHash','Get-Cf7RuntimeProducerRecipeHash','Get-Cf7RuntimeToolchainLockHashV2','Get-Cf7RuntimePolicyHash','Get-Cf7RuntimeV2BuildIdentityHash')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "runtime-build-v2-common.ps1 lacks required function: $name" }
    }
    $artifact = Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $Root -Mode Worktree
    $recipe = Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $Root -Mode Worktree
    $toolchain = Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $Root -Mode Worktree
    $policy = Get-Cf7RuntimePolicyHash -ProjectRoot $Root -Mode Worktree
    $buildIdentity = Get-Cf7RuntimeV2BuildIdentityHash -ArtifactSourceHash $artifact -ProducerRecipeHash $recipe -ToolchainLockHash $toolchain
    return [pscustomobject]@{
        artifactSourceHash=$artifact; producerRecipeHash=$recipe; toolchainLockHash=$toolchain
        policyHash=$policy; buildIdentityHash=$buildIdentity
    }
}

function Invoke-Cf7WorkerGit {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& git @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($exitCode -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
    return @($output)
}

function Assert-Cf7WorkerSparseBundleTree {
    param([Parameter(Mandatory=$true)][string]$Root)
    $declaredSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($domain in @('artifactSource','producerRecipe','toolchainLock','policy')) {
        foreach ($path in Get-Cf7RuntimeV2DomainFiles -ProjectRoot $Root -Domain $domain -Mode Worktree) {
            [void]$declaredSet.Add(([string]$path).Replace('\','/'))
        }
    }
    $declared = [string[]]$declaredSet
    [Array]::Sort($declared, [StringComparer]::Ordinal)
    [string[]]$tracked = @(Invoke-Cf7WorkerGit -Arguments @('-c','core.quotepath=false','-C',$Root,'ls-files','--') |
        ForEach-Object { ([string]$_).Replace('\','/') })
    [Array]::Sort($tracked, [StringComparer]::Ordinal)
    if ($tracked.Count -ne $declared.Count) {
        throw "Synthetic runtime bundle contains undeclared or missing paths: declared=$($declared.Count) tracked=$($tracked.Count)"
    }
    for ($index = 0; $index -lt $declared.Count; $index++) {
        if ([string]$tracked[$index] -cne [string]$declared[$index]) {
            throw "Synthetic runtime bundle path closure mismatch: declared=$($declared[$index]) tracked=$($tracked[$index])"
        }
    }
}

function Assert-Cf7WorkerIdentityMatchesRequest {
    param([Parameter(Mandatory=$true)]$Identity, [Parameter(Mandatory=$true)]$Request)
    foreach ($field in @('artifactSourceHash','producerRecipeHash','toolchainLockHash','policyHash','buildIdentityHash')) {
        if ([string]$Identity.$field -ne [string]$Request.$field) { throw "Frozen checkout identity mismatch: $field" }
    }
}

function Quote-Cf7WorkerArgument {
    param([Parameter(Mandatory=$true)][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-Cf7WorkerProcess {
    param(
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][string[]]$Arguments,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [Parameter(Mandatory=$true)]$Lease
    )
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $FileName
    $info.Arguments = (($Arguments | ForEach-Object { Quote-Cf7WorkerArgument -Value ([string]$_) }) -join ' ')
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($info)
    try {
        $nextHeartbeat = [DateTime]::UtcNow.AddSeconds($HeartbeatSeconds)
        while (-not $process.WaitForExit(1000)) {
            if ([DateTime]::UtcNow -ge $nextHeartbeat) {
                Update-Cf7RuntimeRequestLease -Lease $Lease
                $nextHeartbeat = [DateTime]::UtcNow.AddSeconds($HeartbeatSeconds)
            }
        }
        if ($process.ExitCode -ne 0) { throw "Build command failed with exit code $($process.ExitCode)." }
    } finally { $process.Dispose() }
}

function Get-Cf7NextWorkerRequest {
    foreach ($directory in @(Get-ChildItem -LiteralPath (Join-Path $QueueRoot 'requests') -Directory | Sort-Object Name)) {
        if ($directory.Name.StartsWith('.')) { continue }
        try {
            $request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $directory.Name
            $state = Get-Cf7RuntimeBuildRequestState -QueueRoot $QueueRoot -Request $request -RegistryPath $RegistryPath
            if ($state.status -eq 'ready' -or $state.status -eq 'superseded') { continue }
            if ($workerKeyId) {
                $existingPath = Join-Path (Join-Path (Join-Path $QueueRoot 'results') ([string]$request.buildIdentityHash)) $workerKeyId
                $existingFile = Join-Path $existingPath 'result.json'
                if (Test-Path -LiteralPath $existingFile -PathType Leaf) {
                    try {
                        $existing = Read-Cf7QueueJson -Path $existingFile
                        Test-Cf7RuntimeBuildAttestationV2 -Attestation $existing.attestation -RegistryPath $RegistryPath | Out-Null
                        if ([string]$existing.attestation.payload.builderKeyId -eq $workerKeyId -and
                            [string]$existing.attestation.payload.buildIdentityHash -eq [string]$request.buildIdentityHash) { continue }
                    } catch { }
                }
            }
            return $request
        } catch {
            Write-Warning "Skipping invalid runtime request $($directory.Name): $($_.Exception.Message)"
        }
    }
    return $null
}

function Invoke-Cf7OneWorkerTurnCore {
    $request = Get-Cf7NextWorkerRequest
    if ($null -eq $request) { return $false }
    $lease = Try-EnterCf7RuntimeRequestLease -QueueRoot $QueueRoot -RequestId ([string]$request.requestId) -WorkerId $WorkerId -LeaseTtlSeconds $LeaseTtlSeconds
    if ($null -eq $lease) { return $false }
    $workerPhases = [ordered]@{ claimedAtUtc = [DateTime]::UtcNow.ToString('o') }
    $checkoutJobRoot = $null
    $candidate = $null
    try {
        # Re-read after claiming: a concurrent publisher/superseder may have completed it.
        $request = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId ([string]$request.requestId)
        $state = Get-Cf7RuntimeBuildRequestState -QueueRoot $QueueRoot -Request $request -RegistryPath $RegistryPath
        if ($state.status -eq 'ready' -or $state.status -eq 'superseded') { return $true }
        # Keep the materialized repository on a machine-local, short path.  The source bundle
        # may live on a shared queue, but checking CF7 out below the queue/repository path can
        # exceed Win32 MAX_PATH before the runtime producer even starts.
        $workerPathHash = Get-Cf7RuntimeV2TextSha256 -Text $WorkerId
        $checkoutName = '{0}-{1}-{2}' -f `
            ([string]$request.requestId).Substring(0,12).ToLowerInvariant(),
            $workerPathHash.Substring(0,10).ToLowerInvariant(),
            [Guid]::NewGuid().ToString('N').Substring(0,8)
        $checkoutJobRoot = [IO.Path]::GetFullPath((Join-Path $CheckoutRoot $checkoutName))
        if (-not $checkoutJobRoot.StartsWith($CheckoutRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe runtime checkout path: $checkoutJobRoot"
        }
        $candidateLeaf = New-Cf7RuntimeV2CandidateLeafName `
            -BuildIdentityHash ([string]$request.buildIdentityHash) -BuilderId $WorkerId
        $projectedRuntimeProbe = Join-Path $checkoutJobRoot `
            ('src\tmp\runtime-candidates\v2\' + $candidateLeaf + '\runtime\CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json')
        if ($projectedRuntimeProbe.Length -ge 260) {
            throw "CheckoutRoot exceeds the bootstrap MAX_PATH budget (projected=$($projectedRuntimeProbe.Length), maximum=259): $CheckoutRoot"
        }
        New-Item -ItemType Directory -Path $checkoutJobRoot -Force | Out-Null
        $checkout = Join-Path $checkoutJobRoot 'src'
        $bundle = Join-Path (Get-Cf7RuntimeRequestDirectory -QueueRoot $QueueRoot -RequestId ([string]$request.requestId)) 'source.bundle'
        Invoke-Cf7WorkerProcess -FileName 'git.exe' `
            -Arguments @('-c','core.longpaths=true','clone','--no-checkout','--',$bundle,$checkout) `
            -WorkingDirectory $checkoutJobRoot -Lease $lease
        # Freeze checkout bytes independently of the worker account's system/global Git
        # settings. Otherwise core.autocrlf=true can make Worktree identity disagree with
        # the immutable request even though every bundled Git blob is correct.
        Invoke-Cf7WorkerGit -Arguments @('-C',$checkout,'config','core.autocrlf','false') | Out-Null
        Invoke-Cf7WorkerGit -Arguments @('-C',$checkout,'config','core.longpaths','true') | Out-Null
        Invoke-Cf7WorkerGit -Arguments @('-c','core.longpaths=true','-C',$checkout,'checkout','--detach',([string]$request.requestCommitOid)) | Out-Null
        $treeOid = ([string](Invoke-Cf7WorkerGit -Arguments @('-C',$checkout,'rev-parse','HEAD^{tree}') | Select-Object -First 1)).Trim().ToLowerInvariant()
        $usesSparseBundle = $null -ne $request.PSObject.Properties['bundleTreeOid']
        $expectedBundleTree = if ($usesSparseBundle) {
            ([string]$request.bundleTreeOid).ToLowerInvariant()
        } else {
            # Legacy v1 requests carried the complete frozen release tree.
            ([string]$request.releaseTreeOid).ToLowerInvariant()
        }
        if ($treeOid -ne $expectedBundleTree) {
            throw 'Frozen checkout bundle tree does not match request.'
        }
        if ($usesSparseBundle) {
            Assert-Cf7WorkerSparseBundleTree -Root $checkout
        }
        $workerPhases.checkoutReadyAtUtc = [DateTime]::UtcNow.ToString('o')
        $identity = Get-Cf7WorkerV2Identity -Root $checkout
        Assert-Cf7WorkerIdentityMatchesRequest -Identity $identity -Request $request
        $workerPhases.identityVerifiedAtUtc = [DateTime]::UtcNow.ToString('o')
        Update-Cf7RuntimeRequestLease -Lease $lease
        if ($DryRun) {
            Write-Host "[RuntimeQueueWorker] DRY-RUN request=$($request.requestId) identity=$($request.buildIdentityHash)" -ForegroundColor Yellow
            return $true
        }
        $candidate = Join-Path $checkout ('tmp\runtime-candidates\v2\' + $candidateLeaf)
        if ($BuildCommand) {
            $extension = [IO.Path]::GetExtension($BuildCommand).ToLowerInvariant()
            if ($extension -eq '.ps1') {
                $hostExe = (Get-Process -Id $PID).Path
                Invoke-Cf7WorkerProcess -FileName $hostExe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',$BuildCommand,'-ProjectRoot',$checkout,'-CandidateRoot',$candidate,'-BuilderId',$WorkerId) -WorkingDirectory $checkout -Lease $lease
            } else {
                Invoke-Cf7WorkerProcess -FileName $BuildCommand -Arguments @('-ProjectRoot',$checkout,'-CandidateRoot',$candidate,'-BuilderId',$WorkerId) -WorkingDirectory $checkout -Lease $lease
            }
        } else {
            $hostExe = (Get-Process -Id $PID).Path
            Invoke-Cf7WorkerProcess -FileName $hostExe -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $checkout 'launcher\build-runtime-candidate.ps1'),'-BuilderId',$WorkerId,'-CandidateRoot',$candidate) -WorkingDirectory $checkout -Lease $lease
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw 'Build command did not create the requested candidate root.' }
        $workerPhases.buildFinishedAtUtc = [DateTime]::UtcNow.ToString('o')
        # Post-build identity proof. The pinned producer writes its post-build four-domain
        # identity into the candidate metadata after its own input-drift re-check, so compare
        # that evidence field by field against the immutable request instead of blindly
        # trusting it; any mismatch fails closed. A custom BuildCommand that does not emit v2
        # metadata keeps the full worktree recomputation.
        $after = $null
        $candidateMetadataPath = Join-Path $candidate 'runtime-build-metadata.v2.json'
        if (-not $BuildCommand -and (Test-Path -LiteralPath $candidateMetadataPath -PathType Leaf)) {
            $candidateMetadata = $null
            try { $candidateMetadata = Get-Content -LiteralPath $candidateMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $candidateMetadata = $null }
            if ($null -ne $candidateMetadata -and [string]$candidateMetadata.schema -eq 'cf7-runtime-candidate-metadata.v2') {
                $after = [pscustomobject]@{
                    artifactSourceHash=[string]$candidateMetadata.artifactSourceHash
                    producerRecipeHash=[string]$candidateMetadata.producerRecipeHash
                    toolchainLockHash=[string]$candidateMetadata.toolchainLockHash
                    policyHash=[string]$candidateMetadata.policyHash
                    buildIdentityHash=[string]$candidateMetadata.buildIdentityHash
                }
            }
        }
        if ($null -eq $after) { $after = Get-Cf7WorkerV2Identity -Root $checkout }
        Assert-Cf7WorkerIdentityMatchesRequest -Identity $after -Request $request
        Update-Cf7RuntimeRequestLease -Lease $lease
        $attestation = New-Cf7RuntimeBuildAttestationV2 -ProjectRoot $checkout -DeploymentRoot $candidate -CertificateThumbprint $CertificateThumbprint -RegistryPath $RegistryPath -ExpectedIdentity $request
        Test-Cf7RuntimeBuildAttestationV2 -Attestation $attestation -RegistryPath $RegistryPath | Out-Null
        $result = Publish-Cf7RuntimeProducerResult -QueueRoot $QueueRoot -ProjectRoot $checkout -Request $request -Attestation $attestation -CandidateRoot $candidate -RegistryPath $RegistryPath
        $workerPhases.resultPublishedAtUtc = [DateTime]::UtcNow.ToString('o')
        try {
            # Observability sidecar only; the queue result/attestation records stay canonical.
            $workerPhaseRecord = [pscustomobject]@{
                schema = 'cf7-runtime-worker-phases.v1'
                requestId = [string]$request.requestId
                workerId = $WorkerId
                claimedAtUtc = [string]$workerPhases.claimedAtUtc
                checkoutReadyAtUtc = [string]$workerPhases.checkoutReadyAtUtc
                identityVerifiedAtUtc = [string]$workerPhases.identityVerifiedAtUtc
                buildFinishedAtUtc = [string]$workerPhases.buildFinishedAtUtc
                resultPublishedAtUtc = [string]$workerPhases.resultPublishedAtUtc
                totalSeconds = [Math]::Round(([DateTime]::Parse([string]$workerPhases.resultPublishedAtUtc).ToUniversalTime() - [DateTime]::Parse([string]$workerPhases.claimedAtUtc).ToUniversalTime()).TotalSeconds, 3)
            }
            $workerPhasePath = Join-Path (Join-Path (Join-Path $QueueRoot 'results\_phases') ([string]$request.requestId)) `
                ('worker-' + $WorkerId.Substring(0, [Math]::Min(24, $WorkerId.Length)) + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 16) + '.json')
            Write-Cf7QueueJsonAtomic -Path $workerPhasePath -Value $workerPhaseRecord
        } catch {
            Write-Warning "Could not persist runtime worker phase timings: $($_.Exception.Message)"
        }
        Write-Host "[RuntimeQueueWorker] OK request=$($request.requestId) signer=$($result.builderKeyId) closure=$($result.payloadClosureHash)" -ForegroundColor Green
        return $true
    } catch {
        $failureMessage = [string]$_.Exception.Message
        $diagnosticRoot = if ($candidate) { Join-Path $candidate 'logs' } else { $null }
        try {
            Write-Cf7RuntimeBuildFailure -QueueRoot $QueueRoot -Request $request -WorkerId $WorkerId `
                -Message $failureMessage -DiagnosticRoot $diagnosticRoot
        } catch {
            # Failure persistence is diagnostic, not authority. A long/unavailable queue
            # path must never replace the original build error with a secondary write error.
            Write-Warning "Could not persist runtime build failure for request $($request.requestId): $($_.Exception.Message)"
        }
        $script:workerHadFailure = $true
        Write-Warning "Runtime build request failed: $failureMessage"
        return $false
    } finally {
        Exit-Cf7RuntimeRequestLease -Lease $lease
        if ($checkoutJobRoot) {
            $resolvedCheckout = [IO.Path]::GetFullPath($checkoutJobRoot)
            if ($resolvedCheckout.StartsWith($CheckoutRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and
                    (Test-Path -LiteralPath $resolvedCheckout -PathType Container)) {
                try { Remove-Cf7LocalDirectoryTree -Path $resolvedCheckout -AllowedRoot $CheckoutRoot }
                catch { Write-Warning "Could not clean runtime checkout $resolvedCheckout`: $($_.Exception.Message)" }
            }
        }
    }
}

function Invoke-Cf7OneWorkerTurn {
    # A worker materializes an independent repository. Inheriting a caller's alternate
    # index/worktree/object environment can make Git compare the clone against unrelated
    # state (or even borrow objects that are absent from source.bundle). Keep every Git and
    # producer child process bound only to paths explicitly passed by this worker.
    $gitEnvironmentNames = @(
        'GIT_INDEX_FILE','GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR',
        'GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE',
        'GIT_PREFIX','GIT_CONFIG_COUNT'
    )
    $savedGitEnvironment = @{}
    foreach ($name in $gitEnvironmentNames) {
        $savedGitEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    try {
        return Invoke-Cf7OneWorkerTurnCore
    } finally {
        foreach ($name in $gitEnvironmentNames) {
            [Environment]::SetEnvironmentVariable($name, $savedGitEnvironment[$name], 'Process')
        }
    }
}

function Find-Cf7OrphanedWorkerCheckouts {
    # Report-only residue sweep. A worker that was killed mid-build (power loss, kill -9)
    # cannot record its own failure, so a leftover checkout job directory with no result,
    # no failure record, and no live lease is surfaced for a human. This never deletes
    # anything: cleanup of orphaned residue stays a deliberate operator action.
    if (-not (Test-Path -LiteralPath $CheckoutRoot -PathType Container)) { return }
    $requestsRoot = Join-Path $QueueRoot 'requests'
    foreach ($directory in @(Get-ChildItem -LiteralPath $CheckoutRoot -Directory -ErrorAction SilentlyContinue)) {
        try {
            if ($directory.Name -cnotmatch '^[0-9a-f]{12}-[0-9a-f]{10}-[0-9a-f]{8}$') { continue }
            $requestPrefix = $directory.Name.Substring(0, 12)
            $requestDirs = @(Get-ChildItem -LiteralPath $requestsRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name.StartsWith($requestPrefix, [StringComparison]::OrdinalIgnoreCase) })
            if ($requestDirs.Count -eq 0) {
                Write-Host "[RuntimeQueueWorker] Orphaned checkout residue (no request with prefix $requestPrefix): $($directory.FullName)" -ForegroundColor Yellow
                continue
            }
            $orphanRequestId = $requestDirs[0].Name
            $leaseDirectory = Join-Path (Join-Path $QueueRoot 'leases') $orphanRequestId
            if ((Test-Path -LiteralPath $leaseDirectory -PathType Container) -and
                    -not (Test-Cf7LeaseExpired -LeaseDirectory $leaseDirectory)) { continue }
            $hasOutcome = $false
            $failureRoot = Join-Path (Join-Path $QueueRoot 'results\_failures') $orphanRequestId
            if (Test-Path -LiteralPath $failureRoot -PathType Container) {
                $hasOutcome = @(Get-ChildItem -LiteralPath $failureRoot -Filter 'failure.json' -File -Recurse -ErrorAction SilentlyContinue).Count -gt 0
            }
            if (-not $hasOutcome) {
                try {
                    $orphanRequest = Read-Cf7RuntimeBuildRequest -QueueRoot $QueueRoot -RequestId $orphanRequestId
                    $orphanResultsRoot = Join-Path (Join-Path $QueueRoot 'results') ([string]$orphanRequest.buildIdentityHash).ToUpperInvariant()
                    if (Test-Path -LiteralPath $orphanResultsRoot -PathType Container) {
                        $hasOutcome = @(Get-ChildItem -LiteralPath $orphanResultsRoot -Filter 'result.json' -File -Recurse -ErrorAction SilentlyContinue).Count -gt 0
                    }
                } catch { }
            }
            if (-not $hasOutcome) {
                Write-Host "[RuntimeQueueWorker] Orphaned checkout residue (request $orphanRequestId has no result/failure and no live lease): $($directory.FullName)" -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "Could not inspect runtime checkout residue $($directory.FullName): $($_.Exception.Message)"
        }
    }
}

$mutex = Enter-Cf7RuntimeWorkerMutex -WorkerId $WorkerId
if ($null -eq $mutex) { throw "A runtime build worker is already active for WorkerId=$WorkerId" }
try {
    try { Find-Cf7OrphanedWorkerCheckouts } catch { Write-Warning "Orphaned checkout sweep failed: $($_.Exception.Message)" }
    do {
        $handled = Invoke-Cf7OneWorkerTurn
        if ($Once) { break }
        if (-not $handled) { Start-Sleep -Seconds $PollSeconds }
    } while ($Watch)
} finally { Exit-Cf7RuntimeWorkerMutex -Mutex $mutex }
if ($Once -and $workerHadFailure) { exit 1 }
