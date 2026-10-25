[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=600)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$encoding=[Text.Encoding]::UTF8
$main=[IO.File]::ReadAllText((Join-Path $root 'scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as'),$encoding)
$bullet=[IO.File]::ReadAllText((Join-Path $root 'scripts/逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as'),$encoding)
$bonus=[regex]::Match($main,'(?ms)^_root\.主角函数\.根据模式重新读取武器加成 = function\(模式\) \{.*?^\}').Value
$init=[regex]::Match($bullet,'(?ms)^_root\.子弹属性初始化 = function.*?^\}').Value
$legacy=[regex]::Match($bullet,'(?ms)^_root\.子弹区域shoot = function.*?^\}').Value
if(!$bonus -or !$init -or !$legacy){throw 'Production helper extraction did not match; refusing stale copied functions.'}
$imports=([regex]::Matches([IO.File]::ReadAllText((Join-Path $root 'scripts/asLoaderManifest/_collapsed_frame.as'),$encoding),'(?m)^import [^;]+;')|ForEach-Object {$_.Value}) -join "`n"
$template=[IO.File]::ReadAllText((Join-Path $root 'scripts/test-runners/skill-container-transition/TestLoader.as.template'),$encoding).
    Replace('__PRODUCTION_IMPORTS__',$imports).Replace('__PRODUCTION_BONUS__',$bonus).Replace('__PRODUCTION_BULLET_INIT__',$init).Replace('__PRODUCTION_LEGACY_SHOOT__',$legacy)
$relative='tmp/skill-container-transition/TestLoader.as.template'
$target=Join-Path $root $relative
[void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
Copy-Item -LiteralPath (Join-Path $root 'scripts/test-runners/cf6-exit-guide/TestLoader.as.template') -Destination $target -Force
[IO.File]::WriteAllText($target,$template,[Text.UTF8Encoding]::new($true))
$hostSource=Join-Path $PSScriptRoot 'ShootReloadNativeHost'
$hostTarget=Join-Path $PSScriptRoot 'tmp-skill-container-native-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
foreach($file in @('ShootReloadNativeHost.xfl','DOMDocument.xml','PublishSettings.xml','LIBRARY')) {
    $inputPath=Join-Path $hostSource $file
    $outputPath=Join-Path $hostTarget $file
    if((Test-Path -LiteralPath $inputPath -PathType Leaf) -and (Test-Path -LiteralPath $outputPath) -and
        (Get-FileHash -LiteralPath $inputPath).Hash -eq (Get-FileHash -LiteralPath $outputPath).Hash){continue}
    Copy-Item -LiteralPath $inputPath -Destination $outputPath -Recurse -Force
}
$hostDom=[IO.File]::ReadAllText((Join-Path $hostSource 'DOMDocument.xml'),$encoding).Replace('../scripts/TestLoader.as','../TestLoader.as')
[IO.File]::WriteAllText((Join-Path $hostTarget 'DOMDocument.xml'),$hostDom,[Text.UTF8Encoding]::new($false))
$hostSettings=[IO.File]::ReadAllText((Join-Path $hostSource 'PublishSettings.xml'),$encoding).
    Replace('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>').
    Replace('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>').
    Replace('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>').
    Replace('<flashFileName>ShootReloadNativeHost.swf</flashFileName>','<flashFileName>../SkillContainerTransitionNativeHost.swf</flashFileName>')
[IO.File]::WriteAllText((Join-Path $hostTarget 'PublishSettings.xml'),$hostSettings,[Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') `
    -DomainId 'skill-container-transition' `
    -CompileTargetRelativePath 'scripts/tmp-skill-container-native-host/ShootReloadNativeHost.xfl' `
    -CompileSwfRelativePath 'SkillContainerTransitionNativeHost.swf' `
    -TemplateRelativePath $relative `
    -SuiteRelativePaths @('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/SkillContainerTransitionTest.as') `
    -SuiteFqns @('org.flashNight.arki.unit.UnitComponent.Routing.SkillContainerTransitionTest') `
    -AdditionalAsRelativePaths @('scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransition.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/StateTransitionTest.as','scripts/逻辑/单位函数/单位函数_lsy_主角技能.as','scripts/引擎/引擎_fs_技能路由.as','scripts/引擎/引擎_fs_战技路由.as','scripts/类定义/org/flashNight/arki/unit/UnitComponent/Routing/RoutingLifecycle.as','scripts/类定义/org/flashNight/arki/unit/Action/Melee/BladeShootCore.as','scripts/类定义/org/flashNight/arki/unit/Action/Skill/IchimonjiMovement.as','scripts/逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as') `
    -ExpectedTracePatterns @('(?m)^SkillContainerTransitionTest Tests Passed: 46\r?$','(?m)^SkillContainerTransitionTest Tests Failed: 0\r?$') `
    -SuccessSummary 'Actual things0 skill timelines, production routing and attribute functions; disposable unit fixture, no full-game hit acceptance' `
    -AsyncBehaviorTimeoutSeconds 180 -TimeoutSeconds $TimeoutSeconds
