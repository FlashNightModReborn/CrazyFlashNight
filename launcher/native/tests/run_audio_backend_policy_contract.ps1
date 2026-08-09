[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$nativeRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-audio-backend-policy-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    & (Join-Path $repoRoot 'tools\check-runtime-build-env.ps1') -ProjectRoot $repoRoot -Mode Validate
    foreach ($requiredName in @(
        'CF7_VCVARS64',
        'CF7_MSVC_TOOLS_VERSION',
        'CF7_WINDOWS_SDK_VERSION',
        'CF7_CL_EXE'
    )) {
        if ([string]::IsNullOrWhiteSpace(
                [Environment]::GetEnvironmentVariable($requiredName, 'Process'))) {
            throw "Pinned compiler environment is unavailable: $requiredName"
        }
    }
    $source = Join-Path $PSScriptRoot 'audio_backend_policy_contract.c'
    $policy = Join-Path $nativeRoot 'audio_backend_policy.c'
    $output = Join-Path $tempRoot 'audio_backend_policy_contract.exe'
    $objectOne = Join-Path $tempRoot 'contract.obj'
    $objectTwo = Join-Path $tempRoot 'policy.obj'
    $assertPinned = Join-Path $nativeRoot 'assert-pinned-tools.bat'
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:CF7_VSWHERE_DIR)) {
        $parts += 'set "PATH=%CF7_VSWHERE_DIR%;%PATH%"'
    }
    $parts += @(
        ('call "{0}" {1} -vcvars_ver={2} >nul' -f
            $env:CF7_VCVARS64,
            $env:CF7_WINDOWS_SDK_VERSION,
            $env:CF7_MSVC_TOOLS_VERSION),
        ('call "{0}" >nul' -f $assertPinned),
        ('"{0}" /nologo /TC /W4 /WX /utf-8 /I"{1}" /c "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE, $nativeRoot, $source, $objectOne),
        ('"{0}" /nologo /TC /W4 /WX /utf-8 /I"{1}" /c "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE, $nativeRoot, $policy, $objectTwo),
        ('"{0}" /nologo "{1}" "{2}" /Fe:"{3}"' -f
            $env:CF7_CL_EXE, $objectOne, $objectTwo, $output)
    )
    & $env:ComSpec /d /s /c ($parts -join ' && ')
    if ($LASTEXITCODE -ne 0) { throw 'Audio backend policy contract compilation failed.' }
    & $output
    if ($LASTEXITCODE -ne 0) { throw 'Audio backend policy contract failed.' }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
