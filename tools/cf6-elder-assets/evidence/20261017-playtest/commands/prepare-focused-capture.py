from pathlib import Path
import json,re,zipfile,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
TMP=Path(__file__).resolve().parent
subprocess.run([sys.executable,'-X','utf8','-B',str(TMP/'fix-head-capture.py')],check=True,cwd=ROOT)
template=ROOT/'scripts/test-runners/cf6-elder-render/TestLoader-capture.as.template'
runner=ROOT/'scripts/run-cf6-elder-render-tests.ps1'
with zipfile.ZipFile(TMP/'render-pass1/elder/capture-source-before-scope.zip','x',zipfile.ZIP_DEFLATED) as z:
    for p in [template,runner]:z.writestr(p.relative_to(ROOT).as_posix(),p.read_bytes())
source=(ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderRenderTest.as').read_text('utf-8-sig')
keys=re.findall(r'"([a-z0-9-]+)"',re.search(r'keys:Array=\[(.*?)\];',source)[1])
keys+=['burst-left-13','beam-left-29','phase-left-55','heavy-beam-left-53']
assert len(keys)==len(set(keys))==25
s=template.read_text('utf-8-sig')
assert '_root.elderRenderFrames=' not in s
s=s.replace('_root.elderRenderCapture=true;', '_root.elderRenderCapture=true;\n_root.elderRenderFrames='+json.dumps(keys,separators=(',',':'))+';')
template.write_text(s,'utf-8-sig',newline='\n')
s=runner.read_text('utf-8-sig')
old="elseif($Capture){'Cf6ElderRenderTest: \\d+ passed, 0 failed; 807 draw points'}"
assert old in s
runner.write_text(s.replace(old,"elseif($Capture){'Cf6ElderRenderTest: \\d+ passed, 0 failed; 25 draw points'}"),'utf-8-sig',newline='\n')
plan=json.loads((TMP/'render-plan1.json').read_text('utf8'))
plan['output']='render-pass2'
(TMP/'render-plan2.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n','utf8')
change=json.loads((TMP/'render-only-harness-changes.json').read_text('utf8'))
change['paths'].append(template.relative_to(ROOT).as_posix())
change['elderScope']={'fullSweepAttempt':'render-pass1/elder','fullSweepStatus':'cancelled; no success claimed','captureKeys':keys,'defaultFullSweepStillAvailable':True,'gameResourcesChanged':False}
(TMP/'render-only-harness-changes.json').write_text(json.dumps(change,ensure_ascii=False,indent=2)+'\n','utf8')
print('Prepared full 204-point Headbot redraw, 25 selected Elder frames, 32 Bladebot frames')
