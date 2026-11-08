[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=900,[ValidateRange(1,3600)][int]$AsyncBehaviorTimeoutSeconds=1800,[switch]$SkipCompile,[switch]$LifetimeOnly,[switch]$AllForms)
$ErrorActionPreference='Stop'
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-firepower-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-actions-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-type61/build-fixed-roster-fixture.py') --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$consumerFlag=if($AllForms){'--firepower-projectiles'}else{'--projectiles'}
& python -X utf8 -B (Join-Path $PSScriptRoot '../tools/cf6-soldier-assets/build-fixed-test-consumer.py') $consumerFlag
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$template='scripts/test-runners/cf6-fixed-projectiles/TestLoader.as.template'
$birthPattern='[1-9]\d*';$materializations=158;$cases=37
if($AllForms){
    if($LifetimeOnly){throw 'AllForms and LifetimeOnly are independent scopes'}
    $root=Split-Path -Parent $PSScriptRoot
    $source=Join-Path $root $template
    $template='tmp/cf6-fixed-projectiles-all-forms/TestLoader.as.template'
    $target=Join-Path $root $template
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
    Copy-Item -LiteralPath $source -Destination $target -Force
    [IO.File]::WriteAllText($target,('_root.cf6AdmissionAllForms=true;' + "`n" + [IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)),[Text.UTF8Encoding]::new($true))
    $finalSource=Get-Content -LiteralPath (Join-Path $root 'tools/cf6-type61/fixed-roster.source.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $cases=37+@($finalSource.admission.forms).Count
}
if ($LifetimeOnly) {
    $root=Split-Path -Parent $PSScriptRoot
    $source=Join-Path $root $template
    $template='tmp/cf6-fixed-projectiles-lifetime/TestLoader.as.template'
    $target=Join-Path $root $template
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
    Copy-Item -LiteralPath $source -Destination $target -Force
    $body='_root.cf6ProjectileLifetimeOnly=true;' + "`n" + [IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($target,$body,[Text.UTF8Encoding]::new($true))
    $birthPattern='\d+';$materializations=0;$cases=2
}
$hostName=if($AllForms){'Cf6FirepowerProjectileHost'}else{'Cf6FixedProjectileHost'}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'cf6-fixed-projectiles' `
    -CompileTargetRelativePath ("scripts/$hostName/$hostName.xfl") `
    -CompileSwfRelativePath ("scripts/$hostName.swf") `
    -TemplateRelativePath $template `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6FixedSoldierNativeTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsTest.as','scripts/类定义/org/flashNight/arki/scene/Cf6SoldierFirepowerTest.as') `
    -SuiteFqns @('org.flashNight.arki.scene.Cf6FixedSoldierNativeTest','org.flashNight.arki.scene.Cf6FixedActionsTest','org.flashNight.arki.scene.Cf6SoldierFirepowerTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/scene/Cf6SoldierFirepowerFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedActionsFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedRosterFixture.as','scripts/类定义/org/flashNight/arki/scene/Cf6FixedProjectileHarness.as') `
    -ExpectedTracePatterns @('(?m)^Cf6SoldierFirepowerTest: [1-9]\d* passed, 0 failed; 282 independent slot anchors\r?$',("(?m)^Cf6FixedProjectileHarness: [1-9]\d* actual births, $birthPattern collision settlements, 0 failed\r?$"),'(?m)^Cf6FixedActionsTest: \d+ passed, 0 failed; 22 same-source cycles and native ownership\r?$',("(?m)^Cf6FixedSoldierNativeTest: \d+ passed, 0 failed; $materializations fixed materializations, $cases native action cases\r?$")) `
    -SuccessSummary 'Fixed158 real actor, factory, collision and projectile retirement; controlled damage magnitude and target observations' `
    -TimeoutSeconds $TimeoutSeconds -AsyncBehaviorTimeoutSeconds $AsyncBehaviorTimeoutSeconds -SkipCompile:$SkipCompile
exit $LASTEXITCODE
