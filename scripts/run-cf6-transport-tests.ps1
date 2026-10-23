[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$hostSource=Join-Path $PSScriptRoot 'Cf6ActorAppearanceNativeHost'
$hostTarget=Join-Path $projectDir 'tmp-cf6-transport-native-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
Copy-Item -LiteralPath (Join-Path $hostSource 'Cf6ActorAppearanceNativeHost.xfl') -Destination (Join-Path $hostTarget 'Cf6TransportNativeHost.xfl') -Force
[xml]$doc=[IO.File]::ReadAllText((Join-Path $hostSource 'DOMDocument.xml'),[Text.Encoding]::UTF8)
foreach($node in @($doc.SelectNodes("//*[local-name()='symbols']/* | //*[local-name()='elements']/*"))) {[void]$node.ParentNode.RemoveChild($node)}
$doc.Save((Join-Path $hostTarget 'DOMDocument.xml'))
$publish=[IO.File]::ReadAllText((Join-Path $hostSource 'PublishSettings.xml'),[Text.Encoding]::UTF8).Replace('Cf6ActorAppearanceNativeHost.swf','Cf6TransportNativeHost.swf')
[IO.File]::WriteAllText((Join-Path $hostTarget 'PublishSettings.xml'),$publish,[Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
 -DomainId 'cf6-transport' `
 -CompileTargetRelativePath 'tmp-cf6-transport-native-host/Cf6TransportNativeHost.xfl' `
 -CompileSwfRelativePath 'Cf6TransportNativeHost.swf' `
 -TemplateRelativePath 'scripts/test-runners/cf6-transport/TestLoader.as.template' `
 -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TransportTest.as') `
 -SuiteFqns @('org.flashNight.arki.scene.Cf6TransportTest') `
 -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6TransportService.as','scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as') `
 -ExpectedTracePatterns @('(?m)^Cf6TransportTest Tests Passed: 63\r?$', '(?m)^Cf6TransportTest Tests Failed: 0\r?$') `
 -SuccessSummary '63 actual transport SWF and event-wheel reservation/ownership/unknown-delivery assertions' `
 -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
