[CmdletBinding()]
param(
    [switch]$Integration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Passed = 0
$script:Failed = 0

function Assert-Cf7Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Cf7BytesEqual {
    param([byte[]]$Actual, [byte[]]$Expected, [string]$Message)
    Assert-Cf7Test ($Actual.Length -eq $Expected.Length) "$Message (length)"
    for ($index = 0; $index -lt $Actual.Length; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) { throw "$Message (offset $index)" }
    }
}

function Invoke-Cf7Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
    } catch {
        $script:Failed++
        Write-Host "[FAIL] $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Write-Cf7Utf8NoBom {
    param([string]$Path, [string]$Text)
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false, $true))
}

function Invoke-Cf7Generator {
    param(
        [string]$PowerShellPath,
        [string]$GeneratorPath,
        [string]$OutputPath,
        [AllowNull()][string]$NodeBinding,
        [switch]$Check,
        [switch]$FailGate
    )

    $oldNode = [Environment]::GetEnvironmentVariable('CF7_NODE_EXE', [EnvironmentVariableTarget]::Process)
    $oldFail = [Environment]::GetEnvironmentVariable('CF7_TOOLCHAIN_TEST_FAIL_GATE', [EnvironmentVariableTarget]::Process)
    try {
        [Environment]::SetEnvironmentVariable('CF7_NODE_EXE', $NodeBinding, [EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable('CF7_TOOLCHAIN_TEST_FAIL_GATE', $(if ($FailGate) { '1' } else { $null }), [EnvironmentVariableTarget]::Process)
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $GeneratorPath, '-OutputPath', $OutputPath)
        if ($Check) { $arguments += '-Check' }
        $oldErrorAction = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $PowerShellPath @arguments 2>&1)
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldErrorAction
        }
        return @{ exitCode = $exitCode; output = $output }
    } finally {
        [Environment]::SetEnvironmentVariable('CF7_NODE_EXE', $oldNode, [EnvironmentVariableTarget]::Process)
        [Environment]::SetEnvironmentVariable('CF7_TOOLCHAIN_TEST_FAIL_GATE', $oldFail, [EnvironmentVariableTarget]::Process)
    }
}

$generator = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'write-qualification-toolchain.ps1')).Path
$assembler = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'assemble-a6-evidence.js')).Path
$systemRoot = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
$powershell = (Resolve-Path -LiteralPath (Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')).Path
$nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $nodeCommand) { throw 'Node.js is required for qualification toolchain tests.' }
$node = (Resolve-Path -LiteralPath $nodeCommand.Source).Path

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('cf7-audio-v2-toolchain-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $fixtureRoot = Join-Path $tempRoot 'fixture-repo'
    $fixtureTools = Join-Path $fixtureRoot 'tools'
    $fixtureAudio = Join-Path $fixtureTools 'audio-v2'
    $fixtureBins = Join-Path $fixtureRoot 'fixture-tools'
    New-Item -ItemType Directory -Path $fixtureAudio -Force | Out-Null
    New-Item -ItemType Directory -Path $fixtureBins -Force | Out-Null
    [IO.File]::Copy($generator, (Join-Path $fixtureAudio 'write-qualification-toolchain.ps1'))

    foreach ($relative in @('cl.exe', 'dotnet.exe', 'vcvars64.bat')) {
        Write-Cf7Utf8NoBom -Path (Join-Path $fixtureBins $relative) -Text ("fixture $relative`n")
    }
    $markerPath = Join-Path $fixtureRoot 'environment-check-calls.txt'
    $fixtureGate = @'
param([string]$ProjectRoot, [string]$Mode)
$ErrorActionPreference = 'Stop'
if ($Mode -ne 'RuntimePublish') { throw 'fixture requires RuntimePublish' }
if ($env:CF7_TOOLCHAIN_TEST_FAIL_GATE -eq '1') { throw 'fixture environment gate failed' }
[IO.File]::AppendAllText((Join-Path $ProjectRoot 'environment-check-calls.txt'), "called`n", [Text.UTF8Encoding]::new($false))
$bins = Join-Path $ProjectRoot 'fixture-tools'
$env:CF7_DOTNET_EXE = Join-Path $bins 'dotnet.exe'
$env:CF7_CL_EXE = Join-Path $bins 'cl.exe'
$env:CF7_VCVARS64 = Join-Path $bins 'vcvars64.bat'
$env:CF7_MSVC_TOOLS_VERSION = '14.99.fixture'
$env:CF7_WINDOWS_SDK_VERSION = '10.0.fixture'
'@
    Write-Cf7Utf8NoBom -Path (Join-Path $fixtureTools 'check-runtime-build-env.ps1') -Text $fixtureGate

    $fixtureGenerator = (Resolve-Path -LiteralPath (Join-Path $fixtureAudio 'write-qualification-toolchain.ps1')).Path
    $toolchainPath = Join-Path $fixtureRoot 'qualification-toolchain.json'

    Invoke-Cf7Test 'fixture gate writes assembler-exact canonical JSON without MSVC' {
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $toolchainPath -NodeBinding $node
        Assert-Cf7Test ($result.exitCode -eq 0) ("generator failed: " + ($result.output -join ' | '))
        $bytes = [IO.File]::ReadAllBytes($toolchainPath)
        Assert-Cf7Test ($bytes.Length -gt 1) 'toolchain JSON is empty'
        Assert-Cf7Test -Condition (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) -Message 'toolchain JSON has a UTF-8 BOM'
        Assert-Cf7Test -Condition (-not ($bytes -contains 0x0D)) -Message 'toolchain JSON contains CR bytes'
        $value = ([Text.UTF8Encoding]::new($false, $true).GetString($bytes)) | ConvertFrom-Json
        $actualKeys = @($value.PSObject.Properties.Name | Sort-Object)
        $expectedKeys = @('cl', 'cmd', 'dotnet', 'msvcToolsVersion', 'node', 'nodeVersion', 'powershell', 'schema', 'vcvars64', 'windowsSdkVersion')
        Assert-Cf7Test (($actualKeys -join '|') -eq ($expectedKeys -join '|')) 'top-level keys differ'
        Assert-Cf7Test ($value.schema -eq 'cf7.audio-v2.qualification-toolchain.v1') 'schema differs'
        Assert-Cf7Test ($value.node.path -eq $node) 'explicit Node binding was not preserved'
        foreach ($name in @('cl', 'cmd', 'dotnet', 'node', 'powershell', 'vcvars64')) {
            Assert-Cf7Test ($value.$name.sha256 -match '^[A-F0-9]{64}$') "$name SHA is not uppercase SHA-256"
            Assert-Cf7Test ($value.$name.sha256 -eq (Get-FileHash -LiteralPath $value.$name.path -Algorithm SHA256).Hash.ToUpperInvariant()) "$name SHA differs"
        }
        $validation = @(& $node -e 'require(process.argv[1]).validateToolchain(process.argv[2])' $assembler $toolchainPath 2>&1)
        Assert-Cf7Test ($LASTEXITCODE -eq 0) ("assembler rejected generated toolchain: " + ($validation -join ' | '))
        Assert-Cf7Test (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter '.qualification-toolchain.json.*.tmp').Count -eq 0) 'successful atomic rename left a temporary file'
    }

    Invoke-Cf7Test 'Check and Validate alias are read-only exact-current validators' {
        $before = [IO.File]::ReadAllBytes($toolchainPath)
        $beforeWrite = (Get-Item -LiteralPath $toolchainPath).LastWriteTimeUtc
        $checked = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $toolchainPath -NodeBinding $node -Check
        Assert-Cf7Test ($checked.exitCode -eq 0) ("Check failed: " + ($checked.output -join ' | '))
        $aliasOutput = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $fixtureGenerator -OutputPath $toolchainPath -Validate 2>&1)
        Assert-Cf7Test ($LASTEXITCODE -eq 0) ("Validate alias failed: " + ($aliasOutput -join ' | '))
        Assert-Cf7BytesEqual -Actual ([IO.File]::ReadAllBytes($toolchainPath)) -Expected $before -Message 'check mode changed output bytes'
        Assert-Cf7Test ((Get-Item -LiteralPath $toolchainPath).LastWriteTimeUtc -eq $beforeWrite) 'check mode changed output timestamp'
    }

    Invoke-Cf7Test 'drifted JSON fails Check and remains unchanged' {
        $drift = [Text.UTF8Encoding]::new($false).GetBytes("{}`n")
        [IO.File]::WriteAllBytes($toolchainPath, $drift)
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $toolchainPath -NodeBinding $node -Check
        Assert-Cf7Test ($result.exitCode -ne 0) 'Check accepted drifted JSON'
        Assert-Cf7BytesEqual -Actual ([IO.File]::ReadAllBytes($toolchainPath)) -Expected $drift -Message 'failed Check changed drifted output'
    }

    Invoke-Cf7Test 'CreateNew publication preserves an existing destination' {
        $existing = [Text.UTF8Encoding]::new($false).GetBytes("existing`n")
        [IO.File]::WriteAllBytes($toolchainPath, $existing)
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $toolchainPath -NodeBinding $node
        Assert-Cf7Test ($result.exitCode -ne 0) 'generator replaced an existing destination'
        Assert-Cf7BytesEqual -Actual ([IO.File]::ReadAllBytes($toolchainPath)) -Expected $existing -Message 'CreateNew conflict changed destination'
        Assert-Cf7Test (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter '.qualification-toolchain.json.*.tmp').Count -eq 0) 'CreateNew conflict left a temporary file'
    }

    Invoke-Cf7Test 'environment-gate failure leaves no output or temporary file' {
        $failedPath = Join-Path $fixtureRoot 'gate-failed.json'
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $failedPath -NodeBinding $node -FailGate
        Assert-Cf7Test ($result.exitCode -ne 0) 'failed environment gate was accepted'
        Assert-Cf7Test (-not (Test-Path -LiteralPath $failedPath)) 'failed environment gate left output'
        Assert-Cf7Test (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter '.gate-failed.json.*.tmp').Count -eq 0) 'failed environment gate left a temporary file'
    }

    Invoke-Cf7Test 'invalid explicit CF7_NODE_EXE never falls back to PATH' {
        $failedPath = Join-Path $fixtureRoot 'bad-node.json'
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $failedPath -NodeBinding 'node.exe'
        Assert-Cf7Test ($result.exitCode -ne 0) 'relative explicit Node binding was accepted or replaced from PATH'
        Assert-Cf7Test (-not (Test-Path -LiteralPath $failedPath)) 'invalid Node binding left output'
    }

    Invoke-Cf7Test 'missing CF7_NODE_EXE performs the ordinary source fallback once' {
        $fallbackPath = Join-Path $fixtureRoot 'fallback-toolchain.json'
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $fallbackPath -NodeBinding $null
        Assert-Cf7Test ($result.exitCode -eq 0) ("Node fallback failed: " + ($result.output -join ' | '))
        $value = Get-Content -LiteralPath $fallbackPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Assert-Cf7Test ($value.node.path -eq $node) 'Node fallback did not bind the canonical command path'
    }

    Invoke-Cf7Test 'unsafe relative output is rejected before running the environment gate' {
        $beforeCalls = if (Test-Path -LiteralPath $markerPath) { @(Get-Content -LiteralPath $markerPath).Count } else { 0 }
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath 'relative-toolchain.json' -NodeBinding $node
        Assert-Cf7Test ($result.exitCode -ne 0) 'relative output was accepted'
        $afterCalls = if (Test-Path -LiteralPath $markerPath) { @(Get-Content -LiteralPath $markerPath).Count } else { 0 }
        Assert-Cf7Test ($afterCalls -eq $beforeCalls) 'unsafe output still ran the environment gate'
    }

    Invoke-Cf7Test 'output path through a junction is rejected before the environment gate' {
        $realParent = Join-Path $fixtureRoot 'real-output-parent'
        $junctionParent = Join-Path $fixtureRoot 'junction-output-parent'
        New-Item -ItemType Directory -Path $realParent | Out-Null
        New-Item -ItemType Junction -Path $junctionParent -Target $realParent | Out-Null
        $beforeCalls = @(Get-Content -LiteralPath $markerPath).Count
        $junctionOutput = Join-Path $junctionParent 'toolchain.json'
        $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $fixtureGenerator -OutputPath $junctionOutput -NodeBinding $node
        Assert-Cf7Test ($result.exitCode -ne 0) 'junction output parent was accepted'
        Assert-Cf7Test (-not (Test-Path -LiteralPath (Join-Path $realParent 'toolchain.json'))) 'junction rejection still wrote through the target'
        Assert-Cf7Test (@(Get-Content -LiteralPath $markerPath).Count -eq $beforeCalls) 'junction output still ran the environment gate'
    }

    if ($Integration) {
        Invoke-Cf7Test 'optional local pinned-environment integration reaches assembler validation' {
            $integrationPath = Join-Path $tempRoot 'local-integration-toolchain.json'
            $result = Invoke-Cf7Generator -PowerShellPath $powershell -GeneratorPath $generator -OutputPath $integrationPath -NodeBinding $node
            Assert-Cf7Test ($result.exitCode -eq 0) ("local pinned environment is unavailable: " + ($result.output -join ' | '))
            $validation = @(& $node -e 'require(process.argv[1]).validateToolchain(process.argv[2])' $assembler $integrationPath 2>&1)
            Assert-Cf7Test ($LASTEXITCODE -eq 0) ("assembler rejected local integration output: " + ($validation -join ' | '))
        }
    } else {
        Write-Host '[SKIP] optional local pinned-environment integration (pass -Integration to enable)' -ForegroundColor Yellow
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "Audio v2 qualification toolchain tests: $script:Passed passed, $script:Failed failed"
if ($script:Failed -gt 0) { exit 1 }
