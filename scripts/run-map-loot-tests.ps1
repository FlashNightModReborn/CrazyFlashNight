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
$suitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\item\LootContainerServiceTest.as'
$plannerSuitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\item\LootMaterializationPlannerTest.as'
$backupPath = $null
$hadRunner = $false
$originalRunnerHash = $null
$runnerInstalled = $false
$restoreSucceeded = $false
$mutexAcquired = $false

$normalizedProjectDir = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\').ToUpperInvariant()
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHashBytes = $sha256.ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($normalizedProjectDir))
} finally {
    $sha256.Dispose()
}
$repoHash = ([System.BitConverter]::ToString($repoHashBytes)).Replace('-', '').Substring(0, 24)
$mutexName = 'Local\CF7_ChestS0Tests_' + $repoHash
$runMutex = [System.Threading.Mutex]::new($false, $mutexName)
$runId = [System.Guid]::NewGuid().ToString('N')
$expectedServicePassCount = 159
$expectedPlannerPassCount = 7
$expectedPassCount = $expectedServicePassCount + $expectedPlannerPassCount

try {
    try {
        $mutexAcquired = $runMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $mutexAcquired = $true
        throw 'A previous focused TestLoader runner terminated while holding the repository mutex. Inspect scripts/TestLoader.as before retrying.'
    }
    if (-not $mutexAcquired) {
        throw 'Another focused TestLoader runner is already using this repository. Refusing to overwrite the shared TestLoader/trace artifacts.'
    }
    Write-Host ("[INFO] Acquired shared TestLoader repository mutex: {0}" -f $mutexName)

    $hadRunner = Test-Path -LiteralPath $runnerPath
    if ($hadRunner) {
        $originalRunnerHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash
    }

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
    Write-Host ("[INFO] Verified focused map loot AS2 suite and explicit imports: {0}" -f $suitePath)

    if ($hadRunner) {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) `
            ('cf7-TestLoader-' + [System.Guid]::NewGuid().ToString('N') + '.as')
        Copy-Item -LiteralPath $runnerPath -Destination $backupPath
        $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
        if ($backupHash -ne $originalRunnerHash) {
            throw 'TestLoader recovery backup hash does not match the original scratch runner.'
        }
    }

    $runnerInstalled = $true
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

    Write-Host ("[INFO] Installed focused map loot TestLoader runner for runId {0}." -f $runId)
    if ($SkipCompile) {
        Write-Host '[OK] Map loot focused runner static validation passed; compile was intentionally skipped.'
    } else {
        $runStartedUtc = [DateTime]::UtcNow
        $traceBeforeUtc = if (Test-Path -LiteralPath $freshTracePath) {
            (Get-Item -LiteralPath $freshTracePath).LastWriteTimeUtc
        } else { $null }
        $compilerErrorsBeforeUtc = if (Test-Path -LiteralPath $compilerErrorsPath) {
            (Get-Item -LiteralPath $compilerErrorsPath).LastWriteTimeUtc
        } else { $null }

        & powershell -NoProfile -ExecutionPolicy Bypass -File $compilePath `
            -Target test -TimeoutSeconds $TimeoutSeconds
        if ($LASTEXITCODE -ne 0) {
            throw "Map loot TestLoader failed with exit code $LASTEXITCODE"
        }

        if (-not (Test-Path -LiteralPath $freshTracePath)) {
            throw 'Map loot TestLoader produced no fresh scripts/flashlog.txt.'
        }
        $traceItem = Get-Item -LiteralPath $freshTracePath
        if (($traceBeforeUtc -and $traceItem.LastWriteTimeUtc -le $traceBeforeUtc) -or
            $traceItem.LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
            throw 'Map loot scripts/flashlog.txt was not refreshed by this run.'
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
        # compile_action.jsfl is allowed to retry the same TestLoader target once after the
        # documented cold-ASO 32K branch failure. testMovie writes trace on both attempts, so a
        # valid fresh run may contain one or two complete blocks with the same injected runId.
        # Accept only those two shapes and validate every block independently; unmatched or a
        # third execution remains a hard failure instead of being hidden by the final green run.
        if ($startCount -lt 1 -or $startCount -gt 2 -or
            $completeCount -ne $startCount -or
            $runBlockMatches.Count -ne $startCount) {
            throw ("Map loot fresh trace contains an invalid runId block set: starts={0}, completes={1}, orderedBlocks={2}." -f
                $startCount, $completeCount, $runBlockMatches.Count)
        }
        $requiredTracePatterns = @(
            '(?m)^=== LootContainerServiceTest start ===\r?$';
            "(?m)^LootContainerServiceTest Tests Passed: $expectedServicePassCount\r?$";
            '(?m)^LootContainerServiceTest Tests Failed: 0\r?$';
            '(?m)^=== LootContainerServiceTest end ===\r?$';
            '(?m)^=== LootMaterializationPlannerTest start ===\r?$';
            "(?m)^LootMaterializationPlannerTest Tests Passed: $expectedPlannerPassCount\r?$";
            '(?m)^LootMaterializationPlannerTest Tests Failed: 0\r?$';
            '(?m)^=== LootMaterializationPlannerTest end ===\r?$'
        )
        for ($blockIndex = 0; $blockIndex -lt $runBlockMatches.Count; $blockIndex++) {
            $runTrace = $runBlockMatches[$blockIndex].Groups['body'].Value
            foreach ($pattern in $requiredTracePatterns) {
                if ($runTrace -notmatch $pattern) {
                    throw "Map loot fresh trace block $($blockIndex + 1) is missing required suite sentinel: $pattern"
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
        $compilerErrorsItem = Get-Item -LiteralPath $compilerErrorsPath
        if (($compilerErrorsBeforeUtc -and
                $compilerErrorsItem.LastWriteTimeUtc -le $compilerErrorsBeforeUtc) -or
            $compilerErrorsItem.LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
            throw 'Map loot scripts/compiler_errors.txt was not refreshed by this run.'
        }
        $compilerErrors = Get-Content -LiteralPath $compilerErrorsPath -Raw -Encoding UTF8
        if ($compilerErrors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Map loot compiler_errors.txt does not report zero compiler errors.'
        }

        Write-Host ("[OK] Map loot fresh trace verified: exact runId, {0} complete block(s), {1} passed per block, 0 failed, and 0 compiler errors." -f
            $runBlockMatches.Count, $expectedPassCount)
    }
}
finally {
    try {
        if ($runnerInstalled) {
            if ($hadRunner) {
                if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath)) {
                    throw 'Cannot restore the original TestLoader because its recovery backup is missing.'
                }
                Copy-Item -LiteralPath $backupPath -Destination $runnerPath -Force
                $restoredHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash
                if ($restoredHash -ne $originalRunnerHash) {
                    throw 'Restored TestLoader hash does not match the original scratch runner.'
                }
                Write-Host '[INFO] Restored original TestLoader scratch runner.'
            } elseif (Test-Path -LiteralPath $runnerPath) {
                Remove-Item -LiteralPath $runnerPath -Force
                Write-Host '[INFO] Removed temporary TestLoader scratch runner.'
            }
        }
        $restoreSucceeded = $true
    } finally {
        try {
            if ($mutexAcquired) { $runMutex.ReleaseMutex() }
        } finally {
            $runMutex.Dispose()
        }
        if ($restoreSucceeded -and $backupPath -and (Test-Path -LiteralPath $backupPath)) {
            Remove-Item -LiteralPath $backupPath -Force
        } elseif (-not $restoreSucceeded -and $backupPath -and
                (Test-Path -LiteralPath $backupPath)) {
            Write-Warning ("TestLoader restore failed; recovery backup retained at {0}" -f $backupPath)
        }
    }
}
