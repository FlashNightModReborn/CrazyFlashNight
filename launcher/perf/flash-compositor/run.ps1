[CmdletBinding()]
param(
    [ValidateSet('fixture','flash')][string]$Source = 'fixture',
    [ValidateSet('auto','intel','nvidia')][string]$Adapter = 'auto',
    [switch]$Auto,
    [ValidateRange(3,60)][int]$PhaseSeconds = 5,
    [ValidateRange(0,3600)][int]$Duration = 0,
    [ValidateSet('embedded','toproot','embeddedF')][string]$Topology = 'embedded',
    [switch]$CaptureOutput,
    [switch]$StallF,
    [switch]$DebugHoldFrames,
    [ValidateSet('none','rain','snow','dust','fog','slash')][string]$Weather = 'none',
    [ValidateRange(0,1)][double]$WeatherIntensity = 0.7,
    [ValidateRange(0.25,4)][double]$WeatherScale = 1,
    [ValidateRange(-500,500)][double]$WeatherPanX = 0,
    [ValidateRange(-500,500)][double]$WeatherPanY = 0,
    [ValidateSet('none','alert','medical','industrial','toxic','corrosion','cold-iron','ambush','banquet','blood-moon','incense','custom')][string]$Atmosphere = 'none',
    [string]$VisualPresets,
    [string]$LutSet,
    [string]$Report,
    [switch]$Build
)
$ErrorActionPreference = 'Stop'
chcp.com 65001 | Out-Null
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$out = Join-Path $repo 'tmp\flash-compositor\bin'
if ($Build) { & (Join-Path $PSScriptRoot 'build.ps1') }
$dll = Join-Path $out 'FlashCompositorProbe.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Run build.ps1 first, or pass -Build' }
$sdk = @((Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'), (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe')) |
    Where-Object { Test-Path -LiteralPath $_ } | Where-Object { (& $_ --list-sdks) -match '^10\.0\.300 ' } | Select-Object -First 1
if (-not $sdk) { throw '.NET SDK 10.0.300 not found' }
if (-not $Report) {
    $name = $Source + '-' + $Adapter + $(if ($Topology -ne 'embedded') { '-' + $Topology } else { '' }) + $(if ($CaptureOutput) { '-capture-output' } else { '' }) + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json'
    $Report = Join-Path $repo ('tmp\flash-compositor\' + $name)
}
$arguments = @($dll, '--adapter', $Adapter, '--report', [IO.Path]::GetFullPath($Report), '--phase-seconds', [string]$PhaseSeconds, '--duration', [string]$Duration, '--topology', $Topology)
if ($Auto) { $arguments += '--auto' }
if ($LutSet) { $arguments += @('--lut-set', [IO.Path]::GetFullPath($LutSet)) }
if ($CaptureOutput) { $arguments += '--capture-output' }
if ($StallF) { $arguments += '--stall-f' }
if ($DebugHoldFrames) { $arguments += '--debug-hold-frames' }
if ($Weather -ne 'none') {
    $arguments += @('--weather', $Weather, '--weather-intensity',
        $WeatherIntensity.ToString('R', [Globalization.CultureInfo]::InvariantCulture))
}
if ($Weather -ne 'none' -or $Atmosphere -ne 'none') {
    $arguments += @('--weather-scale',
        $WeatherScale.ToString('R', [Globalization.CultureInfo]::InvariantCulture), '--weather-pan-x',
        $WeatherPanX.ToString('R', [Globalization.CultureInfo]::InvariantCulture), '--weather-pan-y',
        $WeatherPanY.ToString('R', [Globalization.CultureInfo]::InvariantCulture))
}
if ($Atmosphere -ne 'none') { $arguments += @('--atmosphere', $Atmosphere) }
if ($Weather -ne 'none' -or $Atmosphere -ne 'none') {
    if (-not $VisualPresets) { $VisualPresets = Join-Path $repo 'data\environment\presentation_presets.v1.json' }
    $arguments += @('--visual-presets', [IO.Path]::GetFullPath($VisualPresets))
}
if ($Source -eq 'flash') {
    # Disposable legacy AS2 movie, not the main game and not a player save slot.
    $arguments += @('--flash-exe', (Join-Path $repo 'Adobe Flash Player 20.exe'), '--swf', (Join-Path $repo 'flashswf\movies\bigmovie1.swf'))
}
& $sdk @arguments
$result = $LASTEXITCODE
Write-Output "Report: $Report"
exit $result
