param(
  [ValidateSet("asloader","main","all")] [string]$Docs = "all",
  [string]$CS6 = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$jsfl     = Join-Path $repoRoot "tools\jsfl\publish.jsfl"

if (-not $CS6) {
  try {
    $task = Get-ScheduledTask -TaskName 'FlashCS6Task' -ErrorAction Stop
    $taskAction = $task.Actions | Select-Object -First 1
    if ($taskAction.Execute -and (Test-Path $taskAction.Execute)) {
      $CS6 = $taskAction.Execute
    }
  } catch {
  }
}

if (-not $CS6) {
  $defaults = @(
    "C:\Program Files\Adobe\Adobe Flash CS6\Flash.exe",
    "C:\Program Files (x86)\Adobe\Adobe Flash CS6\Flash.exe"
  )
  foreach ($candidate in $defaults) {
    if (Test-Path $candidate) {
      $CS6 = $candidate
      break
    }
  }
}

if (-not $CS6 -or -not (Test-Path $CS6)) {
  throw "找不到 Flash CS6：请先运行 scripts/setup_compile_env.bat，或手动传入 -CS6 <Flash.exe>。"
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
