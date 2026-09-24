[CmdletBinding()]
param([switch]$SkipBuild, [ValidateSet('intel','nvidia')][string]$Adapter = 'intel')
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
if (-not $SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') }
$out = Join-Path $repo ('tmp\flash-compositor\g2-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $out | Out-Null
$results = @()
# Use the existing default five-second phases; do not relax any frame threshold.
# These are detector qualifications, not Guardian/Flash/input acceptance.
foreach ($name in @('positive','stall-f','hold-frames','capture-output','flash')) {
    $report = Join-Path $out ($name + '.json')
    $extra = switch ($name) {
        'stall-f' { @('-StallF') }
        'hold-frames' { @('-DebugHoldFrames') }
        'capture-output' { @('-CaptureOutput') }
        default { @() }
    }
    $source = if ($name -eq 'flash') { 'flash' } else { 'fixture' }
    $runArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'run.ps1'),
        '-Source',$source,'-Adapter',$Adapter,'-Auto','-Topology','embeddedF','-PhaseSeconds','5','-Report',$report) + @($extra)
    & powershell.exe @runArgs
    $code = $LASTEXITCODE
    $r = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
    $covered = @($r.topologyExperiment.contentPhases | Where-Object { $_.phase -eq 'covered' })
    $stalled = @($r.topologyExperiment.contentPhases | Where-Object { $_.phase -eq 'covered-stalled' })
    $passed = $false
    if ($null -ne $r -and $covered.Count -eq 1) {
        $c = $covered[0]
        switch ($name) {
            { $_ -in 'positive','flash' } {
                $passed = $code -eq 0 -and $r.success -eq $true -and $r.automatedCorePassed -eq $true -and $c.verdict -eq 'streaming-under-cover' -and $c.inputPixelsChanged -eq $true -and $c.outputCorrelated -eq $true
            }
            'stall-f' {
                $passed = $code -eq 2 -and $r.success -eq $false -and $stalled.Count -eq 1 -and $stalled[0].verdict -eq 's-chrome-only' -and $stalled[0].capturedFrames -gt 0 -and $stalled[0].presentedFrames -gt 0 -and $stalled[0].proofs.Count -ge 2 -and $stalled[0].inputPixelsChanged -eq $false -and $c.verdict -eq 'streaming-under-cover' -and $c.outputCorrelated -eq $true
            }
            'hold-frames' {
                $passed = $code -eq 2 -and $r.success -eq $false -and $c.verdict -eq 'stalled-under-cover' -and $c.capturedFrames -eq 0 -and $c.presentedFrames -gt 0 -and $c.proofs.Count -ge 2 -and $c.inputPixelsChanged -eq $false
            }
            'capture-output' {
                $passed = $code -eq 2 -and $r.success -eq $false -and $r.topologyExperiment.negativeControl -eq 'detected' -and $c.verdict -eq 'marker-leak'
            }
        }
    }
    $results += [pscustomobject]@{name=$name;exitCode=$code;passed=[bool]$passed;report=$report}
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
    Write-Output "$name : passed=$passed"
}
$sdk = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
$dll = Join-Path $repo 'tmp\flash-compositor\bin\FlashCompositorProbe.dll'
$invalid = @(
    @('--stall-f'),
    @('--debug-hold-frames','--auto'),
    @('--topology','embeddedF','--auto','--stall-f','--debug-hold-frames'),
    @('--topology','embeddedF','--auto','--stall-f','--capture-output')
)
$i=0
foreach ($case in $invalid) {
    $report = Join-Path $out ("invalid-$i.json")
    & $sdk $dll --report $report @case
    $code = $LASTEXITCODE
    $r = if (Test-Path -LiteralPath $report) { Get-Content -LiteralPath $report -Raw | ConvertFrom-Json } else { $null }
    $results += [pscustomobject]@{name="invalid-$i";exitCode=$code;passed=($code -eq 1 -and $r.success -eq $false -and $null -ne $r.error);report=$report}
    $i++
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'summary.json') -Encoding UTF8
$results | Format-Table -AutoSize
Write-Output "G2 reports: $out"
if (@($results | Where-Object { -not $_.passed }).Count) { exit 1 }
exit 0
