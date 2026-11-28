[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Use a new evidence directory.' }

function Read-CoherentCandidate {
    $result = & (Join-Path $projectRoot 'tools/verify-runtime-bundle-v2.ps1') `
        -ProjectRoot $projectRoot -DeploymentRoot $candidate -Json | ConvertFrom-Json
    if ($result.schema -cne 'cf7-runtime-bundle-verification.v2' -or $result.passed -ne $true -or
        $result.mode -cne 'worktree' -or $result.state -cne 'coherent') {
        throw 'The selftest source must match the selected candidate build identity.'
    }
    return $result
}

$before = Read-CoherentCandidate
New-Item -ItemType Directory -Path $output | Out-Null
$log = Join-Path $output 'selftest.log'
$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `
        (Join-Path $projectRoot 'launcher/native/world-compositor/build-dev.ps1') -Target selftest `
        -OutDir (Join-Path $output 'native') *> $log
    $nativeExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorAction
}
$after = Read-CoherentCandidate
$coherent = $before.buildIdentityHash -ceq $after.buildIdentityHash -and $before.payloadClosureHash -ceq $after.payloadClosureHash
$receipt = [ordered]@{
    schema = 'cf7-input-authority-native-selftest.v1'
    candidateRoot = $candidate
    buildIdentity = $before.buildIdentityHash
    payloadClosure = $before.payloadClosureHash
    coreSha256 = (Get-FileHash -LiteralPath (Join-Path $candidate 'runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll')).Hash
    logSha256 = (Get-FileHash -LiteralPath $log).Hash
    worktreeCoherent = $coherent
    exitCode = $nativeExit
}
$receiptText = ($receipt | ConvertTo-Json -Depth 4) + "`n"
[IO.File]::WriteAllText((Join-Path $output 'receipt.json'), $receiptText, [Text.UTF8Encoding]::new($false))
Write-Output $receiptText
if (-not $coherent) { exit 2 }
exit $nativeExit
