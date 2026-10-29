[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
 -DomainId 'cf6-native-background' `
 -TemplateRelativePath 'scripts/test-runners/cf6-native-background/TestLoader.as.template' `
 -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6NativeBackgroundContractTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanismTest.as') `
 -SuiteFqns @('org.flashNight.arki.scene.Cf6NativeBackgroundContractTest','org.flashNight.arki.scene.Cf6MapMechanismTest') `
 -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapPresentation.as','scripts/类定义/org/flashNight/arki/scene/SceneManager.as','scripts/逻辑/关卡系统/关卡系统_lsy_add2map_加载背景.as') `
 -ExpectedTracePatterns @('(?m)^Cf6NativeBackgroundContractTest Tests Passed: 6\r?$','(?m)^Cf6NativeBackgroundContractTest Tests Failed: 0\r?$','(?m)^Cf6MapMechanismTest Tests Passed: 238\r?$','(?m)^Cf6MapMechanismTest Tests Failed: 0\r?$') `
 -SuccessSummary '6 actual A01 background assertions plus 238 mechanism assertions; production bake and native unload, no full game claim' `
 -AsyncBehaviorTimeoutSeconds 90 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
