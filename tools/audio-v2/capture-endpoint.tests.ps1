[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$captureTool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'capture-endpoint.ps1'))
$captureText = [IO.File]::ReadAllText($captureTool)
$script:Passed = 0

function Assert-Cf7Test {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if (-not $Condition) { throw "assertion failed: $Message" }
}

function Invoke-Cf7Test {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][scriptblock]$Body
    )
    & $Body
    $script:Passed++
    Write-Output ("ok {0} - {1}" -f $script:Passed, $Name)
}

function Get-Cf7TestSha256 {
    param([Parameter(Mandatory=$true)][string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '')
    } finally {
        $algorithm.Dispose()
    }
}

function Invoke-Cf7NegativeCapture {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Arguments,
        [Parameter(Mandatory=$true)][string]$ExpectedMessage
    )
    $cli = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @(
        'CaptureId','CaseId','CandidateRoot','CandidateBuildIdentity','CandidatePayloadClosure',
        'CandidateProcessId','SelectedBackend','EndpointId','DeviceIdDigest','DurationSeconds',
        'RunId','OutputWav','OutputConfiguration')) {
        [void]$cli.Add('-' + $key)
        [void]$cli.Add([string]$Arguments[$key])
    }
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $captureTool @($cli.ToArray()) 2>&1
        $status = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    Assert-Cf7Test ($status -ne 0) 'negative capture invocation unexpectedly succeeded'
    $combinedOutput = [string]::Join("`n", [string[]]$output)
    Assert-Cf7Test ($combinedOutput -match [regex]::Escape($ExpectedMessage)) "negative failure did not contain '$ExpectedMessage'; actual: $combinedOutput"
    Assert-Cf7Test (-not (Test-Path -LiteralPath $Arguments.OutputWav)) 'negative capture published a WAV'
    Assert-Cf7Test (-not (Test-Path -LiteralPath $Arguments.OutputConfiguration)) 'negative capture published a configuration'
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($captureTool, [ref]$tokens, [ref]$parseErrors)

Invoke-Cf7Test 'PowerShell source parses without errors' {
    Assert-Cf7Test ($null -ne $ast) 'parser returned no AST'
    $parseMessage = [string]::Join('; ', @($parseErrors | ForEach-Object { $_.Message }))
    if (-not $parseMessage) { $parseMessage = 'PowerShell parser returned an unspecified error' }
    Assert-Cf7Test ($parseErrors.Count -eq 0) $parseMessage
}

Invoke-Cf7Test 'embedded WASAPI implementation compiles' {
    $sourceMatch = [regex]::Match($captureText, "(?s)\`$captureSource = @'\r?\n(?<source>.*?)\r?\n'@")
    Assert-Cf7Test $sourceMatch.Success 'embedded capture source was not found'
    Add-Type -TypeDefinition $sourceMatch.Groups['source'].Value -Language CSharp -ErrorAction Stop
    Assert-Cf7Test ($null -ne ('Cf7.AudioV2.EndpointCapture.WasapiLoopbackCapture' -as [type])) 'embedded capture type was not loaded'
}

Invoke-Cf7Test 'capture selects an explicit real endpoint and WASAPI loopback' {
    Assert-Cf7Test ($captureText -match 'AUDCLNT_STREAMFLAGS_LOOPBACK') 'loopback stream flag is absent'
    Assert-Cf7Test ($captureText -match 'enumerator\.GetDevice\(endpointId') 'explicit endpoint lookup is absent'
    Assert-Cf7Test ($captureText -notmatch 'enumerator\.GetDefaultAudioEndpoint') 'default endpoint lookup is reachable'
    Assert-Cf7Test ($captureText -match 'Marshal\.Copy\(packetData, raw') 'real WASAPI packet copy is absent'
}

Invoke-Cf7Test 'capture source exposes no synthesized-audio or bypass path' {
    Assert-Cf7Test ($captureText -notmatch '(?i)\b(ffmpeg|sox|naudio|soundplayer|sine|tone|oscillator)\b') 'external or synthesized audio producer is referenced'
    Assert-Cf7Test ($captureText -notmatch '(?i)\b(skipcapture|syntheticcapture|testcapture|allowfake)\b') 'capture bypass switch is present'
    Assert-Cf7Test ($captureText -match 'real WASAPI silent packet') 'silent packet provenance is not explicit'
    Assert-Cf7Test ($captureText -match 'MinimumPeakAbsolutePcm16 = 64') 'peak gate is missing'
    Assert-Cf7Test ($captureText -match 'MinimumNonZeroSampleRatio = 0\.001') 'non-zero sample gate is missing'
}

Invoke-Cf7Test 'capture binds immutable candidate process and output artifacts' {
    Assert-Cf7Test ($captureText -match 'candidate PID does not execute the exact candidate Core') 'exact candidate PID/path check is absent'
    Assert-Cf7Test ($captureText -match 'candidate process did not remain stable') 'candidate process stability check is absent'
    Assert-Cf7Test ($captureText -match 'FileMode\.CreateNew') 'WAV creation is not immutable'
    Assert-Cf7Test ($captureText -match 'already exists; capture artifacts are immutable') 'output immutability preflight is absent'
    Assert-Cf7Test ($captureText -match 'capture tool bytes changed while capture was running') 'tool byte stability check is absent'
    $captureBytes = [IO.File]::ReadAllBytes($captureTool)
    Assert-Cf7Test ($captureBytes[$captureBytes.Length - 1] -eq 10 -and -not ($captureBytes -contains 13)) 'capture tool bytes are not canonical LF'
    Assert-Cf7Test ($captureText -match 'digest equals the release-source Git blob') 'release-source LF/digest preflight is absent'
}

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
$testRoot = Join-Path $temporaryBase ('cf7-audio-capture-tests-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
try {
    $endpointId = 'cf7-test-endpoint-id'
    $validDigest = Get-Cf7TestSha256 -Text $endpointId
    $baseArguments = @{
        CaptureId = 'bgm_playback'
        CaseId = 'bgm_playback'
        CandidateRoot = Join-Path $testRoot 'missing-candidate'
        CandidateBuildIdentity = 'A' * 64
        CandidatePayloadClosure = 'B' * 64
        CandidateProcessId = 1
        SelectedBackend = 'wasapi'
        EndpointId = $endpointId
        DeviceIdDigest = $validDigest
        DurationSeconds = '1'
        RunId = 'capture-negative-test'
        OutputWav = Join-Path $testRoot 'negative.wav'
        OutputConfiguration = Join-Path $testRoot 'negative.json'
    }

    Invoke-Cf7Test 'mismatched case and capture IDs fail before acquisition' {
        $arguments = $baseArguments.Clone()
        $arguments.CaseId = 'sfx_playback'
        Invoke-Cf7NegativeCapture -Arguments $arguments -ExpectedMessage 'captureId must equal its unique endpoint caseId'
    }

    Invoke-Cf7Test 'endpoint digest mismatch fails before acquisition' {
        $arguments = $baseArguments.Clone()
        $arguments.DeviceIdDigest = 'C' * 64
        Invoke-Cf7NegativeCapture -Arguments $arguments -ExpectedMessage 'EndpointId does not match DeviceIdDigest'
    }

    Invoke-Cf7Test 'non-canonical candidate root fails before acquisition' {
        $arguments = $baseArguments.Clone()
        Invoke-Cf7NegativeCapture -Arguments $arguments -ExpectedMessage 'CandidateRoot does not exist'
    }

    Invoke-Cf7Test 'wrong candidate process path fails without publishing evidence' {
        $candidateRoot = Join-Path $testRoot 'candidate'
        $runtimeRoot = Join-Path $candidateRoot 'runtime'
        [void](New-Item -ItemType Directory -Path $runtimeRoot)
        [IO.File]::WriteAllBytes((Join-Path $runtimeRoot 'CRAZYFLASHER7MercenaryEmpire.Core.exe'), [Text.Encoding]::ASCII.GetBytes('not-an-executable'))
        [IO.File]::WriteAllBytes((Join-Path $runtimeRoot 'miniaudio.dll'), [Text.Encoding]::ASCII.GetBytes('not-a-dll'))
        $manifest = [string]::Join("`n", @(
            'cf7-runtime-manifest-v2',
            ("buildIdentityHash`t" + ('A' * 64)),
            ("payloadClosureHash`t" + ('B' * 64)),
            ''
        ))
        [IO.File]::WriteAllText((Join-Path $runtimeRoot 'cf7-runtime-manifest.tsv'), $manifest, (New-Object Text.UTF8Encoding($false)))
        $arguments = $baseArguments.Clone()
        $arguments.CandidateRoot = $candidateRoot
        $arguments.CandidateProcessId = $PID
        Invoke-Cf7NegativeCapture -Arguments $arguments -ExpectedMessage 'candidate PID does not execute the exact candidate Core'
    }
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if ($resolvedTestRoot.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedTestRoot).StartsWith('cf7-audio-capture-tests-', [StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedTestRoot) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
    } else {
        throw "unsafe test cleanup path: $resolvedTestRoot"
    }
}

Write-Output ("capture-endpoint tests passed: {0}" -f $script:Passed)
