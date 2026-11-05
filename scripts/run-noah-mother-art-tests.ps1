[CmdletBinding()]
param([int]$TimeoutSeconds=240,[string]$LegacyMaskControlPath='')
$ErrorActionPreference='Stop'
$template='scripts/test-runners/noah-mother-art/TestLoader.as.template'
$count=31
if($LegacyMaskControlPath){
    $source=(Get-Item -LiteralPath $LegacyMaskControlPath -ErrorAction Stop).FullName
    $targetDir=Join-Path (Split-Path -Parent $PSScriptRoot) 'tmp/noah-mother-v2'
    New-Item -ItemType Directory -Path $targetDir -Force > $null
    $target=Join-Path $targetDir 'giant-v1.swf'
    if($source -ne $target){Copy-Item -LiteralPath $source -Destination $target -Force}
    $template='scripts/test-runners/noah-mother-art/TestLoader.legacy-mask.as.template'
    $count=32
}
& (Join-Path $PSScriptRoot 'test-runners\run-focused-testloader.ps1') -DomainId 'noah-mother-art' -TemplateRelativePath $template -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/NoahMotherArtTest.as') -SuiteFqns @('org.flashNight.arki.scene.NoahMotherArtTest') -ExpectedTracePatterns @("(?m)^NoahMotherArtTest Tests Passed: $count\r?$",'(?m)^NoahMotherArtTest Tests Failed: 0\r?$') -SuccessSummary "$count native art assertions: masks, phase bursts, death and persistent pools" -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds 180
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
