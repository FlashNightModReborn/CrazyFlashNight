[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=420,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$visualRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
python -X utf8 -B (Join-Path $PSScriptRoot 'prepare.py') --check
if($LASTEXITCODE -ne 0){throw 'Native item visual fixture differs from its source identities.'}
& (Join-Path $visualRoot 'scripts/test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-item-visuals' `
    -CompileTargetRelativePath 'tmp-cf6-item-visuals-host/Cf6ItemVisualNativeHost.xfl' `
    -CompileSwfRelativePath 'Cf6ItemVisualNativeHost.swf' `
    -TemplateRelativePath 'tools/cf6-item-visuals/TestLoader.as.template' `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6ItemVisualTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6ItemVisualTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/gesh/xml/XMLParser.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Dressup/DressupReferenceManager.as') `
    -ExpectedTracePatterns @('(?m)^Cf6ItemVisualTest Tests Passed: 54\r?$','(?m)^Cf6ItemVisualTest Tests Failed: 0\r?$') `
    -SuccessSummary '54 actual XML/CAR RSL/native full-rack/icon pixels plus exact native walking phase, stable/hide/restore real-frame and no-crop controls; no save/game claim' `
    -AsyncBehaviorTimeoutSeconds 90 -TimeoutSeconds $TimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
