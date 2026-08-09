param(
    [string]$BuilderId = $env:CF7_RUNTIME_BUILDER_ID,
    [string]$CandidateRoot,
    [switch]$ForceReplace
)

$ErrorActionPreference = 'Stop'
$launcherDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $launcherDir

function Resolve-Cf7RuntimeWorkBase {
    param(
        [string]$OverrideRoot,
        [string]$SystemTempRoot = [IO.Path]::GetTempPath(),
        [string]$SourceProjectRoot
    )
    $requestedRoot = if ([string]::IsNullOrWhiteSpace($OverrideRoot)) {
        if ([string]::IsNullOrWhiteSpace($SystemTempRoot)) {
            throw 'The machine-local system temp path is unavailable. Set CF7_RUNTIME_WORK_ROOT to a safe local directory.'
        }
        Join-Path $SystemTempRoot 'cf7-runtime-build-work'
    } else {
        $OverrideRoot
    }
    if ($requestedRoot -notmatch '^[A-Za-z]:[\\/]') {
        throw "Runtime build work root must be an explicit machine-local absolute path: $requestedRoot"
    }
    $resolved = [IO.Path]::GetFullPath($requestedRoot).TrimEnd('\')
    $filesystemRoot = [IO.Path]::GetPathRoot($resolved)
    if ([string]::IsNullOrWhiteSpace($filesystemRoot) -or
            $resolved -notmatch '^[A-Za-z]:\\' -or
            $resolved.StartsWith('\\', [StringComparison]::Ordinal) -or
            $resolved.Equals($filesystemRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Runtime build work root must be a dedicated machine-local directory, not UNC, relative, or a filesystem root: $requestedRoot"
    }
    # VsDevCmd and its nested batch helpers are not safe when TMP/TEMP contains CMD
    # metacharacters (the repository itself may legitimately contain parentheses).
    if ($resolved -match '[&()<>|^!%]') {
        throw "Runtime build work root contains CMD metacharacters. Choose a short plain local path with CF7_RUNTIME_WORK_ROOT: $resolved"
    }
    if (-not [string]::IsNullOrWhiteSpace($SourceProjectRoot)) {
        $sourceRoot = [IO.Path]::GetFullPath($SourceProjectRoot).TrimEnd('\')
        if ($resolved.Equals($sourceRoot, [StringComparison]::OrdinalIgnoreCase) -or
                $resolved.StartsWith($sourceRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
                $sourceRoot.StartsWith($resolved + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Runtime build work root must remain outside and must not contain the source repository: $resolved"
        }
    }
    try {
        $drive = New-Object IO.DriveInfo($filesystemRoot)
        if ($drive.DriveType -eq [IO.DriveType]::Network) {
            throw "Runtime build work root must be machine-local; mapped network drives are not allowed: $resolved"
        }
    } catch [IO.IOException] {
        throw "Cannot inspect runtime build work drive: $($_.Exception.Message)"
    }
    return $resolved
}

function New-Cf7RuntimeWorkJobLayout {
    param(
        [Parameter(Mandatory=$true)][string]$WorkBase,
        [string]$RunToken = [Guid]::NewGuid().ToString('N')
    )
    if ($RunToken -notmatch '^[0-9a-fA-F]{32}$') { throw 'Runtime build work token must be 32 hexadecimal characters.' }
    $base = [IO.Path]::GetFullPath($WorkBase).TrimEnd('\')
    $jobRoot = [IO.Path]::GetFullPath((Join-Path $base ('job-' + $RunToken.ToLowerInvariant()))).TrimEnd('\')
    $jobParent = [IO.Path]::GetFullPath((Split-Path -Parent $jobRoot)).TrimEnd('\')
    if (-not $jobParent.Equals($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe runtime build work path: $jobRoot"
    }
    $pathProbes = @(
        (Join-Path $jobRoot 'temp\miniaudio-source\miniaudio_bridge.c'),
        (Join-Path $jobRoot 'managed-obj\Release\net10.0-windows\win-x64\CRAZYFLASHER7MercenaryEmpire.Core.GeneratedMSBuildEditorConfig.editorconfig'),
        (Join-Path $jobRoot ('cargo-target\release\build\sol_parser-' + ('a' * 32) + '\out\generated\runtime-build-path-budget.probe'))
    )
    $longestProbe = @($pathProbes | Sort-Object Length -Descending)[0]
    if ($longestProbe.Length -ge 260) {
        throw "Runtime build work root exceeds the native/MSBuild MAX_PATH budget (projected=$($longestProbe.Length), maximum=259): $base"
    }
    return [pscustomobject][ordered]@{
        workBase = $base
        jobRoot = $jobRoot
        longestProbe = $longestProbe
    }
}

function Assert-Cf7RuntimeWorkCleanupTarget {
    param(
        [Parameter(Mandatory=$true)][string]$WorkBase,
        [Parameter(Mandatory=$true)][string]$JobRoot
    )
    $base = [IO.Path]::GetFullPath($WorkBase).TrimEnd('\')
    $target = [IO.Path]::GetFullPath($JobRoot).TrimEnd('\')
    $parent = [IO.Path]::GetFullPath((Split-Path -Parent $target)).TrimEnd('\')
    $leaf = Split-Path -Leaf $target
    if (-not $parent.Equals($base, [StringComparison]::OrdinalIgnoreCase) -or
            $leaf -notmatch '^job-[0-9a-f]{32}$') {
        throw "Refusing to clean a runtime build path outside the exact job boundary: $target"
    }
    return $target
}

$v2Common = Join-Path $projectRoot 'tools\runtime-build-v2-common.ps1'
if (-not (Test-Path -LiteralPath $v2Common -PathType Leaf)) {
    throw "Runtime v2 common helper is missing: $v2Common"
}

function Get-Cf7FileDigestState {
    param([Parameter(Mandatory=$true)][string]$Path)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $exists = Test-Path -LiteralPath $fullPath -PathType Leaf
    [pscustomobject][ordered]@{
        path = $fullPath
        exists = $exists
        sha256 = if ($exists) { (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToUpperInvariant() } else { $null }
    }
}

function Get-Cf7FormalDeploymentSnapshot {
    param([Parameter(Mandatory=$true)][string]$Root)
    $paths = @()
    $bootstrapPath = Join-Path $Root 'CRAZYFLASHER7MercenaryEmpire.exe'
    if (Test-Path -LiteralPath $bootstrapPath -PathType Leaf) { $paths += Get-Item -LiteralPath $bootstrapPath -Force }
    $runtimePath = Join-Path $Root 'runtime'
    if (Test-Path -LiteralPath $runtimePath -PathType Container) {
        $runtimeItem = Get-Item -LiteralPath $runtimePath -Force
        if (($runtimeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Formal runtime directory must not be a reparse point: $runtimePath"
        }
        $runtimeEntries = @(Get-ChildItem -LiteralPath $runtimePath -Recurse -Force)
        $runtimeReparse = @($runtimeEntries | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
        if ($runtimeReparse.Count -gt 0) {
            throw "Formal runtime closure contains a reparse point: $($runtimeReparse[0].FullName)"
        }
        $paths += @($runtimeEntries | Where-Object { -not $_.PSIsContainer })
    }
    $consensusPath = Join-Path $Root 'config\build\runtime-release-consensus.json'
    if (Test-Path -LiteralPath $consensusPath -PathType Leaf) { $paths += Get-Item -LiteralPath $consensusPath -Force }

    $records = @($paths | ForEach-Object {
        if (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Formal deployment file must not be a reparse point: $($_.FullName)"
        }
        [pscustomobject][ordered]@{
            path = $_.FullName.Substring($Root.Length + 1).Replace('\','/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
        }
    } | Sort-Object path)
    $canonical = (($records | ForEach-Object { "$($_.path)`t$($_.sha256)" }) -join "`n") + "`n"
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $fingerprint = ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).Replace('-','')
    } finally {
        $hasher.Dispose()
    }
    return [pscustomobject][ordered]@{
        fingerprintSha256 = $fingerprint
        files = $records
        fileCount = $records.Count
    }
}

function Test-Cf7SameFormalDeploymentSnapshot {
    param(
        [Parameter(Mandatory=$true)]$Before,
        [Parameter(Mandatory=$true)]$After
    )
    return $Before.fileCount -eq $After.fileCount -and
        [string]$Before.fingerprintSha256 -ceq [string]$After.fingerprintSha256
}

$liveCorePath = Join-Path $projectRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll'
$formalDeploymentBefore = Get-Cf7FormalDeploymentSnapshot -Root $projectRoot

# The environment gate selects byte-pinned tools and normalizes process state.
. (Join-Path $projectRoot 'tools\check-runtime-build-env.ps1') -ProjectRoot $projectRoot -Mode RuntimePublish
. $v2Common

foreach ($requiredFunction in @(
    'Get-Cf7RuntimeArtifactSourceHash',
    'Get-Cf7RuntimeProducerRecipeHash',
    'Get-Cf7RuntimeToolchainLockHashV2',
    'Get-Cf7RuntimeV2BuildIdentityHash',
    'Get-Cf7RuntimePayloadClosureV2'
)) {
    if (-not (Get-Command $requiredFunction -CommandType Function -ErrorAction SilentlyContinue)) {
        throw "Runtime v2 common helper lacks function: $requiredFunction"
    }
}

if ([string]::IsNullOrWhiteSpace($BuilderId)) { $BuilderId = 'local-unregistered' }
if ($BuilderId -notmatch '^[a-z0-9][a-z0-9._-]{1,127}$') {
    throw 'BuilderId must be 2-128 lowercase ASCII letters, digits, dot, underscore, or hyphen.'
}

$artifactSourceHash = Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $projectRoot -Mode Worktree
$producerRecipeHash = Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $projectRoot -Mode Worktree
$toolchainLockHash = Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $projectRoot -Mode Worktree
$buildIdentityHash = Get-Cf7RuntimeV2BuildIdentityHash `
    -ArtifactSourceHash $artifactSourceHash `
    -ProducerRecipeHash $producerRecipeHash `
    -ToolchainLockHash $toolchainLockHash

$candidateBase = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\runtime-candidates\v2')).TrimEnd('\')
foreach ($candidatePathSegment in @(
    (Join-Path $projectRoot 'tmp'),
    (Join-Path $projectRoot 'tmp\runtime-candidates'),
    $candidateBase
)) {
    if (Test-Path -LiteralPath $candidatePathSegment) {
        $candidatePathItem = Get-Item -LiteralPath $candidatePathSegment -Force
        if (($candidatePathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Candidate path must not traverse a reparse point: $candidatePathSegment"
        }
    }
}
if (-not $CandidateRoot) {
    $candidateLeaf = New-Cf7RuntimeV2CandidateLeafName `
        -BuildIdentityHash $buildIdentityHash -BuilderId $BuilderId
    $CandidateRoot = Join-Path $candidateBase $candidateLeaf
} elseif (-not [IO.Path]::IsPathRooted($CandidateRoot)) {
    throw 'CandidateRoot must be an absolute path.'
}
$deploymentRoot = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
if ($deploymentRoot.Equals($candidateBase, [StringComparison]::OrdinalIgnoreCase) -or
        -not $deploymentRoot.StartsWith($candidateBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "CandidateRoot must remain under $candidateBase"
}
$relativeCandidateRoot = $deploymentRoot.Substring($candidateBase.Length + 1)
$candidatePathProbe = $candidateBase
foreach ($candidatePathPart in $relativeCandidateRoot.Split('\')) {
    $candidatePathProbe = Join-Path $candidatePathProbe $candidatePathPart
    if (-not (Test-Path -LiteralPath $candidatePathProbe)) { break }
    $candidatePathItem = Get-Item -LiteralPath $candidatePathProbe -Force
    if (($candidatePathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "CandidateRoot must not traverse a reparse point: $candidatePathProbe"
    }
}
$longestBootstrapProbe = Join-Path $deploymentRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json'
if ($longestBootstrapProbe.Length -ge 260) {
    throw "CandidateRoot exceeds the bootstrap MAX_PATH budget (projected=$($longestBootstrapProbe.Length), maximum=259). Choose a shorter repository/checkout path or CandidateRoot."
}
if (Test-Path -LiteralPath $deploymentRoot) {
    if (-not $ForceReplace) { throw "CandidateRoot already exists; immutable candidates are never overwritten: $deploymentRoot" }
    Remove-Item -LiteralPath $deploymentRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $deploymentRoot -Force | Out-Null

$workBase = Resolve-Cf7RuntimeWorkBase `
    -OverrideRoot $env:CF7_RUNTIME_WORK_ROOT `
    -SystemTempRoot ([IO.Path]::GetTempPath()) `
    -SourceProjectRoot $projectRoot
if (-not (Test-Path -LiteralPath $workBase -PathType Container)) {
    New-Item -ItemType Directory -Path $workBase -Force | Out-Null
}
$workBaseItem = Get-Item -LiteralPath $workBase -Force
if (($workBaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Runtime build work root must not be a reparse point: $workBase"
}
$workBase = [IO.Path]::GetFullPath($workBaseItem.FullName).TrimEnd('\')
$workLayout = New-Cf7RuntimeWorkJobLayout -WorkBase $workBase
$jobRoot = $workLayout.jobRoot
$nativeOut = Join-Path $jobRoot 'native-output'
$cargoTarget = Join-Path $jobRoot 'cargo-target'
$publishDir = Join-Path $jobRoot 'managed-publish'
$managedObj = (Join-Path $jobRoot 'managed-obj').TrimEnd('\') + '\'
$managedBin = (Join-Path $jobRoot 'managed-bin').TrimEnd('\') + '\'
$jobTemp = Join-Path $jobRoot 'temp'
New-Item -ItemType Directory -Path $nativeOut,$cargoTarget,$publishDir,$managedObj,$managedBin,$jobTemp -Force | Out-Null
$env:CF7_NATIVE_OUTPUT_DIR = $nativeOut
$env:CF7_CARGO_TARGET_DIR = $cargoTarget
$env:CF7_RUNTIME_JOB_TEMP = $jobTemp
$env:TMP = $jobTemp
$env:TEMP = $jobTemp

function Invoke-Cf7Batch {
    param([Parameter(Mandatory=$true)][string]$Path)
    & cmd.exe /d /s /c "`"$Path`" 2>&1"
    if ($LASTEXITCODE -ne 0) { throw "Native build failed: $Path exit=$LASTEXITCODE" }
}

function Copy-Cf7CanonicalLfFile {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $destinationDirectory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    $bytes = [IO.File]::ReadAllBytes($Source)
    $output = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13) {
            if ($i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { continue }
            $output.Add(10)
        } else {
            $output.Add($bytes[$i])
        }
    }
    [IO.File]::WriteAllBytes($Destination, $output.ToArray())
}

function Write-Cf7CandidateBootstrapLogTail {
    param([Parameter(Mandatory=$true)][string]$DeploymentRoot)
    $logPath = Join-Path $DeploymentRoot 'logs\bootstrap.log'
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { return }
    try {
        $item = Get-Item -LiteralPath $logPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            [Console]::Error.WriteLine('[RuntimeProducer] bootstrap.log is a reparse point; diagnostic tail suppressed.')
            return
        }
        if ($item.Length -gt 1MB) {
            [Console]::Error.WriteLine("[RuntimeProducer] bootstrap.log exceeds 1 MiB; diagnostic tail suppressed: $logPath")
            return
        }
        [Console]::Error.WriteLine("[RuntimeProducer] bootstrap diagnostic tail: $logPath")
        foreach ($line in @(Get-Content -LiteralPath $logPath -Encoding UTF8 -Tail 80)) {
            [Console]::Error.WriteLine([string]$line)
        }
    } catch {
        [Console]::Error.WriteLine("[RuntimeProducer] cannot read bootstrap diagnostics: $($_.Exception.Message)")
    }
}

Write-Host '=== CF7 Runtime Producer v2 ===' -ForegroundColor Cyan
Write-Host '  CANDIDATE ONLY - NOT DEPLOYED; FORMAL RUNTIME WILL NOT BE UPDATED.' -ForegroundColor Yellow
Write-Host "  Artifact source : $artifactSourceHash"
Write-Host "  Producer recipe : $producerRecipeHash"
Write-Host "  Toolchain lock  : $toolchainLockHash"
Write-Host "  Build identity  : $buildIdentityHash"
Write-Host "  Candidate       : $deploymentRoot"
Write-Host "  Work root       : $jobRoot"

try {
    Write-Host '[1/5] Build deterministic miniaudio.dll...' -ForegroundColor Yellow
    $canonicalNativeSource = Join-Path $jobTemp 'miniaudio-source'
    New-Item -ItemType Directory -Path $canonicalNativeSource -Force | Out-Null
    $nativeSourceRoot = (Resolve-Path -LiteralPath (Join-Path $launcherDir 'native')).Path.TrimEnd('\')
    $audioBuildInputPath = Join-Path $nativeSourceRoot 'audio-v2-build-inputs.v1.json'
    if (-not (Test-Path -LiteralPath $audioBuildInputPath -PathType Leaf)) {
        throw "Audio v2 build input manifest is missing: $audioBuildInputPath"
    }
    $audioBuildInputs = Get-Content -LiteralPath $audioBuildInputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($audioBuildInputs.schema -ne 'cf7.audio-v2.native-build-inputs.v1') {
        throw "Unexpected Audio v2 build input schema: $($audioBuildInputs.schema)"
    }
    foreach ($relativeInput in @($audioBuildInputs.materializedInputs)) {
        $relativePath = [string]$relativeInput
        if ([string]::IsNullOrWhiteSpace($relativePath) -or
            [IO.Path]::IsPathRooted($relativePath) -or
            $relativePath -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Unsafe Audio v2 materialized input: $relativePath"
        }
        $sourcePath = [IO.Path]::GetFullPath((Join-Path $nativeSourceRoot $relativePath))
        if (-not $sourcePath.StartsWith($nativeSourceRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Audio v2 materialized input is missing or escapes native root: $relativePath"
        }
        $sourceItem = Get-Item -LiteralPath $sourcePath -Force
        if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Audio v2 materialized input is a reparse point: $relativePath"
        }
        Copy-Cf7CanonicalLfFile `
            -Source $sourcePath `
            -Destination (Join-Path $canonicalNativeSource $relativePath)
    }
    $env:CF7_MINIAUDIO_REPRO_SOURCE_DIR = $canonicalNativeSource
    Invoke-Cf7Batch -Path (Join-Path $launcherDir 'native\build.bat')

    Write-Host '[2/5] Build deterministic sol_parser.dll...' -ForegroundColor Yellow
    Invoke-Cf7Batch -Path (Join-Path $launcherDir 'native\sol_parser\build.bat')

    Write-Host '[3/5] Build deterministic native bootstrap...' -ForegroundColor Yellow
    Invoke-Cf7Batch -Path (Join-Path $launcherDir 'native\bootstrap\build.bat')

    Write-Host '[4/5] Publish managed Core into isolated output...' -ForegroundColor Yellow
    $dotnet = $env:CF7_DOTNET_EXE
    $csproj = Join-Path $launcherDir 'CRAZYFLASHER7MercenaryEmpire.csproj'
    Push-Location $projectRoot
    try {
        & $dotnet publish $csproj `
            -c Release `
            -r win-x64 `
            --self-contained false `
            -p:RestoreLockedMode=true `
            -p:ImportDirectoryBuildProps=false `
            -p:ImportDirectoryBuildTargets=false `
            -p:DebugType=None `
            -p:DebugSymbols=false `
            -p:UseSharedCompilation=false `
            "-p:BaseIntermediateOutputPath=$managedObj" `
            "-p:MSBuildProjectExtensionsPath=$managedObj" `
            "-p:OutputPath=$managedBin" `
            -o $publishDir
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed: exit=$LASTEXITCODE" }
    } finally {
        Pop-Location
    }

    Get-ChildItem -LiteralPath $publishDir -File -Filter '*.pdb' -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

    Write-Host '[5/5] Assemble immutable candidate and manifest...' -ForegroundColor Yellow
    $runtimeDir = Join-Path $deploymentRoot 'runtime'
    New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null
    Get-ChildItem -LiteralPath $publishDir -File | Where-Object {
        $_.Extension -ne '.xml' -and $_.Extension -ne '.pdb'
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $runtimeDir $_.Name) -Force
    }

    foreach ($nativeName in @('miniaudio.dll','sol_parser.dll')) {
        $nativePath = Join-Path $nativeOut $nativeName
        if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) { throw "Native output missing: $nativePath" }
        Copy-Item -LiteralPath $nativePath -Destination (Join-Path $runtimeDir $nativeName) -Force
    }
    $bootstrapPath = Join-Path $nativeOut 'bootstrap.exe'
    if (-not (Test-Path -LiteralPath $bootstrapPath -PathType Leaf)) { throw "Bootstrap output missing: $bootstrapPath" }
    $userFacingExe = Join-Path $deploymentRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
    Copy-Item -LiteralPath $bootstrapPath -Destination $userFacingExe -Force

    foreach ($required in @(
        $userFacingExe,
        (Join-Path $runtimeDir 'CRAZYFLASHER7MercenaryEmpire.Core.exe'),
        (Join-Path $runtimeDir 'CRAZYFLASHER7MercenaryEmpire.Core.dll'),
        (Join-Path $runtimeDir 'miniaudio.dll'),
        (Join-Path $runtimeDir 'sol_parser.dll')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required candidate payload missing: $required" }
    }
    $overBudgetFiles = @(Get-ChildItem -LiteralPath $deploymentRoot -Recurse -File | Where-Object { $_.FullName.Length -ge 260 })
    if ($overBudgetFiles.Count -gt 0) {
        throw "Candidate contains paths outside the bootstrap MAX_PATH budget: $($overBudgetFiles[0].FullName)"
    }

    $payload = Get-Cf7RuntimePayloadClosureV2 -ProjectRoot $projectRoot -DeploymentRoot $deploymentRoot
    $manifestLines = New-Object 'System.Collections.Generic.List[string]'
    [void]$manifestLines.Add('cf7-runtime-manifest-v2')
    [void]$manifestLines.Add("publishMode`tframework-dependent")
    [void]$manifestLines.Add("artifactSourceHash`t$artifactSourceHash")
    [void]$manifestLines.Add("producerRecipeHash`t$producerRecipeHash")
    [void]$manifestLines.Add("toolchainLockHash`t$toolchainLockHash")
    [void]$manifestLines.Add("toolchainBaseline`t$env:CF7_RUNTIME_BASELINE")
    [void]$manifestLines.Add("buildIdentityHash`t$buildIdentityHash")
    [void]$manifestLines.Add("payloadClosureHash`t$($payload.payloadClosureHash)")
    foreach ($file in @($payload.files)) {
        [void]$manifestLines.Add("file`t$($file.path)`t$($file.size)`t$($file.sha256)")
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        (Join-Path $runtimeDir 'cf7-runtime-manifest.tsv'),
        ([string]::Join("`n", [string[]]$manifestLines.ToArray()) + "`n"),
        $utf8NoBom)

    $finalArtifactSourceHash = Get-Cf7RuntimeArtifactSourceHash -ProjectRoot $projectRoot -Mode Worktree
    $finalProducerRecipeHash = Get-Cf7RuntimeProducerRecipeHash -ProjectRoot $projectRoot -Mode Worktree
    $finalToolchainLockHash = Get-Cf7RuntimeToolchainLockHashV2 -ProjectRoot $projectRoot -Mode Worktree
    if ($finalArtifactSourceHash -ne $artifactSourceHash -or
            $finalProducerRecipeHash -ne $producerRecipeHash -or
            $finalToolchainLockHash -ne $toolchainLockHash) {
        throw 'Runtime producer inputs changed while the candidate was being built.'
    }

    # The bootstrap is linked as a Windows GUI application. PowerShell's call operator
    # can return before such a process exits, leaving $LASTEXITCODE stale. Use an
    # explicit Process handle so the manifest result and subsequent archive bytes are
    # causally ordered.
    $verifyStartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $verifyStartInfo.FileName = $userFacingExe
    $verifyStartInfo.Arguments = '--verify-runtime-only'
    $verifyStartInfo.WorkingDirectory = $deploymentRoot
    $verifyStartInfo.UseShellExecute = $false
    $verifyStartInfo.CreateNoWindow = $true
    $verifyProcess = [System.Diagnostics.Process]::Start($verifyStartInfo)
    if ($null -eq $verifyProcess) { throw 'Candidate bootstrap verification process did not start.' }
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
    if ($verifyTimedOut) {
        Write-Cf7CandidateBootstrapLogTail -DeploymentRoot $deploymentRoot
        throw 'Candidate bootstrap verification timed out after 120 seconds.'
    }
    if ($verifyExitCode -ne 0) {
        Write-Cf7CandidateBootstrapLogTail -DeploymentRoot $deploymentRoot
        throw "Candidate bootstrap rejected manifest v2 (exitCode=$verifyExitCode)."
    }
    # bootstrap --verify-runtime-only intentionally writes a diagnostic log beside the executable.
    # Preserve it on failure, but never let successful candidate archives carry timestamped,
    # host-specific bytes outside the signed payload inventory.
    $candidateLogs = Join-Path $deploymentRoot 'logs'
    if (Test-Path -LiteralPath $candidateLogs -PathType Container) {
        $resolvedLogs = [IO.Path]::GetFullPath($candidateLogs)
        if (-not $resolvedLogs.StartsWith($deploymentRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Unsafe candidate log path: $resolvedLogs"
        }
        Remove-Item -LiteralPath $resolvedLogs -Recurse -Force
    }
    if (Test-Path -LiteralPath $candidateLogs) {
        throw 'Candidate diagnostic logs remained after successful verification cleanup.'
    }

    $metadata = [ordered]@{
        schema = 'cf7-runtime-candidate-metadata.v2'
        builderLabel = $BuilderId
        artifactSourceHash = $artifactSourceHash
        producerRecipeHash = $producerRecipeHash
        toolchainLockHash = $toolchainLockHash
        buildIdentityHash = $buildIdentityHash
        payloadClosureHash = [string]$payload.payloadClosureHash
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText(
        (Join-Path $deploymentRoot 'runtime-build-metadata.v2.json'),
        (($metadata | ConvertTo-Json -Depth 5) + "`n"),
        $utf8NoBom)

    $candidateCorePath = Join-Path $deploymentRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll'
    $candidateCore = Get-Cf7FileDigestState -Path $candidateCorePath
    $liveCoreAfter = Get-Cf7FileDigestState -Path $liveCorePath
    $formalDeploymentAfter = Get-Cf7FormalDeploymentSnapshot -Root $projectRoot
    Write-Host '=== Runtime Candidate Complete - NOT DEPLOYED ===' -ForegroundColor Yellow
    Write-Host "  Deployment      : NOT_DEPLOYED"
    Write-Host "  Candidate       : $deploymentRoot"
    Write-Host "  Candidate Core  : $($candidateCore.path)"
    Write-Host "  Candidate SHA   : $($candidateCore.sha256)"
    Write-Host "  Live Core       : $($liveCoreAfter.path)"
    Write-Host "  Live SHA        : $(if ($liveCoreAfter.exists) { $liveCoreAfter.sha256 } else { '<missing>' })"
    Write-Host "  Formal closure  : $($formalDeploymentAfter.fingerprintSha256) ($($formalDeploymentAfter.fileCount) files)"
    Write-Host "  Build identity  : $buildIdentityHash"
    Write-Host "  Payload closure : $($payload.payloadClosureHash)"
    Write-Host '  FORMAL RUNTIME UNCHANGED; acceptance must explicitly select this candidate.' -ForegroundColor Yellow
} finally {
    Remove-Item Env:CF7_MINIAUDIO_REPRO_SOURCE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_NATIVE_OUTPUT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_CARGO_TARGET_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_RUNTIME_JOB_TEMP -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $jobRoot -PathType Container) {
        $resolvedJobRoot = Assert-Cf7RuntimeWorkCleanupTarget -WorkBase $workBase -JobRoot $jobRoot
        $cleanupBaseItem = Get-Item -LiteralPath $workBase -Force
        $cleanupJobItem = Get-Item -LiteralPath $resolvedJobRoot -Force
        if (($cleanupBaseItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($cleanupJobItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to clean a runtime build work tree through a reparse point: $resolvedJobRoot"
        }
        Remove-Item -LiteralPath $resolvedJobRoot -Recurse -Force
    }
    $formalDeploymentAfterCleanup = Get-Cf7FormalDeploymentSnapshot -Root $projectRoot
    if (-not (Test-Cf7SameFormalDeploymentSnapshot -Before $formalDeploymentBefore -After $formalDeploymentAfterCleanup)) {
        throw "Runtime candidate producer changed the formal deployment closure. Producer-only builds must never deploy. before=$($formalDeploymentBefore.fingerprintSha256) after=$($formalDeploymentAfterCleanup.fingerprintSha256)"
    }
}
