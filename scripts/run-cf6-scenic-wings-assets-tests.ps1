[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$scenicRoot=Split-Path -Parent $PSScriptRoot
$scenicAsset=Join-Path $scenicRoot 'flashswf/backgrounds/cf6/preparation/CF6_ScenicWings.swf'
$scenicHash=(Get-FileHash -LiteralPath $scenicAsset -Algorithm SHA256).Hash.ToLowerInvariant()
if($scenicHash -cne '7bf60ebaf1b5d25a073e28e048a0a8ef52317f9ead95a320ffab39bbaf2ca997') {
    throw "Scenic fixture asset changed; review its new native pixels and source identity: $scenicHash"
}
Write-Output ("CF6 scenic source asset: SHA256=$scenicHash bytes="+(Get-Item -LiteralPath $scenicAsset).Length)
$scenicHostSource=Join-Path $scenicRoot 'scripts/Cf6ActorAppearanceNativeHost'
$scenicHostTarget=Join-Path $scenicRoot 'scripts/tmp-cf6-scenic-wings-assets-host'
function Install-ScenicHostFile([string]$Destination,[byte[]]$Bytes) {
    if(Test-Path -LiteralPath $Destination) {
        if([Convert]::ToBase64String([IO.File]::ReadAllBytes($Destination)) -cne [Convert]::ToBase64String($Bytes)) {
            throw "Changed native test host must be preserved and reconciled: $Destination"
        }
        return
    }
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force)
    [IO.File]::WriteAllBytes($Destination,$Bytes)
}
function Replace-ScenicText([string]$Text,[string]$Before,[string]$After) {
    if(([regex]::Matches($Text,[regex]::Escape($Before))).Count -ne 1) {throw "Native test host template changed: $Before"}
    return $Text.Replace($Before,$After)
}
Install-ScenicHostFile (Join-Path $scenicHostTarget 'Cf6ScenicWingsNativeHost.xfl') ([IO.File]::ReadAllBytes((Join-Path $scenicHostSource 'Cf6ActorAppearanceNativeHost.xfl')))
$scenicDocText=[IO.File]::ReadAllText((Join-Path $scenicHostSource 'DOMDocument.xml'),[Text.Encoding]::UTF8)
$scenicDocText=Replace-ScenicText $scenicDocText '../scripts/TestLoader.as' '../TestLoader.as'
[xml]$scenicDocument=$scenicDocText
# Reuse the existing focused host, without unrelated player/equipment RSL imports.
foreach($scenicNode in @($scenicDocument.SelectNodes("//*[local-name()='symbols']/* | //*[local-name()='elements']/*"))) {
    [void]$scenicNode.ParentNode.RemoveChild($scenicNode)
}
Install-ScenicHostFile (Join-Path $scenicHostTarget 'DOMDocument.xml') ([Text.UTF8Encoding]::new($false).GetBytes($scenicDocument.OuterXml))
$scenicPublish=[IO.File]::ReadAllText((Join-Path $scenicHostSource 'PublishSettings.xml'),[Text.Encoding]::UTF8)
$scenicPublish=Replace-ScenicText $scenicPublish '<PackagePaths>scripts/类定义;scripts;</PackagePaths>' '<PackagePaths>类定义;</PackagePaths>'
$scenicPublish=Replace-ScenicText $scenicPublish '<defaultNames>1</defaultNames>' '<defaultNames>0</defaultNames>'
$scenicPublish=Replace-ScenicText $scenicPublish '<flashDefaultName>1</flashDefaultName>' '<flashDefaultName>0</flashDefaultName>'
$scenicPublish=Replace-ScenicText $scenicPublish '<flashFileName>Cf6ActorAppearanceNativeHost.swf</flashFileName>' '<flashFileName>../Cf6ScenicWingsNativeHost.swf</flashFileName>'
Install-ScenicHostFile (Join-Path $scenicHostTarget 'PublishSettings.xml') ([Text.UTF8Encoding]::new($false).GetBytes($scenicPublish))
& (Join-Path $scenicRoot 'scripts/test-runners/run-focused-testloader.ps1') `
 -DomainId 'cf6-scenic-wings-assets' `
 -CompileTargetRelativePath 'scripts/tmp-cf6-scenic-wings-assets-host/Cf6ScenicWingsNativeHost.xfl' `
 -CompileSwfRelativePath 'Cf6ScenicWingsNativeHost.swf' `
 -TemplateRelativePath 'scripts/test-runners/cf6-scenic-wings-assets/TestLoader.as.template' `
 -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ScenicWingsAssetsTest.as') `
 -SuiteFqns @('org.flashNight.arki.scene.Cf6ScenicWingsAssetsTest') `
 -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as','scripts/类定义/org/flashNight/arki/scene/Cf6ExitGuideService.as','scripts/类定义/org/flashNight/arki/scene/Cf6PropDepthService.as','scripts/类定义/org/flashNight/arki/scene/StageManager.as','scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/BulletQueueProcessor.as') `
 -ExpectedTracePatterns @('(?m)^Cf6ScenicWingsAssetsTest Tests Passed: 39\r?$', '(?m)^Cf6ScenicWingsAssetsTest Tests Failed: 0\r?$') `
 -SuccessSummary '39 actual pink NPC Wings/production loader/depth/hit rejection/lifecycle and real clear-cue assertions; no full-game visual acceptance' `
 -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
