param(
    [ValidateSet('baseline','candidate','integration')][string]$Phase = 'candidate',
    [string]$Filter = 'FullyQualifiedName~WindowManagerFocusRestoreTests|FullyQualifiedName~SolIndependentWindowsTraceTests|FullyQualifiedName~FocusTracePhysicalHistoryTests|FullyQualifiedName~SettingsTaskTests|FullyQualifiedName~CompositionRecheckTests',
    [switch]$NoBuild,
    [switch]$Canonical
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'launcher/resolve-dotnet.ps1')
$dotnetResolved = Resolve-Cf7Dotnet -ProjectRoot $repoRoot
$runRoot = Join-Path $repoRoot ('tmp/focus-sol-20261013/' + $Phase + '-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
[void](New-Item -ItemType Directory -Path $runRoot -Force)
$project = Join-Path $repoRoot 'launcher/tests/Launcher.Tests.csproj'
$environmentNames = @('CF7_EVIDENCE_ROOT','CF7_TEST_WINDOW_END','CF7_TEST_INPUT_TICK','DOTNET_CLI_TELEMETRY_OPTOUT','DOTNET_GENERATE_ASPNET_CERTIFICATE','CF7_NODE_EXE')
$previousEnvironment = @{}
foreach ($name in $environmentNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
    if([string]::IsNullOrWhiteSpace($env:CF7_NODE_EXE)) { $env:CF7_NODE_EXE=(Get-Command node.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
    $sourcePaths=& git -C $repoRoot -c core.quotepath=false ls-files --cached --others --exclude-standard -- launcher/src launcher/tests launcher/contracts data/combat_visuals scripts/类定义
    $inputs=@(foreach($relative in $sourcePaths) { if(Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf) {
        $inputHash=Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $relative)
        @{path=$relative;sha256=$inputHash.Hash.ToLowerInvariant()}
    } })
    [IO.File]::WriteAllText((Join-Path $runRoot 'source-inputs.json'),($inputs | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    if (-not $NoBuild) {
        & $dotnetResolved build $project -c Release --no-restore -p:UseSharedCompilation=false --nologo *> (Join-Path $runRoot 'build.log')
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath (Join-Path $runRoot 'build.log') -Tail 24
            throw "Focused build failed: $runRoot"
        }
    }
    if (-not ('CF7RecheckInputQualification' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CF7RecheckInputQualification {
    [StructLayout(LayoutKind.Sequential)] private struct Last { public uint Size, Tick; }
    [DllImport("user32.dll")] private static extern bool GetLastInputInfo(ref Last value);
    public static uint Capture() {
        var value = new Last { Size = (uint)Marshal.SizeOf(typeof(Last)) };
        if (!GetLastInputInfo(ref value)) throw new InvalidOperationException("Input qualification unavailable");
        return value.Tick;
    }
}
'@
    }
    $env:CF7_EVIDENCE_ROOT = $runRoot
    $env:CF7_TEST_INPUT_TICK = [CF7RecheckInputQualification]::Capture().ToString()
    $env:CF7_TEST_WINDOW_END = [DateTimeOffset]::UtcNow.AddMinutes(10).ToString('O')
    $head = & git -C $repoRoot rev-parse HEAD
    [IO.File]::WriteAllText((Join-Path $runRoot 'command.json'), (([ordered]@{
        phase=$Phase; head=$head; sdk=(& $dotnetResolved --version); dotnet=$dotnetResolved;
        filter=$(if($Canonical){'canonical-all'}else{$Filter}); evidenceKind='production-path fixtures; owned HWND synthetic input; no player saves';
        node=$env:CF7_NODE_EXE;sourceInputsSha256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $runRoot 'source-inputs.json')).Hash.ToLowerInvariant();
        inputTick=$env:CF7_TEST_INPUT_TICK; expiresUtc=$env:CF7_TEST_WINDOW_END;
        testSeams='CF7TestSeams=true; separate Core output; absent from production build'
    } | ConvertTo-Json -Depth 4) + "`n"), [Text.UTF8Encoding]::new($false))
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if($Canonical) {
            & powershell -NoProfile -File (Join-Path $repoRoot 'launcher/tests/run_tests.ps1') -NoBuild -ResultsDirectory $runRoot *> (Join-Path $runRoot 'test.log')
        } else {
        & $dotnetResolved test $project -c Release --no-build --no-restore --filter $Filter `
            --logger 'trx;LogFileName=recheck.trx' --logger 'console;verbosity=normal' `
            --results-directory $runRoot *> (Join-Path $runRoot 'test.log')
        }
        $testExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousErrorAction }
    [IO.File]::WriteAllText((Join-Path $runRoot 'exit.json'), (@{exit=$testExit; completedUtc=[DateTimeOffset]::UtcNow} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Get-Content -LiteralPath (Join-Path $runRoot 'test.log') -Tail 12
    Write-Host "Focus/SOL evidence: $runRoot"
    exit $testExit
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name],'Process') }
}
