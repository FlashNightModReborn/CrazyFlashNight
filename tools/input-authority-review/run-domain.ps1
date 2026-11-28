[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CandidateRoot,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path
$runtime = Join-Path $candidate 'runtime'
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Use a new evidence directory.' }

$verification = & (Join-Path $projectRoot 'tools/verify-runtime-bundle-v2.ps1') `
    -ProjectRoot $projectRoot -DeploymentRoot $candidate -IntegrityOnly -Json | ConvertFrom-Json
if ($verification.schema -cne 'cf7-runtime-bundle-verification.v2' -or $verification.passed -ne $true -or
    $verification.state -cne 'integrity-only') { throw 'Candidate integrity verification failed.' }

New-Item -ItemType Directory -Path $output | Out-Null
$dotnetPath = Join-Path $projectRoot 'launcher/resolve-dotnet.ps1'
. $dotnetPath
$sdk = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
$python = (Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$buildPath = Join-Path $output 'build'
& $sdk build (Join-Path $PSScriptRoot 'domain/DomainProbe.csproj') -c Release --artifacts-path $buildPath --nologo `
    *> (Join-Path $output 'build.log')
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 25
    throw 'The independent probe failed to build.'
}

$executable = Join-Path $buildPath 'bin/DomainProbe/release/DomainProbe.exe'
$coreSha = (Get-FileHash -LiteralPath (Join-Path $runtime 'CRAZYFLASHER7MercenaryEmpire.Core.dll')).Hash
$raw = Join-Path $output 'result.json'
$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & $python (Join-Path $PSScriptRoot 'domain/run_private.py') $executable $runtime $projectRoot $raw $coreSha `
        *> (Join-Path $output 'probe.log')
    $probeExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorAction
}
$receipt = [ordered]@{
    schema = 'cf7-modifier-domain-run.v1'
    candidateRoot = $candidate
    buildIdentity = $verification.buildIdentityHash
    payloadClosure = $verification.payloadClosureHash
    coreSha256 = $coreSha
    probeSha256 = (Get-FileHash -LiteralPath $executable).Hash
    probeDllSha256 = (Get-FileHash -LiteralPath ([IO.Path]::ChangeExtension($executable, '.dll'))).Hash
    rawSha256 = if (Test-Path -LiteralPath $raw) { (Get-FileHash -LiteralPath $raw).Hash } else { $null }
    exitCode = $probeExitCode
}
$receiptText = ($receipt | ConvertTo-Json -Depth 4) + "`n"
[IO.File]::WriteAllText((Join-Path $output 'receipt.json'), $receiptText, [Text.UTF8Encoding]::new($false))
Write-Output $receiptText
exit $probeExitCode
