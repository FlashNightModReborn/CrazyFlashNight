param(
    [string]$ProjectRoot,
    [string]$TestTempRoot = $env:CF7_RUNTIME_TEST_TEMP_ROOT
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
. (Join-Path $ProjectRoot 'tools\runtime-build-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-v2-common.ps1')
. (Join-Path $ProjectRoot 'tools\runtime-build-queue-common.ps1')

function Assert-QueueTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "Runtime queue test failed: $Message" }
}

if ([string]::IsNullOrWhiteSpace($TestTempRoot)) {
    $TestTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
}
$TestTempRoot = [IO.Path]::GetFullPath($TestTempRoot).TrimEnd('\')
$testFilesystemRoot = [IO.Path]::GetPathRoot($TestTempRoot)
if ($TestTempRoot.StartsWith('\\', [StringComparison]::Ordinal) -or
        $TestTempRoot.Equals($testFilesystemRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Runtime queue tests require a dedicated machine-local temp directory, not UNC or a filesystem root.'
}
New-Item -ItemType Directory -Path $TestTempRoot -Force | Out-Null
$testRoot = [IO.Path]::GetFullPath((Join-Path $TestTempRoot ('rq-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)))).TrimEnd('\')
if (-not $testRoot.StartsWith($TestTempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe runtime queue test path.' }
$fixtureName = 'QueueFreezeFixture.cs'
$fixtureRepo = Join-Path $testRoot 'repo'
$fixturePath = Join-Path $fixtureRepo ('launcher\src\' + $fixtureName)
$checks = 0
$originalGitIndexFile = $env:GIT_INDEX_FILE
$customIndex = $null
$externalCheckoutRoots = New-Object 'System.Collections.Generic.List[string]'
$externalQueueRoots = New-Object 'System.Collections.Generic.List[string]'
$shortQueueParent = Join-Path $testFilesystemRoot 'tmp'
New-Item -ItemType Directory -Path $shortQueueParent -Force | Out-Null

function New-ShortQueueTestRoot([string]$Prefix) {
    if ($Prefix -notmatch '^[a-z]$') { throw 'Short queue test prefix must be one lowercase letter.' }
    while ($true) {
        $candidate = Join-Path $shortQueueParent ($Prefix + [Guid]::NewGuid().ToString('N').Substring(0, 4))
        try {
            New-Item -ItemType Directory -Path $candidate -ErrorAction Stop | Out-Null
            break
        } catch {
            if (Test-Path -LiteralPath $candidate) { continue }
            throw
        }
    }
    $externalQueueRoots.Add($candidate)
    Assert-Cf7RuntimeQueuePathBudget -QueueRoot $candidate
    return $candidate
}

$fileBoundaryRoot = Join-Path $shortQueueParent 'q1234'
Assert-Cf7RuntimeQueuePathBudget -QueueRoot $fileBoundaryRoot
$fileBoundaryRejected = $false
try { Assert-Cf7RuntimeQueuePathBudget -QueueRoot (Join-Path $shortQueueParent 'q12345') }
catch { $fileBoundaryRejected = $_.Exception.Message.Contains('runtime build MAX_PATH budget') }
Assert-QueueTest $fileBoundaryRejected 'QueueRoot file boundary did not accept 259 and reject 260 characters'

$hash = 'A' * 64
$casPayloadPrefix = Join-Path $fileBoundaryRoot ("cas\candidates\$hash\$hash")
$acceptedParentSegmentLength = 247 - $casPayloadPrefix.Length - 1
if ($acceptedParentSegmentLength -lt 1) { throw 'Cannot construct the runtime queue parent-path boundary fixture.' }
Assert-Cf7RuntimeQueuePathBudget -QueueRoot $fileBoundaryRoot `
    -PayloadRelativePath ((('p' * $acceptedParentSegmentLength) + '/x'))
$parentBoundaryRejected = $false
try {
    Assert-Cf7RuntimeQueuePathBudget -QueueRoot $fileBoundaryRoot `
        -PayloadRelativePath ((('p' * ($acceptedParentSegmentLength + 1)) + '/x'))
} catch { $parentBoundaryRejected = $_.Exception.Message.Contains('directory MAX_PATH budget') }
Assert-QueueTest $parentBoundaryRejected 'QueueRoot parent boundary did not accept 247 and reject 248 characters'

if (Test-Path -LiteralPath $testRoot) { Remove-Cf7LocalDirectoryTree -Path $testRoot -AllowedRoot $TestTempRoot }
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    # Keep the sparse bundle declaration aligned with every repository input that the real
    # producer executes or reads. This deliberately calls out the bootstrap verifier boundary:
    # both bootstrap sources and the pure producer script must be present in the bundle closure.
    $artifactInputs = @(Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain artifactSource -Mode Worktree)
    $recipeInputs = @(Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain producerRecipe -Mode Worktree)
    $toolchainInputs = @(Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain toolchainLock -Mode Worktree)
    $policyInputs = @(Get-Cf7RuntimeV2DomainFiles -ProjectRoot $ProjectRoot -Domain policy -Mode Worktree)
    $bundleInputSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($path in @($artifactInputs + $recipeInputs + $toolchainInputs + $policyInputs)) {
        [void]$bundleInputSet.Add(([string]$path).Replace('\','/'))
    }
    foreach ($required in @(
        'config/build/runtime-inputs.v2.json', 'config/build/runtime-toolchain.lock.json', 'global.json',
        'launcher/CRAZYFLASHER7MercenaryEmpire.csproj', 'launcher/Directory.Packages.props', 'launcher/packages.lock.json',
        'launcher/app.ico', 'launcher/app.manifest', 'launcher/build-runtime-candidate.ps1',
        'launcher/native/assert-pinned-tools.bat', 'launcher/native/build.bat',
        'launcher/native/bootstrap/build.bat', 'launcher/native/bootstrap/bootstrap.cpp',
        'launcher/native/bootstrap/bootstrap.rc', 'launcher/native/sol_parser/.cargo/config.toml',
        'launcher/native/sol_parser/build.bat',
        'launcher/native/sol_parser/Cargo.toml', 'launcher/native/sol_parser/Cargo.lock',
        'launcher/native/sol_parser/rust-toolchain.toml', 'tools/check-runtime-build-env.ps1',
        'tools/runtime-build-v2-common.ps1'
    )) {
        Assert-QueueTest ($bundleInputSet.Contains($required)) "real producer dependency is absent from the sparse bundle declaration: $required"
    }
    $artifactSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($path in $artifactInputs) { [void]$artifactSet.Add(([string]$path).Replace('\','/')) }
    foreach ($source in @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'launcher\src') -Recurse -File -Filter '*.cs')) {
        $relative = $source.FullName.Substring($ProjectRoot.Length + 1).Replace('\','/')
        if ($relative -eq 'launcher/src/Guardian/HotkeyGuard.cs') { continue }
        Assert-QueueTest ($artifactSet.Contains($relative)) "managed compile input is outside artifactSource: $relative"
    }
    foreach ($source in @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'launcher\native') -Recurse -File | Where-Object {
        @('.c','.cpp','.h','.rc') -contains $_.Extension.ToLowerInvariant()
    })) {
        $relative = $source.FullName.Substring($ProjectRoot.Length + 1).Replace('\','/')
        Assert-QueueTest ($artifactSet.Contains($relative)) "native compile input is outside artifactSource: $relative"
    }
    foreach ($source in @(Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'launcher\native\sol_parser\src') -Recurse -File -Filter '*.rs')) {
        $relative = $source.FullName.Substring($ProjectRoot.Length + 1).Replace('\','/')
        Assert-QueueTest ($artifactSet.Contains($relative)) "Rust compile input is outside artifactSource: $relative"
    }
    $checks++

    # A small independent repository keeps the self-contained bundle test fast and proves that
    # no objects or worktree state are borrowed from the developer's repository.
    foreach ($directory in @('tools','config\build','launcher\src')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRepo $directory) -Force | Out-Null
    }
    foreach ($name in @('runtime-build-common.ps1','runtime-build-v2-common.ps1','runtime-build-attestation-v2-common.ps1','runtime-build-queue-common.ps1','verify-runtime-bundle-v2.ps1')) {
        Copy-Item -LiteralPath (Join-Path (Join-Path $ProjectRoot 'tools') $name) -Destination (Join-Path (Join-Path $fixtureRepo 'tools') $name)
    }
    $encoding = New-Object Text.UTF8Encoding($false)
    $fixtureConfig = @'
{
  "schema": "cf7-runtime-inputs.v2",
  "domains": {
    "artifactSource": { "fixedFiles": ["launcher/src/QueueFreezeFixture.cs"], "trees": [] },
    "producerRecipe": { "fixedFiles": ["tools/runtime-build-v2-common.ps1"], "trees": [] },
    "toolchainLock": { "fixedFiles": ["config/build/toolchain.txt", "config/build/冻结输入.txt"], "trees": [] },
    "policy": { "fixedFiles": ["config/build/runtime-inputs.v2.json", "tools/runtime-build-queue-common.ps1"], "trees": [] }
  },
  "payload": {
    "fixedRoots": ["CRAZYFLASHER7MercenaryEmpire.exe"], "trees": ["runtime"],
    "excludePaths": ["runtime/cf7-runtime-manifest.tsv"], "excludePrefixes": []
  }
}
'@
    [IO.File]::WriteAllText((Join-Path $fixtureRepo 'config\build\runtime-inputs.v2.json'), $fixtureConfig + "`n", $encoding)
    [IO.File]::WriteAllText((Join-Path $fixtureRepo 'config\build\toolchain.txt'), 'queue-toolchain' + "`n", $encoding)
    [IO.File]::WriteAllText((Join-Path $fixtureRepo 'config\build\冻结输入.txt'), 'unicode-path-fixture' + "`n", $encoding)
    [IO.File]::WriteAllText($fixturePath, 'internal static class QueueFreezeFixture { internal const string Value = "base"; }' + "`n", $encoding)
    # Model the real repository's text normalization explicitly. Without this file, copying a
    # CRLF PowerShell helper into a core.autocrlf=false fixture stores a CRLF blob, while the
    # worker's independent clone may clean it as LF under machine-level Git configuration.
    [IO.File]::WriteAllText((Join-Path $fixtureRepo '.gitattributes'), "* text=auto`n", $encoding)
    & git -C $fixtureRepo init -q
    & git -C $fixtureRepo config user.name 'CF7 Queue Test'
    & git -C $fixtureRepo config user.email 'queue-test@invalid.local'
    & git -C $fixtureRepo config core.autocrlf false
    & git -C $fixtureRepo config core.longpaths true
    # Reproduce the Git default that exposed the real failure, regardless of a
    # maintainer or CI image overriding core.quotepath globally.
    & git -C $fixtureRepo config core.quotepath true
    if ($LASTEXITCODE -ne 0) { throw 'Cannot pin core.quotepath for the Unicode queue fixture.' }
    & git -C $fixtureRepo add -A
    # Store one path that exceeds MAX_PATH once the fixture is cloned below the queue.  It is
    # deliberately outside every runtime identity domain: the assertion is that a worker can
    # materialize a real CF7-shaped repository before selecting the much smaller build inputs.
    $longRelativePath = 'assets/' + ((1..5 | ForEach-Object { 'long-' + ('x' * 45) }) -join '/') + '/marker.txt'
    $longBlob = ('long-path-fixture' | & git -C $fixtureRepo hash-object -w --stdin).Trim()
    & git -C $fixtureRepo update-index --add --cacheinfo "100644,$longBlob,$longRelativePath"
    if ($LASTEXITCODE -ne 0) { throw 'Cannot add long-path queue fixture blob.' }
    & git -C $fixtureRepo commit -q -m 'queue fixture base'
    if ($LASTEXITCODE -ne 0) { throw 'Cannot initialize runtime queue fixture repository.' }

    [IO.File]::WriteAllText($fixturePath, 'internal static class QueueFreezeFixture { internal const string Value = "staged-v1"; }' + "`n", $encoding)
    & git -C $fixtureRepo add -- ('launcher/src/' + $fixtureName)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot stage runtime queue fixture.' }
    [IO.File]::WriteAllText($fixturePath, 'internal static class QueueFreezeFixture { internal const string Value = "worktree-v2"; }' + "`n", $encoding)

    # Exercise request creation while the caller already owns a non-default Git index. The
    # helper must use that index for Index snapshots and restore it after both success/failure.
    $gitDirectory = ([string](& git -C $fixtureRepo rev-parse --absolute-git-dir)).Trim()
    $customIndex = Join-Path $testRoot 'caller-owned.index'
    Copy-Item -LiteralPath (Join-Path $gitDirectory 'index') -Destination $customIndex
    $env:GIT_INDEX_FILE = $customIndex

    $queueRoot = New-ShortQueueTestRoot -Prefix 'q'
    $newRequestScript = Join-Path $ProjectRoot 'tools\new-runtime-build-request.ps1'
    $longQueueRoot = Join-Path $testRoot ('queue-' + ('x' * 96))
    $longQueueRequestFailed = $false
    try { & $newRequestScript -ProjectRoot $fixtureRepo -QueueRoot $longQueueRoot -SourceKind Index | Out-Null }
    catch {
        $longQueueRequestFailed = $_.Exception.Message.Contains('QueueRoot exceeds the runtime build MAX_PATH budget')
    }
    Assert-QueueTest $longQueueRequestFailed 'request creation did not reject an over-budget QueueRoot before materialization'
    Assert-QueueTest (-not (Test-Path -LiteralPath $longQueueRoot)) 'over-budget request created queue state before failing'

    $workerScript = Join-Path $ProjectRoot 'tools\invoke-runtime-build-worker.ps1'
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $workerOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workerScript `
            -ProjectRoot $ProjectRoot -QueueRoot $longQueueRoot -WorkerId 'queue-path-budget-test' `
            -CertificateThumbprint ('0' * 40) -Once -DryRun 2>&1)
        $workerExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    Assert-QueueTest ($workerExitCode -ne 0) 'worker accepted an over-budget QueueRoot'
    Assert-QueueTest (($workerOutput -join "`n").Contains('QueueRoot exceeds the runtime build MAX_PATH budget')) `
        'worker did not fail at the QueueRoot path-budget gate'
    Assert-QueueTest (-not (Test-Path -LiteralPath $longQueueRoot)) 'over-budget worker created queue state before failing'

    $requestA = & $newRequestScript -ProjectRoot $fixtureRepo -QueueRoot $queueRoot -SourceKind Index
    $requestB = & $newRequestScript -ProjectRoot $fixtureRepo -QueueRoot $queueRoot -SourceKind Index
    Assert-QueueTest ([string]$requestA.schema -eq 'cf7-runtime-build-request.v2') 'sparse request did not use the v2 schema'
    Assert-QueueTest ([string]$env:GIT_INDEX_FILE -ceq $customIndex) 'request creation did not restore the caller-owned Git index'
    Assert-QueueTest ($requestA.requestId -eq $requestB.requestId) 'identical release tree + policy was not deduplicated'
    $requestDirectories = @(Get-ChildItem -LiteralPath (Join-Path $queueRoot 'requests') -Directory | Where-Object { -not $_.Name.StartsWith('.') })
    Assert-QueueTest ($requestDirectories.Count -eq 1) 'deduplicated request created more than one immutable directory'
    $checks++

    $clone = Join-Path $testRoot 'frozen-clone'
    # The caller-owned index belongs to fixtureRepo. It must remain visible to the request
    # creator, but must not leak into an independent clone: Git would otherwise consult that
    # external index and incorrectly decide the clone worktree already has every file.
    $savedCallerIndex = $env:GIT_INDEX_FILE
    try {
        $env:GIT_INDEX_FILE = $null
        $ErrorActionPreference = 'Continue'
        & git -c core.longpaths=true clone --no-checkout -- (Join-Path $requestDirectories[0].FullName 'source.bundle') $clone 2>&1 | Out-Null
        $cloneExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($cloneExitCode -ne 0) { throw 'Cannot clone request test bundle.' }
        $ErrorActionPreference = 'Continue'
        & git -c core.longpaths=true -C $clone checkout --detach ([string]$requestA.requestCommitOid) 2>&1 | Out-Null
        $checkoutExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($checkoutExitCode -ne 0) { throw 'Cannot checkout request test commit.' }
        $frozenBundlePaths = @(& git -c core.quotepath=false -C $clone ls-tree -r --name-only 'HEAD^{tree}')
        Assert-QueueTest ($frozenBundlePaths -contains ('launcher/src/' + $fixtureName)) `
            "synthetic bundle omitted the staged artifactSource fixture; paths=$($frozenBundlePaths -join ',')"
        Assert-QueueTest ($frozenBundlePaths -ccontains 'config/build/冻结输入.txt') `
            "synthetic bundle did not preserve a literal non-ASCII domain path; paths=$($frozenBundlePaths -join ',')"
        $frozenText = [IO.File]::ReadAllText((Join-Path $clone ('launcher\src\' + $fixtureName)))
        Assert-QueueTest ($frozenText.Contains('staged-v1') -and -not $frozenText.Contains('worktree-v2')) 'request did not freeze Git index bytes'
        $clonedBundleTree = ([string](& git -C $clone rev-parse 'HEAD^{tree}')).Trim()
        Assert-QueueTest ($clonedBundleTree -eq [string]$requestA.bundleTreeOid) 'bundle tree identity mismatch'
        Assert-QueueTest ($clonedBundleTree -ne [string]$requestA.releaseTreeOid) 'request bundle unexpectedly materialized the full release tree'
        Assert-QueueTest (-not (Test-Path -LiteralPath (Join-Path $clone ($longRelativePath -replace '/', '\')))) `
            'request bundle carried an unrelated long-path asset'
        Assert-QueueTest ((Get-Item -LiteralPath (Join-Path $requestDirectories[0].FullName 'source.bundle')).Length -lt 1MB) `
            'runtime request bundle was not reduced to the declared identity domains'
    } finally {
        $env:GIT_INDEX_FILE = $savedCallerIndex
        $ErrorActionPreference = 'Stop'
    }
    Assert-QueueTest ([string]$env:GIT_INDEX_FILE -ceq $customIndex) 'independent clone verification leaked the caller-owned Git index'
    $checks++

    $treeRequest = & $newRequestScript -ProjectRoot $fixtureRepo -QueueRoot $queueRoot -SourceKind Treeish -Treeish HEAD
    Assert-QueueTest ([string]$env:GIT_INDEX_FILE -ceq $customIndex) 'Treeish request creation leaked its temporary Git index'
    $fixtureHead = ([string](& git -C $fixtureRepo rev-parse 'HEAD^{commit}')).Trim()
    $fixtureHeadTree = ([string](& git -C $fixtureRepo rev-parse 'HEAD^{tree}')).Trim()
    Assert-QueueTest ($treeRequest.sourceCommitOid -eq $fixtureHead -and $treeRequest.releaseTreeOid -eq $fixtureHeadTree) 'Treeish request did not freeze the selected commit tree'
    Assert-QueueTest ($treeRequest.requestId -ne $requestA.requestId) 'different release trees were incorrectly deduplicated'
    $checks++

    $badTreeFailed = $false
    try { & $newRequestScript -ProjectRoot $fixtureRepo -QueueRoot $queueRoot -SourceKind Treeish -Treeish 'refs/heads/does-not-exist' | Out-Null }
    catch { $badTreeFailed = $true }
    Assert-QueueTest $badTreeFailed 'invalid Treeish unexpectedly produced a request'
    Assert-QueueTest ([string]$env:GIT_INDEX_FILE -ceq $customIndex) 'failed request creation leaked its temporary Git index'
    Assert-QueueTest (@(Get-ChildItem -LiteralPath (Join-Path $queueRoot 'requests') -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\.(identity|bundle)\.' }).Count -eq 0) 'failed request creation left a temporary Git index'
    $checks++

    $requestJsonPath = Join-Path $requestDirectories[0].FullName 'request.json'
    $requestJsonBytes = [IO.File]::ReadAllBytes($requestJsonPath)
    try {
        $poisoned = [Text.Encoding]::UTF8.GetString($requestJsonBytes) | ConvertFrom-Json
        $poisoned.producerRecipeHash = ('0' * 64)
        Write-Cf7QueueUtf8File -Path $requestJsonPath -Text (($poisoned | ConvertTo-Json -Depth 8) + "`n")
        $collisionFailed = $false
        try { & $newRequestScript -ProjectRoot $fixtureRepo -QueueRoot $queueRoot -SourceKind Index | Out-Null }
        catch { $collisionFailed = $true }
        Assert-QueueTest $collisionFailed 'an existing request directory with a different frozen identity was reused'
    } finally {
        [IO.File]::WriteAllBytes($requestJsonPath, $requestJsonBytes)
    }
    $checks++

    # Preserve compatibility with already-published v1 requests: those bundles materialized the
    # complete release tree and therefore have no bundleTreeOid. Also use that full bundle as an
    # adversarial v2 fixture; a sparse v2 worker must reject its undeclared extra paths even when
    # every four-domain identity hash still matches.
    $fullBundle = Join-Path $testRoot 'legacy-full-source.bundle'
    $fullBundleRef = 'refs/heads/cf7-queue-legacy-fixture-' + [Guid]::NewGuid().ToString('N')
    & git -C $fixtureRepo update-ref $fullBundleRef $fixtureHead
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create legacy queue fixture ref.' }
    try {
        & git -C $fixtureRepo bundle create $fullBundle $fullBundleRef
        if ($LASTEXITCODE -ne 0) { throw 'Cannot create legacy full-tree queue bundle.' }
    } finally {
        & git -C $fixtureRepo update-ref -d $fullBundleRef 2>$null
    }
    $createdAt = [DateTime]::UtcNow.ToString('o')
    $legacyQueue = New-ShortQueueTestRoot -Prefix 'l'
    Initialize-Cf7RuntimeQueue -QueueRoot $legacyQueue
    $legacyDirectory = Get-Cf7RuntimeRequestDirectory -QueueRoot $legacyQueue -RequestId ([string]$treeRequest.requestId)
    New-Item -ItemType Directory -Path $legacyDirectory -Force | Out-Null
    Copy-Item -LiteralPath $fullBundle -Destination (Join-Path $legacyDirectory 'source.bundle')
    $legacyRequest = [pscustomobject][ordered]@{
        schema='cf7-runtime-build-request.v1'; requestId=[string]$treeRequest.requestId; sourceKind='Treeish'
        releaseTreeOid=$fixtureHeadTree; sourceCommitOid=$fixtureHead; requestCommitOid=$fixtureHead
        artifactSourceHash=[string]$treeRequest.artifactSourceHash; producerRecipeHash=[string]$treeRequest.producerRecipeHash
        toolchainLockHash=[string]$treeRequest.toolchainLockHash; policyHash=[string]$treeRequest.policyHash
        buildIdentityHash=[string]$treeRequest.buildIdentityHash; bundleFile='source.bundle'
        bundleSha256=Get-Cf7QueueFileSha256 -Path (Join-Path $legacyDirectory 'source.bundle')
        requiredQuorum=2; createdAtUtc=$createdAt
    }
    Write-Cf7QueueUtf8File -Path (Join-Path $legacyDirectory 'request.json') -Text (($legacyRequest | ConvertTo-Json -Depth 8) + "`n")
    $legacyRead = Read-Cf7RuntimeBuildRequest -QueueRoot $legacyQueue -RequestId ([string]$legacyRequest.requestId)
    Assert-QueueTest ([string]$legacyRead.schema -eq 'cf7-runtime-build-request.v1') 'legacy full-tree request schema was not accepted'
    $workerScript = Join-Path $ProjectRoot 'tools\invoke-runtime-build-worker.ps1'
    $legacyCheckoutRoot = Join-Path $TestTempRoot ('qL-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    $externalCheckoutRoots.Add($legacyCheckoutRoot)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $legacyOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workerScript `
        -ProjectRoot $fixtureRepo -QueueRoot $legacyQueue -CheckoutRoot $legacyCheckoutRoot `
        -WorkerId 'legacy-queue-worker' -Once -DryRun -LeaseTtlSeconds 30 -HeartbeatSeconds 2 2>&1)
    $legacyExit = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    Assert-QueueTest ($legacyExit -eq 0) "legacy full-tree worker request failed: $($legacyOutput -join ' ')"
    Assert-QueueTest (@(Get-ChildItem -LiteralPath $legacyCheckoutRoot -Force -ErrorAction SilentlyContinue).Count -eq 0) `
        'legacy worker did not clean its short-path checkout'
    $checks++

    $undeclaredQueue = New-ShortQueueTestRoot -Prefix 'u'
    Initialize-Cf7RuntimeQueue -QueueRoot $undeclaredQueue
    $undeclaredDirectory = Get-Cf7RuntimeRequestDirectory -QueueRoot $undeclaredQueue -RequestId ([string]$treeRequest.requestId)
    New-Item -ItemType Directory -Path $undeclaredDirectory -Force | Out-Null
    Copy-Item -LiteralPath $fullBundle -Destination (Join-Path $undeclaredDirectory 'source.bundle')
    $undeclaredRequest = [pscustomobject][ordered]@{
        schema='cf7-runtime-build-request.v2'; requestId=[string]$treeRequest.requestId; sourceKind='Treeish'
        releaseTreeOid=$fixtureHeadTree; sourceCommitOid=$fixtureHead; requestCommitOid=$fixtureHead; bundleTreeOid=$fixtureHeadTree
        artifactSourceHash=[string]$treeRequest.artifactSourceHash; producerRecipeHash=[string]$treeRequest.producerRecipeHash
        toolchainLockHash=[string]$treeRequest.toolchainLockHash; policyHash=[string]$treeRequest.policyHash
        buildIdentityHash=[string]$treeRequest.buildIdentityHash; bundleFile='source.bundle'
        bundleSha256=Get-Cf7QueueFileSha256 -Path (Join-Path $undeclaredDirectory 'source.bundle')
        requiredQuorum=2; createdAtUtc=$createdAt
    }
    Write-Cf7QueueUtf8File -Path (Join-Path $undeclaredDirectory 'request.json') -Text (($undeclaredRequest | ConvertTo-Json -Depth 8) + "`n")
    $undeclaredCheckoutRoot = Join-Path $TestTempRoot ('qR-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    $externalCheckoutRoots.Add($undeclaredCheckoutRoot)
    $ErrorActionPreference = 'Continue'
    $undeclaredOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workerScript `
        -ProjectRoot $fixtureRepo -QueueRoot $undeclaredQueue -CheckoutRoot $undeclaredCheckoutRoot `
        -WorkerId 'undeclared-queue-worker' -Once -DryRun -LeaseTtlSeconds 30 -HeartbeatSeconds 2 2>&1)
    $undeclaredExit = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    Assert-QueueTest ($undeclaredExit -ne 0) 'v2 worker accepted undeclared full-tree paths outside the four-domain sparse closure'
    Assert-QueueTest (($undeclaredOutput -join "`n") -match 'undeclared or missing paths|path closure mismatch') `
        'v2 worker failed for an unexpected reason instead of the sparse path closure'
    Assert-QueueTest (@(Get-ChildItem -LiteralPath $undeclaredCheckoutRoot -Force -ErrorAction SilentlyContinue).Count -eq 0) `
        'rejected v2 worker did not clean its short-path checkout'
    $checks++

    # A secondary queue-write failure must not replace the original worker diagnosis. A regular
    # file at the request's failure-directory path deterministically blocks diagnostic persistence
    # on PowerShell 5/7 and regardless of the host's LongPathsEnabled setting.
    $failureMaskQueue = New-ShortQueueTestRoot -Prefix 'f'
    Initialize-Cf7RuntimeQueue -QueueRoot $failureMaskQueue
    $failureMaskDirectory = Get-Cf7RuntimeRequestDirectory -QueueRoot $failureMaskQueue -RequestId ([string]$treeRequest.requestId)
    New-Item -ItemType Directory -Path $failureMaskDirectory -Force | Out-Null
    Copy-Item -LiteralPath $fullBundle -Destination (Join-Path $failureMaskDirectory 'source.bundle')
    Write-Cf7QueueUtf8File -Path (Join-Path $failureMaskDirectory 'request.json') `
        -Text (($undeclaredRequest | ConvertTo-Json -Depth 8) + "`n")
    $failureMaskBlocker = Join-Path (Join-Path $failureMaskQueue 'results\_failures') ([string]$treeRequest.requestId)
    [IO.File]::WriteAllText($failureMaskBlocker, 'block failure persistence', $encoding)
    $failureMaskCheckoutRoot = Join-Path $TestTempRoot ('qF-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    $externalCheckoutRoots.Add($failureMaskCheckoutRoot)
    $ErrorActionPreference = 'Continue'
    $failureMaskOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $workerScript `
        -ProjectRoot $fixtureRepo -QueueRoot $failureMaskQueue -CheckoutRoot $failureMaskCheckoutRoot `
        -WorkerId 'failure-mask-worker' -Once -DryRun -LeaseTtlSeconds 30 -HeartbeatSeconds 2 2>&1)
    $failureMaskExit = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    $failureMaskText = $failureMaskOutput -join "`n"
    Assert-QueueTest ($failureMaskExit -ne 0) 'worker accepted the deliberately undeclared failure-persistence bundle'
    Assert-QueueTest ($failureMaskText -match 'Runtime build request failed: Synthetic runtime bundle (?:contains undeclared or missing paths|path closure mismatch)') `
        "failure persistence replaced the original worker diagnosis: $failureMaskText"
    Assert-QueueTest ($failureMaskText -match 'Could not persist runtime build failure') `
        'worker did not report the secondary failure-persistence error'
    Assert-QueueTest (@(Get-ChildItem -LiteralPath $failureMaskCheckoutRoot -Force -ErrorAction SilentlyContinue).Count -eq 0) `
        'failure-persistence worker did not clean its isolated checkout'
    $checks++

    $statusScript = Join-Path $ProjectRoot 'tools\get-runtime-build-request-status.ps1'
    $statusOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $statusScript -ProjectRoot $fixtureRepo -QueueRoot $queueRoot -RequestId ([string]$requestA.requestId) -Json)
    $statusExit = $LASTEXITCODE
    $statusObject = ($statusOutput -join "`n") | ConvertFrom-Json
    Assert-QueueTest ($statusExit -eq 10 -and [string]$statusObject.status -eq '0/2') 'pending status or exit code contract changed'
    $checks++

    # Worker dry-run still clones the bundle and recomputes all v2 identity domains, but never
    # invokes the producer or needs a signing certificate.
    $workerCheckoutRoot = Join-Path $TestTempRoot ('qM-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
    $externalCheckoutRoots.Add($workerCheckoutRoot)
    $maximumLengthWorkerId = 'w' + ('x' * 63)
    & (Join-Path $ProjectRoot 'tools\invoke-runtime-build-worker.ps1') -ProjectRoot $fixtureRepo -QueueRoot $queueRoot `
        -CheckoutRoot $workerCheckoutRoot -WorkerId $maximumLengthWorkerId -Once -DryRun -LeaseTtlSeconds 30 -HeartbeatSeconds 2
    if ($LASTEXITCODE -ne 0) { throw 'Runtime worker dry-run failed.' }
    Assert-QueueTest ([string]$env:GIT_INDEX_FILE -ceq $customIndex) 'runtime worker did not restore the caller-owned Git index'
    Assert-QueueTest (@(Get-ChildItem -LiteralPath $workerCheckoutRoot -Force -ErrorAction SilentlyContinue).Count -eq 0) `
        'worker did not clean its machine-local isolated checkout'
    $checks++

    $leaseA = Try-EnterCf7RuntimeRequestLease -QueueRoot $queueRoot -RequestId ([string]$requestA.requestId) -WorkerId 'lease-worker-a' -LeaseTtlSeconds 30
    $leaseBlocked = Try-EnterCf7RuntimeRequestLease -QueueRoot $queueRoot -RequestId ([string]$requestA.requestId) -WorkerId 'lease-worker-b' -LeaseTtlSeconds 30
    Assert-QueueTest ($null -ne $leaseA -and $null -eq $leaseBlocked) 'lease competition admitted two workers'
    $leaseRecord = Read-Cf7QueueJson -Path (Join-Path $leaseA.directory 'lease.json')
    $leaseRecord.expiresAtUtc = [DateTime]::UtcNow.AddMinutes(-1).ToString('o')
    Write-Cf7QueueJsonAtomic -Path (Join-Path $leaseA.directory 'lease.json') -Value $leaseRecord
    $leaseB = Try-EnterCf7RuntimeRequestLease -QueueRoot $queueRoot -RequestId ([string]$requestA.requestId) -WorkerId 'lease-worker-b' -LeaseTtlSeconds 30
    Assert-QueueTest ($null -ne $leaseB) 'expired lease was not reclaimed atomically'
    Exit-Cf7RuntimeRequestLease -Lease $leaseB
    $checks++

    $failureDiagnosticRoot = Join-Path $testRoot 'failure-diagnostics'
    New-Item -ItemType Directory -Path $failureDiagnosticRoot -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $failureDiagnosticRoot 'bootstrap.log'), 'bounded bootstrap diagnostic', $encoding)
    $longDiagnosticName = ('d' * 124) + '.log'
    [IO.File]::WriteAllText((Join-Path $failureDiagnosticRoot $longDiagnosticName), 'maximum-name diagnostic', $encoding)
    Write-Cf7RuntimeBuildFailure -QueueRoot $queueRoot -Request $requestA -WorkerId 'lease-worker-b' `
        -Message 'intentional queue test failure' -DiagnosticRoot $failureDiagnosticRoot
    $capturedDiagnostics = @(Get-ChildItem -LiteralPath (Join-Path $queueRoot 'results\_failures') -File -Recurse |
        Where-Object { $_.Name -eq 'bootstrap.log' -or $_.Name -eq $longDiagnosticName })
    $bootstrapDiagnostic = @($capturedDiagnostics | Where-Object Name -eq 'bootstrap.log')
    $maximumNameDiagnostic = @($capturedDiagnostics | Where-Object Name -eq $longDiagnosticName)
    $failureRecord = Read-Cf7QueueJson -Path (@(Get-ChildItem -LiteralPath (Join-Path $queueRoot 'results\_failures') `
        -Filter 'failure.json' -File -Recurse)[0].FullName)
    Assert-QueueTest ($capturedDiagnostics.Count -eq 2 -and $bootstrapDiagnostic.Count -eq 1 -and
        $maximumNameDiagnostic.Count -eq 1 -and
        [IO.File]::ReadAllText($bootstrapDiagnostic[0].FullName) -eq 'bounded bootstrap diagnostic' -and
        [IO.File]::ReadAllText($maximumNameDiagnostic[0].FullName) -eq 'maximum-name diagnostic' -and
        [string]::IsNullOrWhiteSpace([string]$failureRecord.diagnosticCaptureError)) `
        'worker failure diagnostics were not boundedly persisted before checkout cleanup'
    $failed = Get-Cf7RuntimeBuildRequestState -QueueRoot $queueRoot -Request $requestA -RegistryPath (Join-Path $fixtureRepo 'missing-registry.json') -AttestationValidator { param($a,$r) }
    Assert-QueueTest ($failed.status -eq 'failed') 'failed request state was not surfaced'
    $checks++

    $candidate = Join-Path $testRoot 'candidate'
    New-Item -ItemType Directory -Path (Join-Path $candidate 'runtime') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $candidate 'CRAZYFLASHER7MercenaryEmpire.exe'), 'queue-bootstrap', $encoding)
    [IO.File]::WriteAllText((Join-Path $candidate 'runtime\queue-fixture.dll'), 'queue-payload', $encoding)
    [IO.File]::WriteAllText((Join-Path $candidate 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json'), '{}'+"`n", $encoding)
    $closure = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $fixtureRepo -DeploymentRoot $candidate
    $manifestLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @(
        'cf7-runtime-manifest-v2', "publishMode`tframework-dependent",
        "artifactSourceHash`t$($requestA.artifactSourceHash)", "producerRecipeHash`t$($requestA.producerRecipeHash)",
        "toolchainLockHash`t$($requestA.toolchainLockHash)", "toolchainBaseline`tqueue-test",
        "buildIdentityHash`t$($requestA.buildIdentityHash)", "payloadClosureHash`t$($closure.payloadClosureHash)"
    )) { $manifestLines.Add($line) }
    foreach ($row in @($closure.files)) { $manifestLines.Add("file`t$($row.path)`t$($row.size)`t$($row.sha256)") }
    [IO.File]::WriteAllText((Join-Path $candidate 'runtime\cf7-runtime-manifest.tsv'), ([string]::Join("`n", $manifestLines.ToArray()) + "`n"), $encoding)
    $validator = { param($attestation, $registry) if ([string]$attestation.schema -ne 'cf7-runtime-build-attestation.v2') { throw 'fake attestation schema rejected' } }
    function New-QueueFakeAttestation([string]$KeyCharacter, [string]$FaultDomain) {
        $key = ($KeyCharacter * 64).ToUpperInvariant()
        return [pscustomobject]@{
            schema='cf7-runtime-build-attestation.v2'
            payload=[pscustomobject]@{
                schema='cf7-runtime-build-attestation-payload.v2'; builderKeyId=$key; builderEpoch=1; faultDomain=$FaultDomain
                artifactSourceHash=[string]$requestA.artifactSourceHash; producerRecipeHash=[string]$requestA.producerRecipeHash
                toolchainLockHash=[string]$requestA.toolchainLockHash; policyHash=[string]$requestA.policyHash
                buildIdentityHash=[string]$requestA.buildIdentityHash; payloadClosureHash=[string]$closure.payloadClosureHash
                createdAtUtc=[DateTime]::UtcNow.ToString('o'); files=$closure.files
            }
            signature=[pscustomobject]@{ algorithm='TEST'; value='test-only' }
        }
    }
    $registry = Join-Path $fixtureRepo 'config\build\runtime-builders.v2.json'
    $attestationA = New-QueueFakeAttestation -KeyCharacter 'A' -FaultDomain 'machine-a'
    Publish-Cf7RuntimeProducerResult -QueueRoot $queueRoot -ProjectRoot $fixtureRepo -Request $requestA -Attestation $attestationA -CandidateRoot $candidate -RegistryPath $registry -AttestationValidator $validator | Out-Null
    Publish-Cf7RuntimeProducerResult -QueueRoot $queueRoot -ProjectRoot $fixtureRepo -Request $requestA -Attestation $attestationA -CandidateRoot $candidate -RegistryPath $registry -AttestationValidator $validator | Out-Null
    $identityResults = Join-Path (Join-Path $queueRoot 'results') ([string]$requestA.buildIdentityHash)
    Assert-QueueTest (@(Get-ChildItem -LiteralPath $identityResults -Filter result.json -File -Recurse).Count -eq 1) 'buildIdentity + signer result was not deduplicated'
    $checks++

    $attestationC = New-QueueFakeAttestation -KeyCharacter 'C' -FaultDomain 'machine-a'
    Publish-Cf7RuntimeProducerResult -QueueRoot $queueRoot -ProjectRoot $fixtureRepo -Request $requestA -Attestation $attestationC -CandidateRoot $candidate -RegistryPath $registry -AttestationValidator $validator | Out-Null
    $oneDomain = Get-Cf7RuntimeBuildRequestState -QueueRoot $queueRoot -Request $requestA -RegistryPath $registry -AttestationValidator $validator
    Assert-QueueTest ($oneDomain.status -eq '1/2') 'two signers in one fault domain incorrectly formed quorum'
    $attestationB = New-QueueFakeAttestation -KeyCharacter 'B' -FaultDomain 'machine-b'
    Publish-Cf7RuntimeProducerResult -QueueRoot $queueRoot -ProjectRoot $fixtureRepo -Request $requestA -Attestation $attestationB -CandidateRoot $candidate -RegistryPath $registry -AttestationValidator $validator | Out-Null
    $ready = Get-Cf7RuntimeBuildRequestState -QueueRoot $queueRoot -Request $requestA -RegistryPath $registry -AttestationValidator $validator
    Assert-QueueTest ($ready.status -eq 'ready' -and $ready.quorum -eq '2/2') 'different fault domains did not form a 2-of-N quorum'
    $checks++

    $newRequestId = [string]$treeRequest.requestId
    Set-Cf7RuntimeRequestSuperseded -QueueRoot $queueRoot -RequestId ([string]$requestA.requestId) -ByRequestId $newRequestId
    $superseded = Get-Cf7RuntimeBuildRequestState -QueueRoot $queueRoot -Request $requestA -RegistryPath $registry -AttestationValidator $validator
    Assert-QueueTest ($superseded.status -eq 'superseded' -and $superseded.supersededBy -eq $newRequestId) 'superseded request state was not preserved'
    $checks++

    Write-Host "[RuntimeBuildQueueTest] OK checks=$checks" -ForegroundColor Green
} finally {
    $env:GIT_INDEX_FILE = $originalGitIndexFile
    if ($customIndex -and (Test-Path -LiteralPath $customIndex)) { Remove-Item -LiteralPath $customIndex -Force }
    foreach ($checkoutRoot in $externalCheckoutRoots) {
        if (Test-Path -LiteralPath $checkoutRoot) { Remove-Cf7LocalDirectoryTree -Path $checkoutRoot -AllowedRoot $TestTempRoot }
    }
    foreach ($queueTestRoot in $externalQueueRoots) {
        if (Test-Path -LiteralPath $queueTestRoot) { Remove-Cf7LocalDirectoryTree -Path $queueTestRoot -AllowedRoot $shortQueueParent }
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Cf7LocalDirectoryTree -Path $testRoot -AllowedRoot $TestTempRoot }
}
