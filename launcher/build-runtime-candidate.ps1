param(
    [string]$BuilderId = $env:CF7_RUNTIME_BUILDER_ID,
    [string]$CandidateRoot,
    [switch]$ForceReplace
)

$ErrorActionPreference = 'Stop'
$launcherDir = $PSScriptRoot
$projectRoot = Split-Path -Parent $launcherDir
$v2Common = Join-Path $projectRoot 'tools\runtime-build-v2-common.ps1'
if (-not (Test-Path -LiteralPath $v2Common -PathType Leaf)) {
    throw "Runtime v2 common helper is missing: $v2Common"
}

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
if (-not $CandidateRoot) {
    $candidateLeaf = New-Cf7RuntimeV2CandidateLeafName `
        -BuildIdentityHash $buildIdentityHash -BuilderId $BuilderId
    $CandidateRoot = Join-Path $candidateBase $candidateLeaf
}
$deploymentRoot = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
if (-not $deploymentRoot.StartsWith($candidateBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "CandidateRoot must remain under $candidateBase"
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

$workBase = if ($env:CF7_RUNTIME_WORK_ROOT) {
    [IO.Path]::GetFullPath($env:CF7_RUNTIME_WORK_ROOT).TrimEnd('\')
} else {
    [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\runtime-build-work')).TrimEnd('\')
}
if (-not (Test-Path -LiteralPath $workBase -PathType Container)) {
    New-Item -ItemType Directory -Path $workBase -Force | Out-Null
}
$jobRoot = Join-Path $workBase ([Guid]::NewGuid().ToString('N'))
$jobRoot = [IO.Path]::GetFullPath($jobRoot)
if (-not $jobRoot.StartsWith($workBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe runtime build work path: $jobRoot"
}
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
Write-Host "  Artifact source : $artifactSourceHash"
Write-Host "  Producer recipe : $producerRecipeHash"
Write-Host "  Toolchain lock  : $toolchainLockHash"
Write-Host "  Build identity  : $buildIdentityHash"
Write-Host "  Candidate       : $deploymentRoot"

try {
    Write-Host '[1/5] Build deterministic miniaudio.dll...' -ForegroundColor Yellow
    $canonicalNativeSource = Join-Path $jobTemp 'miniaudio-source'
    New-Item -ItemType Directory -Path $canonicalNativeSource -Force | Out-Null
    Copy-Cf7CanonicalLfFile `
        -Source (Join-Path $launcherDir 'native\miniaudio_bridge.c') `
        -Destination (Join-Path $canonicalNativeSource 'miniaudio_bridge.c')
    Copy-Cf7CanonicalLfFile `
        -Source (Join-Path $launcherDir 'native\miniaudio.h') `
        -Destination (Join-Path $canonicalNativeSource 'miniaudio.h')
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

    Write-Host '=== Runtime Candidate Complete ===' -ForegroundColor Green
    Write-Host "  Candidate       : $deploymentRoot"
    Write-Host "  Payload closure : $($payload.payloadClosureHash)"
} finally {
    Remove-Item Env:CF7_MINIAUDIO_REPRO_SOURCE_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_NATIVE_OUTPUT_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_CARGO_TARGET_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:CF7_RUNTIME_JOB_TEMP -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $jobRoot -PathType Container) {
        $resolvedJobRoot = [IO.Path]::GetFullPath($jobRoot)
        if ($resolvedJobRoot.StartsWith($workBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedJobRoot -Recurse -Force
        }
    }
}
