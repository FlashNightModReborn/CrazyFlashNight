[CmdletBinding()]
param(
    [switch]$KeepBuildDirectory
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$testDirectory = $PSScriptRoot
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $testDirectory '..\..\..')).Path
$environmentCheck = Join-Path $projectRoot 'tools\check-runtime-build-env.ps1'
$sourcePath = Join-Path $testDirectory 'audio_bridge_v2_contract.c'
$nativeDirectory = (Resolve-Path -LiteralPath (Join-Path $testDirectory '..')).Path
$pinnedToolAssertion = Join-Path $nativeDirectory 'assert-pinned-tools.bat'

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Audio ABI contract source is missing: $sourcePath"
}

& $environmentCheck -ProjectRoot $projectRoot -Mode Validate

foreach ($requiredName in @(
    'CF7_VCVARS64',
    'CF7_MSVC_TOOLS_VERSION',
    'CF7_WINDOWS_SDK_VERSION',
    'CF7_CL_EXE'
)) {
    $requiredValue = [Environment]::GetEnvironmentVariable($requiredName, 'Process')
    if ([string]::IsNullOrWhiteSpace($requiredValue)) {
        throw "Pinned compiler environment is unavailable: $requiredName"
    }
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$buildLeaf = 'cf7-audio-bridge-v2-contract-' + [Guid]::NewGuid().ToString('N')
$buildDirectory = [IO.Path]::GetFullPath((Join-Path $temporaryParent $buildLeaf)).TrimEnd('\')
if (-not $buildDirectory.StartsWith($temporaryParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($buildDirectory) -cne $buildLeaf) {
    throw "Refusing unsafe contract build directory: $buildDirectory"
}

New-Item -ItemType Directory -Path $buildDirectory | Out-Null
$objectPath = Join-Path $buildDirectory 'audio_bridge_v2_contract.obj'
$executablePath = Join-Path $buildDirectory 'audio_bridge_v2_contract.exe'

try {
    $compileParts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:CF7_VSWHERE_DIR)) {
        $compileParts += 'set "PATH=%CF7_VSWHERE_DIR%;%PATH%"'
    }
    $compileParts += @(
        ('call "{0}" {1} -vcvars_ver={2} >nul' -f
            $env:CF7_VCVARS64,
            $env:CF7_WINDOWS_SDK_VERSION,
            $env:CF7_MSVC_TOOLS_VERSION),
        ('call "{0}" >nul' -f $pinnedToolAssertion),
        ('"{0}" /nologo /TC /utf-8 /W4 /WX /D_CRT_SECURE_NO_WARNINGS /I"{1}" "{2}" /Fo"{3}" /Fe"{4}"' -f
            $env:CF7_CL_EXE,
            $nativeDirectory,
            $sourcePath,
            $objectPath,
            $executablePath)
    )
    $compileCommand = $compileParts -join ' && '

    $savedErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $compileOutput = @(& $env:ComSpec /d /s /c $compileCommand 2>&1)
        $compileExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorActionPreference
    }
    if ($compileExitCode -ne 0) {
        $compileOutput | ForEach-Object { Write-Host $_ }
        throw "Audio ABI contract compilation failed with exit code $compileExitCode"
    }
    $compileOutput | ForEach-Object { Write-Host $_ }

    $testOutput = @(& $executablePath 2>&1)
    $testExitCode = $LASTEXITCODE
    $testOutput | ForEach-Object { Write-Host $_ }
    if ($testExitCode -ne 0) {
        throw "Audio ABI contract failed with exit code $testExitCode"
    }

    Write-Host '[PASS] Repeatable local Audio ABI v2 contract runner completed.' -ForegroundColor Green
} finally {
    if ($KeepBuildDirectory) {
        Write-Host "[INFO] Contract build directory retained: $buildDirectory"
    } elseif (Test-Path -LiteralPath $buildDirectory -PathType Container) {
        $resolvedBuildDirectory = [IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $buildDirectory).Path).TrimEnd('\')
        if (-not $resolvedBuildDirectory.StartsWith($temporaryParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetFileName($resolvedBuildDirectory) -cne $buildLeaf) {
            throw "Refusing unsafe contract cleanup target: $resolvedBuildDirectory"
        }
        Remove-Item -LiteralPath $resolvedBuildDirectory -Recurse -Force
    }
}
