[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DllPath,

    [string]$ContainedBasePath,

    [string]$LargeM4aSourcePath,

    [switch]$SkipShippedLargeM4a
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$nativeRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $nativeRoot '..\..')).Path
$resolvedDll = (Resolve-Path -LiteralPath $DllPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $resolvedDll -PathType Leaf)) {
    throw "Audio v2 DLL is not a file: $resolvedDll"
}
$resolvedBase = $null
if (-not [string]::IsNullOrWhiteSpace($ContainedBasePath)) {
    $resolvedBase = (Resolve-Path -LiteralPath $ContainedBasePath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedBase -PathType Container)) {
        throw "Contained base is not a directory: $resolvedBase"
    }
}
$resolvedLargeM4a = $null
$decoderFixtureManifest = Join-Path $projectRoot `
    'tools\audio-v2\qualification-decoder-fixtures.v1.json'
if (-not (Test-Path -LiteralPath $decoderFixtureManifest -PathType Leaf)) {
    throw "Decoder fixture manifest is missing: $decoderFixtureManifest"
}
if ($SkipShippedLargeM4a -and
    -not [string]::IsNullOrWhiteSpace($LargeM4aSourcePath)) {
    throw 'LargeM4aSourcePath and SkipShippedLargeM4a are mutually exclusive.'
}
if (-not $SkipShippedLargeM4a -and
    [string]::IsNullOrWhiteSpace($LargeM4aSourcePath)) {
    $largeM4aCandidates = @(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'sounds') `
            -Recurse -File -Filter '*.m4a' |
            Where-Object { $_.Length -gt 8388608 }
    )
    if ($largeM4aCandidates.Count -ne 1) {
        throw "Expected exactly one shipped M4A larger than 8 MiB; found $($largeM4aCandidates.Count)."
    }
    $LargeM4aSourcePath = $largeM4aCandidates[0].FullName
}
if (-not $SkipShippedLargeM4a) {
    $resolvedLargeM4a = (Resolve-Path -LiteralPath $LargeM4aSourcePath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedLargeM4a -PathType Leaf)) {
        throw "Large M4A source is not a file: $resolvedLargeM4a"
    }
}

& (Join-Path $projectRoot 'tools\check-runtime-build-env.ps1') `
    -ProjectRoot $projectRoot `
    -Mode Validate

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$leaf = 'cf7-audio-runtime-contract-' + [Guid]::NewGuid().ToString('N')
$tempRoot = [IO.Path]::GetFullPath((Join-Path $tempParent $leaf)).TrimEnd('\')
if (-not $tempRoot.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($tempRoot) -cne $leaf) {
    throw "Unsafe runtime contract root: $tempRoot"
}
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$decoderFixtureRoot = $null

try {
    if ([string]::IsNullOrWhiteSpace($resolvedBase)) {
        $resolvedBase = Join-Path $tempRoot 'contained'
        New-Item -ItemType Directory -Path $resolvedBase | Out-Null
    }
    $fixtureLeaf = '.cf7-audio-decoder-contract-' + [Guid]::NewGuid().ToString('N')
    $decoderFixtureRoot = [IO.Path]::GetFullPath(
        (Join-Path $resolvedBase $fixtureLeaf)).TrimEnd('\')
    $resolvedBaseFull = [IO.Path]::GetFullPath($resolvedBase).TrimEnd('\')
    if (-not $decoderFixtureRoot.StartsWith(
            $resolvedBaseFull + '\',
            [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($decoderFixtureRoot) -cne $fixtureLeaf) {
        throw "Unsafe decoder fixture root: $decoderFixtureRoot"
    }
    New-Item -ItemType Directory -Path $decoderFixtureRoot | Out-Null
    $fixtureInventory = Join-Path $tempRoot 'decoder-fixtures.tsv'
    $fixtureDefinition = Get-Content -LiteralPath $decoderFixtureManifest `
        -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($fixtureDefinition.schema -ne `
            'cf7.audio-v2.decoder-fixture-inventory.v1' -or
        @($fixtureDefinition.fixtures).Count -ne 6) {
        throw 'Decoder fixture manifest schema/count drifted.'
    }
    $fixtureExpectations = [System.Collections.Generic.List[object]]::new()
    $inventoryLines = [System.Collections.Generic.List[string]]::new()
    $fixtureIndex = 0
    foreach ($fixture in $fixtureDefinition.fixtures) {
        $bytes = [Convert]::FromBase64String([string]$fixture.bytesBase64)
        $leafName = 'fixture-{0}.bin' -f $fixtureIndex
        $fixturePath = Join-Path $decoderFixtureRoot $leafName
        [IO.File]::WriteAllBytes($fixturePath, $bytes)
        $actualDigest = (Get-FileHash -Algorithm SHA256 `
            -LiteralPath $fixturePath).Hash.ToUpperInvariant()
        $expectedDigest = ([string]$fixture.sha256).ToUpperInvariant()
        if ($actualDigest -cne $expectedDigest) {
            throw "Decoder fixture digest mismatch: $($fixture.fixtureId)"
        }
        $expectedFrames = switch ([string]$fixture.fixtureId) {
            'opus-ogg-tone-48000-mono' { 24000 }
            'silent-pcm16-wave-48000-mono' { 24000 }
            'vorbis-ogg-tone-48000-mono' { 24000 }
            default { 0 }
        }
        $fixtureExpectations.Add([pscustomobject]@{
            Category = [int]$fixture.expectedCategory
            ExpectedFrames = $expectedFrames
            FixtureId = [string]$fixture.fixtureId
            SignalClass = [string]$fixture.signalClass
        })
        $inventoryLines.Add("$leafName`t$expectedDigest")
        $fixtureIndex++
    }
    [IO.File]::WriteAllText(
        $fixtureInventory,
        (($inventoryLines -join "`n") + "`n"),
        [Text.UTF8Encoding]::new($false))
    $source = Join-Path $PSScriptRoot 'audio_bridge_v2_runtime_contract.c'
    $object = Join-Path $tempRoot 'runtime-contract.obj'
    $executable = Join-Path $tempRoot 'runtime-contract.exe'
    $probeSource = Join-Path $projectRoot `
        'tools\audio-v2\qualification-offline-probe.c'
    $probeObject = Join-Path $tempRoot 'qualification-offline-probe.obj'
    $probeExecutable = Join-Path $tempRoot 'qualification-offline-probe.exe'
    $parts = @()
    if (-not [string]::IsNullOrWhiteSpace($env:CF7_VSWHERE_DIR)) {
        $parts += 'set "PATH=%CF7_VSWHERE_DIR%;%PATH%"'
    }
    $parts += @(
        ('call "{0}" {1} -vcvars_ver={2} >nul' -f
            $env:CF7_VCVARS64,$env:CF7_WINDOWS_SDK_VERSION,$env:CF7_MSVC_TOOLS_VERSION),
        ('call "{0}" >nul' -f (Join-Path $nativeRoot 'assert-pinned-tools.bat')),
        ('"{0}" /nologo /TC /std:c17 /W4 /WX /utf-8 /I"{1}" /c "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$source,$object),
        ('"{0}" /nologo "{1}" bcrypt.lib /Fe:"{2}"' -f
            $env:CF7_CL_EXE,$object,$executable),
        ('"{0}" /nologo /TC /std:c17 /W4 /WX /utf-8 /D_CRT_SECURE_NO_WARNINGS /I"{1}" /c "{2}" /Fo"{3}"' -f
            $env:CF7_CL_EXE,$nativeRoot,$probeSource,$probeObject),
        ('"{0}" /nologo "{1}" /Fe:"{2}"' -f
            $env:CF7_CL_EXE,$probeObject,$probeExecutable)
    )
    & $env:ComSpec /d /s /c ($parts -join ' && ')
    if ($LASTEXITCODE -ne 0) {
        throw 'Audio v2 runtime contract compilation failed.'
    }
    & $executable $resolvedDll $resolvedBase
    if ($LASTEXITCODE -ne 0) {
        throw 'Audio v2 runtime contract failed for the synthetic input-bound fixture.'
    }
    if (-not [string]::IsNullOrWhiteSpace($resolvedLargeM4a)) {
        & $executable $resolvedDll $resolvedBase $resolvedLargeM4a
        if ($LASTEXITCODE -ne 0) {
            throw 'Audio v2 runtime contract failed for the shipped large M4A.'
        }
    }

    $probeOutput = @(& $probeExecutable `
        $resolvedDll $decoderFixtureRoot $fixtureInventory)
    if ($LASTEXITCODE -ne 0) {
        throw "Audio v2 decoder probe contract failed with exit code $LASTEXITCODE."
    }
    if ($probeOutput.Count -ne $fixtureExpectations.Count + 3 -or
        $probeOutput[0] -cne 'CF7_AUDIO_V2_OFFLINE_PROBE_V1' -or
        -not $probeOutput[1].StartsWith('runtime' + "`t", `
            [StringComparison]::Ordinal) -or
        $probeOutput[-1] -cne ('complete' + "`t" + $fixtureExpectations.Count)) {
        throw 'Audio v2 decoder probe output envelope/count drifted.'
    }
    for ($index = 0; $index -lt $fixtureExpectations.Count; $index++) {
        $columns = @($probeOutput[$index + 2] -split "`t")
        $expected = $fixtureExpectations[$index]
        if ($columns.Count -ne 14 -or $columns[0] -cne 'asset' -or
            [int]$columns[1] -ne $index) {
            throw "Decoder probe row is malformed at index $index."
        }
        $category = [int]$columns[2]
        $outcome = [int]$columns[3]
        $eofState = [int]$columns[4]
        $frames = [uint64]$columns[5]
        $peak = [double]::Parse($columns[7], `
            [Globalization.CultureInfo]::InvariantCulture)
        $rms = [double]::Parse($columns[8], `
            [Globalization.CultureInfo]::InvariantCulture)
        $nonFinite = [uint64]$columns[11]
        if ($category -ne $expected.Category) {
            throw "Decoder fixture category drifted: $($expected.FixtureId) expected=$($expected.Category) actual=$category"
        }
        if ($expected.Category -eq 0) {
            if ($outcome -ne 5 -or $eofState -ne 1 -or
                $frames -eq 0 -or
                ($expected.ExpectedFrames -ne 0 -and
                    $frames -ne $expected.ExpectedFrames) -or
                $nonFinite -ne 0) {
                throw "Decoder fixture EOF/frame contract drifted: $($expected.FixtureId)"
            }
            if ($expected.SignalClass -eq 'nonzero_pcm' -and
                ($peak -le 0 -or $rms -le 0)) {
                throw "Decoder fixture lost decoded signal: $($expected.FixtureId)"
            }
            if ($expected.SignalClass -eq 'intentional_silence' -and
                ($peak -ne 0 -or $rms -ne 0)) {
                throw "Silent decoder fixture emitted signal: $($expected.FixtureId)"
            }
        } elseif ($outcome -ne 7 -or $eofState -eq 1 -or $frames -ne 0) {
            throw "Damaged decoder fixture result contract drifted: $($expected.FixtureId)"
        }
    }
    Write-Host '[OK] Audio v2 decoder probe contract passed (6 fixtures).'
}
finally {
    if ($null -ne $decoderFixtureRoot -and
        (Test-Path -LiteralPath $decoderFixtureRoot -PathType Container)) {
        $resolvedFixtureRoot = [IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $decoderFixtureRoot).Path).TrimEnd('\')
        $resolvedBaseFull = [IO.Path]::GetFullPath($resolvedBase).TrimEnd('\')
        if (-not $resolvedFixtureRoot.StartsWith(
                $resolvedBaseFull + '\',
                [StringComparison]::OrdinalIgnoreCase) -or
            -not [IO.Path]::GetFileName($resolvedFixtureRoot).StartsWith(
                '.cf7-audio-decoder-contract-',
                [StringComparison]::Ordinal)) {
            throw "Unsafe decoder fixture cleanup target: $resolvedFixtureRoot"
        }
        Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolved = [IO.Path]::GetFullPath(
            (Resolve-Path -LiteralPath $tempRoot).Path).TrimEnd('\')
        if (-not $resolved.StartsWith($tempParent + '\', [StringComparison]::OrdinalIgnoreCase) -or
            [IO.Path]::GetFileName($resolved) -cne $leaf) {
            throw "Unsafe runtime contract cleanup target: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
