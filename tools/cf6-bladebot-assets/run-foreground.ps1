[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ResourceRoot,
    [Parameter(Mandatory=$true)][string]$CandidateRoot,
    [Parameter(Mandatory=$true)][string]$Manifest,
    [Parameter(Mandatory=$true)][string]$Slot,
    [Parameter(Mandatory=$true)][string]$SeedSlot,
    [int]$BatchTimeoutMs = 900000
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$resourceAbsolute = (Resolve-Path -LiteralPath $ResourceRoot).Path
$candidateAbsolute = (Resolve-Path -LiteralPath $CandidateRoot).Path
$manifestAbsolute = (Resolve-Path -LiteralPath $Manifest).Path
$candidatePrefix = [IO.Path]::GetFullPath((Join-Path $resourceAbsolute 'tmp/runtime-candidates/v2')).TrimEnd('\') + '\'
if (-not $candidateAbsolute.StartsWith($candidatePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Only an explicit isolated candidate inside the owned resource checkout is accepted.'
}
if ($Slot -cnotmatch '^cf7_agent_[A-Za-z0-9_-]+$' -or $SeedSlot -cnotmatch '^cf7_agent_[A-Za-z0-9_-]+$' -or $Slot -eq $SeedSlot) {
    throw 'Use distinct dedicated target and cloned-seed slots.'
}
if ($BatchTimeoutMs -lt 60000 -or $BatchTimeoutMs -gt 1800000) { throw 'Batch timeout must be 1..30 minutes.' }

# A temporary thread request keeps display capture active; no power plan or
# system setting is changed. The normal window still needs foreground admission.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public static class BladebotForegroundDisplay {
    [DllImport("kernel32.dll", SetLastError=true)]
    private static extern uint SetThreadExecutionState(uint flags);
    private static readonly ManualResetEvent Started = new ManualResetEvent(false);
    private static readonly ManualResetEvent Stop = new ManualResetEvent(false);
    private static Thread thread;
    private static uint previous;
    private static bool restored;
    public static bool Acquire(int maximumMilliseconds) {
        thread = new Thread(() => {
            previous = SetThreadExecutionState(0x80000003);
            Started.Set();
            if (previous != 0) {
                Stop.WaitOne(maximumMilliseconds);
                restored = SetThreadExecutionState(previous) != 0;
            }
        });
        thread.IsBackground = true;
        thread.Start();
        return Started.WaitOne(3000) && previous != 0;
    }
    public static bool Release() {
        Stop.Set();
        return thread != null && thread.Join(3000) && restored;
    }
}
'@
if (-not [BladebotForegroundDisplay]::Acquire($BatchTimeoutMs + 360000)) { throw 'Temporary display request failed.' }
Write-Output 'Temporary display request acquired on a dedicated thread.'
$previousNodePath = $env:NODE_PATH
$resultCode = 1
try {
    # Reuse the already installed local validator dependencies; never install packages here.
    $env:NODE_PATH = Join-Path $sourceRoot 'tools/arena-calibration/node_modules'
    Push-Location -LiteralPath $resourceAbsolute
    try {
        & node tools/arena-calibration/run-unattended.js --slot $Slot --seed-slot $SeedSlot `
            --manifest $manifestAbsolute --candidate-root $candidateAbsolute `
            --max-recovery-attempts 0 --batch-timeout-ms $BatchTimeoutMs --shutdown
        $resultCode = $LASTEXITCODE
    } finally { Pop-Location }
} finally {
    $env:NODE_PATH = $previousNodePath
    $released = [BladebotForegroundDisplay]::Release()
    Write-Output ('Temporary display request released: ' + $released)
}
exit $resultCode
