[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# 根 CMD 限定本次 Windows PowerShell 模块目录，防止继承 PowerShell 7 模块。
Get-Command Get-FileHash -ErrorAction Stop | Out-Null
$workbenchProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
& (Join-Path $workbenchProjectRoot 'automation/dev.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
