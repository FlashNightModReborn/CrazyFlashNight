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
    #   test / testloader → scripts/TestLoader（带 trace；实际 suite 由被忽略的 scripts/TestLoader.as scratch runner 决定）
    #   publish / asloader → scripts/asLoader（发布 asLoader.swf；自动启用 -VerifySwf scripts/asLoader.swf）
    #   <FLA/XFL 路径>     → 指定文档（相对仓库根或绝对路径）
    #   省略             → 用 Flash 当前活动文档（向后兼容旧行为）
    [string]$Target = '',
    # 对任意 -Target 强制 publish-only（doc.publish() 而非 testMovie）：编译产出 SWF + Compiler Errors，
    # 不启动测试播放器。publish/asloader 与 main 目标已隐含 publish；资源 FLA（如 things0）想避免弹播放器时显式加此开关。
    [switch]$PublishOnly
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectDir = Split-Path -Parent $ScriptDir
$Marker = Join-Path $ScriptDir 'publish_done.marker'
$ErrorMarker = Join-Path $ScriptDir 'publish_error.marker'
$UncertainMarker = Join-Path $ScriptDir 'compile_state_uncertain.marker'
$ScratchMarker = Join-Path $ScriptDir 'testloader_scratch_inflight.marker'
$CompileOutput = Join-Path $ScriptDir 'compile_output.txt'
$CompilerErrors = Join-Path $ScriptDir 'compiler_errors.txt'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'
$LocalFlashLog = Join-Path $ScriptDir 'flashlog.txt'
$ScratchTransactionScript = Join-Path $ScriptDir 'test-runners\testloader-scratch-transaction.ps1'
. $ScratchTransactionScript
$LoaderFileName = 'cf7_compile_loader.jsfl'
$compileTriggered = $false
$compileTerminalObserved = $false
$nonTerminalUncertainWritten = $false
$compileUncertainToken = [System.Guid]::NewGuid().ToString('N')
$inFlightUncertainBody = $null

function Write-CompileUncertain {
    param([Parameter(Mandatory = $true)][string]$Reason)

    $body = '{0:o} | token={1} | {2}' -f
        [System.DateTime]::UtcNow, $compileUncertainToken, $Reason
    [System.IO.File]::WriteAllText(
        $UncertainMarker, $body, [System.Text.UTF8Encoding]::new($false))
    return $body
}

function Remove-OwnedCompileUncertain {
    param([Parameter(Mandatory = $true)][string]$ExpectedBody)

    if (-not (Test-Path -LiteralPath $UncertainMarker)) {
        return
    }
    $actualBody = [System.IO.File]::ReadAllText(
        $UncertainMarker, [System.Text.Encoding]::UTF8)
    if ($actualBody -ceq $ExpectedBody) {
        Remove-Item -LiteralPath $UncertainMarker
    } else {
        Write-Host '[WARN] uncertain marker 已由其他故障事件替换；保留该闸门，拒绝删除非本轮 marker。'
    }
}

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
    if ($_.CategoryInfo.Category -eq 'PermissionDenied' -or
        $_.FullyQualifiedErrorId -match '0x80041003') {
        Write-Host '[ERROR] 当前进程无权读取 CompileTriggerTask（Task Scheduler 返回 Access Denied）'
        Write-Host '        这通常表示命令运行在受限 Windows 沙箱中，不代表计划任务缺失。'
        Write-Host '        请批准该编译命令在沙箱外运行；仅在沙箱外仍报告任务缺失时才重跑 setup_compile_env.bat。'
    } else {
        Write-Host '[ERROR] CompileTriggerTask 未找到，请先运行 scripts/setup_compile_env.bat'
    }
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

# 所有编译目标共用 compile_target/mode cfg、marker 与诊断文件；跨进程并发会串目标或伪造新鲜证据。
$normalizedCompileRoot = [System.IO.Path]::GetFullPath($ProjectDir).TrimEnd('\').ToUpperInvariant()
$compileHasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $compileRepoHash = ([System.BitConverter]::ToString(
        $compileHasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedCompileRoot)))).
        Replace('-', '').Substring(0, 24)
} finally {
    $compileHasher.Dispose()
}
$compileMutex = [System.Threading.Mutex]::new(
    $false, 'Local\CF7_FlashCompile_' + $compileRepoHash)
$compileMutexAcquired = $false
$compileLease = $env:CF7_FLASH_COMPILE_LEASE
$leaseOwnerPid = 0
try {
    if ([string]::IsNullOrWhiteSpace($compileLease)) {
        try {
            $compileMutexAcquired = $compileMutex.WaitOne(0)
        } catch [System.Threading.AbandonedMutexException] {
            $compileMutexAcquired = $true
            [void](Write-CompileUncertain 'repository compile mutex was abandoned')
            Write-Host '[ERROR] 上一个编译进程异常退出；Flash/JSFL 可能仍会迟到写入，确认运行态与 marker 后再重试。'
            exit 1
        }
        if (-not $compileMutexAcquired) {
            Write-Host '[ERROR] 同一仓库已有 Flash 编译在运行；拒绝覆盖共享 cfg/marker/诊断文件。'
            exit 1
        }
    } else {
        # Focused runners install a temporary TestLoader entry and therefore own this
        # mutex across install -> compile -> evidence consumption -> restore. The
        # nonce is process-local (inherited only by this child); the probe makes an
        # accidentally supplied lease fail closed unless another process really
        # holds the repository compile mutex.
        $expectedLeasePattern = '^v1:' + [regex]::Escape($compileRepoHash) +
            ':\d+:[0-9a-f]{32}$'
        if ($compileLease -notmatch $expectedLeasePattern) {
            Write-Host '[ERROR] CF7_FLASH_COMPILE_LEASE 格式或仓库身份不匹配。'
            exit 1
        }
        $leaseOwnerPid = [int]($compileLease.Split(':')[2])
        $leaseProbeAcquired = $false
        try {
            try {
                $leaseProbeAcquired = $compileMutex.WaitOne(0)
            } catch [System.Threading.AbandonedMutexException] {
                $leaseProbeAcquired = $true
                [void](Write-CompileUncertain 'focused parent compile mutex was abandoned')
            }
            if ($leaseProbeAcquired) {
                Write-Host '[ERROR] 编译 lease 没有对应的父进程 mutex；拒绝无锁执行。'
                exit 1
            }
        } finally {
            if ($leaseProbeAcquired) {
                $compileMutex.ReleaseMutex()
            }
        }
        Write-Host '[INFO] 复用 focused runner 持有的仓库编译 mutex。'
    }
    try {
        Assert-Cf7TestLoaderScratchAdmission -MarkerPath $ScratchMarker `
            -RunnerPath (Join-Path $ScriptDir 'TestLoader.as') `
            -RepoHash $compileRepoHash -CompileLease $compileLease `
            -LeaseOwnerPid $leaseOwnerPid
    } catch {
        Write-Host ('[ERROR] {0}' -f $_.Exception.Message)
        exit 1
    }
    if (Test-Path -LiteralPath $UncertainMarker) {
        Write-Host '[ERROR] 检测到 scripts/compile_state_uncertain.marker；上一轮可能仍有迟到的 Flash/JSFL 写入。'
        Write-Host '        先确认 Flash/计划任务已静止并核对迟到 marker/SWF/diagnostics，再手工删除该文件。'
        exit 1
    }

# 编译目标切换：把 -Target 解析成具体 FLA/XFL，写 scripts/compile_target.cfg（file:/// URI）供 compile_action.jsfl 读取。
#   不传 -Target → 删除该文件 → JSFL 回退「当前活动文档」（向后兼容）。传 -Target → JSFL 读到后删除，避免旧目标残留。
$TargetCfg = Join-Path $ScriptDir 'compile_target.cfg'
$ModeCfg = Join-Path $ScriptDir 'compile_mode.cfg'
Remove-Item -Path $TargetCfg -ErrorAction SilentlyContinue
Remove-Item -Path $ModeCfg -ErrorAction SilentlyContinue
$targetUri = ''
$isTestLoaderTarget = $false
# 编译动作模式：默认 test（testMovie，跑 trace / 刷新 SWF）。main（整套游戏主文件）走 publish——
#   doc.publish() 只编译产出 SWF + 填充 fl.compilerErrors，不 testMovie 拉起全量游戏窗口（连不上 launcher
#   socket 卡住 / 撞反盗版层 / 留僵尸窗口）。compile_action.jsfl 据 compile_mode.cfg 选 publish vs testMovie。
$compileMode = 'test'
if ($Target) {
    switch -Regex ($Target.ToLower()) {
        '^(test|testloader)$'  { $targetPath = Join-Path $ProjectDir 'scripts\TestLoader\TestLoader.xfl' }
        '^(publish|asloader)$' {
            $targetPath = Join-Path $ProjectDir 'scripts\asLoader\asLoader.xfl'
            $compileMode = 'publish'   # asLoader 发布别名必须走 doc.publish()，不得误启 testMovie
        }
        '^(main|mainfile|empire)$' {
            $targetPath = Join-Path $ProjectDir 'CRAZYFLASHER7MercenaryEmpire\CRAZYFLASHER7MercenaryEmpire.xfl'
            $compileMode = 'publish'   # 主文件：publish-only，避免 testMovie 启动整套游戏
        }
        default {
            $targetPath = if ([System.IO.Path]::IsPathRooted($Target)) { $Target } else { Join-Path $ProjectDir $Target }
        }
    }
    if ($PublishOnly) { $compileMode = 'publish' }   # 显式 publish-only（任意 target）
    if (-not (Test-Path $targetPath)) {
        Write-Host ('[ERROR] 编译目标不存在: {0}' -f $targetPath)
        Write-Host '        -Target 取值: test | publish | main | <FLA/XFL 路径>（相对仓库根或绝对）'
        exit 1
    }
    $testLoaderXflPath = [System.IO.Path]::GetFullPath(
        (Join-Path $ProjectDir 'scripts\TestLoader\TestLoader.xfl'))
    $isTestLoaderTarget = [System.IO.Path]::GetFullPath($targetPath) -ieq $testLoaderXflPath
    if ($isTestLoaderTarget -and -not $VerifySwf) {
        $VerifySwf = 'scripts/TestLoader.swf'
        Write-Host '[INFO] TestLoader 目标 -> 自动启用 SWF 刷新与 function codeSize<60000 门'
    }
    $targetUri = Convert-ToJsflUri $targetPath
    Write-Host ('[INFO] 编译目标: {0} -> {1} (模式: {2})' -f $Target, $targetPath, $compileMode)
    # publish 目标自动启用 SWF 刷新门（testing-guide「asLoader publish 一律 -VerifySwf」铁律），除非用户已显式指定。
    if (-not $VerifySwf -and ($Target.ToLower() -match '^(publish|asloader)$')) {
        $VerifySwf = 'scripts/asLoader.swf'
        Write-Host '[INFO] publish 目标 -> 自动启用 -VerifySwf scripts/asLoader.swf'
    }
    # main 目标 doc.publish() 按发布设置输出到仓库根 CRAZYFLASHER7MercenaryEmpire.swf（已实测确认）。
    # 自动启用 SWF 刷新门（fail-closed，对齐 asLoader publish 铁律）：marker 产出但 SWF 未重写 = 判失败。
    if (-not $VerifySwf -and ($Target.ToLower() -match '^(main|mainfile|empire)$')) {
        $VerifySwf = 'CRAZYFLASHER7MercenaryEmpire.swf'
        Write-Host '[INFO] main 目标 -> 自动启用 -VerifySwf CRAZYFLASHER7MercenaryEmpire.swf'
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
        # 主文件 classpath = scripts\类定义\；web-panel 迁移类（task/merc/skill/stageSelect）近期高频编辑，
        #   BOM 丢失会被 CS6 静默跳过整类 → 入门 BOM 门覆盖这些 arki 子树，配合 main 目标 publish 验证。
        $TaskClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\arki\task'
        $MercClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\arki\merc'
        $SkillClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\arki\skill'
        $StageSelectClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\arki\stageSelect'
        $SceneClassDir = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\arki\scene'
        $ObstacleRendererFile = Join-Path $ProjectDir 'scripts\类定义\org\flashNight\arki\unit\UnitComponent\Initializer\ElementComponent\ObstacleRenderer.as'
        $BomArgs = @()
        if (Test-Path $BootClassDir) { $BomArgs += @('--dir', $BootClassDir) }
        if (Test-Path $ServerClassDir) { $BomArgs += @('--dir', $ServerClassDir) }
        if (Test-Path $StateMachineDir) { $BomArgs += @('--dir', $StateMachineDir) }
        if (Test-Path $CommDir) { $BomArgs += @('--dir', $CommDir) }
        if (Test-Path $TaskClassDir) { $BomArgs += @('--dir', $TaskClassDir) }
        if (Test-Path $MercClassDir) { $BomArgs += @('--dir', $MercClassDir) }
        if (Test-Path $SkillClassDir) { $BomArgs += @('--dir', $SkillClassDir) }
        if (Test-Path $StageSelectClassDir) { $BomArgs += @('--dir', $StageSelectClassDir) }
        if (Test-Path $SceneClassDir) { $BomArgs += @('--dir', $SceneClassDir) }
        if (Test-Path $ObstacleRendererFile) { $BomArgs += @('--file', $ObstacleRendererFile) }
        if (Test-Path $TestLoaderEntry) { $BomArgs += @('--file', $TestLoaderEntry) }
        Write-Host '[INFO] 预编译 BOM 门: node tools/check-bom.js --dir boot --dir Server --dir StateMachine --dir 通信 --dir arki\task --dir arki\merc --dir arki\skill --dir arki\stageSelect --dir arki\scene --file ObstacleRenderer.as --file scripts/TestLoader.as'
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
$flashLogBeforeBytes = if ($flashLogBeforeItem) {
    [System.IO.File]::ReadAllBytes($FlashLog)
} else {
    [byte[]]@()
}
$flashLogBeforeSize = $flashLogBeforeBytes.Length
$compileOutputBefore = if (Test-Path $CompileOutput) { (Get-Item $CompileOutput).LastWriteTimeUtc } else { $null }
$compilerErrorsBefore = if (Test-Path $CompilerErrors) {
    $item = Get-Item $CompilerErrors
    '{0}|{1}|{2}' -f $item.LastWriteTimeUtc.Ticks, $item.Length,
        (Get-FileHash -LiteralPath $CompilerErrors -Algorithm SHA256).Hash
} else { $null }

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
$compileStartedUtc = [System.DateTime]::UtcNow
if ($targetUri) {
    [System.IO.File]::WriteAllText($TargetCfg, $targetUri, (New-Object System.Text.UTF8Encoding($false)))
}
# publish 模式（main）→ 写 compile_mode.cfg，compile_action.jsfl 读到后用 doc.publish() 而非 testMovie。
if ($compileMode -eq 'publish') {
    [System.IO.File]::WriteAllText($ModeCfg, $compileMode, (New-Object System.Text.UTF8Encoding($false)))
}
$inFlightUncertainBody = Write-CompileUncertain ('in-flight; target={0}' -f $Target)
$compileTriggered = $true
Start-ScheduledTask -TaskName 'CompileTriggerTask'

for ($i = 1; $i -le $TimeoutSeconds; $i++) {
    if (Test-Path $Marker) {
        $compileTerminalObserved = $true
        Remove-OwnedCompileUncertain -ExpectedBody $inFlightUncertainBody
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
                if ($flashLogBefore -and $flashLogBeforeSize -gt 0 -and
                    $flashLogBytes.Length -ge $flashLogBeforeSize) {
                    # Flash Player may either append to the existing log or truncate/rewrite it.
                    # Size growth alone cannot distinguish the two: a slightly larger rewritten
                    # run previously caused us to discard almost the entire fresh trace. Offset
                    # only when the complete old byte sequence is an exact prefix of the new file.
                    $isAppend = $true
                    for ($byteIndex = 0; $byteIndex -lt $flashLogBeforeSize; $byteIndex++) {
                        if ($flashLogBytes[$byteIndex] -ne $flashLogBeforeBytes[$byteIndex]) {
                            $isAppend = $false
                            break
                        }
                    }
                    if ($isAppend) {
                        $flashTraceOffset = $flashLogBeforeSize
                    }
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

        # Compiler Errors 是所有目标的成功必需证据：必须由本轮重新导出且严格为 0/0。
        $hasCompileError = $false
        if (-not (Test-Path $CompilerErrors)) {
            Write-Host '[ERROR] 本轮没有导出 compiler_errors.txt；不能用 marker 或 SWF 刷新替代编译器 0/0 证据。'
            $hasCompileError = $true
        } else {
            $compilerErrorsItem = Get-Item $CompilerErrors
            $compilerErrorsNow = '{0}|{1}|{2}' -f
                $compilerErrorsItem.LastWriteTimeUtc.Ticks,
                $compilerErrorsItem.Length,
                (Get-FileHash -LiteralPath $CompilerErrors -Algorithm SHA256).Hash
            $errContent = Get-Content -Path $CompilerErrors -Raw -Encoding UTF8
            if ($compilerErrorsNow -eq $compilerErrorsBefore -or
                $compilerErrorsItem.LastWriteTimeUtc -lt $compileStartedUtc.AddSeconds(-1)) {
                Write-Host '[ERROR] compiler_errors.txt 未由本轮刷新；拒绝复用旧的 0/0 证据。'
                $hasCompileError = $true
            } elseif ($errContent -notmatch '^\s*0\s+[^,\r\n]+,\s*0\s+[^,\r\n]+\s*$') {
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

        # TestLoader 编译后近墙门：codeSize 是 UI16，只能拦尚未越墙项；
        # canonical 源闭包度量只作调查信号，还须结合 fresh 行为证据。
        $hasFunctionSizeFailure = $false
        if ($isTestLoaderTarget -and -not $hasSwfStale) {
            $functionSizeTool = Join-Path $ProjectDir 'tools\swf-function-sizes.js'
            $testLoaderSwf = Join-Path $ProjectDir 'scripts\TestLoader.swf'
            if (-not (Test-Path $functionSizeTool) -or -not (Get-Command node -ErrorAction SilentlyContinue)) {
                Write-Host '[ERROR] TestLoader function codeSize 门缺少 node 或 tools/swf-function-sizes.js。'
                $hasFunctionSizeFailure = $true
            } else {
                & node $functionSizeTool $testLoaderSwf --max 60000 --top 5
                if ($LASTEXITCODE -ne 0) {
                    Write-Host '[ERROR] TestLoader 存在 codeSize >= 60000B 的近墙函数。'
                    $hasFunctionSizeFailure = $true
                }
            }
        }

        if ($hasCompileError -or $hasTraceFailure -or $hasSwfStale -or $hasFunctionSizeFailure) {
            Remove-Item -Path $TargetCfg, $ModeCfg -ErrorAction SilentlyContinue
            exit 1
        }
        Remove-Item -Path $TargetCfg, $ModeCfg -ErrorAction SilentlyContinue
        exit 0
    }

    if (Test-Path $ErrorMarker) {
        $compileTerminalObserved = $true
        Remove-OwnedCompileUncertain -ExpectedBody $inFlightUncertainBody
        Write-Host '[ERROR] 编译失败:'
        Get-Content -Path $ErrorMarker -Encoding UTF8
        Remove-Item -Path $ErrorMarker -ErrorAction SilentlyContinue
        Remove-Item -Path $TargetCfg, $ModeCfg -ErrorAction SilentlyContinue
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
[void](Write-CompileUncertain ('timeout after {0}s; target={1}' -f $TimeoutSeconds, $Target))
$nonTerminalUncertainWritten = $true
exit 1
} finally {
    if ($compileTriggered -and -not $compileTerminalObserved -and
        -not $nonTerminalUncertainWritten) {
        [void](Write-CompileUncertain ('compile_test exited before a terminal marker; target={0}' -f $Target))
    }
    if ($compileMutexAcquired) {
        $compileMutex.ReleaseMutex()
    }
    $compileMutex.Dispose()
}
