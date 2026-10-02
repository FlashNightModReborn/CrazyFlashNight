[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$CandidateRoot)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$outputPath=[IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
$scratchRoot=[IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp'))+[IO.Path]::DirectorySeparatorChar
if(-not $outputPath.StartsWith($scratchRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Probe output must remain inside project tmp.'}
if(Test-Path -LiteralPath $outputPath){throw 'Use a fresh probe directory.'}
$transitionCandidate=(Resolve-Path -LiteralPath $CandidateRoot).Path
$transitionCandidateCheck=& (Join-Path $PSScriptRoot 'verify-runtime-bundle-v2.ps1') -ProjectRoot $projectRoot -DeploymentRoot $transitionCandidate -IntegrityOnly -Json
# This PowerShell verifier returns JSON on success; it does not set LASTEXITCODE.
# Admit only its explicit result, never a stale/null exit code from another command.
$transitionVerification=$transitionCandidateCheck | ConvertFrom-Json
if($transitionVerification.schema -cne 'cf7-runtime-bundle-verification.v2' -or
    $transitionVerification.passed -isnot [bool] -or -not $transitionVerification.passed -or
    $transitionVerification.state -cne 'integrity-only'){throw 'Candidate integrity admission failed.'}
. (Join-Path $projectRoot 'launcher/resolve-dotnet.ps1')
$transitionDotnet=Resolve-Cf7Dotnet -ProjectRoot $projectRoot
& $transitionDotnet run --project (Join-Path $PSScriptRoot 'scene-transition-smoke/SceneTransition.Smoke.csproj') -c Release "-p:U12CandidateRoot=$transitionCandidate" -- $projectRoot $outputPath $transitionCandidate
if($LASTEXITCODE -ne 0){throw "U12 isolated composition probe failed: $outputPath"}
Get-Content -LiteralPath (Join-Path $outputPath 'result.json') -Raw -Encoding UTF8
