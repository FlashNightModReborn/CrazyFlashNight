# ============================================================
# CF7:ME 一键启动脚本（headless 自动化）
# 启动守护进程 EXE（内含 Flash Player 启动 + V8 总线）
#
# 2026-05-28 net10 迁移后：
#   - 用户面 CRAZYFLASHER7MercenaryEmpire.exe 是 native bootstrap，runtime 缺失时弹 MessageBox
#   - headless 路径直接走 runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe 跳过 prompt
#   - Core apphost 默认只搜 %ProgramFiles%\dotnet，所以要复刻 bootstrap 的 user-scope 探测
# ============================================================

$scriptDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent -Path $MyInvocation.MyCommand.Path }
$scriptDirectory = (Resolve-Path -LiteralPath $scriptDirectory).Path
$projectRoot = Split-Path -Parent $scriptDirectory

$coreExe = Join-Path $projectRoot "runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe"

if (-not (Test-Path $coreExe)) {
    Write-Host "[Error] Core EXE not found: $coreExe"
    Write-Host "Please run launcher\build.ps1 first."
    exit 1
}

# Runtime 探测 — 共享 tools/dotnet-runtime-detect.ps1（与 bootstrap.cpp ScanOneDotnetRoot 等价：
# 系统位置优先 + 必须含 Microsoft.WindowsDesktop.App.deps.json，避免半安装 user-scope 误命中）
. (Join-Path $projectRoot 'tools\dotnet-runtime-detect.ps1')
if (-not (Set-DotnetRootForCore)) {
    exit 1
}

Write-Host "Starting CF7:ME Guardian Core..."
try {
    Write-Host "Project Root: $projectRoot"
    Write-Host "Core EXE    : $coreExe"
    $portsFile = Join-Path $projectRoot "launcher_ports.json"
    if (Test-Path -LiteralPath $portsFile) {
        try {
            $ports = Get-Content -LiteralPath $portsFile -Raw | ConvertFrom-Json
            $pidAlive = $false
            if ($ports.pid) {
                $pidAlive = [bool](Get-Process -Id ([int]$ports.pid) -ErrorAction SilentlyContinue)
            }
            if (-not $pidAlive) {
                Remove-Item -LiteralPath $portsFile -Force
            }
        } catch {
            Remove-Item -LiteralPath $portsFile -Force -ErrorAction SilentlyContinue
        }
    }

    # 显式传 --project-root（Core 在 runtime\ 子目录，AppContext.BaseDirectory ≠ projectRoot）
    Push-Location $projectRoot
    try {
        $guardian = [System.Diagnostics.Process]::Start($coreExe, "--project-root `"$projectRoot`"")
    } finally {
        Pop-Location
    }
    if ($guardian -eq $null) {
        throw "System.Diagnostics.Process.Start returned null"
    }
    Write-Host "Guardian PID: $($guardian.Id)"
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if ($guardian.HasExited) {
            throw "guardian exited before HTTP bus became ready (exitCode=$($guardian.ExitCode))"
        }
        if (Test-Path -LiteralPath $portsFile) {
            Write-Host "Guardian bus ready: $(Get-Content -LiteralPath $portsFile -Raw)"
            break
        }
        Start-Sleep -Milliseconds 500
        try { $guardian.Refresh() } catch { }
    }
    if (-not (Test-Path -LiteralPath $portsFile)) {
        throw "guardian did not write launcher_ports.json within 30s"
    }
    Write-Host "Guardian started successfully."
    Write-Host "(Flash Player + V8 Bus are managed by the guardian process)"
} catch {
    Write-Host "Failed to start guardian: $_"
    exit 1
}
