[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Preparation,
    [Parameter(Mandatory = $true)][ValidateSet('intel','nvidia')][string]$Adapter
)

$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$preparedFile = (Resolve-Path -LiteralPath $Preparation).Path
$prepared = Get-Content -Encoding UTF8 -Raw -LiteralPath $preparedFile | ConvertFrom-Json
if ($prepared.schema -cne 'cf7-input-authority-wgc-fixture-preparation.v1') { throw 'Use a WGC fixture preparation receipt.' }
$root = Split-Path -Parent $preparedFile
$runner = Join-Path $root 'launcher/perf/flash-compositor/test-g2.ps1'
if ($prepared.runner -cne $runner) { throw 'The stock G2 runner path drifted.' }
foreach ($asset in $prepared.fixtureFiles) {
    $absolute = (Resolve-Path -LiteralPath $asset.path).Path
    if (-not $absolute.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        (Get-FileHash -LiteralPath $absolute).Hash -cne $asset.sha256) { throw 'The prepared WGC fixture bytes drifted.' }
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Cf7G2Desktop {
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr GetThreadDesktop(uint thread);
    [DllImport("user32.dll")] private static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern bool GetUserObjectInformationW(
        IntPtr handle,int index,StringBuilder info,int capacity,out int needed);
    [DllImport("user32.dll",EntryPoint="GetUserObjectInformationW")] private static extern bool ReadDesktopInputState(
        IntPtr handle,int index,out int value,int capacity,out int needed);
    private static string Name(IntPtr handle) {
        var name=new StringBuilder(256);
        int needed;
        return handle!=IntPtr.Zero && GetUserObjectInformationW(handle,2,name,name.Capacity*2,out needed) ? name.ToString() : null;
    }
    public static object Observe() {
        IntPtr thread=GetThreadDesktop(GetCurrentThreadId());
        IntPtr input=OpenInputDesktop(0,false,1);
        try {
            int receivesInput;
            int needed;
            bool proved=thread!=IntPtr.Zero && ReadDesktopInputState(thread,6,out receivesInput,sizeof(int),out needed) && receivesInput!=0;
            return new { threadDesktop=Name(thread), inputDesktop=Name(input), threadReceivesInput=proved };
        } finally { if(input!=IntPtr.Zero)CloseDesktop(input); }
    }
}
'@
$before = [Cf7G2Desktop]::Observe()
if ($before.threadDesktop -cne 'Default' -or $before.inputDesktop -cne 'Default' -or -not $before.threadReceivesInput) {
    throw 'Run the actual WGC fixture in its dedicated Default input-desktop window.'
}
$resultRoot = Join-Path $root 'tmp/flash-compositor'
$existing = @(Get-ChildItem -Directory -LiteralPath $resultRoot -Filter 'g2-*' | Select-Object -ExpandProperty FullName)
$runId = [Guid]::NewGuid().ToString('N')
$startedUtc = [DateTimeOffset]::UtcNow.ToString('O')
$log = Join-Path $root ("stock-g2-" + $runId + ".log")
$previousErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -SkipBuild -Adapter $Adapter *> $log
    $g2Exit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorAction
}
$after = [Cf7G2Desktop]::Observe()
$new = @(Get-ChildItem -Directory -LiteralPath $resultRoot -Filter 'g2-*' |
    Where-Object { $_.FullName -notin $existing } | Select-Object -ExpandProperty FullName)
$summary = if ($new.Count -eq 1) { Join-Path $new[0] 'summary.json' } else { $null }
$receipt = [ordered]@{
    schema = 'cf7-input-authority-wgc-fixture-run.v1'
    runId = $runId
    startedUtc = $startedUtc
    completedUtc = [DateTimeOffset]::UtcNow.ToString('O')
    adapter = $Adapter
    desktopBefore = $before
    desktopAfter = $after
    preparationSha256 = (Get-FileHash -LiteralPath $preparedFile).Hash
    log = $log
    logSha256 = (Get-FileHash -LiteralPath $log).Hash
    summary = $summary
    summarySha256 = if ($summary -and (Test-Path -LiteralPath $summary)) { (Get-FileHash -LiteralPath $summary).Hash } else { $null }
    exitCode = $g2Exit
}
$text = ($receipt | ConvertTo-Json -Depth 5) + "`n"
[IO.File]::WriteAllText((Join-Path $root ("stock-g2-" + $runId + ".json")), $text, [Text.UTF8Encoding]::new($false))
Write-Output $text
if (-not $receipt.summarySha256 -or $after.inputDesktop -cne 'Default' -or -not $after.threadReceivesInput) { exit 2 }
exit $g2Exit
