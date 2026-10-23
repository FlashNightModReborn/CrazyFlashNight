[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[string]$PythonExecutable="python")
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$controlManifest=Join-Path $root 'tools/cf6-scene-completion/surface-controls.json'
$prepareControls=Join-Path $root 'tools/cf6-scene-completion/prepare_surface_controls.py'
& $PythonExecutable -B -X utf8 $prepareControls
if($LASTEXITCODE -ne 0){throw 'Historical surface controls were not verified; Flash suite was not started.'}
Write-Host ('Cf6NativeSurface ControlsManifest: sha256={0}' -f (Get-FileHash -LiteralPath $controlManifest -Algorithm SHA256).Hash)
Write-Host ('Cf6NativeSurface ControlsProducer: sha256={0}' -f (Get-FileHash -LiteralPath $prepareControls -Algorithm SHA256).Hash)
$points=(Get-Content -LiteralPath $controlManifest -Raw -Encoding UTF8 | ConvertFrom-Json).controls
foreach($row in $points) {
    if((Get-FileHash -LiteralPath (Join-Path $root $row.oldSwf) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.oldSha256){throw "Preserved native negative control changed: $($row.id)"}
    foreach($path in @($row.oldSwf,$row.newSwf)) {Write-Host ('Cf6NativeSurface ActualSwf: {0} sha256={1}' -f $path,(Get-FileHash -LiteralPath (Join-Path $root $path) -Algorithm SHA256).Hash)}
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-native-surface' `
    -TemplateRelativePath 'scripts/test-runners/cf6-native-surface/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6NativeSurfaceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6NativeSurfaceTest') `
    -ExpectedTracePatterns @('(?m)^Cf6NativeSurfaceTest Tests Passed: 40\r?$', '(?m)^Cf6NativeSurfaceTest Tests Failed: 0\r?$') `
    -SuccessSummary '40 real old/new floor and native shaft source pixel assertions; field scene/camera composition remains separate' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
