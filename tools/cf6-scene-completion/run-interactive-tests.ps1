[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=360)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$interactiveRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$interactiveHostSource=Join-Path $interactiveRoot 'scripts/Cf6ActorAppearanceNativeHost'
$interactiveHostTarget=Join-Path $interactiveRoot 'scripts/tmp-cf6-interactive-host'
[void](New-Item -ItemType Directory -Path $interactiveHostTarget -Force)
function Install-InteractiveHostFile([string]$Destination,[byte[]]$Bytes) {
    if(Test-Path -LiteralPath $Destination) {
        $existingBytes=[IO.File]::ReadAllBytes($Destination)
        if([Convert]::ToBase64String($existingBytes) -cne [Convert]::ToBase64String($Bytes)) {
            throw "Existing interactive host source differs; preserve it and reconcile before compiling: $Destination"
        }
        return
    }
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force)
    [IO.File]::WriteAllBytes($Destination,$Bytes)
}
Install-InteractiveHostFile (Join-Path $interactiveHostTarget 'Cf6InteractiveNativeHost.xfl') ([IO.File]::ReadAllBytes((Join-Path $interactiveHostSource 'Cf6ActorAppearanceNativeHost.xfl')))
function Replace-InteractiveHostText([string]$Text,[string]$Before,[string]$After) {
    if(([regex]::Matches($Text,[regex]::Escape($Before))).Count -ne 1) {
        throw "Native host template changed; expected exactly one occurrence of: $Before"
    }
    return $Text.Replace($Before,$After)
}
$interactiveDocument=[IO.File]::ReadAllText((Join-Path $interactiveHostSource 'DOMDocument.xml'))
$interactiveDocument=Replace-InteractiveHostText $interactiveDocument '../scripts/TestLoader.as' '../TestLoader.as'
Install-InteractiveHostFile (Join-Path $interactiveHostTarget 'DOMDocument.xml') ([Text.UTF8Encoding]::new($false).GetBytes($interactiveDocument))
foreach($interactiveHostFile in Get-ChildItem -LiteralPath (Join-Path $interactiveHostSource 'LIBRARY') -Recurse -File) {
    $interactiveRelative=$interactiveHostFile.FullName.Substring($interactiveHostSource.Length+1)
    Install-InteractiveHostFile (Join-Path $interactiveHostTarget $interactiveRelative) ([IO.File]::ReadAllBytes($interactiveHostFile.FullName))
}
$interactivePublish=Join-Path $interactiveHostTarget 'PublishSettings.xml'
$interactivePublishText=[IO.File]::ReadAllText((Join-Path $interactiveHostSource 'PublishSettings.xml'))
# Match the production TestLoader's directory layout for class #include macros.
# Keep the resulting SWF at the repository root for production asset URLs.
$interactivePublishText=Replace-InteractiveHostText $interactivePublishText '<PackagePaths>scripts/类定义;scripts;</PackagePaths>' '<PackagePaths>类定义;</PackagePaths>'
$interactivePublishText=Replace-InteractiveHostText $interactivePublishText '<defaultNames>1</defaultNames>' '<defaultNames>0</defaultNames>'
$interactivePublishText=Replace-InteractiveHostText $interactivePublishText '<flashDefaultName>1</flashDefaultName>' '<flashDefaultName>0</flashDefaultName>'
$interactivePublishText=Replace-InteractiveHostText $interactivePublishText '<flashFileName>Cf6ActorAppearanceNativeHost.swf</flashFileName>' '<flashFileName>../Cf6InteractiveNativeHost.swf</flashFileName>'
Install-InteractiveHostFile $interactivePublish ([Text.UTF8Encoding]::new($false).GetBytes($interactivePublishText))
& (Join-Path $interactiveRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-interactive-props' `
    -CompileTargetRelativePath 'scripts/tmp-cf6-interactive-host/Cf6InteractiveNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6InteractiveNativeHost.swf' `
    -TemplateRelativePath 'tools/cf6-scene-completion/InteractiveTestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6InteractivePropTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6InteractivePropTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6InteractivePropService.as','scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounter.as','scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as') `
    -ExpectedTracePatterns @('(?m)^Cf6InteractivePropTest Tests Passed: 69\r?$', '(?m)^Cf6InteractivePropTest Tests Failed: 0\r?$') `
    -SuccessSummary '69 native prop lifecycle and actual damage settlement assertions; consumer playtest remains separate' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
exit $LASTEXITCODE
