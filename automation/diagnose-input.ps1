[CmdletBinding()]
param([ValidateSet('Native', 'System')][string]$Cursor = 'Native')
$ErrorActionPreference = 'Stop'
$inputProbeRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd('\')

# Only a fresh process can select the cursor implementation and exact diagnostic gates.
# Never terminate an existing game or reuse its process as an A/B result.
$inputProbeRunning = @(Get-Process -Name 'CRAZYFLASHER7MercenaryEmpire.Core' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($inputProbeRoot + '\', [StringComparison]::OrdinalIgnoreCase) })
if ($inputProbeRunning.Count -gt 0) {
    throw 'Please exit the running game normally before starting the input comparison.'
}
$inputProbeValues = @{
    CF7_FOCUS_TRACE = '1'
    CF7_INPUT_LATENCY = '1'
    CF7_NATIVE_CURSOR_OVERLAY = $(if ($Cursor -eq 'System') { '0' } else { '1' })
    CF7_DESKTOP_CURSOR = '1'
}
$inputProbePrevious = @{}
foreach ($key in $inputProbeValues.Keys) { $inputProbePrevious[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    foreach ($key in $inputProbeValues.Keys) { [Environment]::SetEnvironmentVariable($key, $inputProbeValues[$key], 'Process') }
    Write-Host "Input comparison: $Cursor cursor. Transition latency recording enabled."
    # dev.ps1 throws on failed child verification/launch. LASTEXITCODE may belong
    # to an unrelated earlier native command and is not this PowerShell call's result.
    & (Join-Path $PSScriptRoot 'dev.ps1') -ReuseOnly
} finally {
    foreach ($key in $inputProbePrevious.Keys) { [Environment]::SetEnvironmentVariable($key, $inputProbePrevious[$key], 'Process') }
}
