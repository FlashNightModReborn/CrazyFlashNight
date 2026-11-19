[CmdletBinding()]
param([int]$TimeoutSeconds=900,[switch]$QuitFlashAfterPublish,
    [switch]$Incremental,[switch]$PlanOnly,[switch]$ForceFull,
    [switch]$ExperimentSource,[ValidateScript({ $_ -cmatch '^[a-z0-9][a-z0-9-]{0,55}$' })][string]$ExperimentOutput,
    [ValidateSet('mirror','overlay')][string]$ExperimentLayout,
    [ValidateSet('resident','shared','boot')][string]$ExperimentModule,
    [ValidateSet('resident','shared','boot')][string]$ForceModule,
    [ValidateSet('Mirror','Overlay')][string]$ModuleLayout)
$ErrorActionPreference='Stop'
if ($ModuleLayout -and $ExperimentLayout) { throw 'Choose either -ModuleLayout or -ExperimentLayout.' }
$repo=Split-Path -Parent $PSScriptRoot
$normalized=[IO.Path]::GetFullPath($repo).TrimEnd('\').ToUpperInvariant()
$hasher=[Security.Cryptography.SHA256]::Create()
try {$repoHash=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized)))).Replace('-','').Substring(0,24)} finally {$hasher.Dispose()}
$mutex=[Threading.Mutex]::new($false,'Local\CF7_FlashCompile_'+$repoHash)
$held=$false
$previousLease=$env:CF7_FLASH_COMPILE_LEASE
$runRoot=$null
$receipt=[ordered]@{schema='cf7-asloader-publish.v1';state='failed';startedUtc=[DateTime]::UtcNow.ToString('o');stages=@()}
$result=1
Push-Location $repo
    # python 解析：PATH 上的 python 可能是 WindowsApps stub（存在但一律 9009），过滤后回退 .workbuddy 便携安装。
    $script:PythonExe = $null
    $pyOnPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if ($pyOnPath -and -not ($pyOnPath -like '*Microsoft\WindowsApps*')) { $script:PythonExe = $pyOnPath }
    if (-not $script:PythonExe) {
        $pyVersions = Join-Path $env:USERPROFILE '.workbuddy\binaries\python\versions'
        if (Test-Path -LiteralPath $pyVersions) {
            $latestPy = Get-ChildItem -LiteralPath $pyVersions -Directory | Sort-Object Name -Descending | Select-Object -First 1
            if ($latestPy -and (Test-Path -LiteralPath (Join-Path $latestPy.FullName 'python.exe'))) { $script:PythonExe = Join-Path $latestPy.FullName 'python.exe' }
        }
    }
    if (-not $script:PythonExe) { throw '未找到可用 python 解释器（PATH 仅有 WindowsApps stub）；asLoader 模块生成需要 python。' }
try {
    if([string]::IsNullOrWhiteSpace($previousLease)) {
        try {$held=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {
            $held=$true
            [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'compile_state_uncertain.marker'),('module parent mutex abandoned; '+[DateTime]::UtcNow.ToString('o')),[Text.UTF8Encoding]::new($false))
            throw 'Previous compile owner exited unexpectedly; inspect its evidence before recovery.'
        }
        if(-not $held){throw 'Another compile owns this repository.'}
        $env:CF7_FLASH_COMPILE_LEASE='m1:'+$repoHash+':'+$PID+':'+[Guid]::NewGuid().ToString('N')
    } else {
        throw 'Module publishing cannot run inside another compile or TestLoader scratch transaction.'
    }
    foreach($marker in @('compile_state_uncertain.marker','testhost_ownership.marker','testplayer_control.cfg')) {
        if(Test-Path -LiteralPath (Join-Path $PSScriptRoot $marker)){throw ('Unresolved Flash state blocks module generation: '+$marker)}
    }
    . (Join-Path $PSScriptRoot 'test-runners/testloader-scratch-transaction.ps1')
    Assert-Cf7TestLoaderScratchAdmission -MarkerPath (Join-Path $PSScriptRoot 'testloader_scratch_inflight.marker') -RunnerPath (Join-Path $PSScriptRoot 'TestLoader.as') -RepoHash $repoHash -CompileLease '' -LeaseOwnerPid 0
    $flashTask = Get-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction SilentlyContinue
    $trigger = Get-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction SilentlyContinue
    $native = $flashTask -and $trigger -and $flashTask.Actions.Count -eq 1 -and
        $trigger.Actions.Count -eq 1 -and $trigger.Actions[0].Execute -ieq $flashTask.Actions[0].Execute -and
        [IO.Path]::GetFileName($flashTask.Actions[0].Execute) -ieq 'Flash.exe'
    $setDirectory = Join-Path $repo 'tmp/asloader-artifact-set'
    $managed = @( 'pending.json', 'active.json', 'last-good.json' ) |
        Where-Object { Test-Path -LiteralPath (Join-Path $setDirectory $_) }
    if ($native -or $managed -or $Incremental -or $PlanOnly -or $ForceFull -or $ForceModule -or $ModuleLayout -or $ExperimentOutput -or $ExperimentSource -or $ExperimentLayout -or $ExperimentModule) {
        if (-not $native) { throw 'Managed module publishing and explicit layout or experiment options require the bound native CS6 task.' }
        $flash = $flashTask.Actions[0].Execute
        $loader = $trigger.Actions[0].Arguments.Trim('"')
        if ($flashTask.Actions.Count -ne 1 -or $trigger.Actions.Count -ne 1 -or
            $trigger.Actions[0].Execute -ine $flash -or -not (Test-Path -LiteralPath $loader -PathType Leaf)) {
            throw 'Cannot identify the bound native Flash compiler and Commands loader for incremental builds.'
        }
        $incrementalArgs = @('-B','-X','utf8','tools/publish_asloader_incremental.py','--flash',$flash,
            '--loader',$loader,'--timeout',[string]$TimeoutSeconds)
        if ($PlanOnly) { $incrementalArgs += '--plan-only' }
        if ($ForceFull) { $incrementalArgs += '--force-full' }
        if ($QuitFlashAfterPublish) { $incrementalArgs += '--quit-after-publish' }
        if ($ExperimentSource) { $incrementalArgs += '--experiment-source' }
        if ($ExperimentOutput) { $incrementalArgs += @('--experiment-output',$ExperimentOutput) }
        if ($ModuleLayout) { $incrementalArgs += @('--module-layout',$ModuleLayout.ToLowerInvariant()) }
        if ($ExperimentLayout) { $incrementalArgs += @('--layout',$ExperimentLayout.ToLowerInvariant()) }
        if ($ExperimentModule) { $incrementalArgs += @('--force-module',$ExperimentModule) }
        if ($ForceModule) { $incrementalArgs += @('--force-module',$ForceModule) }
        # These files are read or imported by the live driver, Node/PowerShell
        # children, and CS6's scheduled JSFL loader. Pin the actual control
        # bytes before Python imports them; the game sources remain editable.
        $toolPaths = @($PSCommandPath, $loader, (Join-Path (Split-Path -Parent $loader) 'flash_project_path.cfg'))
        $liveTools = @(
            'scripts/compile_test.ps1','scripts/compile_action.jsfl',
            'scripts/test-runners/testloader-scratch-transaction.ps1','scripts/test-runners/testplayer-control.ps1',
            'tools/publish_asloader_incremental.py','tools/asloader_toolchain.py','tools/asloader_artifact_set.py',
            'tools/asloader_incremental_inputs.py','tools/build-asloader-modules.py','tools/asloader_module_api.py',
            'tools/asloader_overlay_experiment.py',
            'tools/asloader-git-set.ps1','tools/assert-asloader-consumers-idle.ps1',
            'tools/audit-as2-class-embedding.js','tools/asloader-module-catalog.js','tools/swf-metadata.js',
            'tools/swf-function-sizes.js','tools/check-as2-inheritance-order.js','tools/check-bom.js')
        foreach ($relative in $liveTools) { $toolPaths += Join-Path $repo $relative }
        $sourceTools = @('tools/assemble-collapsed-frame.js','tools/asloader-definition-frames.js',
            'tools/build-choice-rewards.py','tools/choice_reward_catalog.py')
        foreach ($relative in $sourceTools) {
            $toolPaths += Join-Path $repo $relative
            if ($ExperimentSource) { $toolPaths += Join-Path (Join-Path $repo 'tmp/asloader-p1/bench-source') $relative }
        }
        $handles = [Collections.Generic.List[IO.FileStream]]::new()
        $previousPrefix = [Environment]::GetEnvironmentVariable('PYTHONPYCACHEPREFIX','Process')
        try {
            foreach ($path in $toolPaths) {
                $handles.Add([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read))
            }
            if (-not [string]::Equals([IO.File]::ReadAllText($PSCommandPath),
                    $MyInvocation.MyCommand.ScriptBlock.Ast.Extent.Text, [StringComparison]::Ordinal)) {
                throw 'Module publisher source changed after PowerShell loaded it.'
            }
            # -B suppresses writes, not reads of timestamp-valid old .pyc files.
            # Children inherit the unused prefix; no cache directory is created.
            $prefix = Join-Path $repo ('tmp/asloader-p1/pycache-' + [Guid]::NewGuid().ToString('N'))
            if ([IO.Directory]::Exists($prefix) -or [IO.File]::Exists($prefix)) { throw 'Python cache prefix already exists.' }
            [Environment]::SetEnvironmentVariable('PYTHONPYCACHEPREFIX',$prefix,'Process')
            & $script:PythonExe @incrementalArgs
            $nativeExit = $LASTEXITCODE
        } finally {
            [Environment]::SetEnvironmentVariable('PYTHONPYCACHEPREFIX',$previousPrefix,'Process')
            foreach ($handle in $handles) { $handle.Dispose() }
        }
        exit $nativeExit
    }
    $runRoot=Join-Path $repo ('tmp/asloader-builds/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    & node tools/assemble-collapsed-frame.js
    if($LASTEXITCODE -ne 0){throw 'Boot definition generation failed.'}
    & $script:PythonExe -B -X utf8 tools/build-choice-rewards.py --check
    if($LASTEXITCODE -ne 0){throw 'Runtime reward catalog is stale; regenerate its owned data first.'}
    & $script:PythonExe -B -X utf8 tools/build-asloader-modules.py
    if($LASTEXITCODE -ne 0){throw 'Module generation failed.'}
    Copy-Item -LiteralPath (Join-Path $repo 'tmp/asloader-modules/manifest.json') -Destination (Join-Path $runRoot 'inputs.json')
    $receipt.inputManifestSha256=(Get-FileHash -LiteralPath (Join-Path $runRoot 'inputs.json') -Algorithm SHA256).Hash
    $catalog=Get-Content -LiteralPath tools/asloader-modules.json -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($name in @('resident','shared','boot')) {
        $module=$catalog.$name
        $stageRoot=Join-Path $runRoot $name
        New-Item -ItemType Directory -Path $stageRoot | Out-Null
        $log=Join-Path $stageRoot 'compile.log'
        $childArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'compile_test.ps1'),'-Target',$module.xfl,'-VerifySwf',$module.swf,'-PublishOnly','-TimeoutSeconds',[string]$TimeoutSeconds)
        if($QuitFlashAfterPublish){$childArgs+='-QuitFlashAfterPublish'}
        Write-Host ('[INFO] asLoader module: '+$name)
        & powershell @childArgs 2>&1 | Tee-Object -FilePath $log
        $stageExit=$LASTEXITCODE
        foreach($file in @('compile_output.txt','compiler_errors.txt')) {if(Test-Path -LiteralPath (Join-Path $PSScriptRoot $file)){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stageRoot}}
        $stage=[ordered]@{name=$name;exitCode=$stageExit;swf=$module.swf;sha256=$null;bytes=0}
        if(Test-Path -LiteralPath $module.swf){$stage.sha256=(Get-FileHash -LiteralPath $module.swf -Algorithm SHA256).Hash;$stage.bytes=(Get-Item -LiteralPath $module.swf).Length}
        $receipt.stages+=,$stage
        if($stageExit -ne 0){throw ('Module compile failed: '+$name)}
        $savedOutput=Join-Path $stageRoot 'compile_output.txt'
        if(-not (Test-Path -LiteralPath $savedOutput) -or
            (Select-String -LiteralPath $savedOutput -Pattern 'ASO 32K branch detected' -Quiet)){throw ('Missing healthy Output evidence: '+$name)}
    }
    & node tools/audit-as2-class-embedding.js --swf scripts/asLoader.swf
    if($LASTEXITCODE -ne 0){throw 'Complete loader ownership check failed.'}
    & node tools/check-as2-inheritance-order.js --modules
    if($LASTEXITCODE -ne 0){throw 'Module initialization order failed.'}
    & node tools/assemble-collapsed-frame.js --check
    if($LASTEXITCODE -ne 0){throw 'Boot sources changed during compilation.'}
    & $script:PythonExe -B -X utf8 tools/build-choice-rewards.py --check
    if($LASTEXITCODE -ne 0){throw 'Reward catalog sources changed during compilation.'}
    & $script:PythonExe -B -X utf8 tools/build-asloader-modules.py --check
    if($LASTEXITCODE -ne 0){throw 'Module inputs changed during compilation.'}
    $receipt.state='compiled'
    $result=0
} catch {
    $receipt.error=$_.Exception.Message
    Write-Host ('[ERROR] '+$receipt.error)
} finally {
    $receipt.endedUtc=[DateTime]::UtcNow.ToString('o')
    if($runRoot){[IO.File]::WriteAllText((Join-Path $runRoot 'receipt.json'),($receipt|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));Write-Host ('[INFO] Module receipt: '+(Join-Path $runRoot 'receipt.json'))}
    if($null -eq $previousLease){Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue}else{$env:CF7_FLASH_COMPILE_LEASE=$previousLease}
    if($held){$mutex.ReleaseMutex()}
    $mutex.Dispose()
    Pop-Location
}
exit $result
