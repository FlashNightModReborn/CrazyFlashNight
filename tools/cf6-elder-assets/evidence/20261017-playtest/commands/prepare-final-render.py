from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[2];TMP=Path(__file__).resolve().parent
source=(ROOT/'scripts/test-runners/cf6-headbot-render/TestLoader-capture.as.template').read_text('utf-8-sig')
source=source.replace('_root.headbotRenderCapture=true;', '_root.headbotRenderCapture=true;\n_root.headbotRenderFrames=["beam-29","beam-30"];')
(TMP/'TestLoader-head-framing.as.template').write_text(source,'utf-8-sig',newline='\n')
runner='''$ErrorActionPreference='Stop'
& scripts/test-runners/run-focused-testloader.ps1 -DomainId cf6-headbot-render -TemplateRelativePath tmp/cf6-playtest-feedback-20261017/TestLoader-head-framing.as.template -SuiteRelativePaths 'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6HeadbotRenderTest.as' -SuiteFqns org.flashNight.arki.unit.Action.Melee.Cf6HeadbotRenderTest -ExpectedTracePatterns @('Cf6HeadbotRenderTest: \\d+ passed, 0 failed; 2 draw points') -SuccessSummary 'Second beam framing checked on both affected native frames' -TimeoutSeconds 600 -AsyncBehaviorTimeoutSeconds 600
exit $LASTEXITCODE
'''
(TMP/'run-head-framing.ps1').write_text(runner,'utf-8-sig',newline='\n')
plan=json.loads((TMP/'render-plan2.json').read_text('utf8'));plan['output']='render-pass3'
plan['runs'][0]={'name':'headbot','runner':'tmp/cf6-playtest-feedback-20261017/run-head-framing.ps1','args':[]}
(TMP/'render-plan3.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n','utf8')
print('Final render plan: two Headbot framing corrections, 25 Elder keyframes, 32 Bladebot draw points')
