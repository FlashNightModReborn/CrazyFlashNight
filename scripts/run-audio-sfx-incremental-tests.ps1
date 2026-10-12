[CmdletBinding()]
param([int]$TimeoutSeconds=240)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$run=@{
 DomainId='audio-sfx-incremental'
 TemplateRelativePath='scripts/test-runners/audio-sfx-incremental/TestLoader.as.template'
 SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeSfxIncrementalTest.as')
 SuiteFqns=@('org.flashNight.arki.audio.test.AudioBridgeSfxIncrementalTest')
 AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/audio/AudioBridge.as','scripts/类定义/org/flashNight/arki/audio/test/AudioBridgeSfxLegacyFixture.as')
 ExpectedTracePatterns=@('(?m)^AudioBridgeSfxIncrementalTest Tests Passed: [1-9][0-9]*\r?$','(?m)^AudioBridgeSfxIncrementalTest Tests Failed: 0\r?$')
 SuccessSummary='S2 incremental byte count matches frozen production lifecycle and wire'
 TimeoutSeconds=$TimeoutSeconds
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
exit $LASTEXITCODE
