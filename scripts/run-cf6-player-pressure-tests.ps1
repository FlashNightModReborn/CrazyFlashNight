param([int]$TimeoutSeconds=600,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$beforeRoot=Join-Path $root 'tmp/cf6-performance-repair-20261031/before'
$archiveRoot=Join-Path $root 'tools/cf6-soldier-assets/evidence/20261031-pressure-baseline'
$archiveManifest=Join-Path $archiveRoot 'manifest.json'
$frozen=Get-Content -LiteralPath $archiveManifest -Raw -Encoding UTF8 | ConvertFrom-Json
$allowed=@('Codex蛮蛮素材.swf','Codex大刀机器人素材.swf','Codex大头机器人素材.swf','Codex光头保安素材.swf')
if($frozen.files.Count -ne 4 -or @($frozen.files.name | Select-Object -Unique).Count -ne 4){throw 'Invalid frozen baseline inventory.'}
[IO.Directory]::CreateDirectory($beforeRoot) | Out-Null
foreach($entry in $frozen.files){
    if($entry.name -notin $allowed){throw 'Unexpected frozen baseline filename.'}
    $source=Join-Path $archiveRoot $entry.name
    if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256){throw 'Versioned baseline digest mismatch.'}
    $target=Join-Path $beforeRoot $entry.name
    if(-not (Test-Path -LiteralPath $target)){Copy-Item -LiteralPath $source -Destination $target}
}
$cacheManifest=Join-Path $beforeRoot 'manifest.json'
if(Test-Path -LiteralPath $cacheManifest){
    if((Get-FileHash -LiteralPath $cacheManifest -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $archiveManifest -Algorithm SHA256).Hash){throw 'Existing baseline manifest differs; preserve and review it before retrying.'}
}else{Copy-Item -LiteralPath $archiveManifest -Destination $cacheManifest}
foreach($entry in $frozen.files){
    $actual=(Get-FileHash -LiteralPath (Join-Path $beforeRoot $entry.name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -ne $entry.sha256){throw ('Frozen before SWF changed: '+$entry.name)}
}
if($PrepareOnly){Write-Output 'Frozen baseline prepared and verified.';exit 0}
& python -X utf8 -B (Join-Path $root 'tools/cf6-elder-assets/build-playtest-fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId cf6-player-pressure -TemplateRelativePath 'scripts/test-runners/cf6-player-pressure/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6PlayerPressureTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.Cf6PlayerPressureTest' -AdditionalAsRelativePaths 'scripts/test-runners/cf6-playtest/PlaytestFixture.as' -ExpectedTracePatterns @('Cf6PlayerPressureTest: \d+ passed, 0 failed; 68 paired player-source cases') -SuccessSummary '改前改后原生素材、玩家来源受击框与受控移动压力对照完成；不代替真人PVE' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
