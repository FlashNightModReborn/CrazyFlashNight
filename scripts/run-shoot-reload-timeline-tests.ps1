[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$SkipCompile)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$hostSource=Join-Path $PSScriptRoot 'ShootReloadNativeHost'
$hostTarget=Join-Path $projectDir 'tmp-shoot-reload-native-host'
[void](New-Item -ItemType Directory -Path $hostTarget -Force)
foreach($hostFile in @('ShootReloadNativeHost.xfl','DOMDocument.xml','PublishSettings.xml','LIBRARY')) {
    $hostInput=Join-Path $hostSource $hostFile
    $hostOutput=Join-Path $hostTarget $hostFile
    if((Test-Path -LiteralPath $hostInput -PathType Leaf) -and (Test-Path -LiteralPath $hostOutput) -and
        (Get-FileHash -LiteralPath $hostInput).Hash -eq (Get-FileHash -LiteralPath $hostOutput).Hash){continue}
    Copy-Item -LiteralPath $hostInput -Destination $hostTarget -Recurse -Force
}
$suites=@('arki.unit.Action.Shoot.ShootReloadTimelineTest','arki.unit.Action.Shoot.ShootReloadCadenceTest',
    'arki.unit.Action.Shoot.GunslingerDualCadenceTest',
    'arki.unit.Action.Shoot.WeaponAmmoRuntimeTest','arki.unit.Action.Shoot.LongGunSubWeaponCoreTest',
    'arki.unit.Action.Shoot.PistolRecoilCoreTest','arki.unit.Action.Skill.ManualCooldownServiceTest',
    'arki.unit.Action.Skill.DrugInputServiceTest','arki.key.KeyManagerTest')
$focusedRun=@{
    DomainId='shoot-reload-timeline'
    CompileTargetRelativePath='tmp-shoot-reload-native-host/ShootReloadNativeHost.xfl'
    CompileSwfRelativePath='ShootReloadNativeHost.swf'
    TemplateRelativePath='scripts/test-runners/shoot-reload-timeline/TestLoader.as.template'
    SuiteRelativePaths=@($suites | ForEach-Object {'scripts/类定义/org/flashNight/'+$_.Replace('.','/')+'.as'})
    SuiteFqns=@($suites | ForEach-Object {'org.flashNight.'+$_})
    ExpectedTracePatterns=@(
        '(?m)^--- ShootReloadTimelineTest: (?<native>[1-9][0-9]*)/\k<native> passed, 0 failed ---\r?$',
        '(?m)^--- ShootReloadCadenceTest: (?<cadence>[1-9][0-9]*)/\k<cadence> passed, 0 failed ---\r?$',
        '(?m)^--- GunslingerDualCadenceTest: (?<gunslinger>[1-9][0-9]*)/\k<gunslinger> passed, 0 failed ---\r?$',
        '(?m)^--- WeaponAmmoRuntimeTest: (?<ammo>[1-9][0-9]*)/\k<ammo> passed, 0 failed ---\r?$',
        '(?m)^--- LongGunSubWeaponCoreTest: 511/511 passed, 0 failed ---\r?$',
        '(?m)^--- PistolRecoilCoreTest: (?<pistol>[1-9][0-9]*)/\k<pistol> passed, 0 failed ---\r?$',
        '(?m)^--- ManualCooldownServiceTest: 57/57 passed, 0 failed ---\r?$',
        '(?m)^--- DrugInputServiceTest: 58/58 passed, 0 failed ---\r?$',
        '(?m)^--- KeyManagerMigrationTest: 14/14 passed, 0 failed ---\r?$')
    SuccessSummary='Real character reload cadence, ammo, dual-hand recoil and manual input regression'
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=120
    SkipCompile=$SkipCompile
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
