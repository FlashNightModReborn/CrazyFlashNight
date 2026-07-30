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
$ProjectRoot = Split-Path -Parent $ScriptDir
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$LocalFlashLog = Join-Path $ScriptDir 'flashlog.txt'
$CompileOutputPath = Join-Path $ScriptDir 'compile_output.txt'
$CompilerErrorsPath = Join-Path $ScriptDir 'compiler_errors.txt'
$UncertainMarker = Join-Path $ScriptDir 'compile_state_uncertain.marker'
$ScratchMarker = Join-Path $ScriptDir 'testloader_scratch_inflight.marker'
. (Join-Path $ScriptDir 'test-runners\testloader-scratch-transaction.ps1')

function Write-GobangUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $prior = if (Test-Path -LiteralPath $UncertainMarker) {
        [System.IO.File]::ReadAllText(
            $UncertainMarker, [System.Text.Encoding]::UTF8)
    } else {
        ''
    }
    $body = '{0:o} | gobang cycle: {1}' -f [System.DateTime]::UtcNow, $Reason
    if (-not [string]::IsNullOrWhiteSpace($prior)) {
        $body += "`nprevious_marker:`n" + $prior
    }
    [System.IO.File]::WriteAllText(
        $UncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
}

function Normalize-ProblemNames {
    param([string[]]$Names)

    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Names) {
        if (-not $item) { continue }
        foreach ($part in ($item -split ',')) {
            $name = $part.Trim()
            if ($name.Length -gt 0) {
                if ($name -notmatch '^[A-Za-z0-9_]+(?:\*)?$') {
                    throw "Invalid Gobang problem filter '$name'. Use an exact identifier or one trailing wildcard."
                }
                $normalized.Add($name)
            }
        }
    }
    return $normalized.ToArray()
}

function Get-EvidenceIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path
    $digest = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return '{0}|{1}|{2}' -f $item.LastWriteTimeUtc.Ticks, $item.Length, $digest
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
        parse_counts = [ordered]@{
            totals = 0
            local_accuracy = 0
            rapfi_accuracy = 0
            categories = [ordered]@{}
        }
    }

    foreach ($line in $Lines) {
        if ($line -match '^Total:\s+(\d+)\s+\|\s+Run:\s+(\d+)\s+\|\s+Skipped:\s+(\d+)') {
            $summary.parse_counts.totals++
            $summary.total = [int]$matches[1]
            $summary.run = [int]$matches[2]
            $summary.skipped = [int]$matches[3]
            continue
        }
        if ($line -match '^Local AI accuracy:\s+(\d+)/(\d+)\s+\((\d+)%\)') {
            $summary.parse_counts.local_accuracy++
            $summary.local_pass = [int]$matches[1]
            $summary.local_run = [int]$matches[2]
            $summary.local_pct = [int]$matches[3]
            continue
        }
        if ($line -match '^Rapfi accuracy:\s+(\d+)/(\d+)\s+\((\d+)%\)') {
            $summary.parse_counts.rapfi_accuracy++
            $summary.rapfi_pass = [int]$matches[1]
            $summary.rapfi_run = [int]$matches[2]
            $summary.rapfi_pct = [int]$matches[3]
            continue
        }
        if ($line -match '^\s+([A-Za-z0-9_]+):\s+local\s+(\d+)/(\d+)(?:\s+\|\s+rapfi\s+(\d+)/(\d+))?') {
            $categoryName = $matches[1]
            if (-not $summary.parse_counts.categories.Contains($categoryName)) {
                $summary.parse_counts.categories[$categoryName] = 0
            }
            $summary.parse_counts.categories[$categoryName]++
            $summary.categories[$categoryName] = [ordered]@{
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

function Get-ClosedRunLines {
    param(
        [string]$RawText,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    $startMarker = '[CF7_GOBANG_RUN_START id=' + $RunId + ']'
    $endMarker = '[CF7_GOBANG_RUN_END id=' + $RunId + ']'
    $startPattern = '(?m)^' + [regex]::Escape($startMarker) + '\r?$'
    $endPattern = '(?m)^' + [regex]::Escape($endMarker) + '\r?$'
    if ([regex]::Matches($RawText, $startPattern).Count -ne 1 -or
        [regex]::Matches($RawText, $endPattern).Count -ne 1) {
        return @()
    }
    $blockPattern = '(?ms)^' + [regex]::Escape($startMarker) +
        '\r?\n.*?^' + [regex]::Escape($endMarker) + '\r?$'
    $blocks = [regex]::Matches($RawText, $blockPattern)
    if ($blocks.Count -ne 1) { return @() }
    return ($blocks[0].Value -split "`r?`n")
}

function Get-TrainerSummaryValidationErrors {
    param([Parameter(Mandatory = $true)]$Summary)

    $errors = New-Object System.Collections.Generic.List[string]
    if ([int]$Summary.parse_counts.totals -ne 1) {
        $errors.Add("Trainer total summary must occur exactly once; found $($Summary.parse_counts.totals).")
    }
    if ([int]$Summary.parse_counts.local_accuracy -ne 1) {
        $errors.Add("Local AI summary must occur exactly once; found $($Summary.parse_counts.local_accuracy).")
    }
    if ([int]$Summary.parse_counts.rapfi_accuracy -gt 1) {
        $errors.Add("Rapfi summary occurs $($Summary.parse_counts.rapfi_accuracy) times.")
    }
    if ($null -eq $Summary.total -or $null -eq $Summary.run -or
        $null -eq $Summary.skipped) {
        $errors.Add('Total/Run/Skipped fields are incomplete.')
        return $errors.ToArray()
    }
    if ([int]$Summary.total -le 0 -or [int]$Summary.run -le 0) {
        $errors.Add('Trainer selected or executed zero problems.')
    }
    if ([int]$Summary.total -ne ([int]$Summary.run + [int]$Summary.skipped)) {
        $errors.Add('Total must equal Run + Skipped.')
    }
    if ($null -eq $Summary.local_pass -or $null -eq $Summary.local_run -or
        $null -eq $Summary.local_pct) {
        $errors.Add('Local AI accuracy fields are incomplete.')
    } else {
        if ([int]$Summary.local_run -ne [int]$Summary.run) {
            $errors.Add('Local AI denominator does not match Run.')
        }
        if ([int]$Summary.local_pass -lt 0 -or
            [int]$Summary.local_pass -gt [int]$Summary.local_run) {
            $errors.Add('Local AI pass count is outside its denominator.')
        }
        if ([int]$Summary.local_pass -ne [int]$Summary.local_run) {
            $errors.Add('Local AI has one or more failed trainer problems.')
        }
        if ([int]$Summary.local_run -le 0) {
            $errors.Add('Local AI denominator must be positive.')
        } else {
            $expectedPct = [int][Math]::Floor(
                ([double]$Summary.local_pass / [double]$Summary.local_run) * 100 + 0.5)
            if ([int]$Summary.local_pct -ne $expectedPct) {
                $errors.Add("Local AI percentage is $($Summary.local_pct), expected $expectedPct.")
            }
        }
    }
    if ($Summary.categories.Count -eq 0) {
        $errors.Add('Per-category trainer summary is missing.')
    } else {
        $categoryTotal = 0
        $categoryPassTotal = 0
        foreach ($entry in $Summary.categories.GetEnumerator()) {
            $category = $entry.Value
            if ([int]$Summary.parse_counts.categories[$entry.Key] -ne 1) {
                $errors.Add("Category '$($entry.Key)' summary must occur exactly once.")
            }
            if ([int]$category.local_pass -lt 0 -or
                [int]$category.local_pass -gt [int]$category.local_total) {
                $errors.Add("Category '$($entry.Key)' pass count is outside its denominator.")
            }
            $categoryTotal += [int]$category.local_total
            $categoryPassTotal += [int]$category.local_pass
        }
        if ($categoryTotal -ne [int]$Summary.run) {
            $errors.Add("Category denominators total $categoryTotal, expected $($Summary.run).")
        }
        if ($categoryPassTotal -ne [int]$Summary.local_pass) {
            $errors.Add("Category pass counts total $categoryPassTotal, expected $($Summary.local_pass).")
        }
    }
    return $errors.ToArray()
}

$BootstrapExe = Join-Path $ProjectRoot 'CRAZYFLASHER7MercenaryEmpire.exe'
# 2026-05-28 net10 迁移后用户面 exe 是 native bootstrap，启动 Core 后立即退出。
# headless 自动化直接走 Core.exe，才能把 readiness / shutdown 绑定到真实长跑 PID。
$LauncherExe = Join-Path $ProjectRoot 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe'
$PortsFile = Join-Path $ProjectRoot 'launcher_ports.json'

# Runtime 探测 — 共享 tools/dotnet-runtime-detect.ps1（与 bootstrap.cpp ScanOneDotnetRoot 等价：
# 系统位置优先 + 必须含 Microsoft.WindowsDesktop.App.deps.json，避免半安装 user-scope 误命中）
. (Join-Path $ProjectRoot 'tools\dotnet-runtime-detect.ps1')
. (Join-Path $ProjectRoot 'tools\lib\LegacyHttpAuth.ps1')

function Test-BusRunning {
    if (-not (Test-Path -LiteralPath $PortsFile)) { return $false }
    try {
        $ports = Get-Cf7LauncherPortsRecord -ProjectRoot $ProjectRoot
        $response = Invoke-WebRequest `
            -Uri "http://localhost:$($ports.HttpPort)/testConnection" `
            -Method POST -Body '' -TimeoutSec 2 -UseBasicParsing `
            -ErrorAction Stop
        if ($response.StatusCode -eq 200) { return $true }
    } catch {}
    return $false
}

function Get-SelfStartedBusHttpPort {
    param([Parameter(Mandatory = $true)][int]$ExpectedPid)

    if (-not (Test-Path -LiteralPath $PortsFile)) { return $null }
    try {
        $ports = Get-Cf7LauncherPortsRecord -ProjectRoot $ProjectRoot
        if ($ports.Pid -ne $ExpectedPid) { return $null }
        $httpPort = [int]$ports.HttpPort
        $response = Invoke-WebRequest `
            -Uri "http://localhost:$httpPort/testConnection" `
            -Method POST -Body '' -TimeoutSec 2 -UseBasicParsing `
            -ErrorAction Stop
        if ($response.StatusCode -eq 200) { return $httpPort }
    } catch {}
    return $null
}

function Stop-SelfStartedBus {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)]
        [int]$ExpectedPid,
        [AllowNull()]
        [object]$HttpPort
    )

    $forced = $false
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            if ($null -ne $HttpPort) {
                try {
                    $context = Get-Cf7LegacyHttpContext `
                        -ProjectRoot $ProjectRoot
                    if ($context.Pid -ne $ExpectedPid -or
                        $context.HttpPort -ne [int]$HttpPort) {
                        throw 'legacy_http_shutdown_identity_mismatch'
                    }
                    Invoke-WebRequest `
                        -Uri "http://localhost:$([int]$HttpPort)/shutdown" `
                        -Headers $context.Headers -Method POST -Body '' `
                        -TimeoutSec 5 -UseBasicParsing `
                        -ErrorAction Stop | Out-Null
                } catch {
                    Write-Warning (
                        "Self-started bus shutdown request failed; " +
                        "waiting for exact PID $ExpectedPid before fallback.")
                }
            }
            if (-not $Process.WaitForExit(10000)) {
                $forced = $true
                $Process.Kill()
                if (-not $Process.WaitForExit(5000)) {
                    throw "Self-started bus PID $ExpectedPid did not exit after Kill()."
                }
            }
        }

        # A graceful Core shutdown normally removes this file. Hard-kill fallback
        # may not, so clear it only while it still proves ownership by exact PID
        # (and by the observed HTTP port when one was established).
        if (Test-Path -LiteralPath $PortsFile) {
            try {
                $ports = Get-Content -LiteralPath $PortsFile -Raw -Encoding UTF8 |
                    ConvertFrom-Json
                $owned = [int]$ports.pid -eq $ExpectedPid
                if ($owned -and $null -ne $HttpPort) {
                    $owned = [int]$ports.httpPort -eq [int]$HttpPort
                }
                if ($owned) {
                    Remove-Item -LiteralPath $PortsFile -Force
                }
            } catch {
                Write-Warning (
                    'Could not prove launcher_ports.json belongs to the ' +
                    'self-started bus; leaving it untouched.')
            }
        }
        if ($forced) {
            Write-Host "[bus] Forced exact PID $ExpectedPid after graceful timeout"
        } else {
            Write-Host "[bus] Graceful stop confirmed for exact PID $ExpectedPid"
        }
    } finally {
        $Process.Dispose()
    }
}

$busStartedByUs = $false
$busProc = $null
$busReady = $false
$selfStartedBusPid = $null
$selfStartedBusHttpPort = $null

$compileExit = $null
$compileOutput = ''
$summary = $null
$summaryValidationErrors = @()
$elapsedSec = $null
$runId = [System.Guid]::NewGuid().ToString('N')
$Problems = Normalize-ProblemNames -Names $Problems
$beforeTime = if (Test-Path $FlashLog) { (Get-Item $FlashLog).LastWriteTimeUtc } else { [datetime]::MinValue }
$beforeLength = if (Test-Path $FlashLog) { (Get-Item $FlashLog).Length } else { 0 }
$startTime = Get-Date

$installedTestLoaderHash = $null
$scratchTransaction = $null
$normalizedProjectRoot = [System.IO.Path]::GetFullPath(
    $ProjectRoot).TrimEnd('\').ToUpperInvariant()
$compileHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $compileRepoHash = ([System.BitConverter]::ToString(
        $compileHasher.ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($normalizedProjectRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $compileHasher.Dispose()
}
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $compileRepoHash)
$compileMutexAcquired = $false
$compileLease = $null
$behaviorStarted = $false
$behaviorClosed = $false
$runCompletedCleanly = $false
try {
    try {
        $compileMutexAcquired = $compileMutex.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        $compileMutexAcquired = $true
        Write-GobangUncertain `
            -Reason 'gobang cycle observed abandoned compile mutex'
        throw 'A previous compile abandoned the repository mutex. Confirm Flash/JSFL stopped and clear late markers before retrying.'
    }
    if (-not $compileMutexAcquired) {
        throw 'Another Flash compile is using this repository; refusing to replace TestLoader.as.'
    }
    if (Test-Path -LiteralPath $UncertainMarker) {
        throw 'Compile state is uncertain. Confirm Flash/JSFL stopped, inspect late evidence, then remove scripts/compile_state_uncertain.marker.'
    }
    $compileLease = 'v1:{0}:{1}:{2}' -f $compileRepoHash, $PID,
        [System.Guid]::NewGuid().ToString('N')

    # === Bus 管理（默认自动启动 --bus-only，除非 -NoBus 或已有游戏在跑）===
    if (-not $NoBus) {
        if (Test-BusRunning) {
            $busReady = $true
            Write-Host '[bus] Already running'
        } else {
            if (-not (Test-Path -LiteralPath $BootstrapExe -PathType Leaf)) {
                throw "Bootstrap integrity probe not found: $BootstrapExe"
            }
            $verifyProc = Start-Process -FilePath $BootstrapExe `
                -ArgumentList '--verify-only' -PassThru -Wait `
                -WindowStyle Hidden
            try {
                if ($verifyProc.ExitCode -ne 0) {
                    throw (
                        'Runtime bundle integrity verification failed with ' +
                        "exit code $($verifyProc.ExitCode).")
                }
            } finally {
                $verifyProc.Dispose()
            }
            if (-not (Test-Path -LiteralPath $LauncherExe -PathType Leaf)) {
                throw "Launcher not found: $LauncherExe"
            }
            Write-Host '[bus] Starting launcher --bus-only...'
            if (-not (Set-DotnetRootForCore)) {
                throw 'Unable to locate the required .NET Desktop runtime.'
            }
            # Core 在 runtime\ 子目录，必须显式传 project root。
            $busProc = Start-Process -FilePath $LauncherExe `
                -ArgumentList @('--bus-only', '--project-root', $ProjectRoot) `
                -PassThru -WindowStyle Hidden
            $busStartedByUs = $true
            $selfStartedBusPid = $busProc.Id
            $busDeadline = (Get-Date).AddSeconds(15)
            while ((Get-Date) -lt $busDeadline) {
                Start-Sleep -Seconds 1
                $busProc.Refresh()
                if ($busProc.HasExited) { break }
                $ownedPort = Get-SelfStartedBusHttpPort `
                    -ExpectedPid $selfStartedBusPid
                if ($null -ne $ownedPort) {
                    $selfStartedBusHttpPort = [int]$ownedPort
                    $busReady = $true
                    break
                }
            }
            if (-not $busReady) {
                throw "Bus PID $selfStartedBusPid failed exact readiness within 15 seconds."
            }
            Write-Host (
                "[bus] Ready pid=$selfStartedBusPid " +
                "http=$selfStartedBusHttpPort")
        }
    }

    # 写 options 文件（供日志追溯）
    [System.IO.File]::WriteAllText($OptionsFile, (New-OptionsContent -ModeName $Mode -ProblemNames $Problems), [System.Text.UTF8Encoding]::new($false))

    # 持久事务 marker 先落盘，再重写 TestLoader.as；硬杀后下一轮也会 fail-closed。
    $scratchTransaction = New-Cf7TestLoaderScratchTransaction `
        -MarkerPath $ScratchMarker -RunnerPath $TestLoaderAs `
        -RepoHash $compileRepoHash -CompileLease $compileLease `
        -OwnerKind 'gobang'
    Assert-Cf7TestLoaderScratchReadyToInstall -Transaction $scratchTransaction
    $problemFilter = ($Problems -join ',')
    $trainerCode = "import org.flashNight.hana.Gobang.*;" + "`r`n"
    $trainerCode += "trace(`"[CF7_GOBANG_RUN_START id=$runId]`");" + "`r`n"
    $trainerCode += "var trainer:GobangTrainer = new GobangTrainer();" + "`r`n"
    $trainerCode += "trainer.loadBuiltinProblems();" + "`r`n"
    if ($problemFilter.Length -gt 0) {
        $trainerCode += "trainer.filterProblemsByName(`"$problemFilter`");" + "`r`n"
    }
    $trainerCode += "trainer.run(function():Void { trace(`"[CF7_GOBANG_RUN_END id=$runId]`"); });"

    # UTF-8 BOM（AS2 编译器要求）
    $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
    $codeBytes = [System.Text.Encoding]::UTF8.GetBytes($trainerCode)
    $allBytes = New-Object byte[] ($bom.Length + $codeBytes.Length)
    [Array]::Copy($bom, 0, $allBytes, 0, $bom.Length)
    [Array]::Copy($codeBytes, 0, $allBytes, $bom.Length, $codeBytes.Length)
    [System.IO.File]::WriteAllBytes($TestLoaderAs, $allBytes)
    $installedTestLoaderHash = (Get-FileHash -LiteralPath $TestLoaderAs -Algorithm SHA256).Hash

    $compileEvidenceBefore = [ordered]@{}
    foreach ($path in @($CompileOutputPath, $CompilerErrorsPath)) {
        $compileEvidenceBefore[$path] = Get-EvidenceIdentity -Path $path
    }
    $compileStartedUtc = [System.DateTime]::UtcNow
    $previousCompileLease = $env:CF7_FLASH_COMPILE_LEASE
    try {
        $env:CF7_FLASH_COMPILE_LEASE = $compileLease
        $compileOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass `
            -File $CompileScript -Target test `
            -TimeoutSeconds $WaitTimeoutSec *>&1 | Out-String)
        $compileExit = $LASTEXITCODE
    } finally {
        if ($null -eq $previousCompileLease) {
            Remove-Item Env:CF7_FLASH_COMPILE_LEASE -ErrorAction SilentlyContinue
        } else {
            $env:CF7_FLASH_COMPILE_LEASE = $previousCompileLease
        }
    }
    if ($compileExit -ne 0) {
        $freshCompilerDiagnostics = (Test-Path -LiteralPath $CompilerErrorsPath) -and
            (Get-EvidenceIdentity -Path $CompilerErrorsPath) -ne
                $compileEvidenceBefore[$CompilerErrorsPath] -and
            (Get-Item -LiteralPath $CompilerErrorsPath).LastWriteTimeUtc -ge
                $compileStartedUtc.AddSeconds(-1)
        $freshCompileOutput = (Test-Path -LiteralPath $CompileOutputPath) -and
            (Get-EvidenceIdentity -Path $CompileOutputPath) -ne
                $compileEvidenceBefore[$CompileOutputPath] -and
            (Get-Item -LiteralPath $CompileOutputPath).LastWriteTimeUtc -ge
                $compileStartedUtc.AddSeconds(-1)
        $compilerWasClean = $freshCompilerDiagnostics -and
            (Get-Content -LiteralPath $CompilerErrorsPath -Raw -Encoding UTF8) -match
                '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$'
        if ($compilerWasClean -or
            (-not $freshCompilerDiagnostics -and $freshCompileOutput)) {
            # A post-testMovie gate may fail while the long trainer is still alive.
            $behaviorStarted = $true
        }
        Write-Host $compileOutput.TrimEnd()
        throw "Gobang trainer TestLoader compile failed with exit code $compileExit."
    }
    $behaviorStarted = $true
    foreach ($path in @($CompileOutputPath, $CompilerErrorsPath)) {
        if (-not (Test-Path -LiteralPath $path) -or
            (Get-EvidenceIdentity -Path $path) -eq $compileEvidenceBefore[$path] -or
            (Get-Item -LiteralPath $path).LastWriteTimeUtc -lt
                $compileStartedUtc.AddSeconds(-1)) {
            throw "Gobang compile evidence was not freshly replaced: $path"
        }
    }
    $compilerErrors = Get-Content -LiteralPath $CompilerErrorsPath -Raw -Encoding UTF8
    if ($compilerErrors -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
        throw 'Gobang compiler diagnostics are not 0 errors / 0 warnings.'
    }
    $compileEvidence = Get-Content -LiteralPath $CompileOutputPath -Raw -Encoding UTF8
    $retryCount = [regex]::Matches(
        $compileEvidence, 'ASO 32K branch detected').Count
    if ($retryCount -ne 0) {
        throw "Gobang compile required $retryCount 32K retry; refusing a duplicate behavior run."
    }

    $deadline = (Get-Date).AddSeconds($WaitTimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $FlashLog) {
            $item = Get-Item $FlashLog
            if ($item.LastWriteTimeUtc -gt $beforeTime -or $item.Length -gt $beforeLength) {
                $raw = Get-Content -Raw -Encoding UTF8 $FlashLog
                $lines = Get-ClosedRunLines -RawText $raw -RunId $runId
                if ($lines.Length -gt 0) {
                    $behaviorClosed = $true
                    Copy-Item $FlashLog $LocalFlashLog -Force
                    $summary = Parse-Summary -Lines $lines
                    $summaryValidationErrors = @(
                        Get-TrainerSummaryValidationErrors -Summary $summary)
                    $runCompletedCleanly =
                        $summaryValidationErrors.Count -eq 0
                    $elapsedSec = [int]((Get-Date) - $startTime).TotalSeconds
                    break
                }
            }
        }
        Start-Sleep -Seconds 1
    }
}
finally {
    $cleanupErrors = New-Object System.Collections.Generic.List[string]
    if ($behaviorStarted -and -not $behaviorClosed) {
        try {
            Write-GobangUncertain (
                "behavior did not reach one exact terminal block; runId=$runId; " +
                'the old test player may still append to the global Flash log')
        } catch {
            $cleanupErrors.Add("uncertain marker: $($_.Exception.Message)")
        }
    }
    if (-not $KeepOptionsFile) {
        Remove-Item -LiteralPath $OptionsFile -ErrorAction SilentlyContinue
    }
    # 持有 compile mutex 到 scratch 恢复与本轮自启 bus 停止完成。
    if ($scratchTransaction -and $installedTestLoaderHash) {
        try {
            Restore-Cf7TestLoaderScratchTransaction `
                -Transaction $scratchTransaction `
                -InstalledHash $installedTestLoaderHash
        } catch {
            $cleanupErrors.Add("scratch restore: $($_.Exception.Message)")
        }
    }
    if ($busStartedByUs -and ($StopBusAfter -or -not $runCompletedCleanly)) {
        Write-Host '[bus] Stopping (started by this script)...'
        try {
            Stop-SelfStartedBus -Process $busProc `
                -ExpectedPid $selfStartedBusPid `
                -HttpPort $selfStartedBusHttpPort
            $busStartedByUs = $false
            Write-Host '[bus] Stopped'
        } catch {
            $cleanupErrors.Add("bus stop: $($_.Exception.Message)")
        }
    }
    if ($busStartedByUs -and $null -ne $busProc) {
        # Keep the intentionally surviving bus, but do not retain this cycle's
        # local Process wrapper/OS handle until the caller happens to run GC.
        try { $busProc.Dispose() } catch {
            $cleanupErrors.Add("bus process handle dispose: $($_.Exception.Message)")
        }
    }
    if ($compileMutexAcquired) {
        try { $compileMutex.ReleaseMutex() } catch {
            $cleanupErrors.Add("compile mutex release: $($_.Exception.Message)")
        }
    }
    try { $compileMutex.Dispose() } catch {
        $cleanupErrors.Add("compile mutex dispose: $($_.Exception.Message)")
    }
    if ($scratchTransaction -and
        (Test-Path -LiteralPath $scratchTransaction.MarkerPath)) {
        Write-Warning ("TestLoader scratch transaction remains blocked; recovery backup: {0}" -f
            $scratchTransaction.BackupPath)
    }
    if ($cleanupErrors.Count -gt 0) {
        throw ('Gobang cleanup failed: ' + ($cleanupErrors -join ' | '))
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

[void]$summary.Remove('parse_counts')
$result = [ordered]@{
    mode = $Mode
    problems = $Problems
    compile_exit = $compileExit
    elapsed_sec = $elapsedSec
    run_id = $runId
    summary = $summary
    validation_errors = $summaryValidationErrors
}
$trainerFailed = $summary.fails.Count -gt 0 -or
    $summaryValidationErrors.Count -gt 0

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    if ($trainerFailed) { exit 1 }
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
if ($summaryValidationErrors.Count -gt 0) {
    Write-Host 'Validation errors:'
    foreach ($item in $summaryValidationErrors) {
        Write-Host ('  ' + $item)
    }
}
if ($trainerFailed) { exit 1 }
