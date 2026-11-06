[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
# A separate disposable native host; the passed appearance fixture remains unchanged.
$hostSource=Join-Path $PSScriptRoot 'Cf6ActorAppearanceNativeHost'
$hostTarget=Join-Path $PSScriptRoot 'tmp-cf6-traversal-native-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
foreach($file in @('DOMDocument.xml','PublishSettings.xml','LIBRARY')) {
    Copy-Item -LiteralPath (Join-Path $hostSource $file) -Destination $hostTarget -Recurse -Force
}
$hostEntry=Join-Path $hostTarget 'Cf6TraversalNativeHost.xfl'
$sourceEntry=Join-Path $hostSource 'Cf6ActorAppearanceNativeHost.xfl'
if(!(Test-Path -LiteralPath $hostEntry)) {Copy-Item -LiteralPath $sourceEntry -Destination $hostEntry}
elseif((Get-FileHash -LiteralPath $hostEntry).Hash -cne (Get-FileHash -LiteralPath $sourceEntry).Hash) {throw 'Native host entry differs; preserve and reconcile before replacing it'}
$dom=Join-Path $hostTarget 'DOMDocument.xml'
$domText=[IO.File]::ReadAllText($dom,[Text.Encoding]::UTF8).Replace('../scripts/TestLoader.as','../TestLoader.as')
[IO.File]::WriteAllText($dom,$domText,[Text.UTF8Encoding]::new($false))
$publish=Join-Path $hostTarget 'PublishSettings.xml'
$text=[IO.File]::ReadAllText($publish,[Text.Encoding]::UTF8).Replace('Cf6ActorAppearanceNativeHost.swf','../Cf6TraversalNativeHost.swf').Replace('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>').Replace('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>').Replace('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>')
[IO.File]::WriteAllText($publish,$text,[Text.UTF8Encoding]::new($false))
if($PrepareOnly) {return}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-traversal-native' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-traversal-native-host/Cf6TraversalNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6TraversalNativeHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-traversal-native/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TraversalNativeTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6TraversalNativeTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalRules.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6ActorMaskState.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransition.as') `
    -ExpectedTracePatterns @('(?m)^Cf6TraversalNativeTest Tests Passed: 121\r?$', '(?m)^Cf6TraversalNativeTest Tests Failed: 0\r?$') `
    -SuccessSummary '112 native player/state/traversal assertions with elevator standing hold: three gun modes across 174-frame doors and 30-frame elevators, native walking legs and no upper-body reload traversal; no full-game acceptance' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
