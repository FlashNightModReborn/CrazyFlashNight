[CmdletBinding()]
param(
    [string]$CandidateRoot,
    [string]$NativeDll,
    [Parameter(Mandatory=$true)][string]$OutputRoot
)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if(([string]::IsNullOrWhiteSpace($CandidateRoot)) -eq ([string]::IsNullOrWhiteSpace($NativeDll))) {
    throw 'Specify exactly one of CandidateRoot or NativeDll.'
}
$identity=$null
if($CandidateRoot) {
    $CandidateRoot=(Resolve-Path -LiteralPath $CandidateRoot).Path
    & (Join-Path $repo 'tools\verify-runtime-bundle-v2.ps1') -DeploymentRoot $CandidateRoot -IntegrityOnly
    if($LASTEXITCODE -ne 0){throw 'Candidate integrity check failed.'}
    $identity=Get-Content -LiteralPath (Join-Path $CandidateRoot 'runtime-build-metadata.v2.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $NativeDll=Join-Path $CandidateRoot 'runtime\FlashCompositorNative.dll'
}
$NativeDll=(Resolve-Path -LiteralPath $NativeDll).Path
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $OutputRoot){throw 'OutputRoot must not already exist.'}
. (Join-Path $repo 'launcher\resolve-dotnet.ps1')
$sdk=Resolve-Cf7Dotnet -ProjectRoot $repo
$build=Join-Path $repo 'tmp\viewport-regression-probe'
Push-Location $repo
try {
    & $sdk build (Join-Path $PSScriptRoot 'FlashCompositorProbe.csproj') -c Release -o $build --nologo -p:RestoreLockedMode=true
    if($LASTEXITCODE -ne 0){throw 'Viewport regression probe build failed.'}
    & $sdk (Join-Path $build 'FlashCompositorProbe.dll') --viewport-regression $NativeDll $OutputRoot
    $probeExit=$LASTEXITCODE
    $provenance=[ordered]@{
        sourceCommit=(& git rev-parse HEAD)
        nativePath=$NativeDll
        nativeSha256=(Get-FileHash -LiteralPath $NativeDll -Algorithm SHA256).Hash
        candidateRoot=$CandidateRoot
        buildIdentityHash=if($identity){$identity.buildIdentityHash}else{$null}
        payloadClosureHash=if($identity){$identity.payloadClosureHash}else{$null}
        scope='Owned source -> WGC -> exact native GPU; no player save, physical input or scanout attestation'
    }
    $provenance | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputRoot 'provenance.json') -Encoding UTF8
    if($probeExit -ne 0){throw "Viewport regression failed: $probeExit. See $OutputRoot\results.json"}
} finally {Pop-Location}
