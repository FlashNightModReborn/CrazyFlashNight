param([string]$DestinationDirectory = 'C:/Users/iuo/Downloads')
$ErrorActionPreference = 'Stop'
chcp.com 65001 > $null
$packageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$packageEvidence = Join-Path $packageRoot 'tmp/issue-152-acceptance'
$packageStatusPath = Join-Path $packageEvidence 'acceptance-status.json'
if (-not (Test-Path -LiteralPath $packageStatusPath -PathType Leaf)) { throw 'Finish and record acceptance-status.json before packaging' }
if (@(Get-CimInstance Win32_Process -Filter "Name='CRAZYFLASHER7MercenaryEmpire.Core.exe'" | Where-Object {
    $_.ExecutablePath -and $_.ExecutablePath.StartsWith($packageRoot + '\', [StringComparison]::OrdinalIgnoreCase)
}).Count) { throw 'All task game processes must exit normally before freezing the archive' }
$packageDestination = [IO.Path]::GetFullPath($DestinationDirectory)
if (-not (Test-Path -LiteralPath $packageDestination -PathType Container)) { throw 'Destination directory must already exist' }
$packageStamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$packageName = 'issue-152-implementation-acceptance-' + $packageStamp
$packageStage = Join-Path $packageEvidence $packageName
$packageZip = Join-Path $packageDestination ($packageName + '.zip')
if ((Test-Path -LiteralPath $packageStage) -or (Test-Path -LiteralPath $packageZip)) { throw 'Archive destination already exists; never overwrite' }
[void][IO.Directory]::CreateDirectory($packageStage)

function Invoke-PackageGit([string[]]$Arguments) {
    $gitStart = [Diagnostics.ProcessStartInfo]::new()
    $gitStart.FileName = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
    $gitStart.WorkingDirectory = $packageRoot
    $gitStart.RedirectStandardOutput = $true
    $gitStart.RedirectStandardError = $true
    $gitStart.UseShellExecute = $false
    $gitStart.CreateNoWindow = $true
    $gitStart.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) { [void]$gitStart.ArgumentList.Add($argument) }
    $gitProcess = [Diagnostics.Process]::Start($gitStart)
    $gitOutput = $gitProcess.StandardOutput.ReadToEnd()
    $gitError = $gitProcess.StandardError.ReadToEnd()
    $gitProcess.WaitForExit()
    if ($gitProcess.ExitCode -ne 0) { throw ('git failed: ' + $gitError) }
    $gitProcess.Dispose()
    return $gitOutput
}
function Copy-PackageFile([string]$Source, [string]$RelativeDestination) {
    $packageSourceFile = Get-Item -LiteralPath $Source -Force
    if ($packageSourceFile.PSIsContainer -or ($packageSourceFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw ('Not a regular file: ' + $Source)
    }
    $packageTarget = [IO.Path]::GetFullPath((Join-Path $packageStage $RelativeDestination))
    if (-not $packageTarget.StartsWith($packageStage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive path escaped staging directory' }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($packageTarget))
    [IO.File]::Copy($packageSourceFile.FullName, $packageTarget, $false)
}

# The initial tree was clean. These are this task's tracked edits; preserve the
# concurrently touched medicine file outside this issue's package.
$packageScope = Get-Content -LiteralPath (Join-Path $packageEvidence 'source-scope.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($packageScope.schema -cne 'issue152-source-scope.v1' -or $packageScope.baseCommit -cne 'e582cf62da63b8e1b6057df88aa0caf4eadf85b9'){throw 'Source scope is not the reviewed task baseline'}
$packageTracked = @($packageScope.tracked)
$packageNewAllowlist = @(
    'data/shops/remote-access.json',
    'launcher/src/AgentRuntime/TrustedRunner/TrustedRegressionSlots.cs',
    'launcher/src/Data/NpcShopAccessPolicy.cs',
    'launcher/tests/AgentRuntime/TrustedRunner/TrustedRegressionSlotsTests.cs',
    'launcher/tests/Tasks/NpcShopAccessPolicyTests.cs',
    'launcher/tests/runtime-canonical-lf.tests.ps1',
    'scripts/类定义/org/flashNight/arki/item/InfrastructureVehicleAccess.as',
    'scripts/类定义/org/flashNight/arki/item/NpcShopAccessFixture.as',
    'scripts/类定义/org/flashNight/arki/item/NpcShopAccessService.as',
    'tools/cf7-agent/regression-profile.js','tools/cf7-agent/regression-session.js',
    'tools/cf7-agent/tests/regression-profile.test.js'
)
$packageUntracked = (Invoke-PackageGit -Arguments @('ls-files','--others','--exclude-standard','-z')).Split([char]0,[StringSplitOptions]::RemoveEmptyEntries)
$packageNew = @($packageUntracked | Where-Object { $_ -in $packageNewAllowlist -or $_.StartsWith('tools/issue-152/',[StringComparison]::Ordinal) })
foreach ($packageRelative in @($packageTracked) + @($packageNew)) {
    Copy-PackageFile (Join-Path $packageRoot $packageRelative) ('sources/' + $packageRelative)
}
$packagePatch = Invoke-PackageGit -Arguments (@('diff','--binary','--full-index',[string]$packageScope.baseCommit,'--') + $packageTracked)
[IO.File]::WriteAllText((Join-Path $packageStage 'implementation.patch'),$packagePatch,[Text.UTF8Encoding]::new($false))

foreach ($packageFile in Get-ChildItem -LiteralPath $packageEvidence -File) {
    if ($packageFile.Extension -notin @('.json','.log','.md')) { continue }
    if ($packageFile.Name -match '^session-') {
        $packageText = [IO.File]::ReadAllText($packageFile.FullName)
        if ($packageText -match '"(?:credentialProof|connectionToken|clientSecret|password|contentBase64|pixels)"\s*:') {
            throw ('Audit contains an excluded secret/pixel field: ' + $packageFile.Name)
        }
    }
    Copy-PackageFile $packageFile.FullName ('evidence/' + $packageFile.Name)
}
foreach ($packageFile in Get-ChildItem -LiteralPath (Join-Path $packageEvidence 'seeds') -Recurse -File) {
    Copy-PackageFile $packageFile.FullName ('prepared-seeds/' + [IO.Path]::GetRelativePath((Join-Path $packageEvidence 'seeds'),$packageFile.FullName))
}
foreach ($packageFile in Get-ChildItem -LiteralPath (Join-Path $packageEvidence 'late-publish') -File) {
    if ($packageFile.Extension -in @('.json','.log','.txt')) { Copy-PackageFile $packageFile.FullName ('evidence/late-publish/' + $packageFile.Name) }
}
foreach ($packageResultDirectory in @('final-host-results','timed-input-host-results','ancestor-focus-host-results','composition-surface-host-results','composition-surface-current-host-results')) {
    $packageResult=Join-Path $packageEvidence ($packageResultDirectory+'/recheck.trx')
    if(Test-Path -LiteralPath $packageResult -PathType Leaf){Copy-PackageFile $packageResult ('evidence/'+$packageResultDirectory+'/recheck.trx')}
}
$packagePreparation = Get-Content -LiteralPath (Join-Path $packageEvidence 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($packageSlot in $packagePreparation.slots.slot) {
    Copy-PackageFile (Join-Path $packageRoot ('saves/' + $packageSlot + '.json')) ('played-test-saves/' + $packageSlot + '.json')
}
$packageReadback = Get-Content -LiteralPath (Join-Path $packageEvidence 'played-save-readback-final.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($packageReadback.schema -cne 'issue152-played-save-readback.v1' -or $packageReadback.success -ne $true -or
    (@($packageReadback.slots.slot | Sort-Object) -join ',') -cne (@($packagePreparation.slots.slot | Sort-Object) -join ',')) {
    throw 'The final production readback must cover exactly the prepared five slots'
}
$packageSolBase = [IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Macromedia/Flash Player/#SharedObjects')) + '\'
foreach ($packagePlayedSlot in $packageReadback.slots) {
    $packageSolPath = [IO.Path]::GetFullPath($packagePlayedSlot.solPath)
    if (-not $packageSolPath.StartsWith($packageSolBase,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($packageSolPath) -cne ($packagePlayedSlot.slot + '.sol') -or
        $packagePlayedSlot.source -cne 'sol' -or $packagePlayedSlot.expectedMatches -ne $true) {
        throw 'Refusing to archive an unbound or non-fixture SOL file'
    }
    Copy-PackageFile $packageSolPath ('played-test-sol/' + $packagePlayedSlot.slot + '.sol')
}
$packageVerification = Join-Path $packageRoot 'tmp/issue-152-verification'
foreach ($packageFile in Get-ChildItem -LiteralPath $packageVerification -File) {
    if ($packageFile.Extension -in @('.json','.log','.md')) { Copy-PackageFile $packageFile.FullName ('verification/' + $packageFile.Name) }
}
Copy-PackageFile (Join-Path $packageRoot 'tools/issue-152/README.md') '验收路线.md'
$packageStatus = Get-Content -LiteralPath $packageStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
$packageManifest = [ordered]@{
    schema='issue152-delivery.v1';createdAtUtc=[datetime]::UtcNow.ToString('o')
    baseCommit='e582cf62da63b8e1b6057df88aa0caf4eadf85b9'
    handoffSha256='AABBDCFC7F9AC3B76565555B2B0659237DD73BA6964C733DA9251AC71B047F52'
    status=$packageStatus;candidateIncluded=$false
    instructions=@('Read 验收路线.md and evidence/acceptance-status.json first.',
        'The complete immutable candidate stays at its recorded local path. Rebuild it on another machine; no partial runtime is included.',
        'sources/ contains reviewed source changes; implementation.patch covers tracked changes only.',
        'prepared-seeds/ are frozen initial fixtures. played-test-saves/ are actual post-test snapshots, not a reset source.',
        'played-test-sol/ contains only the exact five test SOL files selected by the final production readback. Never restore them over an existing differing slot.',
        'Never overwrite an existing player or test slot. Preparation refuses collisions. No commit, push or formal promotion was performed.')
    files=@(Get-ChildItem -LiteralPath $packageStage -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{path=[IO.Path]::GetRelativePath($packageStage,$_.FullName).Replace('\','/');bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
    })
}
[IO.File]::WriteAllText((Join-Path $packageStage 'manifest.json'),($packageManifest|ConvertTo-Json -Depth 24)+"`n",[Text.UTF8Encoding]::new($false))
[IO.Compression.ZipFile]::CreateFromDirectory($packageStage,$packageZip,[IO.Compression.CompressionLevel]::Optimal,$false)
$packageArchive = [IO.Compression.ZipFile]::OpenRead($packageZip)
try {
    if ($packageArchive.Entries.Count -ne $packageManifest.files.Count + 1) { throw 'ZIP entry count differs from manifest' }
    foreach ($packageRecord in $packageManifest.files) {
        $packageEntry = $packageArchive.GetEntry($packageRecord.path)
        if ($null -eq $packageEntry -or $packageEntry.Length -ne $packageRecord.bytes) { throw ('ZIP entry missing or wrong size: ' + $packageRecord.path) }
        $packageEntryStream = $packageEntry.Open()
        try { $packageHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($packageEntryStream)) }
        finally { $packageEntryStream.Dispose() }
        if ($packageHash -cne $packageRecord.sha256) { throw ('ZIP digest mismatch: ' + $packageRecord.path) }
    }
} finally { $packageArchive.Dispose() }
[ordered]@{path=$packageZip;bytes=(Get-Item -LiteralPath $packageZip).Length;sha256=(Get-FileHash -LiteralPath $packageZip -Algorithm SHA256).Hash;verifiedFiles=$packageManifest.files.Count;stage=$packageStage}|ConvertTo-Json
