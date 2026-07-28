[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory = $true)]
    [string]$CandidateRoot,
    [string]$QualificationExe
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')
$CandidateRoot = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\')
if ([string]::IsNullOrWhiteSpace($QualificationExe)) {
    $QualificationExe = Join-Path $ProjectRoot `
        'tmp\player-info-hud-renderer-qualification\bin\Release\net10.0-windows\win-x64\RendererQualification.exe'
}
$QualificationExe = (Resolve-Path -LiteralPath $QualificationExe).Path

$sourceRuntime = Join-Path $CandidateRoot 'runtime'
if (-not (Test-Path -LiteralPath $sourceRuntime -PathType Container)) {
    throw "Candidate runtime directory is missing: $sourceRuntime"
}
if (-not (Test-Path -LiteralPath $QualificationExe -PathType Leaf)) {
    throw "Qualification executable is missing: $QualificationExe"
}

$testBase = [IO.Path]::GetFullPath(
    (Join-Path $ProjectRoot 'tmp\player-info-hud-production-contract-negative-tests')
).TrimEnd('\')
$jobRoot = Join-Path $testBase ([Guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $jobRoot 'candidate'
$fixtureRuntime = Join-Path $fixtureRoot 'runtime'
$checks = 0

function Copy-RequiredFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $source = Join-Path $sourceRuntime $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Candidate test input is missing: runtime/$RelativePath"
    }
    $destination = Join-Path $fixtureRuntime $RelativePath
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [IO.File]::Copy($source, $destination, $false)
}

function Invoke-Contract {
    param(
        [Parameter(Mandatory = $true)][string]$Case,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][string]$ExpectedOutput
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(
            & $QualificationExe `
                --production-contract-only `
                --project-root $ProjectRoot `
                --candidate-root $fixtureRoot 2>&1
        )
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = $output -join "`n"
    if ($exitCode -ne $ExpectedExitCode) {
        throw "$Case returned exit $exitCode instead of $ExpectedExitCode. Output: $text"
    }
    if ($text.IndexOf($ExpectedOutput, [StringComparison]::Ordinal) -lt 0) {
        throw "$Case did not emit '$ExpectedOutput'. Output: $text"
    }
    $script:checks++
}

function Set-UnexpectedRendererPackage {
    param(
        [Parameter(Mandatory = $true)][string]$DepsPath,
        [Parameter(Mandatory = $true)][byte[]]$OriginalBytes,
        [Parameter(Mandatory = $true)][string]$PackageIdentity
    )

    $deps = [Text.Encoding]::UTF8.GetString($OriginalBytes) | ConvertFrom-Json
    $rendererTarget = @($deps.targets.PSObject.Properties | Where-Object {
        $null -ne $_.Value.PSObject.Properties['Svg.Skia/5.1.1']
    } | Select-Object -First 1)
    if ($rendererTarget.Count -ne 1) {
        throw 'Cannot locate the renderer-bearing deps target in the valid candidate.'
    }
    $deps.libraries | Add-Member `
        -MemberType NoteProperty `
        -Name $PackageIdentity `
        -Value ([pscustomobject]@{})
    $rendererTarget[0].Value | Add-Member `
        -MemberType NoteProperty `
        -Name $PackageIdentity `
        -Value ([pscustomobject]@{})
    $json = ($deps | ConvertTo-Json -Depth 100) + "`n"
    [IO.File]::WriteAllText(
        $DepsPath,
        $json,
        (New-Object Text.UTF8Encoding($false)))
}

$requiredRuntimeFiles = @(
    'CRAZYFLASHER7MercenaryEmpire.Core.dll',
    'CRAZYFLASHER7MercenaryEmpire.Core.deps.json',
    'THIRD-PARTY-NOTICES.txt',
    'ExCSS.dll',
    'HarfBuzzSharp.dll',
    'libHarfBuzzSharp.dll',
    'ShimSkiaSharp.dll',
    'SkiaSharp.dll',
    'libSkiaSharp.dll',
    'Svg.Animation.dll',
    'Svg.Custom.dll',
    'Svg.Model.dll',
    'Svg.SceneGraph.dll',
    'Svg.Skia.dll'
)

try {
    New-Item -ItemType Directory -Path $fixtureRuntime -Force | Out-Null
    foreach ($relativePath in $requiredRuntimeFiles) {
        Copy-RequiredFile -RelativePath $relativePath
    }

    Invoke-Contract `
        -Case 'baseline' `
        -ExpectedExitCode 0 `
        -ExpectedOutput 'PLAYER_INFO_PRODUCTION_CONTRACT_OK'

    $unexpectedDll = Join-Path $fixtureRuntime 'Svg.Foo.dll'
    [IO.File]::WriteAllBytes($unexpectedDll, [byte[]](1))
    try {
        Invoke-Contract `
            -Case 'unexpected-svg-dll' `
            -ExpectedExitCode 1 `
            -ExpectedOutput 'Candidate renderer payload closure mismatch'
    } finally {
        if (Test-Path -LiteralPath $unexpectedDll) {
            Remove-Item -LiteralPath $unexpectedDll -Force
        }
    }

    $unexpectedNative = Join-Path $fixtureRuntime 'native\linux-x64\libHarfBuzzSharp.so'
    New-Item -ItemType Directory -Path (Split-Path -Parent $unexpectedNative) -Force |
        Out-Null
    [IO.File]::WriteAllBytes($unexpectedNative, [byte[]](1))
    try {
        Invoke-Contract `
            -Case 'unexpected-linux-native' `
            -ExpectedExitCode 1 `
            -ExpectedOutput 'Candidate renderer payload closure mismatch'
    } finally {
        if (Test-Path -LiteralPath $unexpectedNative) {
            Remove-Item -LiteralPath $unexpectedNative -Force
        }
    }

    $junctionTarget = Join-Path $jobRoot 'junction-target'
    $unexpectedJunction = Join-Path $fixtureRuntime 'linked-renderer'
    New-Item -ItemType Directory -Path $junctionTarget -Force | Out-Null
    [IO.File]::WriteAllBytes(
        (Join-Path $junctionTarget 'Svg.Foo.dll'),
        [byte[]](1))
    New-Item `
        -ItemType Junction `
        -Path $unexpectedJunction `
        -Target $junctionTarget | Out-Null
    try {
        Invoke-Contract `
            -Case 'runtime-junction' `
            -ExpectedExitCode 1 `
            -ExpectedOutput 'Candidate runtime closure contains a reparse point'
    } finally {
        if (Test-Path -LiteralPath $unexpectedJunction) {
            [IO.Directory]::Delete($unexpectedJunction)
        }
    }

    $depsPath = Join-Path $fixtureRuntime 'CRAZYFLASHER7MercenaryEmpire.Core.deps.json'
    $originalDeps = [IO.File]::ReadAllBytes($depsPath)
    try {
        Set-UnexpectedRendererPackage `
            -DepsPath $depsPath `
            -OriginalBytes $originalDeps `
            -PackageIdentity 'Svg.Foo/1.0.0'
        Invoke-Contract `
            -Case 'unexpected-deps-package' `
            -ExpectedExitCode 1 `
            -ExpectedOutput 'Candidate renderer dependency libraries closure mismatch'
    } finally {
        [IO.File]::WriteAllBytes($depsPath, $originalDeps)
    }

    try {
        Set-UnexpectedRendererPackage `
            -DepsPath $depsPath `
            -OriginalBytes $originalDeps `
            -PackageIdentity 'SvgUnexpected/1.0.0'
        Invoke-Contract `
            -Case 'unexpected-renderer-family-prefix' `
            -ExpectedExitCode 1 `
            -ExpectedOutput 'Candidate renderer dependency libraries closure mismatch'
    } finally {
        [IO.File]::WriteAllBytes($depsPath, $originalDeps)
    }

    try {
        $originalDepsText = [Text.Encoding]::UTF8.GetString($originalDeps)
        $needle = '"Svg.Skia/5.1.1": {'
        $replacement = '"Svg.Skia/5.1.1": {},' + "`n      " + $needle
        $duplicateDepsText = ([regex]::new([regex]::Escape($needle))).Replace(
            $originalDepsText,
            $replacement,
            1)
        if ([string]::Equals(
                $duplicateDepsText,
                $originalDepsText,
                [StringComparison]::Ordinal)) {
            throw 'Cannot inject duplicate renderer identity into the valid candidate deps.'
        }
        [IO.File]::WriteAllText(
            $depsPath,
            $duplicateDepsText,
            (New-Object Text.UTF8Encoding($false)))
        Invoke-Contract `
            -Case 'duplicate-renderer-target-identity' `
            -ExpectedExitCode 1 `
            -ExpectedOutput 'duplicates=[Svg.Skia/5.1.1]'
    } finally {
        [IO.File]::WriteAllBytes($depsPath, $originalDeps)
    }

    Invoke-Contract `
        -Case 'restored-baseline' `
        -ExpectedExitCode 0 `
        -ExpectedOutput 'PLAYER_INFO_PRODUCTION_CONTRACT_OK'

    Write-Host "[PlayerInfoProductionContractTest] OK checks=$checks" `
        -ForegroundColor Green
} finally {
    $resolvedJob = [IO.Path]::GetFullPath($jobRoot)
    if ($resolvedJob.StartsWith($testBase + '\', [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolvedJob)) {
        Remove-Item -LiteralPath $resolvedJob -Recurse -Force
    }
}
