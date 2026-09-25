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
# C0 toproot additions: rejected option combinations are appended; the five cases above are unchanged.
$negativeCases = $negativeCases + @(
    @('--topology','bogus'),
    @('--capture-output'),
    @('--topology','toproot','--capture-output')
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
# --- C0 toproot experiments (appended cases; the embedded matrix and its judgments above are unchanged) ---
foreach ($source in @('fixture','flash')) {
    foreach ($adapter in @('intel','nvidia')) {
        $report = Join-Path $reports "toproot-$source-$adapter.json"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $run -Source $source -Adapter $adapter -Auto -PhaseSeconds 3 -Topology toproot -Report $report
        $code = $LASTEXITCODE
        $data = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
        $passed = $code -eq 0 -and $data.success -eq $true -and $data.automatedCorePassed -eq $true `
            -and $null -ne $data.topologyExperiment -and $data.topologyExperiment.marker.verdict -eq 'isolated'
        $results += [pscustomobject]@{ source="toproot-$source"; adapter=$adapter; exitCode=$code; passed=[bool]$passed; report=$report }
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
        Write-Output "toproot-$source / $adapter : passed=$passed"
    }
}
# Deliberate misconfiguration: capture the output window P itself. The run must be detected as failed.
$report = Join-Path $reports "toproot-capture-output.json"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $run -Source fixture -Adapter intel -Auto -PhaseSeconds 3 -Topology toproot -CaptureOutput -Report $report
$code = $LASTEXITCODE
$data = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
$passed = $code -ne 0 -and $null -ne $data -and $data.success -eq $false -and $data.automatedCorePassed -eq $false `
    -and $data.topologyExperiment.negativeControl -eq 'detected'
$results += [pscustomobject]@{ source='toproot-capture-output'; adapter='intel'; exitCode=$code; passed=[bool]$passed; report=$report }
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
Write-Output "toproot-capture-output : passed=$passed"
# --- C0 embeddedF experiments (appended cases; all cases and judgments above are unchanged) ---
foreach ($source in @('fixture','flash')) {
    foreach ($adapter in @('intel','nvidia')) {
        $report = Join-Path $reports "embeddedF-$source-$adapter.json"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $run -Source $source -Adapter $adapter -Auto -PhaseSeconds 3 -Topology embeddedF -Report $report
        $code = $LASTEXITCODE
        $data = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
        $te = if ($null -ne $data) { $data.topologyExperiment } else { $null }
        $full = $code -eq 0 -and $data.success -eq $true -and $data.automatedCorePassed -eq $true `
            -and $null -ne $te -and $te.marker.verdict -eq 'isolated' -and $te.covered.verdict -eq 'streaming-under-cover' `
            -and $te.assertions.captureHwndIsS -eq $true -and $te.assertions.cropIsFRegion -eq $true `
            -and $te.assertions.fIsDescendantOfS -eq $true -and $te.assertions.pNotDescendantOfS -eq $true `
            -and $te.assertions.pIsOwnGaRoot -eq $true -and $te.assertions.pFullyCoversFRegion -eq $true
        # A SetParent failure is an honest 'untested' for the flash source only, never a pass for fixture.
        $untested = $source -eq 'flash' -and $null -ne $te -and $code -eq 4 -and $data.success -eq $false `
            -and $null -ne $te.flashEmbedding -and $te.flashEmbedding.status -eq 'untested'
        $note = if ($untested) { 'untested:flash-embedding' } else { '' }
        $results += [pscustomobject]@{ source="embeddedF-$source"; adapter=$adapter; exitCode=$code; passed=[bool]($full -or $untested); note=$note; report=$report }
        $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
        Write-Output ("embeddedF-$source / $adapter : passed=" + ($full -or $untested) + $(if ($untested) { ' (flash embedding untested)' } else { '' }))
    }
}
# Deliberate misconfiguration on embeddedF: capturing P instead of S must be detected as failed.
$report = Join-Path $reports "embeddedF-capture-output.json"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $run -Source fixture -Adapter intel -Auto -PhaseSeconds 3 -Topology embeddedF -CaptureOutput -Report $report
$code = $LASTEXITCODE
$data = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
$passed = $code -ne 0 -and $null -ne $data -and $data.success -eq $false -and $data.automatedCorePassed -eq $false `
    -and $data.topologyExperiment.negativeControl -eq 'detected' -and $data.topologyExperiment.covered.verdict -eq 'marker-leak'
$results += [pscustomobject]@{ source='embeddedF-capture-output'; adapter='intel'; exitCode=$code; passed=[bool]$passed; note='negative-control'; report=$report }
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
Write-Output "embeddedF-capture-output : passed=$passed"
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $reports 'summary.json') -Encoding UTF8
$results | Format-Table source,adapter,exitCode,passed -AutoSize
Write-Output "Suite reports: $reports"
if (@($results | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
exit 0
