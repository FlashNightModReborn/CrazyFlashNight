param([Parameter(Mandatory=$true)][ValidatePattern('^r[0-9]+$')][string]$Revision)
$ErrorActionPreference='Stop'
chcp.com 65001 | Out-Null
$taskRoot=$PSScriptRoot
$log=Join-Path $taskRoot ('final-checks-'+$Revision+'.log')
if(Test-Path -LiteralPath $log){throw 'Preserve prior final-check log'}
& python -X utf8 -B tools/cf6-elder-assets/verify.py *>&1 | Tee-Object -FilePath $log
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& node tools/check-bom.js --dir tools/cf6-elder-assets --dir tools/cf6-bladebot-assets --dir tools/cf6-headbot-assets --dir scripts/test-runners/cf6-elder --dir scripts/test-runners/cf6-elder-render --dir scripts/test-runners/cf6-bladebot --dir scripts/test-runners/cf6-bladebot-beam-render --dir scripts/test-runners/cf6-knockback-scope --dir scripts/test-runners/cf6-headbot --dir scripts/test-runners/cf6-headbot-render --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderRenderTest.as --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6BladebotAssetTest.as --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6BladebotBeamRenderTest.as --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6HeadbotAssetTest.as --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6HeadbotRenderTest.as --file scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6KnockbackScopeTest.as --file scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as *>&1 | Tee-Object -FilePath $log -Append
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& node tools/cf7-balance-tool/node_modules/tsx/dist/cli.mjs -e 'import {runXmlRoundtripCheck} from "./tools/cf7-balance-tool/packages/xml-io/src/roundtrip-check.ts";const r=runXmlRoundtripCheck(["data/enemy_properties/CF6重制敌人.xml"]);console.log(JSON.stringify(r));if(r.failed)process.exit(1);' *>&1 | Tee-Object -FilePath $log -Append
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& node tools/derive-arena-unit-catalog.js --check *>&1 | Tee-Object -FilePath $log -Append
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
& python -X utf8 -B (Join-Path $taskRoot 'check-integration.py') *>&1 | Tee-Object -FilePath $log -Append
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
