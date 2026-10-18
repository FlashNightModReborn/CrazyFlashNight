$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=(Get-Location).Path
$out=Join-Path $repo 'tmp/cf6-combat-audio-20261017/native-stop1'
$uncertain=Join-Path $repo 'scripts/compile_state_uncertain.marker'
$body=[IO.File]::ReadAllText($uncertain,[Text.Encoding]::UTF8)
if($body -notmatch 'domain=cf6-elder; runId=f65436bab42647c6ab4154dafb945ce4;'){throw 'Unknown failed behavior identity'}
$old=Get-Content -LiteralPath (Join-Path $out 'testloader_scratch_inflight.marker') -Raw -Encoding UTF8 | ConvertFrom-Json
if(Get-Process -Id $old.owner_pid -ErrorAction SilentlyContinue){throw 'Old focused process is still running'}
Copy-Item -LiteralPath $uncertain -Destination (Join-Path $out 'failed-behavior-uncertain.marker')
if((Get-FileHash -LiteralPath scripts/TestLoader.as).Hash -ne $old.original_sha256){throw 'Scratch original is not restored'}
foreach($name in @('testloader_scratch_inflight.marker','compile_target.cfg','compile_mode.cfg','testplayer_control.cfg')){
 if(Test-Path -LiteralPath (Join-Path $repo ('scripts/'+$name))){throw ('Pending state '+$name)}
}
if((Get-ScheduledTask -TaskName CompileTriggerTask).State -ne 'Ready'){throw 'Trigger is not idle'}
& powershell -NoProfile -ExecutionPolicy Bypass -File scripts/compile_test.ps1 -StopTestPlayers 2>&1 | Tee-Object -FilePath (Join-Path $out 'fresh-stop.log')
if($LASTEXITCODE -ne 0){throw 'Fresh stopped-player proof failed'}
$mutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$old.repo_hash))
$held=$false;$abandoned=$false
try {
 try {$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true;$abandoned=$true}
 if(!$held -or $abandoned){throw 'Repository compiler state is not quiet'}
 $paths=@('scripts/TestLoader.swf','scripts/compiler_errors.txt','scripts/compile_output.txt','scripts/TestLoader.as',(Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'))
 $ids=@{};foreach($name in $paths){$ids[$name]=(Get-FileHash -LiteralPath $name).Hash}
 Start-Sleep -Milliseconds 700
 foreach($name in $paths){if((Get-FileHash -LiteralPath $name).Hash -ne $ids[$name]){throw 'Late evidence is still changing'}}
 if([IO.File]::ReadAllText($uncertain,[Text.Encoding]::UTF8) -cne $body){throw 'Unknown-state identity changed'}
 if((Get-ScheduledTask -TaskName CompileTriggerTask).State -ne 'Ready'){throw 'A trigger is active'}
 Remove-Item -LiteralPath $uncertain
 [ordered]@{failedRunId='f65436bab42647c6ab4154dafb945ce4';failedResultPreserved=$true;playerStoppedByFreshControl=$true;sourceRestoredSha256=$ids['scripts/TestLoader.as'];lateEvidenceStable=$true;oldOwnerExited=$true;editor11904Preserved=(Get-Process -Id 11904 -ErrorAction SilentlyContinue) -ne $null;readOnlyFixtureRootCause='DamageManagerFactory.init called twice by combined isolated suites; registry rejects duplicate Basic';time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'recovery.json') -Encoding UTF8
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
Get-Content -LiteralPath (Join-Path $out 'recovery.json') -Raw -Encoding UTF8
