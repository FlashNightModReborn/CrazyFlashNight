$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskDir='tmp/cf6-combat-calibration-20261017'
if(Test-Path -LiteralPath "$taskDir/native-cleanup-after-r22-final.json"){throw 'Preserve prior cleanup'}
$beforeFolders=@(Get-ChildItem -LiteralPath 'tmp/flash-testplayer-control' -Directory | ForEach-Object Name)
$editor=Get-Process -Id 20176
$editorStart=$editor.StartTime.ToUniversalTime().ToString('o')
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -StopTestPlayers *> "$taskDir/native-cleanup-after-r22-final-retry1.log"
if($LASTEXITCODE -ne 0){throw 'Native stop did not complete'}
$newFolders=@(Get-ChildItem -LiteralPath 'tmp/flash-testplayer-control' -Directory | Where-Object { $_.Name -notin $beforeFolders })
if($newFolders.Count -ne 1){throw 'Cannot identify one fresh control receipt'}
$folder=$newFolders[0]
$last=Get-Content -LiteralPath (Join-Path $folder.FullName 'phase-1.receipt') -Raw -Encoding UTF8
if($last -notmatch 'closed=false'){throw 'Final control did not prove test player absence'}
$sourceHash=(Get-FileHash -LiteralPath 'scripts/TestLoader.as' -Algorithm SHA256).Hash
if($sourceHash -ne 'E38E2151BF619814A0EA65BF2B19D11D8F78A7704787C47C046666ACEE2F090B'){throw 'Scratch original not restored'}
foreach($name in @('compile_state_uncertain.marker','testloader_scratch_inflight.marker','compile_target.cfg','compile_mode.cfg','testplayer_control.cfg')){
 if(Test-Path -LiteralPath (Join-Path 'scripts' $name)){throw "Pending control: $name"}
}
$editorAfter=Get-Process -Id 20176
if($editorAfter.StartTime.ToUniversalTime().ToString('o') -ne $editorStart){throw 'Editor identity changed'}
Copy-Item -LiteralPath $folder.FullName -Destination "$taskDir/native-cleanup-after-r22-final-receipts" -Recurse
[ordered]@{ok=$true;originalRunnerSha256=$sourceHash;pendingMarkersAbsent=$true;controlReceipts=$folder.FullName;
 editorPid=20176;editorStartUtc=$editorStart;editorPreserved=$true;time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath "$taskDir/native-cleanup-after-r22-final.json" -Encoding UTF8
