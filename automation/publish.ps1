param(
  [ValidateSet("asloader","main","all")] [string]$Docs = "all",
  [string]$CS6 = "C:\Program Files (x86)\Adobe\Adobe Flash CS6\Flash.exe"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$jsfl     = Join-Path $repoRoot "tools\jsfl\publish.jsfl"

if (-not (Test-Path $CS6)) {
  $alt = "C:\Program Files\Adobe\Adobe Flash CS6\Flash.exe"
  if (Test-Path $alt) { $CS6 = $alt } else {
    throw "找不到 Flash CS6：请用 -CS6 指定 Flash.exe 路径。"
  }
}
if (-not (Test-Path $jsfl)) { throw "缺少 JSFL: $jsfl" }

Write-Host "CS6: $CS6"
Write-Host "JSFL: $jsfl"
Write-Host "Docs: $Docs"

# 以 JSFL + 参数方式启动 CS6 并等待结束
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $CS6
$psi.Arguments = "`"$jsfl`" $Docs"
$psi.WorkingDirectory = $repoRoot
$psi.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit()

if ($proc.ExitCode -ne 0) { throw "Flash CS6 进程返回码 $($proc.ExitCode)" }
Write-Host "发布完成。日志见 automation/logs/"
