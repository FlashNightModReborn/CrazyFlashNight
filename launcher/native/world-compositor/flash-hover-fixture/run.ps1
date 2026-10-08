[CmdletBinding()]
param([string]$NativeRoot,
    [ValidateSet('Raw','Direct','Cooperative')][string]$Mode='Raw',
    [switch]$BoundariesOnly,
    [switch]$S1NegativeControl,
    [switch]$ManagedBuildOnly)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
if(-not $ManagedBuildOnly -and [string]::IsNullOrWhiteSpace($NativeRoot)){throw 'NativeRoot is required for fixture execution.'}
if(-not [string]::IsNullOrWhiteSpace($NativeRoot)){$NativeRoot=[IO.Path]::GetFullPath($NativeRoot)}
$movies=if($Mode -eq 'Cooperative'){@('CooperativeProbe.swf','CooperativeChild.swf')}else{@('HoverProbe.swf')}
if(-not $ManagedBuildOnly){
    foreach($movie in $movies){if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $movie))) { throw ('Compile the explicit CS6 target first: '+$movie) }}
}
if($BoundariesOnly -and $Mode -ne 'Raw'){throw 'BoundariesOnly applies only to the raw oracle.'}
if($S1NegativeControl -and $Mode -ne 'Cooperative'){throw 'S1NegativeControl requires Cooperative mode.'}
. (Join-Path $repo 'launcher/resolve-dotnet.ps1')
$dotnet=Resolve-Cf7Dotnet -ProjectRoot $repo
$run=Join-Path $repo ('tmp/flash-hover-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$bin=Join-Path $run 'bin'
$evidence=Join-Path $run 'evidence'
New-Item -ItemType Directory -Force -Path $bin,$evidence | Out-Null
& $dotnet build (Join-Path $PSScriptRoot 'FlashHoverHost.csproj') -c Release -o $bin --nologo
if($LASTEXITCODE -ne 0){throw 'Fixture build failed'}
if(-not (Test-Path -LiteralPath (Join-Path $bin 'CRAZYFLASHER7MercenaryEmpire.Core.dll') -PathType Leaf)){
    throw 'Referenced Core is missing from the isolated fixture closure.'
}
if($ManagedBuildOnly){
    Write-Host ('HOVER_MANAGED_BUILD_ONLY='+$bin)
    Write-Host 'No SWF compilation, fixture execution or input injection was performed.'
    exit 0
}
foreach($name in @('FlashCompositorNative.dll','FlashInputBridge.dll','FlashInputBroker.exe')) {
    Copy-Item -LiteralPath (Join-Path $NativeRoot $name) -Destination $bin
}
$previousTrace=$env:CF7_FOCUS_TRACE
$previousWait=$env:CF7_HOVER_SETUP_WAIT
$previousRoot=$env:DOTNET_ROOT_X64
$previousCooperative=$env:CF7_HOVER_COOPERATIVE
$previousDirect=$env:CF7_HOVER_DIRECT_CONTROL
$previousBoundaries=$env:CF7_HOVER_BOUNDARIES_ONLY
$previousS1Negative=$env:CF7_COOPERATIVE_S1_NEGATIVE
try {
    $env:CF7_FOCUS_TRACE='1';$env:CF7_HOVER_SETUP_WAIT='1';$env:DOTNET_ROOT_X64=Split-Path $dotnet -Parent
    $env:CF7_HOVER_COOPERATIVE=if($Mode -eq 'Cooperative'){'1'}else{'0'}
    $env:CF7_HOVER_DIRECT_CONTROL=if($Mode -eq 'Direct'){'1'}else{'0'}
    $env:CF7_HOVER_BOUNDARIES_ONLY=if($BoundariesOnly){'1'}else{'0'}
    $env:CF7_COOPERATIVE_S1_NEGATIVE=if($S1NegativeControl){'1'}else{'0'}
    Write-Host ('Activate the fixture ONCE and inspect its two buttons, then create: '+(Join-Path $evidence 'continue.flag'))
    & (Join-Path $bin 'FlashHoverHost.exe') $repo $evidence
    $result=$LASTEXITCODE
} finally {
    $env:CF7_FOCUS_TRACE=$previousTrace;$env:CF7_HOVER_SETUP_WAIT=$previousWait;$env:DOTNET_ROOT_X64=$previousRoot
    $env:CF7_HOVER_COOPERATIVE=$previousCooperative;$env:CF7_HOVER_DIRECT_CONTROL=$previousDirect;$env:CF7_HOVER_BOUNDARIES_ONLY=$previousBoundaries
    $env:CF7_COOPERATIVE_S1_NEGATIVE=$previousS1Negative
}
exit $result
