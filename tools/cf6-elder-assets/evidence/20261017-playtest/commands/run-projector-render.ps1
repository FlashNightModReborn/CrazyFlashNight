param([Parameter(Mandatory=$true)][string]$PlanPath)
$ErrorActionPreference='Stop'
$repo=(Get-Location).Path
$tmp=Join-Path $repo 'tmp/cf6-playtest-feedback-20261017'
$plan=Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bindings=(Get-Content -LiteralPath (Join-Path $tmp 'render-plan2.json') -Raw -Encoding UTF8 | ConvertFrom-Json).bindings
$player='C:/Users/fs/Downloads/adboeflash cs6(1)/Adobe Flash CS6/Players/Debug/FlashPlayerDebugger.exe'
$scripts=Join-Path $repo 'scripts'
$raw=Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
$swf=Join-Path $scripts 'TestLoader.swf'
$scratch=Join-Path $scripts 'TestLoader.as'
. (Join-Path $scripts 'test-runners/testloader-scratch-transaction.ps1')
function Get-SourceBindings {
 $rows=@();foreach($relative in $bindings){$p=Join-Path $repo $relative;$rows+=[ordered]@{path=$relative;bytes=(Get-Item -LiteralPath $p).Length;sha256=(Get-FileHash -LiteralPath $p).Hash}}
 return ,$rows
}
$repoHash='850C6434887C81955225822A'
$mutex=[Threading.Mutex]::new($false,('Local\CF7_FlashCompile_'+$repoHash))
$held=$false
try {
 $held=$mutex.WaitOne(0)
 if(!$held){throw 'Another compilation is active'}
 foreach($n in @('testloader_scratch_inflight.marker','compile_state_uncertain.marker','testplayer_control.cfg','compile_target.cfg','compile_mode.cfg')){if(Test-Path -LiteralPath (Join-Path $scripts $n)){throw ('Pending state: '+$n)}}
 if(Get-Process -Name FlashPlayerDebugger -ErrorAction SilentlyContinue){throw 'An independent debugger is already running'}
 if((Get-ScheduledTask -TaskName CompileTriggerTask).State -ne 'Ready'){throw 'Compiler task is active'}
 foreach($run in $plan.runs){
  $folder=Join-Path $tmp ($plan.output+'/'+$run.name)
  if(Test-Path -LiteralPath $folder){throw 'Preserve existing evidence'}
  New-Item -ItemType Directory -Path $folder | Out-Null
  $before=Get-SourceBindings
  $before | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'bindings-before.json') -Encoding UTF8
  $executionId=[guid]::NewGuid().ToString('N')
  $compilerSource=$run.reuseCompiledFrom
  if($compilerSource){
   $compiled=Join-Path $tmp $compilerSource
   if((Get-FileHash -LiteralPath $swf).Hash -ne (Get-FileHash -LiteralPath (Join-Path $compiled 'TestLoader.swf')).Hash){throw 'Compiled binary changed'}
   $source=Get-Content -LiteralPath (Join-Path $tmp $run.compiledSource) -Raw -Encoding UTF8
   $runId=[regex]::Match($source,'Start: ([0-9a-f]{32})').Groups[1].Value
   if(!$runId){throw 'No exact compiled run identifier'}
   foreach($n in @('compiler_errors.txt','compile_output.txt')){Copy-Item -LiteralPath (Join-Path $compiled $n) -Destination $folder}
   Copy-Item -LiteralPath (Join-Path $tmp $run.compiledSource) -Destination (Join-Path $folder 'compiled-TestLoader.as')
  } else {
   $runId=[guid]::NewGuid().ToString('N')
   $lease='v1:'+ $repoHash+':'+$PID+':'+[guid]::NewGuid().ToString('N')
   $transaction=New-Cf7TestLoaderScratchTransaction -MarkerPath (Join-Path $scripts 'testloader_scratch_inflight.marker') -RunnerPath $scratch -RepoHash $repoHash -CompileLease $lease -OwnerKind ('projector-render:'+ $run.name)
   $installedHash=$null
   try {
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $transaction
    $source=(Get-Content -LiteralPath (Join-Path $repo $run.template) -Raw -Encoding UTF8).Replace('__FOCUSED_RUN_ID__',$runId)
    [IO.File]::WriteAllText($scratch,$source,[Text.UTF8Encoding]::new($true))
    $installedHash=(Get-FileHash -LiteralPath $scratch).Hash
    Copy-Item -LiteralPath $scratch -Destination (Join-Path $folder 'compiled-TestLoader.as')
    $env:CF7_FLASH_COMPILE_LEASE=$lease
    $ErrorActionPreference='Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'compile_test.ps1') -Target test -PublishOnly -TimeoutSeconds 600 2>&1 | Tee-Object -FilePath (Join-Path $folder 'compile.log')
    $compileExit=$LASTEXITCODE
    $ErrorActionPreference='Stop'
    foreach($n in @('compiler_errors.txt','compile_output.txt')){Copy-Item -LiteralPath (Join-Path $scripts $n) -Destination $folder}
    if($compileExit -ne 0){throw 'CS6 publication failed'}
   } finally {
    Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
    if($installedHash){Restore-Cf7TestLoaderScratchTransaction -Transaction $transaction -InstalledHash $installedHash}
   }
  }
  if((Get-Content -LiteralPath (Join-Path $folder 'compiler_errors.txt') -Raw -Encoding UTF8).Trim() -notmatch '^0 [^,]+, 0 .+$'){throw 'Compiler is not 0/0'}
  Copy-Item -LiteralPath $swf -Destination $folder
  if(Test-Path -LiteralPath $raw){Copy-Item -LiteralPath $raw -Destination (Join-Path $folder 'raw-trace-before-execution.txt')}
  [IO.File]::WriteAllBytes($raw,[byte[]]@())
  $proc=$null;$pass=$false;$terminal=$false;$failure=$null;$stopMode=$null
  $started=Get-Date
  try {
   $proc=Start-Process -FilePath $player -ArgumentList ('"'+$swf+'"') -WorkingDirectory $scripts -WindowStyle Hidden -PassThru
   $processStart=$proc.StartTime
   [ordered]@{executionId=$executionId;runId=$runId;playerPath=$player;playerSha256=(Get-FileHash -LiteralPath $player).Hash;playerFileVersion=(Get-Item -LiteralPath $player).VersionInfo.FileVersion;processId=$proc.Id;processStart=$processStart.ToString('o');swfPath=$swf;swfSha256=(Get-FileHash -LiteralPath $swf).Hash;compilerEvidence=$compilerSource;started=$started.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'execution.json') -Encoding UTF8
   Write-Host ('[RUN] '+$run.name+' standalone native renderer; execution='+$executionId)
   $deadline=[DateTime]::UtcNow.AddSeconds(600)
   do {
    $trace=if(Test-Path -LiteralPath $raw){[IO.File]::ReadAllText($raw,[Text.Encoding]::UTF8)}else{''}
    if($trace -match ('(?m)^FocusedTestRunId '+[regex]::Escape($run.domain)+' Complete: '+$runId+'\r?$')){$terminal=$true;break}
    if($proc.HasExited){throw 'Native player exited before Complete'}
    Start-Sleep -Milliseconds 500
   } while([DateTime]::UtcNow -lt $deadline)
   if(!$terminal){throw 'Native renderer exceeded its 600 second deadline'}
   if([regex]::Matches($trace,'(?m)^FocusedTestRunId .* Start: .*').Count -ne 1 -or [regex]::Matches($trace,'(?m)^FocusedTestRunId .* Complete: .*').Count -ne 1){throw 'Unexpected marker count'}
   if($trace -notmatch $run.pattern -or $trace -match '\[TEST_FAIL\]'){throw 'Native renderer did not pass'}
   $pass=$true
  } catch {$failure=$_.Exception.Message}
  finally {
   if(Test-Path -LiteralPath $raw){Copy-Item -LiteralPath $raw -Destination (Join-Path $folder 'flashlog.txt')}
   if($proc -and !$proc.HasExited){
    if($proc.StartTime -ne $processStart){throw 'Player identity changed'}
    $stopMode='CloseMainWindow';[void]$proc.CloseMainWindow()
    if(!$proc.WaitForExit(10000)){$stopMode='Terminate owned read-only renderer';$proc.Kill();$proc.WaitForExit()}
   }
  }
  $after=Get-SourceBindings
  $after | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'bindings-after.json') -Encoding UTF8
  $same=($before | ConvertTo-Json -Depth 5 -Compress) -ceq ($after | ConvertTo-Json -Depth 5 -Compress)
  $pass=$pass -and $same
  [ordered]@{name=$run.name;exitCode=$(if($pass){0}else{1});bindingsUnchanged=$same;behaviorTerminal=$terminal;failure=$failure;playerStopped=(!$proc -or $proc.HasExited);stopMode=$stopMode;seconds=((Get-Date)-$started).TotalSeconds;time=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'result.json') -Encoding UTF8
  Get-Content -LiteralPath (Join-Path $folder 'result.json') -Encoding UTF8
  if(!$pass){exit 1}
 }
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
