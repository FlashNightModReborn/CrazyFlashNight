[CmdletBinding()]
param(
    [string]$LargeM4aSourcePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nativeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $nativeRoot '..\..')).Path
& (Join-Path $projectRoot 'tools\check-runtime-build-env.ps1') `
    -ProjectRoot $projectRoot `
    -Mode Validate

foreach ($name in @(
    'CF7_VCVARS64',
    'CF7_MSVC_TOOLS_VERSION',
    'CF7_WINDOWS_SDK_VERSION',
    'CF7_CL_EXE')) {
    if ([string]::IsNullOrWhiteSpace(
            [Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "Pinned compiler environment is unavailable: $name"
    }
}

if ([string]::IsNullOrWhiteSpace($LargeM4aSourcePath)) {
    $candidates = @(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sounds') `
            -Recurse -File -Filter '*.m4a' |
            Where-Object { $_.Length -gt 8388608 }
    )
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one shipped M4A larger than 8 MiB; found $($candidates.Count)."
    }
    $LargeM4aSourcePath = $candidates[0].FullName
}
$resolvedM4a = (Resolve-Path -LiteralPath $LargeM4aSourcePath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedM4a -PathType Leaf)) {
    throw "Large M4A source is not a file: $resolvedM4a"
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$leaf = 'cf7-audio-mf-async-contract-' + [Guid]::NewGuid().ToString('N')
$tempRoot = [IO.Path]::GetFullPath((Join-Path $tempParent $leaf)).TrimEnd('\')
if (-not $tempRoot.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($tempRoot) -cne $leaf) {
    throw "Unsafe MF async contract root: $tempRoot"
}
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $contractSource = Join-Path $PSScriptRoot 'audio_mf_decoder_async_contract.cpp'
    $miniaudioSource = Join-Path $nativeRoot 'miniaudio.c'
    $mfSource = Join-Path $nativeRoot 'audio_mf_decoder.cpp'
    $contractObject = Join-Path $tempRoot 'contract.obj'
    $miniaudioObject = Join-Path $tempRoot 'miniaudio.obj'
    $mfObject = Join-Path $tempRoot 'audio_mf_decoder.obj'
    $executable = Join-Path $tempRoot 'audio-mf-async-contract.exe'
    $forceInclude = Join-Path $nativeRoot 'audio_miniaudio_config.h'

    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:CF7_VSWHERE_DIR)) {
        $parts += 'set "PATH=%CF7_VSWHERE_DIR%;%PATH%"'
    }
    $parts += @(
        ('call "{0}" {1} -vcvars_ver={2} >nul' -f
            $env:CF7_VCVARS64,$env:CF7_WINDOWS_SDK_VERSION,$env:CF7_MSVC_TOOLS_VERSION),
        ('call "{0}" >nul' -f (Join-Path $nativeRoot 'assert-pinned-tools.bat')),
        ('"{0}" /nologo /TC /std:c17 /O2 /W2 /utf-8 /I"{1}" /FI"{2}" /c "{3}" /Fo"{4}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$forceInclude,$miniaudioSource,$miniaudioObject),
        ('"{0}" /nologo /TP /std:c++17 /EHsc /O2 /W4 /WX /utf-8 /I"{1}" /FI"{2}" /c "{3}" /Fo"{4}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$forceInclude,$mfSource,$mfObject),
        ('"{0}" /nologo /TP /std:c++17 /EHsc /O2 /W4 /WX /utf-8 /I"{1}" /FI"{2}" /c "{3}" /Fo"{4}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$forceInclude,$contractSource,$contractObject),
        ('"{0}" /nologo "{1}" "{2}" "{3}" mfplat.lib mfreadwrite.lib mfuuid.lib ole32.lib propsys.lib shlwapi.lib /Fe:"{4}"' -f
            $env:CF7_CL_EXE,$contractObject,$miniaudioObject,$mfObject,$executable)
    )
    & $env:ComSpec /d /s /c ($parts -join ' && ')
    if ($LASTEXITCODE -ne 0) {
        throw 'Audio MF async contract compilation failed.'
    }

    & $executable $resolvedM4a
    if ($LASTEXITCODE -ne 0) {
        throw 'Audio MF async contract failed.'
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolved = [IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $tempRoot).Path).TrimEnd('\')
        if (-not $resolved.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -cne $leaf) {
            throw "Unsafe MF async contract cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
