[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $projectDir 'scripts\TestLoader.as'
$templatePath = Join-Path $projectDir 'scripts\test-runners\chest-s0\TestLoader.as.template'
$compilePath = Join-Path $projectDir 'scripts\compile_test.ps1'
$freshTracePath = Join-Path $projectDir 'scripts\flashlog.txt'
$compilerErrorsPath = Join-Path $projectDir 'scripts\compiler_errors.txt'
$as2ClassRoot = Join-Path $projectDir 'scripts\类定义'
$backupPath = $null
$hadRunner = Test-Path -LiteralPath $runnerPath
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

try {
    try {
        $mutexAcquired = $runMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $mutexAcquired = $true
        throw 'A previous Chest S0 runner terminated while holding the repository mutex. Inspect scripts/TestLoader.as before retrying.'
    }
    if (-not $mutexAcquired) {
        throw 'Another Chest S0 runner is already using this repository. Refusing to overwrite the shared TestLoader/trace artifacts.'
    }
    Write-Host ("[INFO] Acquired Chest S0 repository mutex: {0}" -f $mutexName)

    # F01-F04 必须由独立 production-path TestLoader 套件提供，不能让旧 P01-P04
    # supplemental preflight 的字面量或模型 helper 冒充真实 Flash wiring。
    $productionSentinel = 'ChestS0ProductionFlashWiring Cases Passed: 4/4'
    $productionTests = @(Get-ChildItem -LiteralPath $as2ClassRoot -Recurse -Filter '*.as' |
        Where-Object {
            (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8).Contains($productionSentinel)
        })
    if ($productionTests.Count -ne 1) {
        throw ("Chest S0 F01-F04 requires exactly one production-path AS2 suite containing '{0}'; found {1}." -f
            $productionSentinel, $productionTests.Count)
    }
    $productionTestPath = $productionTests[0].FullName
    if ($productionTests[0].Name -eq 'ChestS0FlashWiringTest.as') {
        throw 'P01-P04 supplemental preflight cannot be reused as the F01-F04 production-path suite.'
    }
    $productionTestSource = Get-Content -LiteralPath $productionTestPath -Raw -Encoding UTF8
    $productionPathRequirements = @(
        @{ Label = 'real global interactionKeyDown dispatch'; Pattern = 'publishGlobal(?:0)?\s*\(\s*"interactionKeyDown"' };
        @{ Label = 'production KillEventComponent bridge'; Pattern = 'KillEventComponent\.initialize\s*\(' };
        @{ Label = 'production SceneManager instance'; Pattern = 'SceneManager\.getInstance\s*\(' };
        @{ Label = 'production SceneManager.removeGameWorld'; Pattern = '\.removeGameWorld\s*\(' };
        @{ Label = 'root open-frame callback'; Pattern = '_root\.地图元件\.资源箱开启脚本\s*\(' };
        @{ Label = 'root break-frame callback'; Pattern = '_root\.地图元件\.资源箱破碎脚本\s*\(' }
    )
    foreach ($requirement in $productionPathRequirements) {
        if ($productionTestSource -notmatch $requirement.Pattern) {
            throw ("Chest S0 F01-F04 production-path suite is missing {0}: {1}" -f
                $requirement.Label, $productionTestPath)
        }
    }
    foreach ($caseId in @('F01', 'F02', 'F03', 'F04')) {
        if ($productionTestSource -notmatch [regex]::Escape($caseId)) {
            throw "Chest S0 production-path suite is missing explicit case id $caseId."
        }
    }
    Write-Host ("[INFO] Verified independent Chest S0 F01-F04 production-path suite: {0}" -f
        $productionTestPath)

    if ($hadRunner) {
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) `
            ('cf7-TestLoader-' + [System.Guid]::NewGuid().ToString('N') + '.as')
        Copy-Item -LiteralPath $runnerPath -Destination $backupPath
    }

    $runnerInstalled = $true
    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText(
        $runnerPath, [System.Text.Encoding]::UTF8)
    $runIdPlaceholder = '__CHEST_S0_RUN_ID__'
    $placeholderCount = [regex]::Matches(
        $runnerText, [regex]::Escape($runIdPlaceholder)).Count
    if ($placeholderCount -ne 2) {
        throw "Chest S0 TestLoader template must contain exactly two runId placeholders; found $placeholderCount."
    }
    $runnerText = $runnerText.Replace($runIdPlaceholder, $runId)
    [System.IO.File]::WriteAllText(
        $runnerPath, $runnerText, [System.Text.UTF8Encoding]::new($true))
    $bytes = [System.IO.File]::ReadAllBytes($runnerPath)
    if ($bytes.Length -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) {
        throw 'Chest S0 TestLoader template is not UTF-8 with BOM.'
    }

    Write-Host ("[INFO] Installed ChestS0TestSuite TestLoader runner for runId {0}." -f $runId)
        $runStartedUtc = [DateTime]::UtcNow
        $traceBeforeUtc = if (Test-Path -LiteralPath $freshTracePath) {
            (Get-Item -LiteralPath $freshTracePath).LastWriteTimeUtc
        } else { $null }
        $compilerErrorsBeforeUtc = if (Test-Path -LiteralPath $compilerErrorsPath) {
            (Get-Item -LiteralPath $compilerErrorsPath).LastWriteTimeUtc
        } else { $null }

        & powershell -ExecutionPolicy Bypass -File $compilePath -Target test -TimeoutSeconds $TimeoutSeconds
        if ($LASTEXITCODE -ne 0) { throw "Chest S0 TestLoader failed with exit code $LASTEXITCODE" }

        if (-not (Test-Path -LiteralPath $freshTracePath)) {
            throw 'Chest S0 TestLoader produced no fresh scripts/flashlog.txt.'
        }
        $traceItem = Get-Item -LiteralPath $freshTracePath
        if (($traceBeforeUtc -and $traceItem.LastWriteTimeUtc -le $traceBeforeUtc) -or
            $traceItem.LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
            throw 'Chest S0 scripts/flashlog.txt was not refreshed by this run.'
        }

        $trace = Get-Content -LiteralPath $freshTracePath -Raw -Encoding UTF8
        $requiredTracePatterns = @(
            '(?m)^BoxInteractionArbiterTest: 13/13 cases, [1-9][0-9]* assertions passed\r?$',
            '(?m)^ChestSessionServiceTest Cases Passed: 13/13\r?$',
            '(?m)^ChestS0SocketBridgeTest Cases Passed: 10/10\r?$',
            '(?m)^ChestS0SupplementalPreflight Cases Passed: 4/4\r?$',
            '(?m)^ChestS0ProductionFlashWiring Cases Passed: 4/4\r?$',
            '(?m)^ChestSessionServiceTest Tests Failed: 0\r?$',
            '(?m)^ChestS0SocketBridgeTest Tests Failed: 0\r?$',
            '(?m)^ChestS0SupplementalPreflight Tests Failed: 0\r?$',
            '(?m)^ChestS0ProductionFlashWiring Tests Failed: 0\r?$',
            '(?m)^=== ChestS0TestSuite .*F01-F04.* complete ===\r?$'
        )
        foreach ($caseId in @('F01', 'F02', 'F03', 'F04')) {
            $requiredTracePatterns += "(?m)^PASS: $caseId(?:\s|:|-).+\r?$"
        }
        $runIdPattern = [regex]::Escape($runId)
        $requiredTracePatterns += @(
            "(?m)^ChestS0TestRunId Start: $runIdPattern\r?$",
            "(?m)^ChestS0TestRunId Complete: $runIdPattern\r?$"
        )
        foreach ($pattern in $requiredTracePatterns) {
            if ($trace -notmatch $pattern) {
                throw "Chest S0 fresh trace is missing required completion sentinel: $pattern"
            }
        }
        if ($trace -match '\[TEST_FAIL\]' -or
            $trace -match '(^|[\r\n])\s*\[FAIL\]' -or
            $trace -match 'Tests Failed:\s*[1-9]') {
            throw 'Chest S0 fresh trace contains a test failure sentinel.'
        }

        if (-not (Test-Path -LiteralPath $compilerErrorsPath)) {
            throw 'Chest S0 TestLoader produced no fresh scripts/compiler_errors.txt.'
        }
        $compilerErrorsItem = Get-Item -LiteralPath $compilerErrorsPath
        if (($compilerErrorsBeforeUtc -and $compilerErrorsItem.LastWriteTimeUtc -le $compilerErrorsBeforeUtc) -or
            $compilerErrorsItem.LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
            throw 'Chest S0 scripts/compiler_errors.txt was not refreshed by this run.'
        }
        $compilerErrors = Get-Content -LiteralPath $compilerErrorsPath -Raw -Encoding UTF8
        if ($compilerErrors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Chest S0 compiler_errors.txt does not report zero compiler errors.'
        }

        Write-Host '[OK] Chest S0 A01-A25 plus A03F, S01-S10 socket actual-wire, P01-P04 supplemental preflight, and independent F01-F04 production wiring fresh trace, exact runId, and compiler errors verified.'
}
finally {
    try {
        if ($runnerInstalled) {
            if ($hadRunner) {
                if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath)) {
                    throw 'Cannot restore the original TestLoader because its recovery backup is missing.'
                }
                Copy-Item -LiteralPath $backupPath -Destination $runnerPath -Force
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
