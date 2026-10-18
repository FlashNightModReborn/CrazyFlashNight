"""Small native rendering fixture: exact fragment APIs, with no combat or save setup."""
from pathlib import Path
import argparse,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
FOLDER=ROOT/'scripts/test-runners/cf6-robot-death-render'
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
source=ROOT/'scripts/逻辑/关卡系统/关卡系统_lsy_地图元件.as'
text=source.read_text('utf-8-sig');body='import org.flashNight.arki.spatial.animation.*;\n_root.地图元件={};\n'
for name in ['地图元件破碎动画','停止地图元件破碎动画','地图元件破碎动画运行中']:
    start=text.index('_root.地图元件.'+name+' = function(')
    body+=text[start:text.index('\n};',start)+3]+'\n'
outputs={'DeathFixture.as':body}
plan=json.loads((HERE/'death-render-plan.json').read_text('utf8'))
for key,row in plan.items():
    keys=['death-'+str(f) for f in row['frames']]+['death-left-'+str(row['mirrorFrame'])]
    config='{swf:'+json.dumps('../flashswf/arts/new/'+row['swf'],ensure_ascii=False)+',linkage:'+json.dumps(row['linkage'],ensure_ascii=False)+',total:'+str(row['total'])+',fragmentStart:'+str(row['fragmentStart'])+',mirrorFrame:'+str(row['mirrorFrame'])+',frames:'+json.dumps(keys)+'}'
    outputs['TestLoader-'+key+'.as.template']='#include "test-runners/cf6-robot-death-render/DeathFixture.as"\nimport org.flashNight.arki.unit.Action.Melee.*;\n_root.robotRenderConfig='+config+';\n_root.robotRenderCapture=true;\n_root.cf6RobotDeathRenderComplete=function():Void {trace("FocusedTestRunId cf6-robot-death-'+key+' Complete: __FOCUSED_RUN_ID__");};\ntrace("FocusedTestRunId cf6-robot-death-'+key+' Start: __FOCUSED_RUN_ID__");\norg.flashNight.arki.unit.Action.Melee.Cf6RobotDeathRenderTest.runAllTests();\n'
FOLDER.mkdir(parents=True,exist_ok=True)
for name,content in outputs.items():
    p=FOLDER/name;expected=b'\xef\xbb\xbf'+content.encode('utf8')
    if args.check:assert p.read_bytes()==expected
    else:
        if not p.exists():shutil.copyfile(ROOT/'scripts/test-runners/cf6-headbot/TestLoader.as.template',p)
        assert p.read_bytes()[:3]==expected[:3];p.write_bytes(expected)
manifest={'source':source.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'functions':['地图元件破碎动画','停止地图元件破碎动画','地图元件破碎动画运行中'],'planSha256':hashlib.sha256((HERE/'death-render-plan.json').read_bytes()).hexdigest(),
    'outputs':[{'path':(FOLDER/n).relative_to(ROOT).as_posix(),'sha256':hashlib.sha256((b'\xef\xbb\xbf'+v.encode('utf8'))).hexdigest()} for n,v in outputs.items()]}
p=HERE/'death-render-fixture-manifest.json'
if args.check:assert json.loads(p.read_text('utf8'))==manifest
else:p.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps({'ok':True,'exactSourceFunctions':3,'families':3,'selectedImages':24}))
