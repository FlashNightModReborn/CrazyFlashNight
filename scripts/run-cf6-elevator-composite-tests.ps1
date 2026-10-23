[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$runtime=Join-Path $root 'data/stages/books/cf6-sting.runtime.json'
$definition=Get-Content -LiteralPath $runtime -Raw -Encoding UTF8 | ConvertFrom-Json
$transports=@($definition.maps | Where-Object { $null -ne $_.mechanism.transport } | ForEach-Object {$_.id})
if($definition.maps.Count -ne 20 -or ($transports -join ',') -ne 'A09,A14,A18'){throw 'Elevator fixture requires current generated 20-room runtime with three transports.'}
Write-Host ('Cf6ElevatorComposite RuntimeJson: {0} bytes={1} sha256={2}' -f $runtime,(Get-Item -LiteralPath $runtime).Length,(Get-FileHash -LiteralPath $runtime -Algorithm SHA256).Hash)
$sourceIndex=Get-Content -LiteralPath (Join-Path $root 'tools/cf6-map-source/generated/map-input.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($mapId in @('A10','A13')) {
    $layer=@($sourceIndex.maps.$mapId.layers | Where-Object {$_.role -eq 'elevator-scroll'})[0]
    $svg=Join-Path $root $layer.source.svg
    $png=Join-Path (Split-Path -Parent (Split-Path -Parent $svg)) ('baked/'+[IO.Path]::GetFileNameWithoutExtension($svg)+'.png')
    foreach($file in @($svg,$png,(Join-Path $root "flashswf/backgrounds/cf6/CF6_$($mapId)_elevator-scroll.swf"))) {
        Write-Host ('Cf6ElevatorComposite ShaftSource: {0} sha256={1}' -f $file,(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash)
    }
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-elevator-composite' `
    -TemplateRelativePath 'scripts/test-runners/cf6-elevator-composite/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ElevatorCompositeTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6ElevatorCompositeTest') `
    -AdditionalAsRelativePaths @('scripts/逻辑/关卡系统/关卡系统_lsy_add2map_加载背景.as','scripts/类定义/org/flashNight/arki/scene/SceneManager.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapPresentation.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/BookDefinition.as','scripts/类定义/org/flashNight/gesh/json/JSONLoader.as') `
    -ExpectedTracePatterns @('(?m)^Cf6ElevatorCompositeTest Tests Passed: 95\r?$', '(?m)^Cf6ElevatorCompositeTest Tests Failed: 0\r?$') `
    -SuccessSummary '95 production mask binding, original nonblack shaft, async mask negative control, runtime initialization and real production bake/bitmap/negative-depth shaft/window assertions; immediate and delayed source initialization contrasted' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
