[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$run=@{
    DomainId='ai-diagnostics'
    TemplateRelativePath='scripts/test-runners/ai-diagnostics/TestLoader.as.template'
    SuiteRelativePaths=@('scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/AIDiagnosticsTest.as')
    SuiteFqns=@('org.flashNight.arki.unit.UnitAI.combat.AIDiagnosticsTest')
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/WeaponEvaluator.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/UtilityEvaluator.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/DecisionTrace.as'
        'scripts/类定义/org/flashNight/arki/unit/UnitAI/combat/scoring/ScoringPipeline.as'
        'scripts/类定义/org/flashNight/arki/unit/PlayerInfoProvider.as'
    )
    ExpectedTracePatterns=@(
        '(?m)^AIDiagnosticsTest Tests Passed: [1-9][0-9]*\r?$'
        '(?m)^AIDiagnosticsTest Tests Failed: 0\r?$'
    )
    SuccessSummary='AI diagnostic flag parity, actual score/selection/RNG and post-switch DPS cache timing'
    TimeoutSeconds=$TimeoutSeconds
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @run
