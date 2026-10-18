$ErrorActionPreference='Stop'
$repo=(Get-Location).Path
$tmp=Join-Path $repo 'tmp/cf6-playtest-feedback-20261017'
$out=Join-Path $tmp 'render-stop3/recovery-after-user'
if(Test-Path -LiteralPath $out){throw 'Preserve recovery evidence'}
New-Item -ItemType Directory -Path $out | Out-Null
$scripts=Join-Path $repo 'scripts'
$marker=Join-Path $scripts 'testloader_scratch_inflight.marker'
$uncertain=Join-Path $scripts 'compile_state_uncertain.marker'
$target=Join-Path $scripts 'compile_target.cfg'
$body=[IO.File]::ReadAllText($marker,[Text.Encoding]::UTF8)
$record=$body | ConvertFrom-Json
if($body -cne [IO.File]::ReadAllText((Join-Path $tmp 'render-stop3/testloader_scratch_inflight.marker'),[Text.Encoding]::UTF8)){throw 'Scratch marker changed'}
$uncertainBody=[IO.File]::ReadAllText($uncertain,[Text.Encoding]::UTF8)
if($uncertainBody -cne [IO.File]::ReadAllText((Join-Path $tmp 'render-stop3/compile_state_uncertain.marker'),[Text.Encoding]::UTF8)){throw 'Uncertain marker changed'}
$targetBody=[IO.File]::ReadAllText($target,[Text.Encoding]::UTF8)
if($targetBody -cne [IO.File]::ReadAllText((Join-Path $tmp 'render-stop3/compile_target.cfg'),[Text.Encoding]::UTF8)){throw 'Target changed'}
if(Get-Process -Id 7424 -ErrorAction SilentlyContinue){throw 'Old host has not exited'}
if(Get-Process -Id $record.owner_pid -ErrorAction SilentlyContinue){throw 'Old scratch owner is active'}
$hosts=@(Get-Process -Name Flash -ErrorAction SilentlyContinue)
if($hosts.Count -ne 1 -or $hosts[0].Id -ne 11904){throw 'Unexpected current host'}
$newHostStart=$hosts[0].StartTime
if((Get-ScheduledTask -TaskName CompileTriggerTask).State -ne 'Ready'){throw 'Trigger is not idle'}
$installedHash='3C00324670F7828C1C81BF83C47955FDBEF563ED8C37D4FB43EEB7E76764416B'
if((Get-FileHash -LiteralPath $record.runner_path).Hash -ne $installedHash){throw 'Scratch source changed'}
foreach($p in @($marker,$uncertain,$target,$record.backup_path)){Copy-Item -LiteralPath $p -Destination $out}
$evidence=@('TestLoader.swf','compiler_errors.txt','compile_output.txt','flashlog.txt')
function Get-DiagnosticSnapshot {
 $rows=@();foreach($n in $evidence){$p=Join-Path $scripts $n;$i=Get-Item -LiteralPath $p;$rows+=[ordered]@{name=$n;bytes=$i.Length;mtime=$i.LastWriteTimeUtc.Ticks;sha256=(Get-FileHash -LiteralPath $p).Hash}}
 return ,$rows
}
$before=Get-DiagnosticSnapshot
$before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'diagnostics-before.json') -Encoding UTF8
Start-Sleep -Milliseconds 750
if(($before | ConvertTo-Json -Compress) -cne ((Get-DiagnosticSnapshot) | ConvertTo-Json -Compress)){throw 'Late diagnostics are still changing'}
$mutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$record.repo_hash));$held=$false;$abandoned=$false
try {
 try {$held=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true;$abandoned=$true}
 if(!$held){throw 'Another compiler owns the mutex'}
 . (Join-Path $scripts 'test-runners/testloader-scratch-transaction.ps1')
 $transaction=[pscustomobject]@{MarkerPath=$marker;MarkerBody=$body;RunnerPath=$record.runner_path;HadRunner=$record.had_runner;BackupPath=$record.backup_path;OriginalHash=$record.original_sha256}
 Restore-Cf7TestLoaderScratchTransaction -Transaction $transaction -InstalledHash $installedHash
 if([IO.File]::ReadAllText($target,[Text.Encoding]::UTF8) -cne $targetBody){throw 'Retained target changed'}
 # Manual recovery after the old host exited; preserve and remove only its exact unconsumed target.
 Remove-Item -LiteralPath $target
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
$controlBefore=@(Get-ChildItem -LiteralPath (Join-Path $repo 'tmp/flash-testplayer-control') -Directory | Select-Object -ExpandProperty Name)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'compile_test.ps1') -StopTestPlayers 2>&1 | Tee-Object -FilePath (Join-Path $out 'fresh-stop.log')
if($LASTEXITCODE -ne 0){throw 'Fresh player control did not succeed; uncertain marker retained'}
$controls=@(Get-ChildItem -LiteralPath (Join-Path $repo 'tmp/flash-testplayer-control') -Directory | Where-Object {$_.Name -notin $controlBefore})
if($controls.Count -ne 1){throw 'Unexpected player-control receipts'}
if((Get-Content -LiteralPath (Join-Path $controls[0].FullName 'phase-1.receipt') -Raw) -notmatch 'closed=false'){throw 'No final absence confirmation'}
$mutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$record.repo_hash));$held=$false
try {
 $held=$mutex.WaitOne(0);if(!$held){throw 'Another compiler is active'}
 if((Get-Process -Id 11904).StartTime -ne $newHostStart){throw 'Current host identity changed'}
 if(($before | ConvertTo-Json -Compress) -cne ((Get-DiagnosticSnapshot) | ConvertTo-Json -Compress)){throw 'A late compile changed diagnostics'}
 if((Get-FileHash -LiteralPath $record.runner_path).Hash -ne $record.original_sha256){throw 'Restored runner changed'}
 if([IO.File]::ReadAllText($uncertain,[Text.Encoding]::UTF8) -cne $uncertainBody){throw 'Uncertainty changed during recovery'}
 Remove-Item -LiteralPath $uncertain
 [ordered]@{humanReportedTestPlayerClosed=$true;oldHostExited=$true;currentHostId=11904;currentHostStart=$newHostStart.ToString('o');triggerIdle=$true;lateDiagnosticsUnchanged=$true;abandonedMutexObserved=$abandoned;scratchRestoredSha256=$record.original_sha256;freshControlReceipts=$controls[0].FullName;failedAttemptNotUpgraded=$true;time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'recovery.json') -Encoding UTF8
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
Get-Content -LiteralPath (Join-Path $out 'recovery.json') -Encoding UTF8
