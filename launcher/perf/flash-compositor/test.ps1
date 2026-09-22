[CmdletBinding()]
param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') }
$run = Join-Path $PSScriptRoot 'run.ps1'
$reports = Join-Path $repo ('tmp\flash-compositor\suite-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $reports | Out-Null
$results = @()
foreach ($source in @('fixture','flash')) {
    foreach ($adapter in @('intel','nvidia')) {
        $report = Join-Path $reports "$source-$adapter.json"
        # Sequential runs: no two graphics probes compete for a device or source window.
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $run -Source $source -Adapter $adapter -Auto -PhaseSeconds 3 -Report $report
        $code = $LASTEXITCODE
        $data = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
        $passed = $code -eq 0 -and $data.success -eq $true -and $data.automatedCorePassed -eq $true
        $results += [pscustomobject]@{ source=$source; adapter=$adapter; exitCode=$code; passed=[bool]$passed; report=$report }
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
        Write-Output "$source / $adapter : passed=$passed"
    }
}
$sdk = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
if (-not (Test-Path -LiteralPath $sdk)) { $sdk = Join-Path $env:ProgramFiles 'dotnet\dotnet.exe' }
$dll = Join-Path $repo 'tmp\flash-compositor\bin\FlashCompositorProbe.dll'
$negativeCases = @(
    @('--adapter','invalid'),
    @('--hwnd','1','--pid','1','--auto'),
    @('--phase-seconds','0'),
    @('--flash-exe','missing.exe'),
    @('--adapter','intel','--adapter','nvidia')
)
$index = 0
foreach ($case in $negativeCases) {
    $report = Join-Path $reports "rejected-$index.json"
    & $sdk $dll --report $report @case
    $code = $LASTEXITCODE
    $data = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
    $results += [pscustomobject]@{ source='invalid-cli'; adapter='none'; exitCode=$code; passed=($code -ne 0 -and $data.success -eq $false -and $null -ne $data.error); report=$report }
    $index++
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
$results | Format-Table source,adapter,exitCode,passed -AutoSize
Write-Output "Suite reports: $reports"
if (@($results | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
exit 0
