[CmdletBinding()]
param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 240,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runnerPath = Join-Path $projectDir 'scripts\TestLoader.as'
$templatePath = Join-Path $projectDir 'scripts\test-runners\scene-collision-manager\TestLoader.as.template'
$compilePath = Join-Path $projectDir 'scripts\compile_test.ps1'
$tracePath = Join-Path $projectDir 'scripts\flashlog.txt'
$compilerErrorsPath = Join-Path $projectDir 'scripts\compiler_errors.txt'
$suitePath = Join-Path $projectDir 'scripts\类定义\org\flashNight\arki\scene\SceneCollisionManagerTest.as'
$backupPath = $null
$hadRunner = $false
$originalRunnerHash = $null
$runnerInstalled = $false
$restoreSucceeded = $false
$mutexAcquired = $false
$runId = [System.Guid]::NewGuid().ToString('N')
$expectedPassCount = 21

$normalizedProjectDir = [System.IO.Path]::GetFullPath($projectDir).TrimEnd('\').ToUpperInvariant()
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $repoHashBytes = $sha256.ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($normalizedProjectDir))
} finally {
    $sha256.Dispose()
}
$repoHash = ([System.BitConverter]::ToString($repoHashBytes)).Replace('-', '').Substring(0, 24)
# 与其他 focused TestLoader runner 共用同一仓库互斥锁。
$mutexName = 'Local\CF7_FocusedTestLoader_' + $repoHash
$runMutex = [System.Threading.Mutex]::new($false, $mutexName)

function Test-Utf8Bom([string]$Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
}

try {
    try {
        $mutexAcquired = $runMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $mutexAcquired = $true
        throw 'A previous focused TestLoader runner terminated while holding the repository mutex. Inspect scripts/TestLoader.as before retrying.'
    }
    if (-not $mutexAcquired) {
        throw 'Another focused TestLoader runner is already using this repository.'
    }
    Write-Host ("[INFO] Acquired shared TestLoader repository mutex: {0}" -f $mutexName)

    foreach ($path in @($suitePath, $templatePath, $compilePath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required scene collision test artifact is missing: $path"
        }
    }
    if (-not (Test-Utf8Bom $suitePath)) {
        throw 'SceneCollisionManagerTest.as is not UTF-8 with BOM.'
    }
    if (-not (Test-Utf8Bom $templatePath)) {
        throw 'Scene collision TestLoader template is not UTF-8 with BOM.'
    }

    $suiteSource = [System.IO.File]::ReadAllText($suitePath, [System.Text.Encoding]::UTF8)
    foreach ($pattern in @(
            'class\s+org\.flashNight\.arki\.scene\.SceneCollisionManagerTest';
            'public\s+static\s+function\s+runAllTests\s*\(';
            'trace\("SceneCollisionManagerTest Tests Passed: "\s*\+\s*_passed\)';
            'trace\("SceneCollisionManagerTest Tests Failed: "\s*\+\s*_failed\)';
            'trace\("SceneCollisionManagerTest Cases Passed: 4/4"\)')) {
        if ($suiteSource -notmatch $pattern) {
            throw "Scene collision AS2 suite is missing required sentinel: $pattern"
        }
    }
    $checkCount = [regex]::Matches($suiteSource, '(?m)^\s*check\s*\(').Count
    if ($checkCount -ne $expectedPassCount) {
        throw "Scene collision AS2 suite contains $checkCount checks; expected $expectedPassCount."
    }

    $hadRunner = Test-Path -LiteralPath $runnerPath
    if ($hadRunner) {
        $originalRunnerHash = (Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash
        $backupPath = Join-Path ([System.IO.Path]::GetTempPath()) `
            ('cf7-TestLoader-' + [System.Guid]::NewGuid().ToString('N') + '.as')
        Copy-Item -LiteralPath $runnerPath -Destination $backupPath
        if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne
                $originalRunnerHash) {
            throw 'TestLoader recovery backup hash does not match the original runner.'
        }
    }

    $runnerInstalled = $true
    Copy-Item -LiteralPath $templatePath -Destination $runnerPath -Force
    $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.Encoding]::UTF8)
    $placeholder = '__SCENE_COLLISION_RUN_ID__'
    $placeholderCount = [regex]::Matches(
        $runnerText, [regex]::Escape($placeholder)).Count
    if ($placeholderCount -ne 2) {
        throw "Scene collision TestLoader template must contain two runId placeholders; found $placeholderCount."
    }
    $runnerText = $runnerText.Replace($placeholder, $runId)
    [System.IO.File]::WriteAllText(
        $runnerPath, $runnerText, [System.Text.UTF8Encoding]::new($true))
    if (-not (Test-Utf8Bom $runnerPath)) {
        throw 'Installed scene collision TestLoader runner is not UTF-8 with BOM.'
    }

    Write-Host ("[INFO] Installed focused scene collision runner for runId {0}." -f $runId)
    if ($SkipCompile) {
        Write-Host '[OK] Scene collision focused runner static validation passed; Flash compile was intentionally skipped.'
    } else {
        $runStartedUtc = [DateTime]::UtcNow
        $traceBeforeUtc = if (Test-Path -LiteralPath $tracePath) {
            (Get-Item -LiteralPath $tracePath).LastWriteTimeUtc
        } else { $null }
        $compilerBeforeUtc = if (Test-Path -LiteralPath $compilerErrorsPath) {
            (Get-Item -LiteralPath $compilerErrorsPath).LastWriteTimeUtc
        } else { $null }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compilePath `
            -Target test -TimeoutSeconds $TimeoutSeconds
        if ($LASTEXITCODE -ne 0) {
            throw "Scene collision TestLoader failed with exit code $LASTEXITCODE"
        }

        if (-not (Test-Path -LiteralPath $tracePath)) {
            throw 'Scene collision TestLoader produced no scripts/flashlog.txt.'
        }
        $traceItem = Get-Item -LiteralPath $tracePath
        if (($traceBeforeUtc -and $traceItem.LastWriteTimeUtc -le $traceBeforeUtc) -or
            $traceItem.LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
            throw 'Scene collision scripts/flashlog.txt was not refreshed by this run.'
        }
        $trace = [System.IO.File]::ReadAllText($tracePath, [System.Text.Encoding]::UTF8)
        $escapedRunId = [regex]::Escape($runId)
        $blockPattern = "(?ms)^SceneCollisionManagerTestRunId Start: $escapedRunId\r?`n" +
            "(?<body>.*?)^SceneCollisionManagerTestRunId Complete: $escapedRunId\r?$"
        $blocks = [regex]::Matches($trace, $blockPattern)
        if ($blocks.Count -lt 1 -or $blocks.Count -gt 2) {
            throw "Scene collision fresh trace contains $($blocks.Count) complete runId blocks; expected one or the documented cold-ASO retry pair."
        }
        for ($blockIndex = 0; $blockIndex -lt $blocks.Count; $blockIndex++) {
            $body = $blocks[$blockIndex].Groups['body'].Value
            foreach ($pattern in @(
                    "(?m)^SceneCollisionManagerTest Tests Passed: $expectedPassCount\r?$";
                    '(?m)^SceneCollisionManagerTest Tests Failed: 0\r?$';
                    '(?m)^SceneCollisionManagerTest Cases Passed: 4/4\r?$')) {
                if ($body -notmatch $pattern) {
                    throw "Scene collision fresh trace block $($blockIndex + 1) is missing: $pattern"
                }
            }
            if ([regex]::Matches($body, '(?m)^PASS: ').Count -ne $expectedPassCount -or
                $body -match '(?m)^FAIL: ' -or $body -match 'Tests Failed:\s*[1-9]') {
                throw "Scene collision fresh trace block $($blockIndex + 1) has an invalid assertion result."
            }
        }

        if (-not (Test-Path -LiteralPath $compilerErrorsPath)) {
            throw 'Scene collision TestLoader produced no compiler_errors.txt.'
        }
        $compilerItem = Get-Item -LiteralPath $compilerErrorsPath
        if (($compilerBeforeUtc -and $compilerItem.LastWriteTimeUtc -le $compilerBeforeUtc) -or
            $compilerItem.LastWriteTimeUtc -lt $runStartedUtc.AddSeconds(-1)) {
            throw 'Scene collision compiler_errors.txt was not refreshed by this run.'
        }
        $compilerErrors = [System.IO.File]::ReadAllText(
            $compilerErrorsPath, [System.Text.Encoding]::UTF8)
        if ($compilerErrors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
            throw 'Scene collision compiler_errors.txt does not report zero compiler errors.'
        }
        Write-Host ("[OK] Scene collision fresh trace verified: {0} complete block(s), {1}/{1}, 0 failures, 0 compiler errors." -f
            $blocks.Count, $expectedPassCount)
    }
}
finally {
    try {
        if ($runnerInstalled) {
            if ($hadRunner) {
                if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath)) {
                    throw 'Cannot restore the original TestLoader because its backup is missing.'
                }
                Copy-Item -LiteralPath $backupPath -Destination $runnerPath -Force
                if ((Get-FileHash -LiteralPath $runnerPath -Algorithm SHA256).Hash -ne
                        $originalRunnerHash) {
                    throw 'Restored TestLoader hash does not match the original runner.'
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
