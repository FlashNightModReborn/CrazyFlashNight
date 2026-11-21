[CmdletBinding()]
param([ValidateRange(1, 3600)][int]$TimeoutSeconds = 240, [switch]$SkipCompile)
$ErrorActionPreference = 'Stop'
[xml]$stageXml = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../data/stages/基地车库/据点M.xml') -Raw -Encoding UTF8
$controlRoom = $stageXml.GameStage.SubStage | Where-Object { $_.id -eq '4' }
if ($null -eq $controlRoom -or $controlRoom.Trigger.Xmin -ne '600') {
    throw 'Control room must expose the gate interaction trigger at x=600.'
}
$gateEvent = $controlRoom.Event | Where-Object { $_.EventName -eq 'TriggerPressed' }
if ($null -eq $gateEvent -or $gateEvent.Parameter -ne '0' -or $gateEvent.StageProgress -ne 'ForceFinishWave') {
    throw 'Gate interaction must publish ForceFinishWave.'
}
$openingWave = $controlRoom.Wave.SubWave | Where-Object { $_.id -eq '0' }
if ($null -eq $openingWave -or $openingWave.WaveInformation.FinishRequirement -ne '-1') {
    throw 'The first wave must not finish automatically before gate interaction.'
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'stage-m-control-room' `
    -TemplateRelativePath 'scripts/test-runners/stage-m-control-room/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/StageMControlRoomTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.StageMControlRoomTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/WaveSpawner.as') `
    -ExpectedTracePatterns @('(?m)^StageMControlRoomTest Tests Passed: 2\r?$', '(?m)^StageMControlRoomTest Tests Failed: 0\r?$') `
    -SuccessSummary '2/2 interaction-gated first-wave assertions plus exact control-room XML contract; no full game claim' `
    -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
