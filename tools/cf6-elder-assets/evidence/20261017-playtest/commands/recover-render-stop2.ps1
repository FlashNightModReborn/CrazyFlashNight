$ErrorActionPreference='Stop'
$repo=(Get-Location).Path
$out=Join-Path $repo 'tmp/cf6-playtest-feedback-20261017/render-stop2'
$marker=Join-Path $repo 'scripts/testloader_scratch_inflight.marker'
$body=[IO.File]::ReadAllText($marker,[Text.Encoding]::UTF8)
$expected=[IO.File]::ReadAllText((Join-Path $out 'testloader_scratch_inflight.marker'),[Text.Encoding]::UTF8)
if($body -cne $expected){throw 'Scratch identity changed'}
$record=$body | ConvertFrom-Json
if(Get-Process -Id $record.owner_pid -ErrorAction SilentlyContinue){throw 'Owner still running'}
if((Get-ScheduledTask -TaskName CompileTriggerTask).State -ne 'Ready'){throw 'Compile task is not idle'}
foreach($name in @('compile_target.cfg','compile_mode.cfg','testplayer_control.cfg','compile_state_uncertain.marker')){
 if(Test-Path -LiteralPath (Join-Path $repo ('scripts/'+$name))){throw ('Unexpected pending instruction: '+$name)}
}
$control='C:\Program Files (x86)\Steam\steamapps\common\CRAZYFLASHER7StandAloneStarter\CrazyFlashNight\tmp\flash-testplayer-control\751c981098a24805a270eec7e723bbe9'
if((Get-Content -LiteralPath (Join-Path $control 'phase-0.receipt') -Raw) -notmatch 'closed=false' -or (Get-Content -LiteralPath (Join-Path $control 'phase-1.receipt') -Raw) -notmatch 'closed=false'){throw 'Stop was not verified'}
$installedHash=(Get-FileHash -LiteralPath (Join-Path $out 'TestLoader.as')).Hash
if((Get-FileHash -LiteralPath $record.runner_path).Hash -ne $installedHash){throw 'Installed scratch changed'}
Copy-Item -LiteralPath $record.backup_path -Destination (Join-Path $out 'original-TestLoader.as')
$evidence=@('scripts/TestLoader.swf','scripts/compiler_errors.txt','scripts/compile_output.txt','scripts/flashlog.txt',(Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'))
$first=@{};foreach($p in $evidence){$first[$p]=(Get-FileHash -LiteralPath $p).Hash}
Start-Sleep -Milliseconds 500
foreach($p in $evidence){if((Get-FileHash -LiteralPath $p).Hash -ne $first[$p]){throw 'Late evidence still changing'}}
$mutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$record.repo_hash))
$abandoned=$false
try {
 try {$held=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$held=$true;$abandoned=$true}
 if(!$held){throw 'Another compiler owns the mutex'}
 . (Join-Path $repo 'scripts/test-runners/testloader-scratch-transaction.ps1')
 $transaction=[pscustomobject]@{MarkerPath=$marker;MarkerBody=$body;RunnerPath=$record.runner_path;HadRunner=$record.had_runner;BackupPath=$record.backup_path;OriginalHash=$record.original_sha256}
 Restore-Cf7TestLoaderScratchTransaction -Transaction $transaction -InstalledHash $installedHash
 $attempt=Join-Path $repo 'tmp/cf6-playtest-feedback-20261017/render-pass2/headbot'
 foreach($name in @('TestLoader.swf','compiler_errors.txt','compile_output.txt')){Copy-Item -LiteralPath (Join-Path $repo ('scripts/'+$name)) -Destination $attempt}
 Copy-Item -LiteralPath (Join-Path $out 'raw-trace-after-stop.txt') -Destination (Join-Path $attempt 'flashlog.txt')
 $before=Get-Content -LiteralPath (Join-Path $attempt 'bindings-before.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 $after=@();foreach($row in $before){$p=Join-Path $repo $row.path;$after+=[ordered]@{path=$row.path;bytes=(Get-Item -LiteralPath $p).Length;sha256=(Get-FileHash -LiteralPath $p).Hash}}
 $after | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $attempt 'bindings-after.json') -Encoding UTF8
 $unchanged=($before | ConvertTo-Json -Depth 5 -Compress) -ceq ($after | ConvertTo-Json -Depth 5 -Compress)
 [ordered]@{name='headbot';exitCode=1;cancelled=$true;bindingsUnchanged=$unchanged;reason='Stopped read-only render after excessive wall time; no Complete and no passing render result inferred';time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $attempt 'result.json') -Encoding UTF8
 [ordered]@{playerStopControl=$control;compileTaskIdle=$true;oldOwnerExited=$true;lateEvidenceStable=$true;abandonedMutexObserved=$abandoned;scratchRestoredSha256=(Get-FileHash -LiteralPath $record.runner_path).Hash;originalEditorPreserved=(Get-Process -Id 7424 -ErrorAction SilentlyContinue) -ne $null;renderCancelled=$true;time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'recovery.json') -Encoding UTF8
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
Get-Content -LiteralPath (Join-Path $out 'recovery.json') -Encoding UTF8
