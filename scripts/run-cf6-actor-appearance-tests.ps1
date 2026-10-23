[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
& python -X utf8 -B (Join-Path $projectDir 'tools/cf6-scene-completion/build_actor_appearance_fixture.py') --check
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
$hostSource=Join-Path $PSScriptRoot 'Cf6ActorAppearanceNativeHost'
$hostTarget=Join-Path $projectDir 'tmp-cf6-actor-appearance-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
foreach($hostFile in @('Cf6ActorAppearanceNativeHost.xfl','DOMDocument.xml','PublishSettings.xml','LIBRARY')) {
    $hostInput=Join-Path $hostSource $hostFile
    $hostOutput=Join-Path $hostTarget $hostFile
    if((Test-Path -LiteralPath $hostInput -PathType Leaf) -and (Test-Path -LiteralPath $hostOutput) -and
        (Get-FileHash -LiteralPath $hostInput).Hash -eq (Get-FileHash -LiteralPath $hostOutput).Hash){continue}
    Copy-Item -LiteralPath $hostInput -Destination $hostTarget -Recurse -Force
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-actor-appearance' `
    -CompileTargetRelativePath 'tmp-cf6-actor-appearance-host/Cf6ActorAppearanceNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6ActorAppearanceNativeHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-actor-appearance/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorAppearanceTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6ActorAppearanceTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskPresentation.as','scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6ActorAppearanceTest Tests Passed: 52\r?$', '(?m)^Cf6ActorAppearanceTest Tests Failed: 0\r?$') `
    -SuccessSummary '52 native-hero/XML-dressup/authored-mask/door-layer pixel assertions; no real saves or full-game claim' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile