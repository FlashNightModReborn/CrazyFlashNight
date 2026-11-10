[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$hostSource=Join-Path $PSScriptRoot 'ShootReloadNativeHost'
$hostTarget=Join-Path $PSScriptRoot 'tmp-shoot-reload-native-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
foreach($hostFile in @('ShootReloadNativeHost.xfl','DOMDocument.xml','PublishSettings.xml','LIBRARY')) {
    $hostInput=Join-Path $hostSource $hostFile
    $hostOutput=Join-Path $hostTarget $hostFile
    if((Test-Path -LiteralPath $hostInput -PathType Leaf) -and (Test-Path -LiteralPath $hostOutput) -and
        (Get-FileHash -LiteralPath $hostInput).Hash -eq (Get-FileHash -LiteralPath $hostOutput).Hash){continue}
    Copy-Item -LiteralPath $hostInput -Destination $hostTarget -Recurse -Force
}
# Native host shares the ordinary TestLoader class/include base (scripts/).
$utf8=[Text.UTF8Encoding]::new($false)
$hostDom=[IO.File]::ReadAllText((Join-Path $hostSource 'DOMDocument.xml'),$utf8).Replace('../scripts/TestLoader.as','../TestLoader.as')
[IO.File]::WriteAllText((Join-Path $hostTarget 'DOMDocument.xml'),$hostDom,$utf8)
$hostSettings=[IO.File]::ReadAllText((Join-Path $hostSource 'PublishSettings.xml'),$utf8).
    Replace('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>').
    Replace('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>').
    Replace('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>').
    Replace('<flashFileName>ShootReloadNativeHost.swf</flashFileName>','<flashFileName>../ShootReloadNativeHost.swf</flashFileName>')
[IO.File]::WriteAllText((Join-Path $hostTarget 'PublishSettings.xml'),$hostSettings,$utf8)
$suites=@('arki.unit.Action.Shoot.ShootReloadTimelineTest','arki.unit.Action.Shoot.ShootReloadCadenceTest',
    'arki.unit.Action.Shoot.GunslingerDualCadenceTest','arki.unit.Action.Shoot.DualGunReloadTimelineTest',
    'arki.unit.Action.Shoot.WeaponAmmoRuntimeTest','arki.unit.Action.Shoot.LongGunSubWeaponCoreTest',
    'arki.unit.Action.Shoot.PistolRecoilCoreTest','arki.unit.Action.Skill.ManualCooldownServiceTest',
    'arki.unit.Action.Skill.DrugInputServiceTest','arki.key.KeyManagerTest',
    'arki.scene.StageIntroServiceTest','arki.scene.BookRunRulesTest',
    'arki.scene.Cf6BookRunStoryTest','arki.scene.Cf6TraversalLifecycleTest','neur.Server.Issue205SourceProbeTest')
$focusedRun=@{
    DomainId='shoot-reload-timeline'
    CompileTargetRelativePath='scripts/tmp-shoot-reload-native-host/ShootReloadNativeHost.xfl'
    CompileSwfRelativePath='ShootReloadNativeHost.swf'
    TemplateRelativePath='scripts/test-runners/shoot-reload-timeline/TestLoader.as.template'
    SuiteRelativePaths=@($suites | ForEach-Object {'scripts/类定义/org/flashNight/'+$_.Replace('.','/')+'.as'})
    SuiteFqns=@($suites | ForEach-Object {'org.flashNight.'+$_})
    AdditionalAsRelativePaths=@(
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransitionPlanTest.as',
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransitionTest.as',
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransitionPlan.as',
        'scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransition.as',
        'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ReloadManager.as',
        'scripts/类定义/org/flashNight/arki/unit/Action/Skill/SkillReloadCore.as',
        'scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as',
        'scripts/类定义/org/flashNight/arki/unit/UnitAI/core/AIEnvironment.as',
        'scripts/逻辑/单位函数/单位函数_fs_空中控制器.as',
        'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as',
        'scripts/逻辑/单位函数/单位函数_lsy_主角行走状态机.as',
        'scripts/逻辑/单位函数/单位函数_lsy_主角技能.as',
        'scripts/类定义/org/flashNight/arki/scene/StageManager.as',
        'scripts/类定义/org/flashNight/arki/scene/BookRunRules.as',
        'scripts/类定义/org/flashNight/arki/scene/BookRunService.as',
        'scripts/类定义/org/flashNight/arki/scene/StageIntroService.as',
        'scripts/类定义/org/flashNight/arki/scene/Cf6TraversalService.as',
        'scripts/类定义/org/flashNight/arki/scene/Cf6MapMechanism.as',
        'scripts/类定义/org/flashNight/arki/scene/Cf6VehicleService.as',
        'scripts/类定义/org/flashNight/arki/scene/Cf6BossEncounter.as',
        'scripts/类定义/org/flashNight/arki/scene/Cf6TutorialTurretService.as',
        'scripts/类定义/org/flashNight/arki/scene/BookRunClock.as',
        'scripts/类定义/org/flashNight/arki/scene/StageRunSession.as')
    ExpectedTracePatterns=@(
        '(?m)^--- ShootReloadTimelineTest: (?<native>[1-9][0-9]*)/\k<native> passed, 0 failed ---\r?$',
        '(?m)^--- ShootReloadCadenceTest: (?<cadence>[1-9][0-9]*)/\k<cadence> passed, 0 failed ---\r?$',
        '(?m)^--- DualGunReloadTimelineTest: (?<dual>[1-9][0-9]*)/\k<dual> passed, 0 failed ---\r?$',
        '(?m)^--- GunslingerDualCadenceTest: (?<gunslinger>[1-9][0-9]*)/\k<gunslinger> passed, 0 failed ---\r?$',
        '(?m)^--- WeaponAmmoRuntimeTest: (?<ammo>[1-9][0-9]*)/\k<ammo> passed, 0 failed ---\r?$',
        '(?m)^--- LongGunSubWeaponCoreTest: 511/511 passed, 0 failed ---\r?$',
        '(?m)^--- PistolRecoilCoreTest: (?<pistol>[1-9][0-9]*)/\k<pistol> passed, 0 failed ---\r?$',
        '(?m)^--- ManualCooldownServiceTest: 57/57 passed, 0 failed ---\r?$',
        '(?m)^--- DrugInputServiceTest: 58/58 passed, 0 failed ---\r?$',
        '(?m)^--- KeyManagerMigrationTest: 14/14 passed, 0 failed ---\r?$',
        '(?m)^--- A1MovementAdmissionTest: (?<a1move>[1-9][0-9]*)/\k<a1move> passed, 0 failed ---\r?$',
        '(?m)^StateTransitionPlan Test Suite\r?\n[\s\S]*?^Results: (?<stplan>[1-9][0-9]*)/\k<stplan> passed, 0 failed \([0-9]+ms\)\r?$',
        '(?m)^StateTransition Test Suite\r?\n[\s\S]*?^Results: (?<stapply>[1-9][0-9]*)/\k<stapply> passed, 0 failed \([0-9]+ms\)\r?$',
        '(?m)^StageIntroServiceTest Tests Passed: [1-9][0-9]*\r?\nStageIntroServiceTest Tests Failed: 0\r?$',
        '(?m)^BookRunRulesTest Tests Passed: [1-9][0-9]*\r?\nBookRunRulesTest Tests Failed: 0\r?$',
        '(?m)^Cf6BookRunStoryTest Tests Passed: [1-9][0-9]*\r?\nCf6BookRunStoryTest Tests Failed: 0\r?$',
        '(?m)^Cf6TraversalLifecycleTest Tests Passed: [1-9][0-9]*\r?\nCf6TraversalLifecycleTest Tests Failed: 0\r?$', '(?m)^Issue205SourceProbeTest Tests Passed: 14\r?$', '(?m)^Issue205SourceProbeTest Tests Failed: 0\r?$')
    SuccessSummary='Real character reload cadence, ammo, dual-hand recoil, movement/state-transition admission, stage intro and CF6 book-run/traversal regression'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=180
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
