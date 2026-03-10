# compile_test.ps1 - Agent 自动编译触发脚本 (PowerShell 版)
# 前提条件：
#   1. 运行过 setup_compile_env.bat（一次性）
#   2. CompileTriggerTask 计划任务已创建
#   3. Flash CS6 已运行且 TestLoader 已打开

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Marker = Join-Path $ScriptDir 'publish_done.marker'
$ErrorMarker = Join-Path $ScriptDir 'publish_error.marker'
$FlashLog = Join-Path $env:APPDATA 'Macromedia\Flash Player\Logs\flashlog.txt'

# ---- 检查计划任务 ----
try {
    $task = Get-ScheduledTask -TaskName 'CompileTriggerTask' -ErrorAction Stop
} catch {
    Write-Host '[ERROR] CompileTriggerTask 未找到，请先运行 scripts/setup_compile_env.bat'
    exit 1
}

# ---- 清理旧状态 ----
Remove-Item -Path $Marker -ErrorAction SilentlyContinue
Remove-Item -Path $ErrorMarker -ErrorAction SilentlyContinue

# ---- 通过计划任务触发编译 ----
Write-Host '[INFO] 触发编译...'
Start-ScheduledTask -TaskName 'CompileTriggerTask'

# ---- 等待完成（最多 30 秒）----
for ($i = 1; $i -le 30; $i++) {
    if (Test-Path $Marker) {
        Write-Host "[OK] 编译完成 (${i}s)"
        Remove-Item -Path $Marker

        # 读取 trace 输出
        if (Test-Path $FlashLog) {
            Write-Host '=== FLASH TRACE OUTPUT ==='
            Get-Content -Path $FlashLog -Encoding UTF8
            Write-Host '=== END ==='
            Copy-Item $FlashLog (Join-Path $ScriptDir 'flashlog.txt') -Force
        } else {
            Write-Host '[INFO] 无 trace 输出 (publish 模式不执行 trace)'
        }
        exit 0
    }

    if (Test-Path $ErrorMarker) {
        Write-Host '[ERROR] 编译失败:'
        Get-Content -Path $ErrorMarker -Encoding UTF8
        Remove-Item -Path $ErrorMarker
        exit 1
    }

    Start-Sleep -Seconds 1
}

Write-Host '[TIMEOUT] 30 秒未完成，可能原因：'
Write-Host '  - Flash CS6 未运行'
Write-Host '  - TestLoader 未在 Flash 中打开'
Write-Host '  - CompileTriggerTask 计划任务未创建'
exit 1
