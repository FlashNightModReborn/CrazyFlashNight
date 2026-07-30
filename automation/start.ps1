[CmdletBinding()]
param(
    [string]$CandidateRoot,
    [switch]$EnableLegacyHttpAutomation,
    [string]$UnattendedSlot,
    [ValidateSet('jsonl','mcp')]
    [string]$UnattendedAdapter = 'jsonl',
    [string]$UnattendedClientInstanceId
)

# 默认只启动仓库根目录下已经正式部署的 runtime。
# 隔离候选必须通过 -CandidateRoot 显式选择，且只能来自本仓库的 v2 candidate 目录。
# 旧 localhost 高权限 HTTP 仅供显式迁移 runner；启用时 Launcher 不开放 Agent Runtime，
# 避免同一进程内的低权限 pipe principal 借 same-user bearer 文件越权。
$ErrorActionPreference = 'Stop'
$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent -Path $MyInvocation.MyCommand.Path }
$scriptDirectory = (Resolve-Path -LiteralPath $scriptDirectory).Path.TrimEnd('\')
$projectRoot = (Split-Path -Parent $scriptDirectory).TrimEnd('\')
$launchProjectRoot = [string]$projectRoot
$unattendedRequested =
    -not [string]::IsNullOrWhiteSpace($UnattendedSlot)
if ($unattendedRequested) {
    $allowedUnattendedSlots = @(
        'cf7_agent_equipment_tuning',
        'cf7_agent_arena_calibration',
        'cf7_agent_character_build',
        'cf7_agent_loot_target_full_v1'
    )
    if ($UnattendedSlot -cnotin $allowedUnattendedSlots) {
        throw '-UnattendedSlot is not in the frozen unattended slot allowlist.'
    }
    if ($EnableLegacyHttpAutomation) {
        throw 'Unattended Agent Runtime cannot enable legacy HTTP automation.'
    }
}
if (-not [string]::IsNullOrWhiteSpace($UnattendedClientInstanceId)) {
    throw '-UnattendedClientInstanceId was removed; the trusted Core runner generates its own identity.'
}
$dotnetRuntimeHelper = Join-Path $launchProjectRoot 'tools\dotnet-runtime-detect.ps1'
if (-not (Test-Path -LiteralPath $dotnetRuntimeHelper -PathType Leaf)) {
    throw "Dotnet runtime detection helper is missing: $dotnetRuntimeHelper"
}

function Get-Cf7Sha256 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Cf7PlainPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Description
    )
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must not be a reparse point: $Path"
    }
}

function Get-Cf7RuntimeManifestIdentity {
    param([Parameter(Mandatory=$true)][string]$DeploymentRoot)
    $manifestPath = Join-Path $DeploymentRoot 'runtime\cf7-runtime-manifest.tsv'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Runtime v2 manifest missing: $manifestPath"
    }
    Assert-Cf7PlainPath -Path $manifestPath -Description 'Runtime manifest'
    $lines = @([IO.File]::ReadAllLines($manifestPath, [Text.Encoding]::UTF8) | Where-Object { $_ -ne '' })
    if ($lines.Count -lt 9 -or $lines[0] -cne 'cf7-runtime-manifest-v2') {
        throw "Runtime manifest is not cf7-runtime-manifest-v2: $manifestPath"
    }
    $wanted = @(
        'artifactSourceHash',
        'producerRecipeHash',
        'toolchainLockHash',
        'buildIdentityHash',
        'payloadClosureHash'
    )
    $values = @{}
    foreach ($line in $lines | Select-Object -Skip 1) {
        $parts = @($line -split "`t")
        if ($parts.Count -eq 2 -and $parts[0] -in $wanted) {
            if ($values.ContainsKey($parts[0])) { throw "Duplicate runtime manifest field: $($parts[0])" }
            if ([string]$parts[1] -notmatch '^[0-9A-Fa-f]{64}$') {
                throw "Invalid runtime manifest hash field: $($parts[0])"
            }
            $values[$parts[0]] = ([string]$parts[1]).ToUpperInvariant()
        }
    }
    foreach ($field in $wanted) {
        if (-not $values.ContainsKey($field)) { throw "Runtime manifest lacks identity field: $field" }
    }
    return [pscustomobject][ordered]@{
        path = $manifestPath
        artifactSourceHash = $values.artifactSourceHash
        producerRecipeHash = $values.producerRecipeHash
        toolchainLockHash = $values.toolchainLockHash
        buildIdentityHash = $values.buildIdentityHash
        payloadClosureHash = $values.payloadClosureHash
    }
}

function Invoke-Cf7RuntimeVerifier {
    param(
        [Parameter(Mandatory=$true)][string]$Executable,
        [Parameter(Mandatory=$true)][string]$Arguments,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $Executable
    $startInfo.Arguments = $Arguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process) { throw "Runtime verifier did not start: $Executable" }
    try {
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        if (-not $process.WaitForExit(120000)) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(10000)
            throw 'Runtime bundle verification timed out after 120 seconds.'
        }
        if ($process.ExitCode -ne 0) {
            throw "Runtime bundle integrity check failed (exitCode=$($process.ExitCode))."
        }
    } finally {
        $process.Dispose()
    }
}

$runtimeMode = 'formal_runtime'
$deploymentRoot = $projectRoot
$candidateMetadata = $null
if (-not [string]::IsNullOrWhiteSpace($CandidateRoot)) {
    if (-not [IO.Path]::IsPathRooted($CandidateRoot)) {
        throw '-CandidateRoot must be an explicit absolute path.'
    }
    $candidateBase = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp\runtime-candidates\v2')).TrimEnd('\')
    $requestedCandidate = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
    if ($requestedCandidate.Equals($candidateBase, [StringComparison]::OrdinalIgnoreCase) -or
            -not $requestedCandidate.StartsWith($candidateBase + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "-CandidateRoot is outside the repository v2 candidate directory: $candidateBase"
    }
    if (-not (Test-Path -LiteralPath $requestedCandidate -PathType Container)) {
        throw "CandidateRoot does not exist: $requestedCandidate"
    }
    foreach ($candidateBasePath in @(
        (Join-Path $projectRoot 'tmp'),
        (Join-Path $projectRoot 'tmp\runtime-candidates'),
        $candidateBase
    )) {
        if (-not (Test-Path -LiteralPath $candidateBasePath -PathType Container)) {
            throw "Candidate directory chain is incomplete: $candidateBasePath"
        }
        Assert-Cf7PlainPath -Path $candidateBasePath -Description 'Candidate base path segment'
    }
    $resolvedCandidate = (Resolve-Path -LiteralPath $requestedCandidate).Path.TrimEnd('\')
    if (-not $resolvedCandidate.Equals($requestedCandidate, [StringComparison]::OrdinalIgnoreCase)) {
        throw "CandidateRoot does not resolve to its canonical repository path: $requestedCandidate"
    }

    # Reject junction/symlink escapes at every path segment below tmp/runtime-candidates/v2.
    $relativeCandidate = $resolvedCandidate.Substring($candidateBase.Length + 1)
    $pathProbe = $candidateBase
    foreach ($segment in $relativeCandidate.Split('\')) {
        $pathProbe = Join-Path $pathProbe $segment
        Assert-Cf7PlainPath -Path $pathProbe -Description 'Candidate path segment'
    }

    $metadataPath = Join-Path $resolvedCandidate 'runtime-build-metadata.v2.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw "Candidate metadata missing: $metadataPath"
    }
    Assert-Cf7PlainPath -Path $metadataPath -Description 'Candidate metadata'
    try {
        $candidateMetadata = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Candidate metadata is invalid JSON: $metadataPath ($($_.Exception.Message))"
    }
    if ([string]$candidateMetadata.schema -cne 'cf7-runtime-candidate-metadata.v2') {
        throw "Candidate metadata schema is invalid: $($candidateMetadata.schema)"
    }
    foreach ($field in @(
        'artifactSourceHash',
        'producerRecipeHash',
        'toolchainLockHash',
        'buildIdentityHash',
        'payloadClosureHash'
    )) {
        if ([string]$candidateMetadata.$field -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "Candidate metadata hash is invalid: $field"
        }
    }
    $deploymentRoot = $resolvedCandidate
    $runtimeMode = 'isolated_candidate'
}

$coreExe = Join-Path $deploymentRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe'
$coreDll = Join-Path $deploymentRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.dll'
$bootstrapExe = Join-Path $deploymentRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
$runtimeDirectory = Join-Path $deploymentRoot 'runtime'
if (-not (Test-Path -LiteralPath $runtimeDirectory -PathType Container)) {
    throw "Runtime directory is missing: $runtimeDirectory"
}
Assert-Cf7PlainPath -Path $runtimeDirectory -Description 'Runtime directory'
foreach ($required in @($coreExe, $coreDll, $bootstrapExe)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        if ($runtimeMode -eq 'formal_runtime') {
            throw "Formal runtime payload is missing: $required. launcher/build.ps1 only creates a NOT_DEPLOYED candidate; complete the v2 promotion before using the default start path."
        }
        throw "Candidate runtime payload is missing: $required"
    }
    Assert-Cf7PlainPath -Path $required -Description 'Runtime executable payload'
}

$manifestIdentity = Get-Cf7RuntimeManifestIdentity -DeploymentRoot $deploymentRoot
if ($null -ne $candidateMetadata) {
    foreach ($field in @(
        'artifactSourceHash',
        'producerRecipeHash',
        'toolchainLockHash',
        'buildIdentityHash',
        'payloadClosureHash'
    )) {
        $metadataValue = ([string]$candidateMetadata.$field).ToUpperInvariant()
        $manifestValue = ([string]$manifestIdentity.$field).ToUpperInvariant()
        if ($metadataValue -cne $manifestValue) {
            throw "Candidate metadata/manifest mismatch: $field metadata=$metadataValue manifest=$manifestValue"
        }
    }
}

# Resolve the Core runtime before invoking the bundle verifier. Windows PowerShell's
# script-scope behavior can discard helper functions after nested verifier scripts return;
# invoking the helper immediately keeps the environment result, not a fragile function name.
. $dotnetRuntimeHelper
$setDotnetRootCommand = Get-Command Set-DotnetRootForCore -CommandType Function -ErrorAction Stop
if ($unattendedRequested) {
    if (-not (& $setDotnetRootCommand -Quiet)) { exit 1 }
} elseif (-not (& $setDotnetRootCommand)) {
    exit 1
}

# Use the trusted repository verifier to validate the complete manifest inventory before
# executing any candidate payload. The bootstrap then validates the actual launch mode.
$selectedDeploymentRoot = [string]$deploymentRoot
$selectedCoreExe = [string]$coreExe
$selectedCoreDll = [string]$coreDll
$selectedBootstrapExe = [string]$bootstrapExe
$bundleVerifier = Join-Path $launchProjectRoot 'tools\verify-runtime-bundle-v2.ps1'
if (-not (Test-Path -LiteralPath $bundleVerifier -PathType Leaf)) {
    throw "Runtime v2 verifier missing: $bundleVerifier"
}
$LASTEXITCODE = 0
if ($unattendedRequested) {
    & $bundleVerifier -ProjectRoot $launchProjectRoot -DeploymentRoot $selectedDeploymentRoot -IntegrityOnly *> $null
} else {
    & $bundleVerifier -ProjectRoot $launchProjectRoot -DeploymentRoot $selectedDeploymentRoot -IntegrityOnly
}
if ($LASTEXITCODE -ne 0) {
    throw "Runtime v2 bundle verifier rejected $selectedDeploymentRoot (exitCode=$LASTEXITCODE)."
}
$verifyArgument = if ($runtimeMode -eq 'isolated_candidate') { '--verify-runtime-only' } else { '--verify-only' }
Invoke-Cf7RuntimeVerifier -Executable $selectedBootstrapExe -Arguments $verifyArgument -WorkingDirectory $selectedDeploymentRoot

$portsFile = Join-Path $launchProjectRoot 'launcher_ports.json'
if (Test-Path -LiteralPath $portsFile) {
    try {
        $existingPorts = Get-Content -LiteralPath $portsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $existingPid = if ($existingPorts.pid) { [int]$existingPorts.pid } else { 0 }
        if ($existingPid -gt 0 -and (Get-Process -Id $existingPid -ErrorAction SilentlyContinue)) {
            throw "A Guardian process is already running (pid=$existingPid). Stop it before starting runtime mode '$runtimeMode'; an existing process must never satisfy a new candidate acceptance run."
        }
        Remove-Item -LiteralPath $portsFile -Force
    } catch {
        if ($_.Exception.Message -like 'A Guardian process is already running*') { throw }
        Remove-Item -LiteralPath $portsFile -Force -ErrorAction SilentlyContinue
    }
}

if ($unattendedRequested) {
    $runnerStart = [Diagnostics.ProcessStartInfo]::new()
    $runnerStart.FileName = [IO.Path]::GetFullPath($selectedCoreExe)
    $runnerStart.WorkingDirectory = $selectedDeploymentRoot
    $runnerStart.UseShellExecute = $false
    # Windows PowerShell 5.1 exposes ProcessStartInfo without ArgumentList.
    # Both interpolated values have already passed closed ASCII allowlists.
    $runnerStart.Arguments =
        "--agent-unattended-runner --adapter $UnattendedAdapter --slot $UnattendedSlot"
    $trustedRunner = [Diagnostics.Process]::Start($runnerStart)
    if ($null -eq $trustedRunner) {
        throw 'Trusted unattended Core runner failed to start.'
    }
    $trustedRunner.WaitForExit()
    $trustedRunnerExitCode = $trustedRunner.ExitCode
    $trustedRunner.Dispose()
    if ($trustedRunnerExitCode -ne 0) {
        throw "Trusted unattended Core runner failed (exitCode=$trustedRunnerExitCode)."
    }
    return
}

$coreSha256 = Get-Cf7Sha256 -Path $selectedCoreDll
Write-Host '=== CF7 Runtime Launch Identity ===' -ForegroundColor Cyan
Write-Host "  Runtime Mode    : $runtimeMode"
Write-Host "  Deployment Root : $selectedDeploymentRoot"
Write-Host "  Core Path       : $selectedCoreDll"
Write-Host "  Core SHA256     : $coreSha256"
Write-Host "  Build Identity  : $($manifestIdentity.buildIdentityHash)"
Write-Host "  Payload Closure : $($manifestIdentity.payloadClosureHash)"
if ($runtimeMode -eq 'isolated_candidate') {
    Write-Host '  Deployment      : NOT_DEPLOYED (explicit candidate acceptance run)' -ForegroundColor Yellow
} else {
    Write-Host '  Deployment      : FORMAL_RUNTIME' -ForegroundColor Green
}

$guardian = $null
try {
    Write-Host "Starting CF7:ME Guardian Core ($runtimeMode)..."
    if ($EnableLegacyHttpAutomation) {
        Write-Host '  Control plane   : LEGACY_HTTP_AUTOMATION (Agent Runtime admission disabled)' -ForegroundColor Yellow
    }
    Push-Location $launchProjectRoot
    try {
        $coreArguments = "--project-root `"$launchProjectRoot`""
        if ($EnableLegacyHttpAutomation) {
            $coreArguments += ' --legacy-http-automation'
        }
        $guardian = [System.Diagnostics.Process]::Start(
            $selectedCoreExe,
            $coreArguments)
    } finally {
        Pop-Location
    }
    if ($null -eq $guardian) { throw 'System.Diagnostics.Process.Start returned null.' }

    $actualProcessPath = $null
    $processPathError = $null
    $processPathDeadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $processPathDeadline -and $null -eq $actualProcessPath) {
        try {
            $guardian.Refresh()
            if ($guardian.HasExited) {
                throw "Guardian exited before process path verification (exitCode=$($guardian.ExitCode))."
            }
            $mainModulePath = [string]$guardian.MainModule.FileName
            if ([string]::IsNullOrWhiteSpace($mainModulePath)) {
                throw 'Guardian MainModule.FileName is not available yet.'
            }
            $actualProcessPath = [IO.Path]::GetFullPath($mainModulePath)
        } catch {
            if ($_.Exception.Message -like 'Guardian exited before process path verification*') { throw }
            $processPathError = $_.Exception.Message
            Start-Sleep -Milliseconds 50
        }
    }
    if ($null -eq $actualProcessPath) {
        throw "Guardian process path verification timed out: $processPathError"
    }
    if (-not $actualProcessPath.Equals([IO.Path]::GetFullPath($selectedCoreExe), [StringComparison]::OrdinalIgnoreCase)) {
        throw "Guardian process path mismatch: expected=$selectedCoreExe actual=$actualProcessPath"
    }

    Write-Host "Guardian PID: $($guardian.Id)"
    $deadline = (Get-Date).AddSeconds(30)
    $readyPorts = $null
    while ((Get-Date) -lt $deadline) {
        if ($guardian.HasExited) {
            throw "Guardian exited before HTTP bus became ready (exitCode=$($guardian.ExitCode))."
        }
        if (Test-Path -LiteralPath $portsFile) {
            try {
                $readyPorts = Get-Content -LiteralPath $portsFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not $readyPorts.pid -or [int]$readyPorts.pid -ne $guardian.Id) {
                    throw "launcher_ports.json belongs to a different process: expected=$($guardian.Id) actual=$($readyPorts.pid)"
                }
                break
            } catch {
                if ($_.Exception.Message -like 'launcher_ports.json belongs to a different process*') { throw }
                $readyPorts = $null
            }
        }
        Start-Sleep -Milliseconds 500
        try { $guardian.Refresh() } catch { }
    }
    if ($null -eq $readyPorts) { throw 'Guardian did not write a matching launcher_ports.json within 30 seconds.' }
    Write-Host "Guardian bus ready: $($readyPorts | ConvertTo-Json -Compress)"
    Write-Host 'Guardian started successfully.'
    Write-Host "Runtime identity confirmed: mode=$runtimeMode coreSha256=$coreSha256 buildIdentity=$($manifestIdentity.buildIdentityHash) payloadClosure=$($manifestIdentity.payloadClosureHash)"
    Write-Host '(Flash Player + V8 Bus are managed by the guardian process)'
    $guardian.Dispose()
    $guardian = $null
} catch {
    if ($null -ne $guardian) {
        try { if (-not $guardian.HasExited) { $guardian.Kill() } } catch { }
        try { $guardian.Dispose() } catch { }
    }
    Write-Host "Failed to start guardian: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
