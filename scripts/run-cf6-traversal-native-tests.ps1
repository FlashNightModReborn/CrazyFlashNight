[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
# A separate disposable native host; the passed appearance fixture remains unchanged.
$hostSource=Join-Path $PSScriptRoot 'Cf6ActorAppearanceNativeHost'
$hostTarget=Join-Path $projectDir 'tmp-cf6-traversal-native-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
foreach($file in @('DOMDocument.xml','PublishSettings.xml','LIBRARY')) {
    Copy-Item -LiteralPath (Join-Path $hostSource $file) -Destination $hostTarget -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $hostSource 'Cf6ActorAppearanceNativeHost.xfl') -Destination (Join-Path $hostTarget 'Cf6TraversalNativeHost.xfl') -Force
$publish=Join-Path $hostTarget 'PublishSettings.xml'
$text=[IO.File]::ReadAllText($publish,[Text.Encoding]::UTF8).Replace('Cf6ActorAppearanceNativeHost.swf','Cf6TraversalNativeHost.swf')
[IO.File]::WriteAllText($publish,$text,[Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-traversal-native' `
    -CompileTargetRelativePath 'tmp-cf6-traversal-native-host/Cf6TraversalNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6TraversalNativeHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-traversal-native/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TraversalNativeTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6TraversalNativeTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransition.as') `
    -ExpectedTracePatterns @('(?m)^Cf6TraversalNativeTest Tests Passed: 97\r?$', '(?m)^Cf6TraversalNativeTest Tests Failed: 0\r?$') `
    -SuccessSummary '97 native player/state/traversal assertions: three gun modes across 174-frame doors and 30-frame elevators, native walking legs and no upper-body reload traversal; no full-game acceptance' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
