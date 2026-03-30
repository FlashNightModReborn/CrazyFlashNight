param(
    [string]$Mode = 'trainer_only',
    [int]$WaitTimeoutSec = 180,
    [string[]]$Problems = @(),
    [switch]$Json,
    [switch]$KeepOptionsFile,
    [switch]$NoBus,
    [switch]$StopBusAfter
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$CompileScript = Join-Path $ScriptDir 'compile_test.ps1'
$OptionsFile = Join-Path $ScriptDir 'testloader_options.txt'
$TestLoaderAs = Join-Path $ScriptDir 'TestLoader.as'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$LocalFlashLog = Join-Path $ScriptDir 'flashlog.txt'

function Normalize-ProblemNames {
    param([string[]]$Names)

    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Names) {
        if (-not $item) { continue }
        foreach ($part in ($item -split ',')) {
            $name = $part.Trim()
            if ($name.Length -gt 0) {
                $normalized.Add($name)
            }
        }
    }
    return $normalized.ToArray()
}

function New-OptionsContent {
    param(
        [string]$ModeName,
        [string[]]$ProblemNames
    )

    $isTrainerOnly = $ModeName -eq 'trainer_only'
    $runTests = if ($isTrainerOnly) { '0' } else { '1' }
    $runFullGame = if ($isTrainerOnly) { '0' } else { '1' }
    $runGui = if ($isTrainerOnly) { '0' } else { '1' }
    $problemFilter = (($ProblemNames | Where-Object { $_ -and $_.Trim().Length -gt 0 }) -join ',')
    return @"
mode=$ModeName
runTrainer=1
runTests=$runTests
runFullGame=$runFullGame
runGui=$runGui
problemFilter=$problemFilter
difficulty=100
frameBudget=8
rapfiTime=2000
maxMoves=80
"@
}

function Parse-Summary {
    param([string[]]$Lines)

    $summary = [ordered]@{
        total = $null
        run = $null
        skipped = $null
        local_pass = $null
        local_run = $null
        local_pct = $null
        rapfi_pass = $null
        rapfi_run = $null
        rapfi_pct = $null
        categories = [ordered]@{}
        fails = @()
        rapfi_divergences = @()
    }

    foreach ($line in $Lines) {
        if ($line -match '^Total:\s+(\d+)\s+\|\s+Run:\s+(\d+)\s+\|\s+Skipped:\s+(\d+)') {
            $summary.total = [int]$matches[1]
            $summary.run = [int]$matches[2]
            $summary.skipped = [int]$matches[3]
            continue
        }
        if ($line -match '^Local AI accuracy:\s+(\d+)/(\d+)\s+\((\d+)%\)') {
            $summary.local_pass = [int]$matches[1]
            $summary.local_run = [int]$matches[2]
            $summary.local_pct = [int]$matches[3]
            continue
        }
        if ($line -match '^Rapfi accuracy:\s+(\d+)/(\d+)\s+\((\d+)%\)') {
            $summary.rapfi_pass = [int]$matches[1]
            $summary.rapfi_run = [int]$matches[2]
            $summary.rapfi_pct = [int]$matches[3]
            continue
        }
        if ($line -match '^\s+([A-Za-z0-9_]+):\s+local\s+(\d+)/(\d+)(?:\s+\|\s+rapfi\s+(\d+)/(\d+))?') {
            $summary.categories[$matches[1]] = [ordered]@{
                local_pass = [int]$matches[2]
                local_total = [int]$matches[3]
                rapfi_pass = $(if ($matches[4]) { [int]$matches[4] } else { $null })
                rapfi_total = $(if ($matches[5]) { [int]$matches[5] } else { $null })
            }
            continue
        }
        if ($line -match '^\[Trainer\] \[FAIL\] ') {
            $summary.fails += $line
            continue
        }
        if ($line -match '^\[Trainer\] \[RAPFI_DIFF\] ') {
            $summary.rapfi_divergences += $line
        }
    }

    return $summary
}

function Get-LatestRunLines {
    param([string]$RawText)

    $startMarker = '=== GOBANG AUTOMATION TEST ==='
    $idx = $RawText.LastIndexOf($startMarker)
    if ($idx -lt 0) {
        return ($RawText -split "`r?`n")
    }
    return ($RawText.Substring($idx) -split "`r?`n")
}

$ProjectRoot = Split-Path -Parent $ScriptDir
$LauncherExe = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'

# 端口候选列表（与 PortAllocator 种子 "1192433993" 一致）
$BusPorts = @(1192, 1924, 9243, 2433, 4339, 3399, 3993, 11924, 19243, 24339, 43399, 33993, 3000)

function Test-BusRunning {
    foreach ($p in $BusPorts) {
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$p/testConnection" `
                -Method POST -Body '' -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
            if ($r.StatusCode -eq 200) { return $true }
        } catch {}
    }
    return $false
}

# === Bus 管理（默认自动启动 --bus-only，除非 -NoBus 或已有游戏在跑）===
$busStartedByUs = $false
if (-not $NoBus) {
    if (Test-BusRunning) {
        Write-Host '[bus] Already running'
    } else {
        if (-not (Test-Path $LauncherExe)) {
            Write-Host "[bus] ERROR: Launcher not found: $LauncherExe" -ForegroundColor Red
            exit 1
        }
        Write-Host '[bus] Starting launcher --bus-only...'
        $busProc = Start-Process -FilePath $LauncherExe -ArgumentList '--bus-only' -PassThru -WindowStyle Minimized
        $busStartedByUs = $true
        # 等待就绪
        $busDeadline = (Get-Date).AddSeconds(15)
        $busReady = $false
        while ((Get-Date) -lt $busDeadline) {
            Start-Sleep -Seconds 1
            if (Test-BusRunning) { $busReady = $true; break }
        }
        if (-not $busReady) {
            Write-Host '[bus] ERROR: Bus failed to start within 15s' -ForegroundColor Red
            exit 1
        }
        Write-Host '[bus] Ready'
    }
}

$compileExit = $null
$compileOutput = ''
$summary = $null
$elapsedSec = $null
$Problems = Normalize-ProblemNames -Names $Problems
$beforeTime = if (Test-Path $FlashLog) { (Get-Item $FlashLog).LastWriteTimeUtc } else { [datetime]::MinValue }
$beforeLength = if (Test-Path $FlashLog) { (Get-Item $FlashLog).Length } else { 0 }
$startTime = Get-Date

$TestLoaderBackup = $null
try {
    # 写 options 文件（供日志追溯）
    [System.IO.File]::WriteAllText($OptionsFile, (New-OptionsContent -ModeName $Mode -ProblemNames $Problems), [System.Text.UTF8Encoding]::new($false))

    # 备份并重写 TestLoader.as（AS2 不能读文件系统，只能直接注入代码）
    if (Test-Path $TestLoaderAs) {
        $TestLoaderBackup = [System.IO.File]::ReadAllBytes($TestLoaderAs)
    }
    $problemFilter = ($Problems -join ',')
    $trainerCode = "import org.flashNight.hana.Gobang.*;" + "`r`n"
    $trainerCode += 'trace("=== GOBANG AUTOMATION TEST ===");' + "`r`n"
    $trainerCode += "var trainer:GobangTrainer = new GobangTrainer();" + "`r`n"
    $trainerCode += "trainer.loadBuiltinProblems();" + "`r`n"
    if ($problemFilter.Length -gt 0) {
        $trainerCode += "trainer.filterProblemsByName(`"$problemFilter`");" + "`r`n"
    }
    $trainerCode += "trainer.run(null);"

    # UTF-8 BOM（AS2 编译器要求）
    $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
    $codeBytes = [System.Text.Encoding]::UTF8.GetBytes($trainerCode)
    $allBytes = New-Object byte[] ($bom.Length + $codeBytes.Length)
    [Array]::Copy($bom, 0, $allBytes, 0, $bom.Length)
    [Array]::Copy($codeBytes, 0, $allBytes, $bom.Length, $codeBytes.Length)
    [System.IO.File]::WriteAllBytes($TestLoaderAs, $allBytes)

    $compileOutput = (& $CompileScript *>&1 | Out-String)
    $compileExit = $LASTEXITCODE

    $deadline = (Get-Date).AddSeconds($WaitTimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $FlashLog) {
            $item = Get-Item $FlashLog
            if ($item.LastWriteTimeUtc -gt $beforeTime -or $item.Length -gt $beforeLength) {
                $raw = Get-Content -Raw -Encoding UTF8 $FlashLog
                $lines = Get-LatestRunLines -RawText $raw
                $summaryIdx = -1
                for ($i = 0; $i -lt $lines.Length; $i++) {
                    if ($lines[$i] -match '\[Trainer\] SUMMARY REPORT') {
                        $summaryIdx = $i
                    }
                }
                if ($summaryIdx -ge 0) {
                    Copy-Item $FlashLog $LocalFlashLog -Force
                    $summary = Parse-Summary -Lines $lines
                    $elapsedSec = [int]((Get-Date) - $startTime).TotalSeconds
                    break
                }
            }
        }
        Start-Sleep -Seconds 1
    }
}
finally {
    if (-not $KeepOptionsFile) {
        Remove-Item -LiteralPath $OptionsFile -ErrorAction SilentlyContinue
    }
    # 恢复 TestLoader.as 原始内容
    if ($null -ne $TestLoaderBackup) {
        [System.IO.File]::WriteAllBytes($TestLoaderAs, $TestLoaderBackup)
    }
}

if ($summary -eq $null) {
    Write-Host '[ERROR] Fresh trainer summary not found.'
    if ($compileOutput) {
        Write-Host '=== compile_test output ==='
        Write-Host $compileOutput.TrimEnd()
        Write-Host '=== end compile_test output ==='
    }
    exit 1
}

$result = [ordered]@{
    mode = $Mode
    problems = $Problems
    compile_exit = $compileExit
    elapsed_sec = $elapsedSec
    summary = $summary
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    exit 0
}

Write-Host ('[cycle] mode={0} compile_exit={1} elapsed={2}s' -f $Mode, $compileExit, $elapsedSec)
if ($Problems.Count -gt 0) {
    Write-Host ('Problems={0}' -f ($Problems -join ','))
}
Write-Host ('Total={0} Run={1} Skipped={2}' -f $summary.total, $summary.run, $summary.skipped)
Write-Host ('Local={0}/{1} ({2}%)' -f $summary.local_pass, $summary.local_run, $summary.local_pct)
if ($summary.rapfi_run -ne $null) {
    Write-Host ('Rapfi={0}/{1} ({2}%)' -f $summary.rapfi_pass, $summary.rapfi_run, $summary.rapfi_pct)
}
Write-Host 'Per-category:'
foreach ($entry in $summary.categories.GetEnumerator()) {
    $cat = $entry.Key
    $value = $entry.Value
    $line = '  ' + $cat + ': local ' + $value.local_pass + '/' + $value.local_total
    if ($value.rapfi_total -ne $null) {
        $line += ' | rapfi ' + $value.rapfi_pass + '/' + $value.rapfi_total
    }
    Write-Host $line
}
if ($summary.fails.Count -gt 0) {
    Write-Host 'Fails:'
    foreach ($fail in $summary.fails) {
        Write-Host ('  ' + $fail)
    }
}
if ($summary.rapfi_divergences.Count -gt 0) {
    Write-Host 'Rapfi divergences:'
    foreach ($item in $summary.rapfi_divergences) {
        Write-Host ('  ' + $item)
    }
}

# === Bus 清理 ===
if ($busStartedByUs -and ($StopBusAfter -or $false)) {
    Write-Host '[bus] Stopping (started by this script)...'
    try { $busProc.Kill() } catch {}
    Write-Host '[bus] Stopped'
}
