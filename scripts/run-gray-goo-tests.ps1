[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[switch]$SkipCompile)
$focusedRun=@{
    DomainId='gray-goo-tests'
    TemplateRelativePath='scripts/test-runners/gray-goo-tests/TestLoader.as.template'
    SuiteRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/bullet/BulletComponent/Queue/ToughnessVulnerabilityPipelineTest.as',
        'scripts/类定义/org/flashNight/arki/item/equipment/EquipmentTestSuite.as',
        'scripts/类定义/org/flashNight/gesh/tooltip/test/BuilderContractTest.as',
        'scripts/类定义/org/flashNight/arki/item/equipment/EquipmentIntervalCurveTest.as',
        'scripts/类定义/org/flashNight/arki/render/GrayGooAssetTest.as')
    SuiteFqns=@(
        'org.flashNight.arki.bullet.BulletComponent.Queue.ToughnessVulnerabilityPipelineTest',
        'org.flashNight.arki.item.equipment.EquipmentTestSuite',
        'org.flashNight.gesh.tooltip.test.BuilderContractTest',
        'org.flashNight.arki.item.equipment.EquipmentIntervalCurveTest',
        'org.flashNight.arki.render.GrayGooAssetTest')
    AdditionalAsRelativePaths=@('scripts/类定义/org/flashNight/arki/item/equipment/EquipmentStatProjector.as')
    ExpectedTracePatterns=@(
        '(?m)^=== ToughnessVulnerabilityPipelineTest result: passed=197 failed=0 ===\r?$',
        '(?s)\A(?!.*✗).*\z',
        '(?m)^✓ #208 灰蛊完整档位覆盖与契约审计测试通过\r?$',
        '(?m)^--- BuilderContractTest: 148/148 passed, 0 failed ---\r?$',
        '(?m)^GrayGooRealProfiles passed=true\r?$',
        '(?m)^--- EquipmentIntervalCurveTest: (?<count>[1-9][0-9]*)/\k<count> passed, 0 failed ---\r?$',
        '(?m)^GrayGooAssetTest phases: XML,I,II,III,max,pooled,reuse,zero-loss\r?$',
        '(?m)^GrayGooAssetTest result: passed=37 failed=0\r?$')
    SuccessSummary='Gray-goo profiles, combat, tooltip, rejected previews, real asset stages and pooling'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=60
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
