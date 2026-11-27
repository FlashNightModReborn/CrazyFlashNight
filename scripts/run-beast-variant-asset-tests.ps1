param([int]$TimeoutSeconds = 180, [int]$AsyncBehaviorTimeoutSeconds = 60)
$ErrorActionPreference = 'Stop'
$beastPatterns = @('BeastVariantAssetTest: \d+ passed, 0 failed; 169 actual attack frames')
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') -DomainId beast-variant -TemplateRelativePath 'scripts/test-runners/beast-variant/TestLoader.as.template' -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/BeastVariantAssetTest.as' -SuiteFqns 'org.flashNight.arki.unit.Action.Melee.BeastVariantAssetTest' -ExpectedTracePatterns $beastPatterns -SuccessSummary '兽化变种僵尸两种攻击及分隔帧的原生像素专项通过' -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
