[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nativeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $nativeRoot '..\..')).Path
& (Join-Path $projectRoot 'tools\check-runtime-build-env.ps1') -ProjectRoot $projectRoot -Mode Validate

foreach ($name in @('CF7_VCVARS64','CF7_MSVC_TOOLS_VERSION','CF7_WINDOWS_SDK_VERSION','CF7_CL_EXE')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "Pinned compiler environment is unavailable: $name"
    }
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$leaf = 'cf7-audio-support-contract-' + [Guid]::NewGuid().ToString('N')
$root = [IO.Path]::GetFullPath((Join-Path $tempParent $leaf)).TrimEnd('\')
if (-not $root.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($root) -cne $leaf) {
    throw "Unsafe support contract root: $root"
}

$base = Join-Path $root 'base'
$outside = Join-Path $root 'outside'
$junction = Join-Path $base 'escape'
New-Item -ItemType Directory -Path $base,$outside | Out-Null
$insideFile = Join-Path $base 'disguised.wav'
$outsideFile = Join-Path $outside 'outside.mp3'
[IO.File]::WriteAllBytes($insideFile, [byte[]](0x49,0x44,0x33,0x04,0x00,0x00,0x00,0x00))
[IO.File]::WriteAllBytes($outsideFile, [byte[]](0x49,0x44,0x33,0x04,0x00,0x00,0x00,0x00))
New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
$junctionFile = Join-Path $junction 'outside.mp3'

try {
    $source = Join-Path $PSScriptRoot 'audio_bridge_support_contract.c'
    $support = Join-Path $nativeRoot 'audio_bridge_support.c'
    $objectOne = Join-Path $root 'contract.obj'
    $objectTwo = Join-Path $root 'support.obj'
    $exe = Join-Path $root 'support-contract.exe'
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:CF7_VSWHERE_DIR)) {
        $parts += 'set "PATH=%CF7_VSWHERE_DIR%;%PATH%"'
    }
    $parts += @(
        ('call "{0}" {1} -vcvars_ver={2} >nul' -f
            $env:CF7_VCVARS64,$env:CF7_WINDOWS_SDK_VERSION,$env:CF7_MSVC_TOOLS_VERSION),
        ('call "{0}" >nul' -f (Join-Path $nativeRoot 'assert-pinned-tools.bat')),
        ('"{0}" /nologo /TC /std:c17 /W4 /WX /utf-8 /I"{1}" /c "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$source,$objectOne),
        ('"{0}" /nologo /TC /std:c17 /W4 /WX /utf-8 /I"{1}" /c "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$support,$objectTwo),
        ('"{0}" /nologo "{1}" "{2}" bcrypt.lib /Fe:"{3}"' -f
            $env:CF7_CL_EXE,$objectOne,$objectTwo,$exe)
    )
    & $env:ComSpec /d /s /c ($parts -join ' && ')
    if ($LASTEXITCODE -ne 0) { throw 'Support contract compilation failed.' }

    & $exe $base $insideFile $outsideFile $junctionFile
    if ($LASTEXITCODE -ne 0) { throw 'Support contract failed.' }
}
finally {
    if (Test-Path -LiteralPath $root -PathType Container) {
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $root).Path).TrimEnd('\')
        if (-not $resolved.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -cne $leaf) {
            throw "Unsafe support contract cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
