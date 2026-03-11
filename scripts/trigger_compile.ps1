# trigger_compile.ps1 - 以管理员权限打开 JSFL 文件触发编译
# 因为计划任务以管理员权限运行，打开 JSFL 不会弹 UAC
# Flash CS6 已运行时，JSFL 会传递给运行中的实例执行

# 定位 compile.jsfl
$cfgBase = "$env:LOCALAPPDATA\Adobe\Flash CS6"
$jsfl = $null
Get-ChildItem $cfgBase -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $candidate = Join-Path $_.FullName "Configuration\Commands\compile.jsfl"
    if (Test-Path $candidate) { $jsfl = $candidate }
}

if (-not $jsfl) {
    Write-Host "[ERROR] compile.jsfl not found in Commands directory"
    exit 1
}

Write-Host "[INFO] Opening: $jsfl"
# 使用 explorer.exe 打开 JSFL，确保在交互式会话中执行
explorer.exe $jsfl
Write-Host "[OK] JSFL opened"
exit 0
