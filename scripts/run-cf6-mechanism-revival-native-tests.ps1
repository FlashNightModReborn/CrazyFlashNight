[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$revivalRoot=Split-Path -Parent $PSScriptRoot
foreach($revivalMap in @('A10','A13')) {
    $revivalAsset=Join-Path $revivalRoot "flashswf/backgrounds/cf6/CF6_${revivalMap}_elevator-scroll.swf"
    if(!(Test-Path -LiteralPath $revivalAsset -PathType Leaf)) {throw "Missing actual elevator resource: $revivalAsset"}
    Write-Output ("CF6 revival elevator asset: map=$revivalMap SHA256="+(Get-FileHash -LiteralPath $revivalAsset -Algorithm SHA256).Hash+" bytes="+(Get-Item -LiteralPath $revivalAsset).Length)
}
$revivalHostSource=Join-Path $revivalRoot 'scripts/Cf6ActorAppearanceNativeHost'
$revivalHostTarget=Join-Path $revivalRoot 'scripts/tmp-cf6-mechanism-revival-host'
function Install-RevivalHostFile([string]$Destination,[byte[]]$Bytes) {
    if(Test-Path -LiteralPath $Destination) {
        if([Convert]::ToBase64String([IO.File]::ReadAllBytes($Destination)) -cne [Convert]::ToBase64String($Bytes)) {
            throw "Changed native test host must be preserved and reconciled: $Destination"
        }
        return
    }
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force)
    [IO.File]::WriteAllBytes($Destination,$Bytes)
}
function Replace-RevivalText([string]$Text,[string]$Before,[string]$After) {
    if(([regex]::Matches($Text,[regex]::Escape($Before))).Count -ne 1) {throw "Native test host template changed: $Before"}
    return $Text.Replace($Before,$After)
}
Install-RevivalHostFile (Join-Path $revivalHostTarget 'Cf6MechanismRevivalNativeHost.xfl') ([IO.File]::ReadAllBytes((Join-Path $revivalHostSource 'Cf6ActorAppearanceNativeHost.xfl')))
$revivalDocText=[IO.File]::ReadAllText((Join-Path $revivalHostSource 'DOMDocument.xml'),[Text.Encoding]::UTF8)
$revivalDocText=Replace-RevivalText $revivalDocText '../scripts/TestLoader.as' '../TestLoader.as'
[xml]$revivalDocument=$revivalDocText
# Keep the existing CS6 host profile and actual loader, without unrelated player/equipment RSL imports.
foreach($revivalNode in @($revivalDocument.SelectNodes("//*[local-name()='symbols']/* | //*[local-name()='elements']/*"))) {
    [void]$revivalNode.ParentNode.RemoveChild($revivalNode)
}
Install-RevivalHostFile (Join-Path $revivalHostTarget 'DOMDocument.xml') ([Text.UTF8Encoding]::new($false).GetBytes($revivalDocument.OuterXml))
$revivalPublish=[IO.File]::ReadAllText((Join-Path $revivalHostSource 'PublishSettings.xml'),[Text.Encoding]::UTF8)
$revivalPublish=Replace-RevivalText $revivalPublish '<PackagePaths>scripts/类定义;scripts;</PackagePaths>' '<PackagePaths>类定义;</PackagePaths>'
$revivalPublish=Replace-RevivalText $revivalPublish '<defaultNames>1</defaultNames>' '<defaultNames>0</defaultNames>'
$revivalPublish=Replace-RevivalText $revivalPublish '<flashDefaultName>1</flashDefaultName>' '<flashDefaultName>0</flashDefaultName>'
$revivalPublish=Replace-RevivalText $revivalPublish '<flashFileName>Cf6ActorAppearanceNativeHost.swf</flashFileName>' '<flashFileName>../Cf6MechanismRevivalNativeHost.swf</flashFileName>'
Install-RevivalHostFile (Join-Path $revivalHostTarget 'PublishSettings.xml') ([Text.UTF8Encoding]::new($false).GetBytes($revivalPublish))
Write-Output 'CF6 revival native host prepared: root output Cf6MechanismRevivalNativeHost.swf; real root-relative elevator resource URLs unchanged'
if($PrepareOnly) {return}
& (Join-Path $revivalRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-mechanism-revival' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-mechanism-revival-host/Cf6MechanismRevivalNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6MechanismRevivalNativeHost.swf' `
    -TemplateRelativePath 'scripts/test-runners/cf6-mechanism-revival/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MechanismRevivalTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6MechanismRevivalTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as','scripts/类定义/org/flashNight/arki/scene/StageRunSession.as','scripts/类定义/org/flashNight/arki/scene/BookRunService.as') `
    -ExpectedTracePatterns @('(?m)^Cf6MechanismRevivalTest Tests Passed: 92\r?$','(?m)^Cf6MechanismRevivalTest Tests Failed: 0\r?$') `
    -SuccessSummary '92 native assertions: same-world revival, actual elevators, frozen traversal and fresh depth ownership; memory run, no coins or saves' `
    -AsyncBehaviorTimeoutSeconds 120 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
