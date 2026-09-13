[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputPath = [IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDirectory))
$scratchRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'tmp')) + [IO.Path]::DirectorySeparatorChar
if (-not $outputPath.StartsWith($scratchRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Smoke output and browser profile must stay inside project tmp.'
}
if (Test-Path -LiteralPath $outputPath) { throw 'Use a fresh smoke output directory.' }
. (Join-Path $projectRoot 'launcher/resolve-dotnet.ps1')
$dialogueDotnet = Resolve-Cf7Dotnet -ProjectRoot $projectRoot
& $dialogueDotnet run --project (Join-Path $PSScriptRoot 'native-dialogue-webview2-smoke/NativeDialogue.Smoke.csproj') -c Release -- $projectRoot $outputPath
if ($LASTEXITCODE -ne 0) { throw "Hidden WebView2 portrait smoke failed: $outputPath" }
$resultPath = Join-Path $outputPath 'result.json'
if (-not (Test-Path -LiteralPath $resultPath)) { throw 'Smoke exited without evidence.' }
Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8
