"""Read-only validation of registered scene-light authoring and anchor references."""
from pathlib import Path
import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
FIELDS = set('Key Preset Shape RenderMode BudgetPool Priority X Y OffsetX OffsetY Angle Radius Length HalfWidth Energy BaseEnergy Color Color2 Animation Amplitude Rate Phase SweepAngle AttachTo Anchor FollowRotation FollowScale FollowVisibility FrameCurve StatePath Enabled'.split())
BOOLS = set('FollowRotation FollowScale FollowVisibility Enabled'.split())
RANGES = {'X':(-1000000,1000000),'Y':(-1000000,1000000),'OffsetX':(-1000000,1000000),'OffsetY':(-1000000,1000000),'Angle':(-36000,36000),'Radius':(1,1024),'Length':(1,1024),'HalfWidth':(.5,512),'Energy':(0,2),'BaseEnergy':(0,2),'Priority':(0,100),'Amplitude':(0,.8),'Rate':(0,30),'Phase':(-36000,36000),'SweepAngle':(0,180)}
TEXTS = {'Key':128,'Preset':64,'Shape':16,'RenderMode':16,'BudgetPool':16,'Animation':16,'AttachTo':128,'Anchor':128,'StatePath':128,'FrameCurve':1024}

def require(ok, message):
    if not ok:
        raise ValueError(message)

def color(value):
    if isinstance(value, int):
        require(0 <= value <= 0xffffff, 'color outside RGB range')
        return value
    require(isinstance(value, str), 'invalid color type')
    require(re.fullmatch(r'(?:#|0[xX])[0-9A-Fa-f]{6}', value) is not None, 'color must be RGB integer, #RRGGBB or 0xRRGGBB')
    return int(value[1:] if value.startswith('#') else value[2:],16)

def validate_record(raw, presets):
    require(set(raw) <= FIELDS, 'unknown light fields: '+str(set(raw)-FIELDS))
    require(isinstance(raw.get('Key'),str) and re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]{0,127}',raw['Key']), 'invalid stable light Key')
    preset=raw.get('Preset','lamp')
    require(preset in presets, 'unknown preset: '+str(preset))
    data={**presets[preset],**raw}
    for key,value in data.items():
        if key in RANGES:
            lo,hi=RANGES[key]
            require(isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value) and lo<=value<=hi, 'invalid '+key)
        elif key in BOOLS:
            require(isinstance(value,bool), 'invalid boolean '+key)
        elif key in TEXTS:
            require(isinstance(value,str) and len(value)<=TEXTS[key], 'invalid text '+key)
    require(data.get('Priority',45)==int(data.get('Priority',45)), 'fractional priority')
    require(data.get('Shape','point') in ('point','cone','beam'), 'invalid Shape')
    mode=data.get('RenderMode','cached');animation=data.get('Animation','constant')
    require(mode in ('cached','realtime','hybrid','visualOnly'), 'invalid RenderMode')
    require(data.get('BudgetPool','scene') in ('scene','shared'), 'invalid BudgetPool')
    require(animation in ('constant','pulse','flicker','sweep'), 'invalid Animation')
    c=color(data.get('Color','#FFE0AD'));c2=color(data.get('Color2',data.get('Color','#FFE0AD')))
    require(mode!='cached' or (animation=='constant' and c==c2), 'cached light must keep constant color and curve')
    require(mode!='hybrid' or (data.get('BaseEnergy',0)<=data.get('Energy',.8)*(1-data.get('Amplitude',0))+1e-5 and c==c2 and animation!='sweep'), 'hybrid base exceeds minimum or moves independently')
    previous=0
    if data.get('FrameCurve'):
        parts=data['FrameCurve'].split(',');require(len(parts)<=32,'curve too large')
        for part in parts:
            pair=part.split(':');require(len(pair)==2,'invalid frame curve pair')
            frame=int(pair[0]);weight=float(pair[1]);require(previous<frame<=10000 and math.isfinite(weight) and 0<=weight<=1,'invalid curve range/order');previous=frame
        require(bool(data.get('AttachTo')),'frame curve needs an instance')
    for field in ('Anchor','StatePath'):
        if data.get(field):
            require(bool(data.get('AttachTo')),field+' needs an instance')
            require(all(p not in ('_root','_parent','__proto__') and p for p in data[field].split('.')), 'path must stay inside its bound instance')
    return data

def xml_record(element):
    require(not element.attrib,'Light uses child fields, not XML attributes')
    raw={}
    for child in element:
        require(child.tag not in raw and len(child)==0,'duplicate or nested light field')
        value=(child.text or '').strip()
        if child.tag in RANGES:
            value=float(value)
            if value.is_integer():value=int(value)
        elif child.tag in BOOLS:
            require(value in ('true','false'),'boolean must be true or false');value=value=='true'
        elif child.tag in ('Color','Color2') and value.isdigit():value=int(value)
        raw[child.tag]=value
    return raw

def definitions(parent,presets):
    result={}
    for e in parent.findall('Lights/Light'):
        raw=xml_record(e);validate_record(raw,presets);require(raw['Key'] not in result,'duplicate light Key');result[raw['Key']]=raw
    return result

def anchors(parent):
    result=set()
    for e in list(parent.findall('Instances/Instance'))+list(parent.findall('SpawnPoint/Point')):
        key=e.findtext('LightKey')
        if key:
            require(re.fullmatch(r'[A-Za-z][A-Za-z0-9_.-]{0,127}',key),'invalid anchor LightKey')
            require(key not in result,'duplicate anchor LightKey');result.add(key)
    return result

def validate_tree(root=ROOT):
    catalog=json.loads((root/'data/environment/scene_lights.v1.json').read_text(encoding='utf-8-sig'))
    require(catalog.get('schema')=='cf7-scene-lights.v1','invalid schema')
    require(isinstance(catalog['sceneReserve'],int) and 0<=catalog['sceneReserve']<=8,'invalid reserve')
    require(0<=catalog['maximumResponse']<=.8,'invalid response')
    presets=catalog['presets']
    for name,data in presets.items():validate_record({'Key':'validate','Preset':name},presets)
    environments={};rows=[]
    for name in ('scene_environment.xml','stage_environment.xml'):
        path=root/'data/environment'/name
        for env in ET.parse(path).getroot().findall('Environment'):
            defs=definitions(env,presets);refs=anchors(env)
            for d in defs.values():require(not d.get('AttachTo') or d['AttachTo'] in refs,'unknown environment anchor '+d.get('AttachTo',''))
            environments[env.findtext('BackgroundURL')]=(defs,refs)
            if defs:rows.append({'path':path.relative_to(root).as_posix(),'scope':env.findtext('BackgroundURL'),'lights':len(defs)})
    for path in sorted((root/'data/stages').rglob('*.xml')):
        stage=ET.parse(path).getroot()
        for index,sub in enumerate(stage.findall('SubStage')):
            bg=Path(sub.findtext('BasicInformation/Background','')).name
            base,refs=environments.get(bg,({},set()))
            require(not(refs & anchors(sub)),'stage/environment anchor collision')
            refs=refs|anchors(sub)
            local=definitions(sub,presets)
            override=sub.find('BasicInformation/Environment')
            if override is not None:
                override_defs=definitions(override,presets)
                if override_defs:base=override_defs
            merged={k:dict(v) for k,v in base.items()}
            for key,value in local.items():merged[key]={**merged.get(key,{}),**value}
            require(len(merged)<=128,'scene light capacity exceeded')
            for d in merged.values():
                validate_record(d,presets);require(not d.get('AttachTo') or d['AttachTo'] in refs,'unknown stage anchor '+d.get('AttachTo',''))
            if local:rows.append({'path':path.relative_to(root).as_posix(),'scope':'SubStage '+str(index),'lights':len(merged)})
    return rows

if __name__=='__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    try:
        rows=validate_tree();print(json.dumps({'success':True,'configuredScopes':len(rows),'rows':rows},ensure_ascii=False))
    except (ValueError,KeyError,ET.ParseError) as error:
        print('Scene light validation failed: '+str(error),file=sys.stderr);sys.exit(1)
