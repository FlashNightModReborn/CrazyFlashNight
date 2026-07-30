# Runtime build/start anti-confusion contract. Kept at tools/ root so the
# native/release policy gate binds every change to this test.
[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) {
    $testScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $testScriptDirectory
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd('\')

function Assert-Cf7Guardrail {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )
    if (-not $Condition) { throw "Runtime entry guardrail regression: $Message" }
}

function Assert-Cf7ScriptParses {
    param([Parameter(Mandatory=$true)][string]$Path)
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed for $Path`: $($errors[0].Message)"
    }
}

function Assert-Cf7Contains {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Message
    )
    Assert-Cf7Guardrail -Condition ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -ge 0) -Message $Message
}

function Assert-Cf7DoesNotContain {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [Parameter(Mandatory=$true)][string]$Needle,
        [Parameter(Mandatory=$true)][string]$Message
    )
    Assert-Cf7Guardrail -Condition ($Text.IndexOf($Needle, [StringComparison]::Ordinal) -lt 0) -Message $Message
}

$buildPath = Join-Path $ProjectRoot 'launcher\build.ps1'
$producerPath = Join-Path $ProjectRoot 'launcher\build-runtime-candidate.ps1'
$startPath = Join-Path $ProjectRoot 'automation\start.ps1'
foreach ($path in @($buildPath, $producerPath, $startPath)) {
    Assert-Cf7Guardrail -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "script missing: $path"
    Assert-Cf7ScriptParses -Path $path
}

$toolchainLockPath = Join-Path $ProjectRoot 'config\build\runtime-toolchain.lock.json'
Assert-Cf7Guardrail -Condition (Test-Path -LiteralPath $toolchainLockPath -PathType Leaf) `
    -Message "toolchain lock missing: $toolchainLockPath"
$toolchainLock = Get-Content -LiteralPath $toolchainLockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$dotnetInstallUrl = [string]$toolchainLock.provisioning.dotnetInstallScriptUrl
$dotnetInstallSha256 = [string]$toolchainLock.provisioning.dotnetInstallScriptSha256
Assert-Cf7Guardrail -Condition ($dotnetInstallUrl -cmatch '^https://raw\.githubusercontent\.com/dotnet/install-scripts/[0-9a-f]{40}/src/dotnet-install\.ps1$') `
    -Message 'dotnet-install provisioning must use an immutable official commit URL'
Assert-Cf7Guardrail -Condition ($dotnetInstallSha256 -cmatch '^[0-9A-F]{64}$') `
    -Message 'dotnet-install provisioning must pin an uppercase SHA-256'

$build = Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8
Assert-Cf7Contains $build "deploymentStatus = 'NOT_DEPLOYED'" 'build result must expose NOT_DEPLOYED'
Assert-Cf7Contains $build 'formalDeploymentModified = $false' 'build result must deny formal closure mutation explicitly'
Assert-Cf7Contains $build 'Get-Cf7FormalDeploymentSnapshot' 'build must fingerprint the complete formal deployment closure'
Assert-Cf7Contains $build 'candidateCorePath =' 'build result must expose candidate Core path'
Assert-Cf7Contains $build 'candidateCoreSha256 =' 'build result must expose candidate Core SHA256'
Assert-Cf7Contains $build 'liveCorePath =' 'build result must expose live Core path'
Assert-Cf7Contains $build 'liveCoreSha256 =' 'build result must expose live Core SHA256'
Assert-Cf7Contains $build 'Test-Cf7SameFormalDeploymentSnapshot' 'build must assert the complete formal deployment did not change'
Assert-Cf7Contains $build 'candidate ready must never be reported as deployed' 'build must print an unambiguous handoff warning'

$producer = Get-Content -LiteralPath $producerPath -Raw -Encoding UTF8
Assert-Cf7Contains $producer 'CANDIDATE ONLY - NOT DEPLOYED' 'producer must print candidate-only state'
Assert-Cf7Contains $producer 'FORMAL RUNTIME UNCHANGED' 'producer must print live deployment state'
Assert-Cf7Contains $producer 'CandidateRoot must be an absolute path.' 'producer must reject relative candidate roots'
Assert-Cf7Contains $producer 'CandidateRoot must not traverse a reparse point' 'producer must reject candidate path indirection'
Assert-Cf7Contains $producer 'Runtime candidate producer changed the formal deployment closure' 'producer must fail if formal deployment changes'

$start = Get-Content -LiteralPath $startPath -Raw -Encoding UTF8
Assert-Cf7Contains $start '[string]$CandidateRoot' 'start must expose explicit CandidateRoot'
Assert-Cf7Contains $start '[switch]$EnableLegacyHttpAutomation' `
    'start must require an explicit switch for the legacy privileged control plane'
Assert-Cf7Contains $start '--legacy-http-automation' `
    'start must pass the exact legacy automation mode to Core only when requested'
Assert-Cf7Contains $start '$runtimeMode = ''formal_runtime''' 'start must default to formal runtime'
Assert-Cf7Contains $start '$runtimeMode = ''isolated_candidate''' 'start must label candidate runtime'
Assert-Cf7Contains $start 'tmp\runtime-candidates\v2' 'start must bind candidates to the repository v2 tree'
Assert-Cf7Contains $start 'Candidate base path segment' 'start must reject candidate base path indirection'
Assert-Cf7Contains $start 'runtime-build-metadata.v2.json' 'start must validate candidate metadata'
Assert-Cf7Contains $start 'cf7-runtime-manifest-v2' 'start must validate a v2 manifest'
Assert-Cf7Contains $start 'verify-runtime-bundle-v2.ps1' 'start must run the trusted bundle verifier'
Assert-Cf7Contains $start '--verify-runtime-only' 'candidate start must use isolated verification'
Assert-Cf7Contains $start '--verify-only' 'formal start must use complete-install verification'
Assert-Cf7Contains $start 'Runtime Mode' 'start must print runtime mode'
Assert-Cf7Contains $start 'Core SHA256' 'start must print Core SHA256'
Assert-Cf7Contains $start 'Build Identity' 'start must print build identity'
Assert-Cf7Contains $start 'Payload Closure' 'start must print payload closure'
Assert-Cf7Contains $start 'Guardian MainModule.FileName is not available yet.' `
    'start must tolerate the Windows process MainModule initialization race'
Assert-Cf7Contains $start 'Guardian exited before process path verification' `
    'start must distinguish early process exit from a transient MainModule race'
Assert-Cf7Contains $start 'launcher_ports.json belongs to a different process' 'start must bind readiness to the process it launched'
Assert-Cf7Contains $start '$runnerStart.FileName = [IO.Path]::GetFullPath($selectedCoreExe)' `
    'unattended start must execute the exact selected Core'
Assert-Cf7Contains $start '$runnerStart.WorkingDirectory = $selectedDeploymentRoot' `
    'unattended start must bind the selected deployment root'
Assert-Cf7Contains $start '$runnerStart.Arguments =' `
    'unattended start must support Windows PowerShell 5.1 ProcessStartInfo'
Assert-Cf7Contains $start '--agent-unattended-runner --adapter $UnattendedAdapter --slot $UnattendedSlot' `
    'unattended start must expose only the closed trusted Core runner arguments'
Assert-Cf7Contains $start '$setDotnetRootCommand -Quiet' `
    'unattended start must not contaminate protocol stdout with runtime detection diagnostics'
Assert-Cf7Guardrail `
    -Condition ($start.IndexOf('$bundleVerifier =', [StringComparison]::Ordinal) -lt
        $start.IndexOf('$runnerStart =', [StringComparison]::Ordinal)) `
    -Message 'unattended start must verify the selected payload before first Core execution'
Assert-Cf7Contains $start '-IntegrityOnly *> $null' `
    'unattended pre-exec inventory verification must not contaminate protocol stdout'
Assert-Cf7Contains $start '$startInfo.RedirectStandardOutput = $true' `
    'native policy verification must not inherit protocol stdout'
Assert-Cf7Contains $start '$startInfo.RedirectStandardError = $true' `
    'native policy verification must not inherit protocol stderr'
Assert-Cf7DoesNotContain $start '.ArgumentList' `
    'start must not require the unavailable Windows PowerShell 5.1 ArgumentList API'
Assert-Cf7DoesNotContain $start 'unattendedRequestPath' `
    'start must not construct or clean up script-owned unattended bootstrap evidence'
Assert-Cf7DoesNotContain $start 'Protect-Cf7CurrentUser' `
    'start must not carry script-owned unattended credential protection code'

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
function Assert-Cf7StartRejectsCandidateRoot {
    param(
        [Parameter(Mandatory=$true)][string]$CandidateRoot,
        [Parameter(Mandatory=$true)][string]$ExpectedText
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $startPath -CandidateRoot $CandidateRoot 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    Assert-Cf7Guardrail -Condition ($exitCode -ne 0) -Message "unsafe CandidateRoot unexpectedly succeeded: $CandidateRoot"
    Assert-Cf7Guardrail -Condition (($output -join "`n").IndexOf($ExpectedText, [StringComparison]::OrdinalIgnoreCase) -ge 0) `
        -Message "CandidateRoot rejection lacked expected diagnostic '$ExpectedText': $($output -join ' | ')"
}

Assert-Cf7StartRejectsCandidateRoot -CandidateRoot $ProjectRoot -ExpectedText 'outside the repository v2 candidate directory'
Assert-Cf7StartRejectsCandidateRoot -CandidateRoot 'tmp\runtime-candidates\v2\relative' -ExpectedText 'explicit absolute path'
$missingCandidate = Join-Path $ProjectRoot ('tmp\runtime-candidates\v2\guardrail-missing-' + [Guid]::NewGuid().ToString('N'))
Assert-Cf7StartRejectsCandidateRoot -CandidateRoot $missingCandidate -ExpectedText 'does not exist'

Write-Host '[RuntimeEntryGuardrails] PASS scripts=3 unsafeCandidateCases=3' -ForegroundColor Green
