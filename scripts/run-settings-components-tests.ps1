[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$suiteFqns=@('org.flashNight.arki.ui.GameSettingsPanelServiceTest','org.flashNight.arki.ui.GaragePurchasePanelServiceTest',
    'org.flashNight.arki.ui.GymTrainingPanelServiceTest','org.flashNight.neur.Server.test.SettingsAuthorityComponentTest')
$suitePaths=@('scripts/类定义/org/flashNight/arki/ui/GameSettingsPanelServiceTest.as','scripts/类定义/org/flashNight/arki/ui/GaragePurchasePanelServiceTest.as',
    'scripts/类定义/org/flashNight/arki/ui/GymTrainingPanelServiceTest.as','scripts/类定义/org/flashNight/neur/Server/test/SettingsAuthorityComponentTest.as')
$patterns=@(foreach($name in $suiteFqns) {
    $short=$name.Split('.')[-1]
    '(?m)^'+$short+' Tests Passed: [1-9][0-9]*\r?$'
    '(?m)^'+$short+' Tests Failed: 0\r?$'
})
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId 'settings-components' `
    -TemplateRelativePath 'scripts/test-runners/settings-components/TestLoader.as.template' `
    -SuiteRelativePaths $suitePaths -SuiteFqns $suiteFqns -ExpectedTracePatterns $patterns `
    -SuccessSummary 'real AS2 services; synthetic roots; all apply paths stop before SO access' `
    -TimeoutSeconds $TimeoutSeconds -AutoStopReadOnlyPlayer -OwnedReadOnlyHost
