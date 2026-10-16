[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$DomainId,
    [Parameter(Mandatory = $true)]
    [string]$TemplateRelativePath,
    [Parameter(Mandatory = $true)]
    [string[]]$SuiteRelativePaths,
    [Parameter(Mandatory = $true)]
    [string[]]$SuiteFqns,
    [string[]]$AdditionalAsRelativePaths = @(),
    [Parameter(Mandatory = $true)]
    [string[]]$ExpectedTracePatterns,
    [Parameter(Mandatory = $true)]
    [string]$SuccessSummary,
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [ValidateRange(1, 3600)]
    [int]$AsyncBehaviorTimeoutSeconds = 30,
    # Native-art suites may own an XFL with explicit shared-library imports.
    # It still includes the same transactional scripts/TestLoader.as entry.
    [string]$CompileTargetRelativePath = '',
    [string]$CompileSwfRelativePath = '',
    [switch]$SkipCompile,
    [switch]$AutoStopReadOnlyPlayer,
    [switch]$OwnedReadOnlyHost,
    [switch]$OwnedDisposableSolHost,
    [string]$SolFixtureConfigPath = '',
    [switch]$ExportAssetBitmaps
)

$ErrorActionPreference = 'Stop'
$scriptsDir = Split-Path -Parent $PSScriptRoot
$projectDir = Split-Path -Parent $scriptsDir
$runnerPath = Join-Path $scriptsDir 'TestLoader.as'
$templatePath = Join-Path $projectDir $TemplateRelativePath
$compilePath = Join-Path $scriptsDir 'compile_test.ps1'
$tracePath = Join-Path $scriptsDir 'flashlog.txt'
$outputPath = Join-Path $scriptsDir 'compile_output.txt'
$errorsPath = Join-Path $scriptsDir 'compiler_errors.txt'
$uncertainMarker = Join-Path $scriptsDir 'compile_state_uncertain.marker'
$scratchMarker = Join-Path $scriptsDir 'testloader_scratch_inflight.marker'
. (Join-Path $PSScriptRoot 'testloader-scratch-transaction.ps1')

function Test-Utf8Bom([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

function Get-EvidenceIdentity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path
    $digest = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return '{0}|{1}|{2}' -f $item.LastWriteTimeUtc.Ticks, $item.Length, $digest
}

function Write-FocusedBehaviorUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $prior = if (Test-Path -LiteralPath $uncertainMarker) {
        [System.IO.File]::ReadAllText(
            $uncertainMarker, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | focused TestLoader: {1}' -f
        [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $uncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

function Export-FocusedRawTrace([string]$Directory, [string]$Name) {
    $rawPath = Join-Path $env:APPDATA 'Macromedia/Flash Player/Logs/flashlog.txt'
    if (-not (Test-Path -LiteralPath $rawPath)) { return }
    $rawStream = [IO.File]::Open($rawPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    $rawReader = [IO.StreamReader]::new($rawStream,[Text.Encoding]::UTF8)
    try { $raw = $rawReader.ReadToEnd() } finally { $rawReader.Dispose() }
    $first = [regex]::Match($raw, '(?m)^FocusedTestRunId ' + [regex]::Escape($DomainId) + ' Start: ' + [regex]::Escape($runId) + '\r?$')
    if ($first.Success) {
        [IO.File]::WriteAllText((Join-Path $Directory $Name),$raw.Substring($first.Index),[Text.UTF8Encoding]::new($false))
    }
}

if ($SuiteRelativePaths.Count -ne $SuiteFqns.Count) {
    throw 'SuiteRelativePaths and SuiteFqns must have the same number of entries.'
}

$suitePaths = @($SuiteRelativePaths | ForEach-Object { Join-Path $projectDir $_ })
$additionalPaths = @($AdditionalAsRelativePaths | ForEach-Object { Join-Path $projectDir $_ })
$requiredPaths = @($templatePath) + $suitePaths + $additionalPaths
if ([string]::IsNullOrEmpty($CompileTargetRelativePath) -ne [string]::IsNullOrEmpty($CompileSwfRelativePath)) {
    throw 'A dedicated focused XFL requires both its target and output paths.'
}
if ($CompileTargetRelativePath) {
    foreach ($relativePath in @($CompileTargetRelativePath, $CompileSwfRelativePath)) {
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $projectDir $relativePath))
        if (-not $fullPath.StartsWith($projectDir + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Focused native target and output must stay within the repository.'
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $projectDir $CompileTargetRelativePath))) {
        throw 'Focused native XFL is missing.'
    }
}
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required AS2 source is missing: $path"
    }
    if (-not (Test-Utf8Bom $path)) {
        throw "Required AS2 source lacks UTF-8 BOM: $path"
    }
}

$templateSource = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
if ([regex]::Matches($templateSource, '__FOCUSED_RUN_ID__').Count -ne 2) {
    throw 'Focused TestLoader template must contain exactly two runId placeholders.'
}
for ($suiteIndex = 0; $suiteIndex -lt $SuiteFqns.Count; $suiteIndex++) {
    $fqn = $SuiteFqns[$suiteIndex]
    $callPattern = '(?m)^\s*' + [regex]::Escape($fqn) +
        '\.runAllTests\s*\(\s*\)\s*;\s*$'
    if ([regex]::Matches($templateSource, $callPattern).Count -ne 1) {
        throw "Template must call exactly once: $fqn.runAllTests();"
    }

    $suiteSource = Get-Content -LiteralPath $suitePaths[$suiteIndex] -Raw -Encoding UTF8
    if ($suiteSource -notmatch ('class\s+' + [regex]::Escape($fqn) + '\s*\{')) {
        throw "Suite source does not define expected class: $fqn"
    }
    if ($suiteSource -notmatch 'public\s+static\s+function\s+runAllTests\s*\(') {
        throw "Suite source lacks public static runAllTests(): $fqn"
    }
}

$normalizedRoot = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\').ToUpperInvariant()
$repoHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHash = ([System.BitConverter]::ToString(
        $repoHasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $repoHasher.Dispose()
}
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $repoHash)
$compileMutexAcquired = $false
$compileLease = $null
$runId = [System.Guid]::NewGuid().ToString('N')
$installedHash = $null
$scratchTransaction = $null
$childCompileSucceeded = $false
$childInvocationReturned = $false
$behaviorTerminalObserved = $false
$ownedBehaviorUncertain = $null
$ownedHostIdentity = $null
. (Join-Path $PSScriptRoot 'testplayer-control.ps1')

if ($ExportAssetBitmaps -and $DomainId -cne 'student-repair') {
    throw 'Bitmap export is restricted to the reviewed student-repair fixture.'
}

if ($AutoStopReadOnlyPlayer -or $OwnedReadOnlyHost) {
    # This closed list is reviewed as in-memory/read-only fixture code. It never
    # covers real save, purchase, reward, or other DeliveryUnknown recovery.
    $readOnlySuites = @{
        'infrastructure-debt' = 'org.flashNight.dev.InfrastructureDebtTest,org.flashNight.dev.InventorySortDebtTest,org.flashNight.dev.ProductionDomainDebtTest'
        'scheduler-debt' = 'org.flashNight.dev.SchedulerDebtTest'
        'scheduler-boundary' = 'org.flashNight.dev.SchedulerBoundaryTest'
        'settings-authority-model' = 'org.flashNight.neur.Server.test.SettingsAuthorityModelTest'
        'settings-components' = 'org.flashNight.arki.ui.GameSettingsPanelServiceTest,org.flashNight.arki.ui.GaragePurchasePanelServiceTest,org.flashNight.arki.ui.GymTrainingPanelServiceTest,org.flashNight.neur.Server.test.SettingsAuthorityComponentTest'
        'swf-authority-debt' = 'org.flashNight.dev.SWFAuthorityDebtTest'
        'student-load-probe' = 'org.flashNight.dev.StudentLoadProbeTest'
        'student-repair' = 'org.flashNight.arki.unit.Action.Melee.StudentRepairAssetTest'
        'lee-action-asset' = 'org.flashNight.arki.unit.Action.Input.EnemyActionAssetTest'
        'wing-tiger' = 'org.flashNight.arki.unit.UnitAI.Custom.WingTigerTest'
    }
    if ($OwnedReadOnlyHost -and @(Get-Process -Name Flash -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'OwnedReadOnlyHost requires a fresh host; an existing editor is preserved.'
    }
    if (-not $readOnlySuites.ContainsKey($DomainId) -or
        ($SuiteFqns -join ',') -cne $readOnlySuites[$DomainId] -or
        $TemplateRelativePath -cne "scripts/test-runners/$DomainId/TestLoader.as.template" -or
        $CompileTargetRelativePath -or $AdditionalAsRelativePaths.Count -gt 0) {
        throw 'Automatic player cleanup is restricted to the reviewed read-only debt fixtures.'
    }
}
if ($OwnedDisposableSolHost) {
    $ownedSolSuites=@{
        'settings-sol-boundary'='org.flashNight.neur.Server.test.SettingsOwnedSolTest'
        'settings-storage-boundary'='org.flashNight.arki.item.RewardStashServiceTest,org.flashNight.neur.Server.test.SaveManagerTest,org.flashNight.neur.Server.test.SettingsOwnedSolTest'
    }
    if($AutoStopReadOnlyPlayer -or $OwnedReadOnlyHost -or !$ownedSolSuites.ContainsKey($DomainId) `
        -or ($SuiteFqns -join ',') -cne $ownedSolSuites[$DomainId] `
        -or $TemplateRelativePath -cne ('scripts/test-runners/'+$DomainId+'/TestLoader.as.template') `
        -or $CompileTargetRelativePath -or $AdditionalAsRelativePaths.Count -gt 0) { throw 'Owned SOL host is restricted to the reviewed unique-slot fixture.' }
    if(@(Get-Process -Name Flash -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Owned SOL host requires a fresh editor; existing editors are preserved.' }
    $solFixtureJson=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $SolFixtureConfigPath).Path,[Text.Encoding]::UTF8)
    $solFixture=$solFixtureJson | ConvertFrom-Json
    if($solFixture.slot -cnotmatch '^cf7_env_set_[0-9a-f]{20}$' -or $solFixture.metadata.slot -cne $solFixture.slot `
        -or $solFixture.metadata.protocol -ne 2 -or $solFixtureJson.Length -gt 16384) { throw 'Invalid owned SOL fixture identity.' }
}

try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Write-FocusedBehaviorUncertain `
            -Reason 'focused runner observed abandoned compile mutex'
        throw 'A previous compile abandoned the repository mutex. Confirm Flash/JSFL stopped and clear late markers before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to install a temporary TestLoader.'
    }
    if (Test-Path -LiteralPath $uncertainMarker) {
        throw 'Compile state is uncertain. Confirm Flash/JSFL stopped, inspect late evidence, then remove scripts/compile_state_uncertain.marker.'
    }
    if (Test-Path -LiteralPath (Join-Path $scriptsDir 'testhost_ownership.marker')) {
        throw 'An earlier owned test host lease remains; inspect its failed cleanup before installing another runner.'
    }
    $compileLease = 'v1:{0}:{1}:{2}' -f $repoHash, $PID,
        [System.Guid]::NewGuid().ToString('N')

    # The single repository compile mutex and persistent marker remain held
    # through evidence consumption and byte-exact scratch recovery.
    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $scratchMarker -RunnerPath $runnerPath -RepoHash $repoHash `
        -CompileLease $compileLease -OwnerKind ('focused:' + $DomainId)
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText(
        $runnerPath, [System.Text.Encoding]::UTF8)
    if($OwnedDisposableSolHost) { $runnerText=$runnerText.Replace('__SETTINGS_SOL_CONFIG__',(ConvertTo-Json -InputObject $solFixtureJson -Compress)) }
    [System.IO.File]::WriteAllText(
        $runnerPath,
        $runnerText.Replace('__FOCUSED_RUN_ID__', $runId).Replace('__STUDENT_EXPORT_BITMAPS__', $ExportAssetBitmaps.IsPresent.ToString().ToLowerInvariant()),
        [System.Text.UTF8Encoding]::new($true))
    $installedHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash

    if ($SkipCompile) {
        Write-Host ("[OK] {0} tracked runner static validation passed; compile skipped." -f
            $DomainId)
    } else {
        if ($OwnedReadOnlyHost -or $OwnedDisposableSolHost) {
            $ownedHostIdentity = Start-Cf7OwnedReadOnlyTestHost -ScriptsDirectory $scriptsDir
            $ownedSourceDirectory = Join-Path $projectDir ('tmp/focused-testloader-recovery/' + $runId + '/owned-source')
            [void](New-Item -ItemType Directory -Path $ownedSourceDirectory -Force)
            foreach ($ownedFile in @('TestLoader.xfl','DOMDocument.xml','PublishSettings.xml')) {
                Copy-Item -LiteralPath (Join-Path $scriptsDir ('TestLoader/' + $ownedFile)) -Destination $ownedSourceDirectory
            }
            [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $ownedSourceDirectory) 'owned-host.json'),($ownedHostIdentity | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        }
        $evidencePaths = @($tracePath, $outputPath, $errorsPath)
        $beforeIdentity = @{}
        foreach ($path in $evidencePaths) {
            $beforeIdentity[$path] = Get-EvidenceIdentity $path
        }
        $started = [System.DateTime]::UtcNow

        $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
        try {
            $env:CF7_FLASH_COMPILE_LEASE = $compileLease
            $targetArgs = @('-Target', 'test')
            if ($CompileTargetRelativePath) {
                $targetArgs = @('-Target', $CompileTargetRelativePath, '-VerifySwf', $CompileSwfRelativePath)
            }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $compilePath `
                @targetArgs -TimeoutSeconds $TimeoutSeconds
        } finally {
            if ($null -eq $previousCompileLease) {
                Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
            } else {
                $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
            }
        }
        $childInvocationReturned = $true
        if ($LASTEXITCODE -ne 0) {
            throw "$DomainId TestLoader exited $LASTEXITCODE."
        }
        if ($CompileTargetRelativePath) {
            & node (Join-Path $projectDir 'tools/swf-function-sizes.js') (Join-Path $projectDir $CompileSwfRelativePath) --max 60000
            if ($LASTEXITCODE -ne 0) { throw 'Focused native host exceeds the AVM1 function-size gate.' }
        }
        $childCompileSucceeded = $true

        foreach ($path in $evidencePaths) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "TestLoader evidence is missing: $path"
            }
            $item = Get-Item -LiteralPath $path
            $afterIdentity = Get-EvidenceIdentity $path
            if ($afterIdentity -eq $beforeIdentity[$path] -or
                $item.LastWriteTimeUtc -lt $started.AddSeconds(-1)) {
                throw "TestLoader evidence was not freshly replaced: $path"
            }
        }

        # Shared-library loading may leave a fresh, empty trace until frame 1.
        # Treat that as pending asynchronous evidence, never as a successful run.
        $trace = Get-Content -LiteralPath $tracePath -Raw -Encoding UTF8
        $trace = [string]$trace
        $escapedDomain = [regex]::Escape($DomainId)
        $escapedRunId = [regex]::Escape($runId)
        $startPattern = "(?m)^FocusedTestRunId $escapedDomain Start: $escapedRunId\r?$"
        $completePattern = "(?m)^FocusedTestRunId $escapedDomain Complete: $escapedRunId\r?$"
        $blockPattern = "(?ms)^FocusedTestRunId $escapedDomain Start: $escapedRunId\r?`n" +
            "(?<body>.*?)^FocusedTestRunId $escapedDomain Complete: $escapedRunId\r?$"
        # testMovie can return before async XML/SWF loads and later-frame checks.
        # Recover only this run's raw trace suffix; preserve every matching marker
        # so the existing duplicate/order/failure checks below remain authoritative.
        if (-not [regex]::IsMatch($trace, $completePattern)) {
            $rawTracePath = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
            $markerPattern = "(?m)^FocusedTestRunId $escapedDomain (?:Start|Complete): $escapedRunId\r?$"
            $traceDeadline = [DateTime]::UtcNow.AddSeconds($AsyncBehaviorTimeoutSeconds)
            $tracePollMilliseconds = if ($ExportAssetBitmaps) { 1000 } else { 100 }
            Write-Host '[INFO] Waiting for this focused run to finish its asynchronous checks.'
            $lastOutputClear = [DateTime]::MinValue
            do {
                if ($ExportAssetBitmaps -and $OwnedReadOnlyHost -and
                    ([DateTime]::UtcNow - $lastOutputClear).TotalSeconds -ge 1) {
                    $outputClear = Invoke-Cf7StopTestPlayers -ScriptsDirectory $scriptsDir -Operation clear_owned_test_output -ControlTimeoutSeconds 30
                    if (-not $outputClear.output_cleared) { throw 'Owned test output drain was not acknowledged.' }
                    $lastOutputClear = [DateTime]::UtcNow
                }
                if (Test-Path -LiteralPath $rawTracePath) {
                    $rawTraceStream = [IO.File]::Open($rawTracePath,
                        [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                    $rawTraceReader = [IO.StreamReader]::new($rawTraceStream, [Text.Encoding]::UTF8)
                    try { $rawTrace = $rawTraceReader.ReadToEnd() }
                    finally { $rawTraceReader.Dispose() }
                    $firstMarker = [regex]::Match($rawTrace, $markerPattern)
                    if ($firstMarker.Success) {
                        $candidateTrace = $rawTrace.Substring($firstMarker.Index)
                        if ([regex]::IsMatch($candidateTrace, $completePattern)) {
                            $trace = $candidateTrace
                            [IO.File]::WriteAllText($tracePath, $trace, [Text.UTF8Encoding]::new($false))
                            break
                        }
                    }
                }
                Start-Sleep -Milliseconds $tracePollMilliseconds
            } while ([DateTime]::UtcNow -lt $traceDeadline)
        }
        $startCount = [regex]::Matches($trace, $startPattern).Count
        $completeCount = [regex]::Matches($trace, $completePattern).Count
        $blocks = [regex]::Matches($trace, $blockPattern)
        # A healthy focused run never accepts the compile_action 32K retry path.
        if ($startCount -ne 1 -or $completeCount -ne 1 -or $blocks.Count -ne 1) {
            throw ("Focused trace marker set is invalid: starts={0}, completes={1}, blocks={2}." -f
                $startCount, $completeCount, $blocks.Count)
        }
        # Only this exact one-start/one-complete ordered block proves the test
        # player is terminal. Content assertions run after that lifecycle proof.
        $behaviorTerminalObserved = $true
        foreach ($block in $blocks) {
            $body = $block.Groups['body'].Value
            foreach ($pattern in $ExpectedTracePatterns) {
                $count = [regex]::Matches($body, $pattern).Count
                if ($count -ne 1) {
                    throw "Focused trace pattern must occur exactly once (found $count): $pattern"
                }
            }
            if ($body -match '\[TEST_FAIL\]' -or
                $body -match '(^|[\r\n])\s*\[FAIL\]' -or
                $body -match 'Tests Failed:\s*[1-9]') {
                throw 'Focused trace contains a failure sentinel.'
            }
        }

        $errors = Get-Content -LiteralPath $errorsPath -Raw -Encoding UTF8
        if ($errors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Focused compiler diagnostics are not 0 errors / 0 warnings.'
        }
        $compileOutput = Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
        $retryCount = [regex]::Matches(
            $compileOutput, 'ASO 32K branch detected').Count
        if ($retryCount -ne 0) {
            throw 'Focused compile required the 32K retry; diagnostics were preserved, but this is not a healthy pass.'
        }
        Write-Host ("[OK] {0}: {1}; blocks=1, 32K retry=0, compiler 0/0, fresh trace/output/errors." -f
            $DomainId, $SuccessSummary)
    }
} finally {
    try {
        if ($childCompileSucceeded -and -not $behaviorTerminalObserved) {
            Write-FocusedBehaviorUncertain (
                "child compile succeeded but exact behavior closure was not observed; " +
                "domain=$DomainId; runId=$runId; the old test player may still append late evidence")
            $ownedBehaviorUncertain = [IO.File]::ReadAllText($uncertainMarker, [Text.Encoding]::UTF8)
        }
    } finally {
        try {
            $cleanupReceipt = $null
            $cleanupAttempted = $false
            try {
            if ($ownedHostIdentity) {
                # Resource finality is separate from every suite passing. A failed companion suite
                # does not revoke this run's explicit native-terminal proof; all failures remain failures.
                $cleanupNativeTrace=$trace
                if($OwnedDisposableSolHost -and (Test-Path -LiteralPath $outputPath) `
                    -and (Get-Item -LiteralPath $outputPath).LastWriteTimeUtc -ge $started.AddSeconds(-1)) {
                    $cleanupNativeTrace=[IO.File]::ReadAllText($outputPath,[Text.Encoding]::UTF8)
                }
                $nativeTerminal = $cleanupNativeTrace -match ('(?m)^SettingsOwnedSolTest NativeRawKnownTerminal: '+[regex]::Escape($solFixture.slot)+'\r?$') `
                    -and $cleanupNativeTrace -match '(?m)^SettingsOwnedSolTest Tests Failed: 0\r?$' `
                    -and $cleanupNativeTrace -match ('(?m)^FocusedTestRunId '+[regex]::Escape($DomainId)+' Complete: '+[regex]::Escape($runId)+'\r?$')
                if($OwnedDisposableSolHost -and !$nativeTerminal) {
                    throw 'Owned SOL boundary is not known terminal; preserve player, source and uncertainty evidence.'
                }
                $cleanupAttempted = $true
                $archiveDirectory = Join-Path $projectDir ('tmp/focused-testloader-recovery/' + $runId)
                [void](New-Item -ItemType Directory -Path $archiveDirectory -Force)
                if (Test-Path -LiteralPath $uncertainMarker) { $ownedBehaviorUncertain = [IO.File]::ReadAllText($uncertainMarker,[Text.Encoding]::UTF8) }
                foreach ($artifact in @($tracePath,$outputPath,$errorsPath,(Join-Path $scriptsDir 'TestLoader.swf'),$uncertainMarker)) {
                    if (Test-Path -LiteralPath $artifact) { Copy-Item -LiteralPath $artifact -Destination $archiveDirectory -Force }
                }
                Export-FocusedRawTrace $archiveDirectory 'raw-trace-before-stop.txt'
                $ownedHostStop = Stop-Cf7OwnedReadOnlyTestHost -Identity $ownedHostIdentity
                Copy-Item -LiteralPath $ownedHostIdentity.ownership_marker -Destination $archiveDirectory -Force
                if ([IO.File]::ReadAllText($ownedHostIdentity.ownership_marker) -cne $ownedHostIdentity.ownership_body) { throw 'Owned host lease changed after exit; refusing cleanup.' }
                Remove-Item -LiteralPath $ownedHostIdentity.ownership_marker
                Export-FocusedRawTrace $archiveDirectory 'raw-trace-after-stop.txt'
                $instructionBodies = @{}
                foreach ($instruction in @('compile_target.cfg','compile_mode.cfg','compile_reopen.marker','testplayer_control.cfg','compile_quit_after_publish.cfg')) {
                    $instructionPath = Join-Path $scriptsDir $instruction
                    if (Test-Path -LiteralPath $instructionPath) {
                        $instructionBodies[$instructionPath] = [IO.File]::ReadAllText($instructionPath,[Text.Encoding]::UTF8)
                        Copy-Item -LiteralPath $instructionPath -Destination $archiveDirectory -Force
                    }
                }
                $stoppedEvidence = @{}
                foreach ($artifact in @($tracePath,$outputPath,$errorsPath,(Join-Path $scriptsDir 'TestLoader.swf'))) { $stoppedEvidence[$artifact] = Get-EvidenceIdentity $artifact }
                Start-Sleep -Milliseconds 250
                foreach ($artifact in $stoppedEvidence.Keys) {
                    if ((Get-EvidenceIdentity $artifact) -cne $stoppedEvidence[$artifact]) { throw 'Late owned-host evidence changed after process exit; recovery remains blocked.' }
                }
                foreach ($instructionPath in $instructionBodies.Keys) {
                    if ([IO.File]::ReadAllText($instructionPath,[Text.Encoding]::UTF8) -cne $instructionBodies[$instructionPath]) { throw 'Owned instruction changed during recovery; refusing removal.' }
                    Remove-Item -LiteralPath $instructionPath
                }
                $cleanupReceipt = @{domain=$DomainId;run_id=$runId;player_stopped=$true;scratch_restored=$true;behavior_terminal=$behaviorTerminalObserved;test_pass_not_inferred=$true;owned_host=$ownedHostStop;utc=[DateTime]::UtcNow.ToString('o')}
            } elseif ($AutoStopReadOnlyPlayer -and $childInvocationReturned -and
                (-not (Test-Path -LiteralPath $uncertainMarker) -or $ownedBehaviorUncertain)) {
                $cleanupAttempted = $true
                $archiveDirectory = Join-Path $projectDir ('tmp/focused-testloader-recovery/' + $runId)
                [void](New-Item -ItemType Directory -Path $archiveDirectory -Force)
                foreach ($artifact in @($tracePath,$outputPath,$errorsPath,(Join-Path $scriptsDir 'TestLoader.swf'),$uncertainMarker)) {
                    if (Test-Path -LiteralPath $artifact) { Copy-Item -LiteralPath $artifact -Destination $archiveDirectory -Force }
                }
                Export-FocusedRawTrace $archiveDirectory 'raw-trace-before-stop.txt'
                $swfBeforeStop = Get-EvidenceIdentity (Join-Path $scriptsDir 'TestLoader.swf')
                $previousStopLease = $env:CF7_FLASH_COMPILE_LEASE
                try {
                    $env:CF7_FLASH_COMPILE_LEASE = $compileLease
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $compilePath -StopTestPlayers
                    if ($LASTEXITCODE -ne 0) { throw 'CS6 player stop was not acknowledged; unknown-state recovery remains blocked.' }
                } finally {
                    if ($null -eq $previousStopLease) { Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue }
                    else { $env:CF7_FLASH_COMPILE_LEASE = $previousStopLease }
                }
                Export-FocusedRawTrace $archiveDirectory 'raw-trace-after-stop.txt'
                if ((Get-EvidenceIdentity (Join-Path $scriptsDir 'TestLoader.swf')) -cne $swfBeforeStop) {
                    throw 'A late compile changed the SWF during player stop; recovery remains blocked.'
                }
                $stoppedEvidence = @{}
                foreach ($artifact in @($tracePath,$outputPath,$errorsPath)) { $stoppedEvidence[$artifact] = Get-EvidenceIdentity $artifact }
                Start-Sleep -Milliseconds 250
                foreach ($artifact in @($tracePath,$outputPath,$errorsPath)) {
                    if ((Get-EvidenceIdentity $artifact) -cne $stoppedEvidence[$artifact]) { throw 'Late diagnostics changed after player stop; recovery remains blocked.' }
                }
                $cleanupReceipt = @{domain=$DomainId;run_id=$runId;player_stopped=$true;scratch_restored=$true;behavior_terminal=$behaviorTerminalObserved;test_pass_not_inferred=$true;utc=[DateTime]::UtcNow.ToString('o')}
            }
            } catch {
                if ($cleanupAttempted -and -not (Test-Path -LiteralPath $uncertainMarker)) {
                    Write-FocusedBehaviorUncertain "player cleanup was not verified; domain=$DomainId; runId=$runId"
                }
                throw
            } finally {
                # Restore bytes even if player control fails, preserving the
                # unknown-state gate and its original failed test evidence.
                if ($scratchTransaction -and $installedHash) {
                    Restore-Cf7TestLoaderScratchTransaction `
                        -Transaction $scratchTransaction -InstalledHash $installedHash
                }
            }
            if ($cleanupReceipt) {
                if ($ownedBehaviorUncertain) {
                    if (-not (Test-Path -LiteralPath $uncertainMarker) -or
                        [IO.File]::ReadAllText($uncertainMarker,[Text.Encoding]::UTF8) -cne $ownedBehaviorUncertain) {
                        throw 'Unknown-state marker changed; refusing to clear another fault.'
                    }
                    Remove-Item -LiteralPath $uncertainMarker
                    Write-Host '[RECOVERED] Read-only player stopped, scratch restored and late evidence inspected; this test still failed.'
                }
                [IO.File]::WriteAllText((Join-Path $archiveDirectory 'cleanup.json'),($cleanupReceipt | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            }
        } finally {
            if ($compileMutexAcquired) { $compileMutex.ReleaseMutex() }
            $compileMutex.Dispose()
            if ($scratchTransaction -and
                (Test-Path -LiteralPath $scratchTransaction.MarkerPath)) {
                Write-Warning ("TestLoader scratch transaction remains blocked; recovery backup: {0}" -f
                    $scratchTransaction.BackupPath)
            }
        }
    }
}
