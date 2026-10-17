[CmdletBinding()]
param(
    [ValidateSet('camera','scene-transition','stage-return','arena-worker-protocol','map-loot','lee-trial','warlord-action-encounter','bookshelf')]
    [string]$Suite='camera',
    [string]$CompilerProjectDirectory='',
    [ValidateRange(30,1800)][int]$TimeoutSeconds=900
)
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
if (!$CompilerProjectDirectory) { $CompilerProjectDirectory=$project }
$compilerRoot=[IO.Path]::GetFullPath($CompilerProjectDirectory)
$compile=Join-Path $compilerRoot 'scripts/compile_test.ps1'
$hostXfl=Join-Path $PSScriptRoot 'CameraLifecycleHost/CameraLifecycleHost.xfl'
$swf=Join-Path $PSScriptRoot 'CameraLifecycleHost.swf'
$entry=Join-Path $PSScriptRoot 'camera_run.as'
$runId=[Guid]::NewGuid().ToString('N')
$evidence=Join-Path $project ('tmp/camera-lifecycle/'+$Suite+'/'+$runId)
[void](New-Item -ItemType Directory -Path $evidence -Force)
$original=[IO.File]::ReadAllBytes($entry)
if ($Suite -eq 'camera') {
    $source='if (_root.__cameraSuite == undefined) org.flashNight.arki.camera.CameraLifecycleTest.start("'+$runId+'");'
    $start='CameraLifecycleRun Start: '+$runId
    $complete='CameraLifecycleRun Complete: '+$runId
    $required=@('CameraLifecycleTest')
} else {
    $template=Join-Path $PSScriptRoot ('test-runners/'+$Suite+'/TestLoader.as.template')
    $source=[IO.File]::ReadAllText($template,[Text.Encoding]::UTF8)
    $source=$source.Replace('__FOCUSED_RUN_ID__',$runId).Replace('__MAP_LOOT_RUN_ID__',$runId)
    if ($Suite -eq 'map-loot') {
        $start='MapLootTestRunId Start: '+$runId;$complete='MapLootTestRunId Complete: '+$runId
    } else {
        $start='FocusedTestRunId '+$Suite+' Start: '+$runId
        $complete='FocusedTestRunId '+$Suite+' Complete: '+$runId
    }
    $required=switch ($Suite) {
        'scene-transition' { @('SceneTransitionServiceTest') }
        'stage-return' { @('StageReturnFlowTest') }
        'arena-worker-protocol' { @('ArenaWorkerProtocolTest') }
        'map-loot' { @('LootContainerServiceTest','LootMaterializationPlannerTest','StageRunSessionTest') }
        'lee-trial' { @('ControlledEnemyLifecycleTest','LeeTrialTelemetryTest','LeeAssaultRulesTest','SceneTransitionGuardHandoffTest') }
        'warlord-action-encounter' { @('ActionEncounterRunnerTest') }
        'bookshelf' { @('BookRunRulesTest','BookshelfPanelServiceTest','BookIterationTest','BookComicServiceTest') }
    }
}
[IO.File]::WriteAllText($entry,$source,[Text.UTF8Encoding]::new($true))
$installed=(Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash
[IO.File]::WriteAllBytes((Join-Path $evidence 'entry-original.as'),$original)
@{entry=$entry;installedSha256=$installed;runId=$runId;suite=$Suite} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $evidence 'entry-ownership.json') -Encoding UTF8
$started=[DateTime]::UtcNow
$rawPath=Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
$finished=$false
$compiled=$false
try {
    # The standard compiler owns its configured project mutex and diagnostics.
    # Only this worktree's dedicated include is changed; main TestLoader is untouched.
    & powershell -NoProfile -ExecutionPolicy Bypass -File $compile -Target $hostXfl -VerifySwf $swf -TimeoutSeconds $TimeoutSeconds
    $canonicalExit=$LASTEXITCODE
    if ($canonicalExit -ne 0) {
        foreach ($name in @('compile_output.txt','compiler_errors.txt','flashlog.txt')) {
            $path=Join-Path $compilerRoot ('scripts/'+$name)
            if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).LastWriteTimeUtc -ge $started.AddSeconds(-1)) {
                Copy-Item -LiteralPath $path -Destination $evidence -Force
            }
        }
        $failedErrors=Join-Path $evidence 'compiler_errors.txt'
        if ((Test-Path -LiteralPath $failedErrors) -and (Test-Path -LiteralPath $swf) -and
            (Get-Item -LiteralPath $swf).LastWriteTimeUtc -ge $started.AddSeconds(-1) -and
            [IO.File]::ReadAllText($failedErrors,[Text.Encoding]::UTF8) -match '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            $compiled=$true
            Copy-Item -LiteralPath $swf -Destination (Join-Path $evidence 'failed-native-host.swf')
            if (Test-Path -LiteralPath $rawPath) {
                $stream=[IO.File]::Open($rawPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
                $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
                try { $failedRaw=$reader.ReadToEnd() } finally { $reader.Dispose() }
                [IO.File]::WriteAllText((Join-Path $evidence 'failed-raw-trace.txt'),$failedRaw,[Text.UTF8Encoding]::new($false))
                $finished=[regex]::Matches($failedRaw,('(?m)^'+[regex]::Escape($start)+'\r?$')).Count -eq 1 -and
                    [regex]::Matches($failedRaw,('(?m)^'+[regex]::Escape($complete)+'\r?$')).Count -eq 1
            }
        }
        throw "Canonical CS6 compile failed: $canonicalExit; evidence=$evidence"
    }
    $compiled=$true
    foreach ($name in @('compile_output.txt','compiler_errors.txt')) {
        $path=Join-Path $compilerRoot ('scripts/'+$name)
        if ((Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $started.AddSeconds(-1)) { throw "Stale compiler evidence: $name" }
        Copy-Item -LiteralPath $path -Destination $evidence
    }
    $diagnostics=[IO.File]::ReadAllText((Join-Path $evidence 'compiler_errors.txt'),[Text.Encoding]::UTF8)
    if ($diagnostics -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') { throw 'Compiler diagnostics must be fresh 0/0.' }
    & node (Join-Path $project 'tools/swf-function-sizes.js') $swf --max 60000
    if ($LASTEXITCODE -ne 0) { throw 'Native host exceeds AVM1 function-size limit.' }
    $deadline=[DateTime]::UtcNow.AddSeconds(75)
    $startPattern='(?m)^'+[regex]::Escape($start)+'\r?$'
    $completePattern='(?m)^'+[regex]::Escape($complete)+'\r?$'
    do {
        if (Test-Path -LiteralPath $rawPath) {
            $stream=[IO.File]::Open($rawPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
            try { $raw=$reader.ReadToEnd() } finally { $reader.Dispose() }
            $match=[regex]::Match($raw,$startPattern)
            if ($match.Success) {
                $trace=$raw.Substring($match.Index)
                [IO.File]::WriteAllText((Join-Path $evidence 'raw-trace.txt'),$trace,[Text.UTF8Encoding]::new($false))
                if ([regex]::Matches($trace,$completePattern).Count -eq 1) { $finished=$true;break }
            }
        }
        Start-Sleep -Milliseconds 150
    } while ([DateTime]::UtcNow -lt $deadline)
    if (!$finished -or [regex]::Matches($trace,$startPattern).Count -ne 1) { throw 'Exact one-start/one-complete raw behavior block missing.' }
    if ($trace -match '(?im)Tests Failed:\s*[1-9]|\[(?:CAMERA_FAIL|TEST_FAIL|FAIL)\]|[1-9][0-9]* failed ---') { throw 'Native behavior contains failures; see raw-trace.txt.' }
    foreach ($test in $required) {
        if ($trace -notmatch ('(?m)^'+$test+' Tests Passed: [1-9][0-9]*\r?$') -or $trace -notmatch ('(?m)^'+$test+' Tests Failed: 0\r?$')) { throw "Missing suite terminal: $test" }
    }
    $counts=switch ($Suite) {
        'camera' { @{CameraLifecycleTest=166} }
        'scene-transition' { @{SceneTransitionServiceTest=103} }
        'stage-return' { @{StageReturnFlowTest=119} }
        'arena-worker-protocol' { @{ArenaWorkerProtocolTest=52} }
        'map-loot' { @{LootContainerServiceTest=198;LootMaterializationPlannerTest=12;StageRunSessionTest=920} }
        'lee-trial' { @{LeeAssaultRulesTest=39;LeeTrialTelemetryTest=5;SceneTransitionGuardHandoffTest=20} }
        'warlord-action-encounter' { @{ActionEncounterRunnerTest=97} }
        'bookshelf' { @{BookRunRulesTest=59;BookshelfPanelServiceTest=93;BookIterationTest=22;BookComicServiceTest=34} }
    }
    foreach ($test in $counts.Keys) {
        if ([regex]::Matches($trace,('(?m)^'+$test+' Tests Passed: '+$counts[$test]+'\r?$')).Count -ne 1) { throw ('Native suite assertion count differs: '+$test) }
    }
    if ($Suite -eq 'map-loot' -and $trace -notmatch '(?m)^BoxInteractionArbiterTest: 13/13 cases, 53 assertions passed\r?$') { throw 'Box interaction native checks missing.' }
    if ($Suite -eq 'lee-trial' -and $trace -notmatch '(?m)^--- EnemyActionRuntimeTest: ([1-9][0-9]*)/\1 passed, 0 failed ---') { throw 'Enemy action runtime checks missing.' }
    if ([IO.File]::ReadAllText((Join-Path $evidence 'compile_output.txt'),[Text.Encoding]::UTF8) -match 'ASO 32K branch detected') { throw 'The native run required an unhealthy 32K retry.' }
    Copy-Item -LiteralPath $swf -Destination (Join-Path $evidence 'native-host.swf')
    @{suite=$Suite;runId=$runId;compiler='0/0';rawBehavior=$true;nativeMovieClip=$true;gameE2e=$false;playerSlotsTouched=$false;
      swf=(Get-FileHash -LiteralPath $swf -Algorithm SHA256).Hash;utc=[DateTime]::UtcNow.ToString('o')} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'result.json') -Encoding UTF8
    Write-Host ('[OK] Native '+$Suite+'; evidence='+$evidence)
} finally {
    if ($compiled -and !$finished) {
        $uncertain=Join-Path $compilerRoot 'scripts/compile_state_uncertain.marker'
        if (!(Test-Path -LiteralPath $uncertain)) {
            [IO.File]::WriteAllText($uncertain,([DateTime]::UtcNow.ToString('o')+' | native camera runner behavior not terminal; suite='+$Suite+' runId='+$runId),[Text.UTF8Encoding]::new($false))
        }
    }
    if (!(Test-Path -LiteralPath (Join-Path $compilerRoot 'scripts/compile_state_uncertain.marker')) -and
        (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash -ceq $installed) {
        [IO.File]::WriteAllBytes($entry,$original)
    }
}
