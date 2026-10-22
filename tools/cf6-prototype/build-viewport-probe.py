"""Generate an isolated, save-free Flash display probe of current canonical map SWFs."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TARGET = ROOT/'scripts/Cf6ViewportProbeHost'


def as2(value):
    if isinstance(value, dict):
        if any(not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) for k in value):
            raise ValueError('unsafe AS2 key')
        return '{'+','.join(k+':'+as2(v) for k,v in value.items())+'}'
    if isinstance(value, list):
        return '['+','.join(as2(v) for v in value)+']'
    return json.dumps(value, ensure_ascii=False, allow_nan=False)


parser=argparse.ArgumentParser()
parser.add_argument('--run-id',required=True)
parser.add_argument('--map',action='append',dest='selected_maps',help='Isolate one or more existing maps in a fresh player')
args=parser.parse_args()
if not re.fullmatch(r'[a-z0-9-]+',args.run_id): raise SystemExit('invalid run id')
chapter=json.loads((ROOT/'data/stages/books/cf6-sting.runtime.json').read_text(encoding='utf-8-sig'))
envs={n.findtext('BackgroundURL'):n for n in ET.parse(ROOT/'data/environment/stage_environment.xml').findall('Environment')}
cases=[];assets={}
for m in chapter['maps']:
    if args.selected_maps and m['id'] not in args.selected_maps: continue
    p=m['presentation'];env=envs[Path(m['background']).name]
    layers=[dict(role='background',url='flashswf/backgrounds/'+m['background'],x=p['backgroundX'],y=p['backgroundY'])]
    layers+=copy.deepcopy(m['mechanism']['layers'])
    for layer in layers:
        path=ROOT/layer['url'];assets[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
        layer['url']=path.as_uri()
        for field in list(layer):
            if field not in ('role','url','x','y','width','height','clip','loopHeight'): del layer[field]
    basic=m['stage']['BasicInformation']
    cases.append(dict(id=m['id'],width=float(env.findtext('Width')),height=float(env.findtext('Height')),
                      scale=p['scale'],spawn=[basic['PlayerX'],basic['PlayerY']],layers=layers))
source=(HERE/'viewport-probe.as.template').read_text(encoding='utf-8-sig').replace('__CASES__',as2(cases)).replace('__RUN_ID__',args.run_id)
if not cases or args.selected_maps and set(args.selected_maps)!={c['id'] for c in cases}: raise ValueError('unknown or missing selected map')
class_body=source.replace('import flash.display.*;','').replace('import flash.geom.*;','').replace('stop();','_root.stop();',1)
class_source='import flash.display.*;\nimport flash.geom.*;\nclass org.flashNight.arki.scene.Cf6ViewportProbe {\n public static function start():Void {\n'+class_body+'\n }\n}\n'
probe_class=ROOT/'scripts/类定义/org/flashNight/arki/scene/Cf6ViewportProbe.as'
probe_class.write_text(class_source,encoding='utf-8-sig')
TARGET.mkdir(exist_ok=True)
proxy=TARGET/'Cf6ViewportProbeHost.xfl'
if not proxy.is_file(): proxy.write_text('PROXY-CS5',encoding='utf-8')
elif proxy.read_text(encoding='utf-8-sig') != 'PROXY-CS5': raise ValueError('unexpected existing XFL proxy')
entry='trace("CF6ViewportHost '+args.run_id+' begin");trace("CF6ViewportHost startType="+typeof org.flashNight.arki.scene.Cf6ViewportProbe.start);org.flashNight.arki.scene.Cf6ViewportProbe.start();trace("CF6ViewportHost '+args.run_id+' initialized");'
dom='<?xml version="1.0" encoding="utf-8"?><DOMDocument xmlns="http://ns.adobe.com/xfl/2008/" frameRate="30" width="1024" height="576" backgroundColor="#101010" xflVersion="2.2"><timelines><DOMTimeline name="场景 1"><layers><DOMLayer name="显示验证"><frames><DOMFrame index="0" keyMode="9728"><Actionscript><script><![CDATA['+entry+']]></script></Actionscript><elements/></DOMFrame></frames></DOMLayer></layers></DOMTimeline></timelines></DOMDocument>'
(TARGET/'DOMDocument.xml').write_text(dom,encoding='utf-8')
settings=(ROOT/'scripts/TestLoader/PublishSettings.xml').read_text(encoding='utf-8-sig').replace('TestLoader','Cf6ViewportProbeHost')
settings=settings.replace('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>').replace('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>')
(TARGET/'PublishSettings.xml').write_text(settings,encoding='utf-8')
manifest={'schema':'cf6-viewport-probe.v1','runId':args.run_id,'maps':len(cases),'viewport':[1024,512],
          'mapIds':[c['id'] for c in cases],
          'purpose':'actual Flash display-list coverage only; no full-game, combat or player acceptance',
          'assets':assets,'chapterSha256':hashlib.sha256((ROOT/'data/stages/books/cf6-sting.runtime.json').read_bytes()).hexdigest(),
          'templateSha256':hashlib.sha256((HERE/'viewport-probe.as.template').read_bytes()).hexdigest()}
(HERE/'generated/viewport-probe-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Prepared isolated Flash viewport probe:',len(cases),'maps,',len(assets),'canonical assets')
