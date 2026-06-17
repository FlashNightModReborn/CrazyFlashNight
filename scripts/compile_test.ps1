# compile_test.ps1 - Agent 自动编译触发脚本 (PowerShell 版)
#
# 用法: powershell -File scripts/compile_test.ps1 [-TimeoutSeconds <秒>]
#   -TimeoutSeconds 默认 30；低压平板 / 慢 CPU 编译耗时更长时调大，例如 -TimeoutSeconds 120

param(
    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 30,
    # asLoader publish 等「产出 SWF 而非 trace」场景：传 -VerifySwf scripts/asLoader.swf，
    # 成功路径会校验该 SWF 的 mtime/size 是否真刷新；marker 产出但 SWF 未重写 = 判失败(fail-closed)，
    # 对齐 testing-guide「0 错误 + scripts/asLoader.swf 已刷新」口径。默认空 = 不校验(普通 trace 测试不受影响)。
    [string]$VerifySwf = '',
    # 编译目标切换（免去手动切 Flash 活动文档）：
    #   test / testloader → scripts/TestLoader（带 trace 的逻辑回归，跑 TransitionsTest + BootSequencerTest）
    #   publish / asloader → scripts/asLoader（发布 asLoader.swf；自动启用 -VerifySwf scripts/asLoader.swf）
    #   <FLA/XFL 路径>     → 指定文档（相对仓库根或绝对路径）
    #   省略             → 用 Flash 当前活动文档（向后兼容旧行为）
    [string]$Target = ''
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectDir = Split-Path -Parent $ScriptDir
$Marker = Join-Path $ScriptDir 'publish_done.marker'
$ErrorMarker = Join-Path $ScriptDir 'publish_error.marker'
$CompileOutput = Join-Path $ScriptDir 'compile_output.txt'
$CompilerErrors = Join-Path $ScriptDir 'compiler_errors.txt'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$LocalFlashLog = Join-Path $ScriptDir 'flashlog.txt'
$LoaderFileName = 'cf7_compile_loader.jsfl'

function Convert-ToJsflUri {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = (Resolve-Path $Path).Path.Replace('\', '/')
    return 'file:///' + $resolved.Replace(':', '|')
}

function Get-CommandsDirForProject {
    param([Parameter(Mandatory = $true)][string]$ProjectDir)

    $cfgBase = Join-Path $env:LOCALAPPDATA 'Adobe\Flash CS6'
    if (-not (Test-Path $cfgBase)) {
        return $null
    }

    $expectedUri = Convert-ToJsflUri $ProjectDir
    $candidates = @()
    Get-ChildItem $cfgBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $commandsDir = Join-Path $_.FullName 'Configuration\Commands'
        if (-not (Test-Path $commandsDir)) {
            return
        }

        $projectCfg = Join-Path $commandsDir 'flash_project_path.cfg'
        $projectUri = if (Test-Path $projectCfg) {
            (Get-Content -Raw -Encoding UTF8 $projectCfg).Trim()
        } else {
            $null
        }

        $candidates += [pscustomobject]@{
            Lang        = $_.Name
            CommandsDir = $commandsDir
            ProjectUri  = $projectUri
        }
    }

    $matched = $candidates | Where-Object { $_.ProjectUri -eq $expectedUri } | Select-Object -First 1
    if ($matched) {
        return $matched.CommandsDir
    }

    $fallback = $null
    $fallbackRank = [int]::MaxValue
    foreach ($candidate in $candidates) {
        $candidateRank = Get-LangRank $candidate.Lang
        if ((-not $fallback) -or $candidateRank -lt $fallbackRank -or ($candidateRank -eq $fallbackRank -and $candidate.Lang -lt $fallback.Lang)) {
            $fallback = $candidate
            $fallbackRank = $candidateRank
        }
    }

    if ($fallback) {
        return $fallback.CommandsDir
    }

    return $null
}

function Get-LangRank {
    param([string]$Lang)

    switch ($Lang) {
        'zh_CN' { return 0 }
        'en_US' { return 1 }
        default { return 2 }
    }
}

function Get-TaskMode {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][string]$ExpectedLoaderPath
    )

    $action = $Task.Actions | Select-Object -First 1
    $executeName = [System.IO.Path]::GetFileName(($action.Execute | Out-String).Trim())
    $arguments = ($action.Arguments | Out-String).Trim()

    $isDirect = $executeName -ieq 'cmd.exe' -and $arguments -eq ('/c start "" "{0}"' -f $ExpectedLoaderPath)
    $isLegacy = $executeName -ieq 'powershell.exe' -and $arguments -match 'trigger_compile\.ps1'

    return [pscustomobject]@{
        Execute   = $action.Execute
        Arguments = $arguments
        IsDirect  = $isDirect
        IsLegacy  = $isLegacy
    }
}

$commandsDir = Get-CommandsDirForProject -ProjectDir $ProjectDir
if (-not $commandsDir) {
    Write-Host '[ERROR] 找不到当前项目对应的 Flash Commands 目录，请先运行 scripts/setup_compile_env.bat'
    exit 1
}

$projectCfgPath = Join-Path $commandsDir 'flash_project_path.cfg'
$expectedProjectUri = Convert-ToJsflUri $ProjectDir
$actualProjectUri = if (Test-Path $projectCfgPath) {
    (Get-Content -Raw -Encoding UTF8 $projectCfgPath).Trim()
} else {
    $null
}
if ($actualProjectUri -ne $expectedProjectUri) {
    Write-Host '[ERROR] flash_project_path.cfg 与当前项目不匹配，请重新运行 scripts/setup_compile_env.bat'
    Write-Host ('        期望: {0}' -f $expectedProjectUri)
    Write-Host ('        当前: {0}' -f $actualProjectUri)
    exit 1
}

$loaderPath = Join-Path $commandsDir $LoaderFileName
if (-not (Test-Path $loaderPath)) {
    Write-Host ('[ERROR] 缺少 Loader: {0}' -f $loaderPath)
    Write-Host '        请重新运行 scripts/setup_compile_env.bat'
    exit 1
}

try {
    $task = Get-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction Stop
} catch {
    Write-Host '[ERROR] CompileTriggerTask 未找到，请先运行 scripts/setup_compile_env.bat'
    exit 1
}

$taskMode = Get-TaskMode -Task $task -ExpectedLoaderPath $loaderPath
if (-not ($taskMode.IsDirect -or $taskMode.IsLegacy)) {
    Write-Host '[ERROR] CompileTriggerTask 不是受支持的触发方式，请重新运行 scripts/setup_compile_env.bat'
    Write-Host ('        Execute  : {0}' -f $taskMode.Execute)
    Write-Host ('        Arguments: {0}' -f $taskMode.Arguments)
    exit 1
}

if ($taskMode.IsLegacy) {
    Write-Host '[WARN] CompileTriggerTask 仍在使用旧版 trigger_compile.ps1 包装器。当前仓库已兼容，但建议重新运行 setup 以切到直开 JSFL。'
}

# 编译目标切换：把 -Target 解析成具体 FLA/XFL，写 scripts/compile_target.cfg（file:/// URI）供 compile_action.jsfl 读取。
#   不传 -Target → 删除该文件 → JSFL 回退「当前活动文档」（向后兼容）。传 -Target → JSFL 读到后删除，避免旧目标残留。
$TargetCfg = Join-Path $ScriptDir 'compile_target.cfg'
Remove-Item -Path $TargetCfg -ErrorAction SilentlyContinue
$targetUri = ''
if ($Target) {
    switch -Regex ($Target.ToLower()) {
        '^(test|testloader)$'  { $targetPath = Join-Path $ProjectDir 'scripts\TestLoader\TestLoader.xfl' }
        '^(publish|asloader)$' { $targetPath = Join-Path $ProjectDir 'scripts\asLoader\asLoader.xfl' }
        default {
            $targetPath = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path $ProjectDir $Target }
        }
    }
    if (-not (Test-Path $targetPath)) {
        Write-Host ('[ERROR] 编译目标不存在: {0}' -f $targetPath)
        Write-Host '        -Target 取值: test | publish | <FLA/XFL 路径>（相对仓库根或绝对）'
        exit 1
    }
    $targetUri = Convert-ToJsflUri $targetPath
    Write-Host ('[INFO] 编译目标: {0} -> {1}' -f $Target, $targetPath)
    # publish 目标自动启用 SWF 刷新门（testing-guide「asLoader publish 一律 -VerifySwf」铁律），除非用户已显式指定。
    if (-not $VerifySwf -and ($Target.ToLower() -match '^(publish|asloader)$')) {
        $VerifySwf = 'scripts/asLoader.swf'
        Write-Host '[INFO] publish 目标 -> 自动启用 -VerifySwf scripts/asLoader.swf'
    }
} else {
    Write-Host '[INFO] 编译目标: Flash 当前活动文档（未指定 -Target）'
}

# [asLoader 重构 P0] 预编译 BOM 门：被 #include 的 .as 丢 BOM 会被 CS6 静默跳过
#   （DoAction 0 字节，compiler_errors 仍报 0 错误），现有冒烟链抓不到。先 fail-fast，
#   省掉一次 77-113s 的无效编译。node 缺失则降级为告警，不阻断旧环境。
$BomChecker = Join-Path $ProjectDir 'tools\check-bom.js'
if (Test-Path $BomChecker) {
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        # asLoader #include 闭包 + import 类包/TestLoader 入口：
        #   import 目标不在 #include 图内 → 显式覆盖，避免 CS6 静默跳过类体或首行语法错。
        $BootClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\boot'
        $ServerClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\neur\Server'
        $StateMachineDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\neur\StateMachine'
        $CommDir = Join-Path $ProjectDir 'scripts\通信'
        $TestLoaderEntry = Join-Path $ProjectDir 'scripts\TestLoader.as'
        $BomArgs = @()
        if (Test-Path $BootClassDir) { $BomArgs += @('--dir', $BootClassDir) }
        if (Test-Path $ServerClassDir) { $BomArgs += @('--dir', $ServerClassDir) }
        if (Test-Path $StateMachineDir) { $BomArgs += @('--dir', $StateMachineDir) }
        if (Test-Path $CommDir) { $BomArgs += @('--dir', $CommDir) }
        if (Test-Path $TestLoaderEntry) { $BomArgs += @('--file', $TestLoaderEntry) }
        Write-Host '[INFO] 预编译 BOM 门: node tools/check-bom.js --dir boot --dir Server --dir StateMachine --dir 通信 --file scripts/TestLoader.as'
        & node $BomChecker @BomArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host '[ERROR] BOM 门失败：存在缺 BOM 的 #include .as，编译器会静默跳过其内容。修复后重试。'
            exit 1
        }
    } else {
        Write-Host '[WARN] 未找到 node，跳过预编译 BOM 门（建议安装 node 以启用静默-跳过防护）'
    }
}

Remove-Item -Path $Marker -ErrorAction SilentlyContinue
Remove-Item -Path $ErrorMarker -ErrorAction SilentlyContinue

$flashLogBeforeItem = if (Test-Path $FlashLog) { Get-Item $FlashLog } else { $null }
$flashLogBefore = if ($flashLogBeforeItem) { $flashLogBeforeItem.LastWriteTimeUtc } else { $null }
$flashLogBeforeSize = if ($flashLogBeforeItem) { $flashLogBeforeItem.Length } else { 0 }
$compileOutputBefore = if (Test-Path $CompileOutput) { (Get-Item $CompileOutput).LastWriteTimeUtc } else { $null }

# SWF 刷新门：触发前记录目标 SWF 的 mtime/size 基线（仅当 -VerifySwf 指定）
$VerifySwfPath = $null
$verifySwfBefore = $null
if ($VerifySwf) {
    $VerifySwfPath = if ([System.IO.Path]::IsPathRooted($VerifySwf)) { $VerifySwf } else { Join-Path $ProjectDir $VerifySwf }
    if (Test-Path $VerifySwfPath) {
        $swfItemBefore = Get-Item $VerifySwfPath
        $verifySwfBefore = [pscustomobject]@{ Mtime = $swfItemBefore.LastWriteTimeUtc; Size = $swfItemBefore.Length }
        Write-Host ('[INFO] SWF 刷新门已启用: {0} (基线 {1} bytes, {2})' -f $VerifySwfPath, $swfItemBefore.Length, $swfItemBefore.LastWriteTime)
    } else {
        Write-Host ('[INFO] SWF 刷新门已启用: {0} (基线不存在，成功路径要求其被新建)' -f $VerifySwfPath)
    }
}

Write-Host ('[INFO] 触发编译... (超时 {0}s)' -f $TimeoutSeconds)
if ($targetUri) {
    [System.IO.File]::WriteAllText($TargetCfg, $targetUri, (New-Object System.Text.UTF8Encoding($false)))
}
Start-ScheduledTask -TaskName 'CompileTriggerTask'

for ($i = 1; $i -le $TimeoutSeconds; $i++) {
    if (Test-Path $Marker) {
        Write-Host ('[OK] 编译完成 ({0}s)' -f $i)
        Remove-Item -Path $Marker -ErrorAction SilentlyContinue

        $flashTraceContent = $null
        if (Test-Path $FlashLog) {
            $flashLogItem = Get-Item $FlashLog
            if ($flashLogBefore -and $flashLogItem.LastWriteTimeUtc -le $flashLogBefore) {
                Write-Host '[WARN] flashlog.txt 未刷新，本次 trace 可能还是旧日志'
            } else {
                $flashLogBytes = [System.IO.File]::ReadAllBytes($FlashLog)
                $flashTraceOffset = 0
                if ($flashLogBefore -and $flashLogBytes.Length -gt $flashLogBeforeSize) {
                    $flashTraceOffset = $flashLogBeforeSize
                }
                $freshBytes = New-Object byte[] ($flashLogBytes.Length - $flashTraceOffset)
                if ($freshBytes.Length -gt 0) {
                    [System.Array]::Copy($flashLogBytes, $flashTraceOffset, $freshBytes, 0, $freshBytes.Length)
                }
                $flashTraceContent = [System.Text.UTF8Encoding]::new($false).GetString($freshBytes)
                Write-Host '=== FLASH TRACE OUTPUT ==='
                Write-Host $flashTraceContent
                Write-Host '=== END ==='
                [System.IO.File]::WriteAllText($LocalFlashLog, $flashTraceContent, [System.Text.UTF8Encoding]::new($false))
            }
        } else {
            Write-Host '[INFO] 无 trace 输出 (publish 模式不执行 trace)'
        }

        if (Test-Path $CompileOutput) {
            $compileOutputItem = Get-Item $CompileOutput
            if ($compileOutputBefore -and $compileOutputItem.LastWriteTimeUtc -le $compileOutputBefore) {
                Write-Host '[WARN] compile_output.txt 未刷新；若本次需要看 Output Panel，请直接检查 Flash IDE 面板'
            } else {
                Write-Host ('[INFO] compile_output.txt 已刷新: {0}' -f $compileOutputItem.LastWriteTime)
            }
        }

        # 检查 Compiler Errors 面板输出
        $hasCompileError = $false
        if (Test-Path $CompilerErrors) {
            $errContent = Get-Content -Path $CompilerErrors -Raw -Encoding UTF8
            if ($errContent -and $errContent -notmatch '^\s*0 个错误' -and $errContent -notmatch '^\s*0 Errors') {
                Write-Host '=== COMPILER ERRORS ==='
                Write-Host $errContent
                Write-Host '=== END COMPILER ERRORS ==='
                $hasCompileError = $true
            }
        }

        $hasTraceFailure = $false
        if ($flashTraceContent -and ($flashTraceContent -match '\[TEST_FAIL\]' -or $flashTraceContent -match '(^|[\r\n])\s*\[FAIL\]' -or $flashTraceContent -match 'Tests Failed:\s*[1-9]')) {
            Write-Host '[ERROR] Flash trace reported test failure ([TEST_FAIL] / [FAIL] / Tests Failed > 0)'
            $hasTraceFailure = $true
        }

        # SWF 刷新门（仅当 -VerifySwf 指定）：publish 模式不产 trace，靠 mtime/size 确认目标 SWF 真被重写，
        # 否则「marker 产出 + 0 错误」会与 testing-guide「SWF 已刷新」口径相反地假成功。
        $hasSwfStale = $false
        if ($VerifySwf) {
            if (Test-Path $VerifySwfPath) {
                $swfNow = Get-Item $VerifySwfPath
                if ((-not $verifySwfBefore) -or ($swfNow.LastWriteTimeUtc -gt $verifySwfBefore.Mtime) -or ($swfNow.Length -ne $verifySwfBefore.Size)) {
                    Write-Host ('[OK] 目标 SWF 已刷新: {0} ({1} bytes, {2})' -f $VerifySwfPath, $swfNow.Length, $swfNow.LastWriteTime)
                } else {
                    Write-Host ('[ERROR] 目标 SWF 未刷新: {0} (mtime/size 未变) — 编译 marker 产出但 SWF 未重写，按 testing-guide 口径判失败' -f $VerifySwfPath)
                    $hasSwfStale = $true
                }
            } else {
                Write-Host ('[ERROR] 目标 SWF 不存在: {0} — publish 未产出 SWF' -f $VerifySwfPath)
                $hasSwfStale = $true
            }
        }

        if ($hasCompileError -or $hasTraceFailure -or $hasSwfStale) {
            Remove-Item -Path $TargetCfg -ErrorAction SilentlyContinue
            exit 1
        }
        Remove-Item -Path $TargetCfg -ErrorAction SilentlyContinue
        exit 0
    }

    if (Test-Path $ErrorMarker) {
        Write-Host '[ERROR] 编译失败:'
        Get-Content -Path $ErrorMarker -Encoding UTF8
        Remove-Item -Path $ErrorMarker -ErrorAction SilentlyContinue
        Remove-Item -Path $TargetCfg -ErrorAction SilentlyContinue
        exit 1
    }

    Start-Sleep -Seconds 1
}

Write-Host ('[TIMEOUT] {0} 秒未完成，可能原因：' -f $TimeoutSeconds)
Write-Host '  - Flash CS6 未运行'
Write-Host '  - TestLoader 未在 Flash 中打开'
Write-Host '  - CompileTriggerTask 计划任务未创建'
Write-Host '  - 仍在弹 UAC 或旧任务卡住'
Write-Host '  - 慢 CPU / 低压平板编译未结束 → 用 -TimeoutSeconds 调大重试'
Remove-Item -Path $TargetCfg -ErrorAction SilentlyContinue
exit 1
