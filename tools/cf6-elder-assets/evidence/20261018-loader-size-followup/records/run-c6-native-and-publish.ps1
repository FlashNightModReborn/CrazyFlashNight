$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017/loader-size-followup'
$taskConsumer='scripts/asLoader.swf'
if(Test-Path -LiteralPath "$taskDir/publish"){throw 'Preserve existing C6 build'}
& python -X utf8 -B "$taskDir/freeze-inputs.py" before *> "$taskDir/freeze-before.log"
if($LASTEXITCODE -ne 0){throw 'Source snapshot failed'}
$taskEditor=Get-Process -Id 20176
$taskEditorStart=$taskEditor.StartTime.ToUniversalTime().ToString('o')
$taskStarted=(Get-Date).ToUniversalTime()
New-Item -ItemType Directory -Path "$taskDir/publish" -ErrorAction Stop | Out-Null
$taskBeforeHash=(Get-FileHash -LiteralPath $taskConsumer -Algorithm SHA256).Hash
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -Target publish -TimeoutSeconds 600 *> "$taskDir/publish/compile.log"
$taskPublishExit=$LASTEXITCODE
foreach($taskName in @('compiler_errors.txt','compile_output.txt','publish_done.marker','compile_state_uncertain.marker')){
 $taskSource=Join-Path scripts $taskName
 if(Test-Path -LiteralPath $taskSource){Copy-Item -LiteralPath $taskSource -Destination "$taskDir/publish/$taskName"}
}
[ordered]@{startedUtc=$taskStarted.ToString('o');completedUtc=(Get-Date).ToUniversalTime().ToString('o');exitCode=$taskPublishExit;target='publish';beforeSha256=$taskBeforeHash;sha256=(Get-FileHash -LiteralPath $taskConsumer -Algorithm SHA256).Hash;bytes=(Get-Item -LiteralPath $taskConsumer).Length;editorPid=20176;editorStartUtc=$taskEditorStart} | ConvertTo-Json | Set-Content -LiteralPath "$taskDir/publish/identity.json" -Encoding UTF8
if($taskPublishExit -ne 0){exit $taskPublishExit}
Copy-Item -LiteralPath $taskConsumer -Destination "$taskDir/publish/asLoader.swf"
& node tools/swf-function-sizes.js scripts/asLoader.swf --max 60000 --top 15 *> "$taskDir/publish/function-sizes.json"
if($LASTEXITCODE -ne 0){throw 'Current loader function size gate failed'}
& node tools/audit-as2-class-embedding.js --json *> "$taskDir/publish/production-class-ownership.json"
if($LASTEXITCODE -ne 0){throw 'Current production class ownership failed'}
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run-boot-sequencer-tests.ps1 -TimeoutSeconds 600 *> "$taskDir/boot-sequencer-runner.log"
$taskNativeExit=$LASTEXITCODE
New-Item -ItemType Directory -Path "$taskDir/native" -ErrorAction Stop | Out-Null
foreach($taskName in @('compiler_errors.txt','compile_output.txt','flashlog.txt','TestLoader.swf','compile_state_uncertain.marker','testloader_scratch_inflight.marker')){
 $taskSource=Join-Path scripts $taskName
 if(Test-Path -LiteralPath $taskSource){Copy-Item -LiteralPath $taskSource -Destination "$taskDir/native/$taskName"}
}
if($taskNativeExit -ne 0){throw "Native boot suite failed: $taskNativeExit"}
$taskBeforeFolders=@(Get-ChildItem -LiteralPath 'tmp/flash-testplayer-control' -Directory | ForEach-Object Name)
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -StopTestPlayers *> "$taskDir/native/cleanup.log"
if($LASTEXITCODE -ne 0){throw 'Fresh native cleanup failed'}
$taskNewFolders=@(Get-ChildItem -LiteralPath 'tmp/flash-testplayer-control' -Directory | Where-Object { $_.Name -notin $taskBeforeFolders })
if($taskNewFolders.Count -ne 1){throw 'Ambiguous native cleanup receipt'}
$taskReceipt=Get-Content -LiteralPath (Join-Path $taskNewFolders[0].FullName 'phase-1.receipt') -Raw -Encoding UTF8
if($taskReceipt -notmatch 'closed=false'){throw 'Final native player absence not proved'}
Copy-Item -LiteralPath $taskNewFolders[0].FullName -Destination "$taskDir/native/cleanup-receipts" -Recurse
foreach($taskName in @('compile_state_uncertain.marker','testloader_scratch_inflight.marker','compile_target.cfg','compile_mode.cfg','testplayer_control.cfg')){
 if(Test-Path -LiteralPath (Join-Path scripts $taskName)){throw "Pending control: $taskName"}
}
if((Get-Process -Id 20176).StartTime.ToUniversalTime().ToString('o') -ne $taskEditorStart){throw 'Original editor changed'}
& python -X utf8 -B "$taskDir/freeze-inputs.py" after *> "$taskDir/freeze-after.log"
if($LASTEXITCODE -ne 0){throw 'Source snapshot changed'}
[ordered]@{ok=$true;freshNativeExitCode=$taskNativeExit;expectedAssertions=103;editorPreserved=$true;editorPid=20176;editorStartUtc=$taskEditorStart;finishedUtc=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath "$taskDir/native/completion.json" -Encoding UTF8
Write-Host 'C6 publish, function-size/ownership gates, 103 native boot assertions and cleanup completed.'
