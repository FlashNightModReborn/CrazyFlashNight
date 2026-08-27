[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $projectDir 'scripts\TestLoader.as'
$templatePath = Join-Path $projectDir 'scripts\test-runners\map-loot\TestLoader.as.template'
$compilePath = Join-Path $projectDir 'scripts\compile_test.ps1'
$freshTracePath = Join-Path $projectDir 'scripts\flashlog.txt'
$compilerErrorsPath = Join-Path $projectDir 'scripts\compiler_errors.txt'
$compileOutputPath = Join-Path $projectDir 'scripts\compile_output.txt'
$uncertainMarker = Join-Path $projectDir 'scripts\compile_state_uncertain.marker'
$scratchMarker = Join-Path $projectDir 'scripts\testloader_scratch_inflight.marker'
. (Join-Path $projectDir 'scripts\test-runners\testloader-scratch-transaction.ps1')
$suitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\item\LootContainerServiceTest.as'
$plannerSuitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\item\LootMaterializationPlannerTest.as'
$arbiterSuitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\test\BoxInteractionArbiterTest.as'
$stageSuitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\scene\StageRunSessionTest.as'
$serverManagerPath = Join-Path $projectDir 'scripts\类定义\org\flashNight\neur\Server\ServerManager.as'
$installedRunnerHash = $null
$scratchTransaction = $null
$compileMutexAcquired = $false

$normalizedProjectDir = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\').ToUpperInvariant()
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHashBytes = $sha256.ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($normalizedProjectDir))
} finally {
    $sha256.Dispose()
}
$repoHash = ([System.BitConverter]::ToString($repoHashBytes)).Replace('-', '').Substring(0, 24)
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $repoHash)
$compileLease = $null
$runId = [System.Guid]::NewGuid().ToString('N')
$expectedServicePassCount = 151
$expectedPlannerPassCount = 9
$expectedStagePassCount = 88
$expectedPassCount = $expectedServicePassCount + $expectedPlannerPassCount + $expectedStagePassCount

function Get-EvidenceIdentity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path
    return '{0}|{1}|{2}' -f $item.LastWriteTimeUtc.Ticks, $item.Length,
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Write-MapBehaviorUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $prior = if (Test-Path -LiteralPath $uncertainMarker) {
        [System.IO.File]::ReadAllText(
            $uncertainMarker, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | map loot TestLoader: {1}' -f
        [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $uncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

$childCompileSucceeded = $false
$behaviorTerminalObserved = $false

try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Write-MapBehaviorUncertain `
            -Reason 'map runner observed abandoned compile mutex'
        throw 'A previous compile abandoned the repository mutex. Confirm Flash/JSFL stopped and clear late markers before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to install a temporary TestLoader.'
    }
    if (Test-Path -LiteralPath $uncertainMarker) {
        throw 'Compile state is uncertain. Confirm Flash/JSFL stopped, inspect late evidence, then remove scripts/compile_state_uncertain.marker.'
    }
    $compileLease = 'v1:{0}:{1}:{2}' -f $repoHash, $PID,
        [System.Guid]::NewGuid().ToString('N')

    if (-not (Test-Path -LiteralPath $suitePath)) {
        throw "Map loot AS2 suite is missing: $suitePath"
    }
    $suiteBytes = [System.IO.File]::ReadAllBytes($suitePath)
    if ($suiteBytes.Length -lt 3 -or $suiteBytes[0] -ne 0xEF -or
        $suiteBytes[1] -ne 0xBB -or $suiteBytes[2] -ne 0xBF) {
        throw 'LootContainerServiceTest.as is not UTF-8 with BOM.'
    }
    $suiteSource = Get-Content -LiteralPath $suitePath -Raw -Encoding UTF8
    $suiteRequirements = @(
        'class\s+org\.flashNight\.arki\.item\.LootContainerServiceTest';
        'public\s+static\s+function\s+runAllTests\s*\(';
        'trace\("LootContainerServiceTest Tests Passed: "\s*\+\s*_passed\)';
        'trace\("LootContainerServiceTest Tests Failed: "\s*\+\s*_failed\)'
    )
    foreach ($pattern in $suiteRequirements) {
        if ($suiteSource -notmatch $pattern) {
            throw "Map loot AS2 suite is missing required sentinel or entrypoint: $pattern"
        }
    }
    foreach ($importName in @('BaseItem', 'EquipmentUtil', 'InventoryPanelService',
            'ItemUtil', 'LootContainerService')) {
        $importPattern = 'import\s+org\.flashNight\.arki\.item\.' +
            [regex]::Escape($importName) + '\s*;'
        if ($suiteSource -notmatch $importPattern) {
            throw "Map loot AS2 suite is missing explicit import: $importName"
        }
    }
    if (-not (Test-Path -LiteralPath $plannerSuitePath)) {
        throw "Map loot materialization AS2 suite is missing: $plannerSuitePath"
    }
    $plannerBytes = [System.IO.File]::ReadAllBytes($plannerSuitePath)
    if ($plannerBytes.Length -lt 3 -or $plannerBytes[0] -ne 0xEF -or
        $plannerBytes[1] -ne 0xBB -or $plannerBytes[2] -ne 0xBF) {
        throw 'LootMaterializationPlannerTest.as is not UTF-8 with BOM.'
    }
    $plannerSource = Get-Content -LiteralPath $plannerSuitePath -Raw -Encoding UTF8
    foreach ($pattern in @(
            'class\s+org\.flashNight\.arki\.item\.LootMaterializationPlannerTest';
            'public\s+static\s+function\s+runAllTests\s*\(';
            'trace\("LootMaterializationPlannerTest Tests Passed: "\s*\+\s*_passed\)';
            'trace\("LootMaterializationPlannerTest Tests Failed: "\s*\+\s*_failed\)')) {
        if ($plannerSource -notmatch $pattern) {
            throw "Map loot materialization AS2 suite is missing required sentinel: $pattern"
        }
    }
    if (-not (Test-Path -LiteralPath $arbiterSuitePath)) {
        throw "Box interaction arbiter AS2 suite is missing: $arbiterSuitePath"
    }
    $arbiterBytes = [System.IO.File]::ReadAllBytes($arbiterSuitePath)
    if ($arbiterBytes.Length -lt 3 -or $arbiterBytes[0] -ne 0xEF -or
        $arbiterBytes[1] -ne 0xBB -or $arbiterBytes[2] -ne 0xBF) {
        throw 'BoxInteractionArbiterTest.as is not UTF-8 with BOM.'
    }
    $arbiterSource = Get-Content -LiteralPath $arbiterSuitePath -Raw -Encoding UTF8
    foreach ($pattern in @(
            'class\s+org\.flashNight\.arki\.unit\.UnitComponent\.Initializer\.test\.BoxInteractionArbiterTest';
            'public\s+static\s+function\s+runAllTests\s*\(';
            'trace\("BoxInteractionArbiterTest: "\s*\+\s*caseCount')) {
        if ($arbiterSource -notmatch $pattern) {
            throw "Box interaction arbiter AS2 suite is missing required sentinel: $pattern"
        }
    }
    if (-not (Test-Path -LiteralPath $stageSuitePath)) {
        throw "Stage run AS2 suite is missing: $stageSuitePath"
    }
    $stageBytes = [System.IO.File]::ReadAllBytes($stageSuitePath)
    if ($stageBytes.Length -lt 3 -or $stageBytes[0] -ne 0xEF -or
        $stageBytes[1] -ne 0xBB -or $stageBytes[2] -ne 0xBF) {
        throw 'StageRunSessionTest.as is not UTF-8 with BOM.'
    }
    $stageSource = Get-Content -LiteralPath $stageSuitePath -Raw -Encoding UTF8
    foreach ($pattern in @(
            'class\s+org\.flashNight\.arki\.scene\.StageRunSessionTest';
            'public\s+static\s+function\s+runAllTests\s*\(';
            'trace\("StageRunSessionTest Tests Passed: "\s*\+\s*_passed\)';
            'trace\("StageRunSessionTest Tests Failed: "\s*\+\s*_failed\)')) {
        if ($stageSource -notmatch $pattern) {
            throw "Stage run AS2 suite is missing required sentinel: $pattern"
        }
    }

    if (-not (Test-Path -LiteralPath $serverManagerPath)) {
        throw "ServerManager AS2 source is missing; cannot verify XMLSocket source isolation: $serverManagerPath"
    }
    $serverManagerBytes = [System.IO.File]::ReadAllBytes($serverManagerPath)
    if ($serverManagerBytes.Length -lt 3 -or $serverManagerBytes[0] -ne 0xEF -or
        $serverManagerBytes[1] -ne 0xBB -or $serverManagerBytes[2] -ne 0xBF) {
        throw 'ServerManager.as is not UTF-8 with BOM; XMLSocket source-isolation contract was not evaluated.'
    }
    $serverManagerSource = Get-Content -LiteralPath $serverManagerPath -Raw -Encoding UTF8
    $initSocketStart = $serverManagerSource.IndexOf('public function initXMLSocket')
    $socketConnectHandlerStart = if ($initSocketStart -ge 0) {
        $serverManagerSource.IndexOf('private function onSocketConnect', $initSocketStart)
    } else { -1 }
    if ($initSocketStart -lt 0 -or $socketConnectHandlerStart -le $initSocketStart) {
        throw 'ServerManager XMLSocket source-isolation contract is missing a bounded initXMLSocket implementation.'
    }
    $initSocketSource = $serverManagerSource.Substring(
        $initSocketStart, $socketConnectHandlerStart - $initSocketStart)
    foreach ($requirement in ([ordered]@{
            'a local XMLSocket generation capture' =
                'var\s+socket\s*:\s*XMLSocket\s*=\s*new\s+XMLSocket\s*\(\s*\)\s*;';
            'installation of the captured generation as the current socket source' =
                'xmlSocket\s*=\s*socket\s*;'
        }).GetEnumerator()) {
        if ($initSocketSource -notmatch $requirement.Value) {
            throw ("ServerManager XMLSocket source-isolation contract is missing {0}." -f
                $requirement.Key)
        }
    }
    $socketSourceGuardCount = [regex]::Matches(
        $initSocketSource, 'self\.xmlSocket\s*!==\s*socket').Count
    if ($socketSourceGuardCount -lt 3) {
        throw ("ServerManager XMLSocket source-isolation contract requires at least 3 current-source guards " +
            "('self.xmlSocket !== socket'); found {0}." -f $socketSourceGuardCount)
    }

    $forceRecoveryStart = $serverManagerSource.IndexOf(
        'public function forceSocketRecovery')
    $messageSendingSection = if ($forceRecoveryStart -ge 0) {
        $serverManagerSource.IndexOf('// ==================== 消息发送', $forceRecoveryStart)
    } else { -1 }
    if ($forceRecoveryStart -lt 0 -or $messageSendingSection -le $forceRecoveryStart) {
        throw 'ServerManager XMLSocket source-isolation contract is missing a bounded forceSocketRecovery implementation.'
    }
    $forceRecoverySource = $serverManagerSource.Substring(
        $forceRecoveryStart, $messageSendingSection - $forceRecoveryStart)
    foreach ($requirement in ([ordered]@{
            'capture of the retiring XMLSocket generation' =
                'var\s+retiringSocket\s*:\s*XMLSocket\s*=\s*xmlSocket\s*;';
            'close of the retiring XMLSocket generation' =
                'retiringSocket\.close\s*\(\s*\)\s*;';
            'identity-guarded retirement to null' =
                'if\s*\(\s*xmlSocket\s*===\s*retiringSocket\s*\)\s*xmlSocket\s*=\s*null\s*;';
            'handoff to the unified onSocketClose recovery path' =
                '(?m)^\s*onSocketClose\s*\(\s*\)\s*;\s*$'
        }).GetEnumerator()) {
        if ($forceRecoverySource -notmatch $requirement.Value) {
            throw ("ServerManager forceSocketRecovery source-isolation contract is missing {0}." -f
                $requirement.Key)
        }
    }
    Write-Host (("[INFO] Verified ServerManager XMLSocket source isolation: {0} current-source guards, " +
        'captured generation retirement, and unified onSocketClose handoff.') -f
        $socketSourceGuardCount)
    Write-Host ("[INFO] Verified focused map loot, materialization, box arbiter, and stage run AS2 suites: {0}" -f $suitePath)

    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $scratchMarker -RunnerPath $runnerPath -RepoHash $repoHash `
        -CompileLease $compileLease -OwnerKind 'map-loot'
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction

    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText(
        $runnerPath, [System.Text.Encoding]::UTF8)
    $runIdPlaceholder = '__MAP_LOOT_RUN_ID__'
    $placeholderCount = [regex]::Matches(
        $runnerText, [regex]::Escape($runIdPlaceholder)).Count
    if ($placeholderCount -ne 2) {
        throw "Map loot TestLoader template must contain exactly two runId placeholders; found $placeholderCount."
    }
    $runnerText = $runnerText.Replace($runIdPlaceholder, $runId)
    [System.IO.File]::WriteAllText(
        $runnerPath, $runnerText, [System.Text.UTF8Encoding]::new($true))
    $bytes = [System.IO.File]::ReadAllBytes($runnerPath)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        throw 'Map loot TestLoader template is not UTF-8 with BOM.'
    }
    $installedRunnerHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash

    Write-Host ("[INFO] Installed focused map loot TestLoader runner for runId {0}." -f $runId)
    if ($SkipCompile) {
        Write-Host '[OK] Map loot focused runner static validation passed; compile was intentionally skipped.'
    } else {
        $runStartedUtc = [DateTime]::UtcNow
        $evidenceBefore = @{}
        foreach ($path in @($freshTracePath, $compilerErrorsPath, $compileOutputPath)) {
            $evidenceBefore[$path] = Get-EvidenceIdentity $path
        }

        $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
        try {
            $env:CF7_FLASH_COMPILE_LEASE = $compileLease
            & powershell -NoProfile -ExecutionPolicy Bypass -File $compilePath `
                -Target test -TimeoutSeconds $TimeoutSeconds
        } finally {
            if ($null -eq $previousCompileLease) {
                Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
            } else {
                $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
            }
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Map loot TestLoader failed with exit code $LASTEXITCODE"
        }
        $childCompileSucceeded = $true
        foreach ($path in @($freshTracePath, $compilerErrorsPath, $compileOutputPath)) {
            if (-not (Test-Path -LiteralPath $path) -or
                (Get-EvidenceIdentity $path) -eq $evidenceBefore[$path] -or
                (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
                throw "Map loot evidence was not freshly replaced: $path"
            }
        }

        if (-not (Test-Path -LiteralPath $freshTracePath)) {
            throw 'Map loot TestLoader produced no fresh scripts/flashlog.txt.'
        }

        $trace = Get-Content -LiteralPath $freshTracePath -Raw -Encoding UTF8
        $runIdPattern = [regex]::Escape($runId)
        $startPattern = "(?m)^MapLootTestRunId Start: $runIdPattern\r?$"
        $completePattern = "(?m)^MapLootTestRunId Complete: $runIdPattern\r?$"
        $runBlockPattern = "(?ms)^MapLootTestRunId Start: $runIdPattern\r?`n" +
            "(?<body>.*?)^MapLootTestRunId Complete: $runIdPattern\r?$"
        $startCount = [regex]::Matches($trace, $startPattern).Count
        $completeCount = [regex]::Matches($trace, $completePattern).Count
        $runBlockMatches = [regex]::Matches($trace, $runBlockPattern)
        # A healthy focused run never accepts the compile_action 32K retry path.
        if ($startCount -ne 1 -or $completeCount -ne 1 -or
            $runBlockMatches.Count -ne 1) {
            throw ("Map loot fresh trace contains an invalid runId block set: starts={0}, completes={1}, orderedBlocks={2}." -f
                $startCount, $completeCount, $runBlockMatches.Count)
        }
        # Content assertions are meaningful only after one exact ordered
        # start/complete pair proves the test player reached a terminal state.
        $behaviorTerminalObserved = $true
        $requiredTracePatterns = @(
            '(?m)^BoxInteractionArbiterTest: 13/13 cases, 53 assertions passed\r?$';
            '(?m)^=== LootContainerServiceTest start ===\r?$';
            "(?m)^LootContainerServiceTest Tests Passed: $expectedServicePassCount\r?$";
            '(?m)^LootContainerServiceTest Tests Failed: 0\r?$';
            '(?m)^=== LootContainerServiceTest end ===\r?$';
            '(?m)^=== LootMaterializationPlannerTest start ===\r?$';
            "(?m)^LootMaterializationPlannerTest Tests Passed: $expectedPlannerPassCount\r?$";
            '(?m)^LootMaterializationPlannerTest Tests Failed: 0\r?$';
            '(?m)^=== LootMaterializationPlannerTest end ===\r?$';
            '(?m)^=== StageRunSessionTest start ===\r?$';
            "(?m)^StageRunSessionTest Tests Passed: $expectedStagePassCount\r?$";
            '(?m)^StageRunSessionTest Tests Failed: 0\r?$';
            '(?m)^=== StageRunSessionTest end ===\r?$'
        )
        for ($blockIndex = 0; $blockIndex -lt $runBlockMatches.Count; $blockIndex++) {
            $runTrace = $runBlockMatches[$blockIndex].Groups['body'].Value
            foreach ($pattern in $requiredTracePatterns) {
                $patternCount = [regex]::Matches($runTrace, $pattern).Count
                if ($patternCount -ne 1) {
                    throw "Map loot fresh trace block $($blockIndex + 1) requires exactly one suite sentinel (found $patternCount): $pattern"
                }
            }
            $passCount = [regex]::Matches($runTrace, '(?m)^PASS: ').Count
            if ($passCount -ne $expectedPassCount) {
                throw "Map loot fresh trace block $($blockIndex + 1) reports $passCount PASS lines; expected exactly $expectedPassCount."
            }
            if ($runTrace -match '\[TEST_FAIL\]' -or
                $runTrace -match '(^|[\r\n])\s*\[FAIL\]' -or
                $runTrace -match 'Tests Failed:\s*[1-9]') {
                throw "Map loot fresh trace block $($blockIndex + 1) contains a test failure sentinel."
            }
        }

        if (-not (Test-Path -LiteralPath $compilerErrorsPath)) {
            throw 'Map loot TestLoader produced no fresh scripts/compiler_errors.txt.'
        }
        $compilerErrors = Get-Content -LiteralPath $compilerErrorsPath -Raw -Encoding UTF8
        if ($compilerErrors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Map loot compiler_errors.txt does not report zero compiler errors.'
        }
        $compileOutput = Get-Content -LiteralPath $compileOutputPath -Raw -Encoding UTF8
        $retryCount = [regex]::Matches(
            $compileOutput, 'ASO 32K branch detected').Count
        if ($retryCount -ne 0) {
            throw "Map loot compile required $retryCount 32K retry; diagnostics were preserved, but this is not a healthy pass."
        }

        Write-Host ("[OK] Map loot fresh trace verified: exact runId, one block, {0} passed, 0 failed, 32K retry=0, and compiler 0/0." -f
            $expectedPassCount)
    }
}
finally {
    try {
        if ($childCompileSucceeded -and -not $behaviorTerminalObserved) {
            Write-MapBehaviorUncertain (
                "child compile succeeded but exact behavior closure was not observed; " +
                "runId=$runId; the old test player may still append late evidence")
        }
    } finally {
        try {
            # The persistent transaction exists before the temporary runner has
            # a proven installed hash. Preserve its marker on any earlier
            # failure instead of attempting an unprovable automatic restore.
            if ($scratchTransaction -and $installedRunnerHash) {
                Restore-Cf7TestLoaderScratchTransaction `
                    -Transaction $scratchTransaction -InstalledHash $installedRunnerHash
                Write-Host '[INFO] Restored original TestLoader scratch runner.'
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
