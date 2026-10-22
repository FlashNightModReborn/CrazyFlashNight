[CmdletBinding()]
param([ValidateRange(1,3600)][int]$TimeoutSeconds=300,[switch]$LegacyBaseline,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$projectDir=Split-Path -Parent $PSScriptRoot
$domainDir=Join-Path $projectDir 'tmp/issue154-black-dragon'
$hostTarget=Join-Path $domainDir 'host'
$hostSource=Join-Path $PSScriptRoot 'ShootReloadNativeHost'
[void](New-Item -ItemType Directory -Path (Join-Path $hostTarget 'LIBRARY') -Force)
$utf8=[Text.UTF8Encoding]::new($false)
$bomUtf8=[Text.UTF8Encoding]::new($true)
$libraryRelative='../../flashswf/arts/things5.swf'
$libraryPath=Join-Path $projectDir 'flashswf/arts/things5.swf'
if($LegacyBaseline) {
    $libraryRelative='original/things5.swf'
    $libraryPath=Join-Path $domainDir 'original/things5.swf'
    if(!(Test-Path -LiteralPath $libraryPath) -or
        (Get-FileHash -LiteralPath $libraryPath).Hash -ne '2091034D4278DE1C5435531F71F01C245BE4798D605E19B78B314E308D5AC8A9') {
        throw 'Legacy baseline must be the preserved original things5 SWF; never replace it with a new build.'
    }
}
$proxySource=Join-Path $hostSource 'ShootReloadNativeHost.xfl'
$proxyTarget=Join-Path $hostTarget 'BlackDragonAttackNativeHost.xfl'
if(!(Test-Path -LiteralPath $proxyTarget) -or
    (Get-FileHash -LiteralPath $proxySource).Hash -ne (Get-FileHash -LiteralPath $proxyTarget).Hash) {
    Copy-Item -LiteralPath $proxySource -Destination $proxyTarget -Force
}
$dom=[IO.File]::ReadAllText((Join-Path $hostSource 'DOMDocument.xml'),$utf8).
    Replace('射速回归','黑龙攻击回归').Replace('Import0','BlackDragonImport').
    Replace('__cadenceRsl','__blackDragonRsl').Replace('../scripts/TestLoader.as','../../../scripts/TestLoader.as')
[IO.File]::WriteAllText((Join-Path $hostTarget 'DOMDocument.xml'),$dom,$utf8)
$settings=[IO.File]::ReadAllText((Join-Path $hostSource 'PublishSettings.xml'),$utf8).
    Replace('ShootReloadNativeHost','BlackDragonAttackNativeHost')
$packagePaths=[Security.SecurityElement]::Escape((Join-Path $PSScriptRoot '类定义')+';'+$PSScriptRoot+';')
$settings=[regex]::Replace($settings,'<PackagePaths>[^<]*</PackagePaths>','<PackagePaths>'+$packagePaths+'</PackagePaths>')
[IO.File]::WriteAllText((Join-Path $hostTarget 'PublishSettings.xml'),$settings,$utf8)
$import=[IO.File]::ReadAllText((Join-Path $hostSource 'LIBRARY/Import0.xml'),$utf8).
    Replace('Import0','BlackDragonImport').Replace('加载MC库-00','加载mc库-黑铁会').
    Replace('flashswf/arts/things0.swf',$libraryRelative)
[IO.File]::WriteAllText((Join-Path $hostTarget 'LIBRARY/BlackDragonImport.xml'),$import,$utf8)

# Compile the actual production function assignments, without a handwritten copy.
$productionRelative='scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as'
$production=[IO.File]::ReadAllText((Join-Path $projectDir $productionRelative),$utf8)
$templateRelative='scripts/test-runners/black-dragon-attack/TestLoader.as.template'
$generatedRelative='tmp/issue154-black-dragon/TestLoader.as.template'
$generatedPath=Join-Path $projectDir $generatedRelative
Copy-Item -LiteralPath (Join-Path $projectDir $templateRelative) -Destination $generatedPath -Force
$template=[IO.File]::ReadAllText($generatedPath,$utf8)
foreach($entry in @(@('状态改变','__ENEMY_STATE_CHANGE_SOURCE__'),@('动画完毕','__ENEMY_ANIMATION_DONE_SOURCE__'))) {
    $matches=[regex]::Matches($production,'(?ms)^_root\.敌人函数\.'+[regex]::Escape($entry[0])+' = function\([^\r\n]*\) \{.*?^\};')
    if($matches.Count -ne 1) {throw ('Production source slice is ambiguous: '+$entry[0])}
    $template=$template.Replace($entry[1],$matches[0].Value)
}
$template=$template.Replace('__EXPECT_LEGACY__',$LegacyBaseline.IsPresent.ToString().ToLowerInvariant())
[IO.File]::WriteAllText($generatedPath,$template,$bomUtf8)
$suiteRelative='scripts/类定义/org/flashNight/arki/unit/Action/Input/BlackDragonAttackTimelineTest.as'
$identities=[ordered]@{}
foreach($relative in @($templateRelative,$generatedRelative,$suiteRelative,$productionRelative,
    'flashswf/arts/things5/LIBRARY/Symbol 654.xml','flashswf/arts/things5/LIBRARY/Symbol 680.xml')) {
    $identities[$relative]=(Get-FileHash -LiteralPath (Join-Path $projectDir $relative)).Hash
}
$preparation=[ordered]@{legacyBaseline=$LegacyBaseline.IsPresent;libraryPath=$libraryPath;
    librarySha256=(Get-FileHash -LiteralPath $libraryPath).Hash;sourceSha256=$identities}
$mode=if($LegacyBaseline){'legacy'}else{'current'}
[IO.File]::WriteAllText((Join-Path $domainDir ($mode+'-preparation.json')),($preparation|ConvertTo-Json -Depth 5),$utf8)
if($PrepareOnly) {
    Write-Host ('[OK] '+$mode+' fixture prepared; TestLoader, CS6 and test players were not touched.')
    return
}
$focusedRun=@{
    DomainId='black-dragon-attack'
    CompileTargetRelativePath='tmp/issue154-black-dragon/host/BlackDragonAttackNativeHost.xfl'
    CompileSwfRelativePath='tmp/issue154-black-dragon/BlackDragonAttackNativeHost.swf'
    TemplateRelativePath=$generatedRelative
    SuiteRelativePaths=@($suiteRelative)
    SuiteFqns=@('org.flashNight.arki.unit.Action.Input.BlackDragonAttackTimelineTest')
    AdditionalAsRelativePaths=@($productionRelative)
    ExpectedTracePatterns=@('(?m)^--- BlackDragonAttackTimelineTest: (?<total>[1-9][0-9]*)/\k<total> passed, 0 failed ---\r?$')
    SuccessSummary=('Mounted black dragon real AI/timeline '+$mode+' regression; no player saves')
    TimeoutSeconds=$TimeoutSeconds
    AsyncBehaviorTimeoutSeconds=90
}
& (Join-Path $PSScriptRoot 'test-runners/run-focused-testloader.ps1') @focusedRun
