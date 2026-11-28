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
$verification = & (Join-Path $projectRoot 'tools/verify-runtime-bundle-v2.ps1') `
    -ProjectRoot $projectRoot -DeploymentRoot $candidate -IntegrityOnly -Json | ConvertFrom-Json
if ($verification.schema -cne 'cf7-runtime-bundle-verification.v2' -or $verification.passed -ne $true -or
    $verification.state -cne 'integrity-only') { throw 'Candidate integrity verification failed.' }

# Preserve the existing G2 scripts' relative paths and evaluator. Only the managed
# test fixture is built here. The native binary comes byte-for-byte from the candidate.
$fixture = 'launcher/perf/flash-compositor'
$runner = Join-Path $output $fixture
$bin = Join-Path $output 'tmp/flash-compositor/bin'
New-Item -ItemType Directory -Path $runner,$bin,(Join-Path $output 'flashswf/movies') -Force | Out-Null
$dotnetPath = Join-Path $projectRoot 'launcher/resolve-dotnet.ps1'
. $dotnetPath
$sdk = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
$buildPath = Join-Path $output 'build'
$csproj = Join-Path $projectRoot "$fixture/FlashCompositorProbe.csproj"
& $sdk build $csproj -c Release --artifacts-path $buildPath --nologo -p:RestoreLockedMode=true `
    *> (Join-Path $output 'build.log')
if ($LASTEXITCODE -ne 0) {
    Get-Content -LiteralPath (Join-Path $output 'build.log') -Tail 25
    throw 'The existing managed WGC fixture failed to build.'
}
$managed = Join-Path $buildPath 'bin/FlashCompositorProbe/release'
$managedFiles = @(Get-ChildItem -File -LiteralPath $managed)
Copy-Item -LiteralPath $managedFiles.FullName -Destination $bin
$assets = @('Adobe Flash Player 20.exe', 'flashswf/movies/bigmovie1.swf')
foreach ($relative in @("$fixture/run.ps1", "$fixture/test-g2.ps1") + $assets) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $relative) -Destination (Join-Path $output $relative)
}
$native = Join-Path $candidate 'runtime/FlashCompositorNative.dll'
$stagedNative = Join-Path $bin 'FlashCompositorNative.dll'
Copy-Item -LiteralPath $native -Destination $stagedNative
$nativeSha256 = (Get-FileHash -LiteralPath $native).Hash
if ((Get-FileHash -LiteralPath $stagedNative).Hash -cne $nativeSha256) { throw 'Native fixture copy drifted.' }

$abiCheckPath = Join-Path $output 'abi-check.json'
$abiResult = & $sdk (Join-Path $bin 'FlashCompositorProbe.dll') --check-native-abi
$abiExit = $LASTEXITCODE
[IO.File]::WriteAllText($abiCheckPath, ($abiResult -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
if ($abiExit -ne 0) { throw 'Native and managed WGC fixture ABI requirements differ.' }
$abi = Get-Content -LiteralPath $abiCheckPath -Raw | ConvertFrom-Json
if ($abi.expected -ne 12 -or $abi.actual -ne $abi.expected -or $abi.statsSize -ne 920 -or $abi.contentStatsSize -ne 40) {
    throw 'WGC fixture ABI or diagnostic structure sizes drifted.'
}

$receipt = [ordered]@{
    schema = 'cf7-input-authority-wgc-fixture-preparation.v1'
    candidateRoot = $candidate
    buildIdentity = $verification.buildIdentityHash
    payloadClosure = $verification.payloadClosureHash
    coreSha256 = (Get-FileHash -LiteralPath (Join-Path $candidate 'runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll')).Hash
    nativeSha256 = $nativeSha256
    abi = $abi
    runner = Join-Path $runner 'test-g2.ps1'
    sdk = (& $sdk --version)
    fixtureFiles = @(foreach ($file in @(Get-ChildItem -File -LiteralPath $bin) + @(Get-ChildItem -File -LiteralPath $runner) + @(Get-Item -LiteralPath $abiCheckPath) +
            @(foreach ($asset in $assets) { Get-Item -LiteralPath (Join-Path $output $asset) })) {
        [ordered]@{path = $file.FullName; sha256 = (Get-FileHash -LiteralPath $file.FullName).Hash}
    })
}
$receiptText = ($receipt | ConvertTo-Json -Depth 6) + "`n"
[IO.File]::WriteAllText((Join-Path $output 'preparation.json'), $receiptText, [Text.UTF8Encoding]::new($false))
Write-Output $receiptText
