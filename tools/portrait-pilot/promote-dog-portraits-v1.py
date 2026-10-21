#!/usr/bin/env python3
"""Bounded native-art crops for the three dogs, with an immutable prior pack.

The user accepted the native art and explicitly requested framing, integration,
commit and push. This is not a new campaign review or a claim of pixel approval.
"""
from __future__ import annotations
import argparse
import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
import lzma
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from PIL import Image, __version__ as PILLOW_VERSION

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'tools/portrait-pilot/evidence/dog-portraits-20261021'
OUTPUT=ROOT/'launcher/web/assets/enemy-portraits'
REFS={'敌人-制式军警犬':475,'敌人-盗贼撕咬犬':476,'敌人-军阀铁卫犬':477}
KEY='nativeDogSupplementalPromotion'
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
ET.register_namespace('xlink','http://www.w3.org/1999/xlink')
ET.register_namespace('ffdec','https://www.free-decompiler.com/flash')

def sha(blob):return hashlib.sha256(blob).hexdigest().upper()
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
def seal(value,field):
    value=copy.deepcopy(value);value.pop(field,None)
    value[field]=sha(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode('utf-8'))
    return value
def digest(value,field):
    if seal(value,field)[field]!=value.get(field):raise ValueError(field+' drift')
def artifact(path):return {'path':path.relative_to(ROOT).as_posix(),'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())}
def verify(record):
    path=(ROOT/record['path']).resolve()
    if not path.is_relative_to(ROOT) or artifact(path)!=record:raise ValueError('artifact drift: '+record['path'])
    return path
def archive(record,expected_sha):
    blob=lzma.decompress(verify(record).read_bytes())
    if sha(blob)!=expected_sha:raise ValueError('decompressed source drift')
    return blob
def module(path,name):
    spec=importlib.util.spec_from_file_location(name,path);obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj
def png(image):
    stream=io.BytesIO();image.save(stream,format='PNG',optimize=True);return stream.getvalue()

def source():
    config=read(EVIDENCE/'source.json');approval=read(EVIDENCE/'authorization.json')
    if (config['schema']!='cf7.native-dog-portrait-source.v1'
        or {r['portraitRef']:r['unitId'] for r in config['rows']}!=REFS
        or approval['source']!='direct human user message in this conversation'
        or approval['userText']!='可行，给这3只狗照着僵尸犬的风格，都配上合适的头像，然后提交推送'
        or set(approval['portraitRefs'])!=set(REFS) or approval['separateNewCropPixelReview'] is not False
        or approval['formalRuntimeDeploymentAuthorized'] is not False):raise ValueError('bounded source/authorization drift')
    verify(config['exporter']);verify(config['styleReference'])
    bank=archive(config['bankArchive'],config['sourceBank']['sha256'])
    if len(bank)!=config['sourceBank']['bytes']:raise ValueError('source bank length drift')
    for row in config['rows']:
        if row['frame']!=1 or row['zoom']!=24 or row['freezeLiveMouth']!=(row['unitId']==477):raise ValueError('pose drift')
        verify(row['exportLog'])
    return config

def crop_svg(blob,crop):
    root=ET.fromstring(blob)
    if root.findall('.//{'+NS+'}image'):raise ValueError('native SVG must not embed a bitmap')
    empty=[]
    for node in root.iter():
        for key,value in node.attrib.items():
            if key.endswith('href') and not value.startswith('#'):raise ValueError('external SVG dependency')
        if node.tag=='{'+NS+'}filter' and not len(node):empty.append(node)
    # FFDec's empty filters hide otherwise valid vectors in Chromium.
    for node in empty:
        ident=node.get('id')
        for owner in root.iter():
            if owner.get('filter')=='url(#'+ident+')':owner.attrib.pop('filter')
            if node in list(owner):owner.remove(node)
    x,y,right,bottom=crop;side=right-x
    root.set('width','512');root.set('height','512');root.set('viewBox',f'{x} {y} {side} {side}');root.set('overflow','hidden')
    return ET.tostring(root,encoding='utf-8')

def derived(row):
    frame=Image.open(io.BytesIO(archive(row['pngArchive'],row['pngSha256']))).convert('RGBA')
    crop=row['cropPixels'];x,y,right,bottom=crop;side=right-x
    overlap=[min(frame.width,right)-max(0,x),min(frame.height,bottom)-max(0,y)]
    # Only a small transparent margin may extend beyond the native frame canvas.
    # At least 1024 actual source pixels must remain along both crop axes.
    if (side!=bottom-y or not 1024<=side<=4096 or min(overlap)<1024
        or max(-x,-y,right-frame.width,bottom-frame.height)>128):raise ValueError('native crop bounds/resolution')
    image=frame.crop(crop).resize((512,512),Image.Resampling.LANCZOS)
    if not image.getchannel('A').getbbox() or image.getchannel('A').getextrema()!=(0,255):raise ValueError('crop alpha')
    return image,crop_svg(archive(row['svgArchive'],row['svgSha256']),crop)

def render_data(write_files=False):
    config=source();entries={};files={}
    subjects=EVIDENCE/'subjects'
    if write_files:subjects.mkdir(exist_ok=True)
    for row in config['rows']:
        image,vector=derived(row);raster=png(image);assets={}
        for fmt,blob in [('svg',vector),('png',raster)]:
            name=sha(blob)[:24].lower()+'.'+fmt;files[name]=blob
            if write_files:(subjects/name).write_bytes(blob)
            assets[fmt]={'url':'assets/enemy-portraits/subjects/'+name,'bytes':len(blob),'sha256':sha(blob)}
        x,y,r,b=row['cropPixels']
        assets['svg'].update(viewBox=[x,y,r-x,b-y],flipX=False,embeddedRasterCount=0,isRasterHeavy=False,runtimeAllowed=True,convolutionFilterCount=0)
        assets['png'].update(size=[512,512],alphaExtrema=[0,255],visibleBounds=list(image.getchannel('A').getbbox()))
        entries[row['portraitRef']]={'portraitRef':row['portraitRef'],'petIds':[],'enemyIds':[row['portraitRef']],
            'status':'ready','defaultVariant':'default','variants':{'default':{
                # Compatibility value used by both existing Web and Native consumers.
                # Its precise authority is disclosed in provenance and authorization.
                'status':'human_accepted','subject':{'preferredFormat':'svg','svg':assets['svg'],'pngFallback':assets['png']},
                'provenance':{'reviewKey':row['portraitRef']+'::default','resolution':'user_authorized_native_art_crop',
                    'decisionStatus':'explicit_user_authorized_integration','orientationAction':'keep',
                    'orientationSource':'native_right_facing_pose_matches_zombie_dog_reference','rasterOrientationTransform':'none',
                    'separateNewCropPixelReview':False,'authorization':artifact(EVIDENCE/'authorization.json'),
                    'sourceEvidence':artifact(EVIDENCE/'source.json'),'sourceBankSha256':config['sourceBank']['sha256'],
                    'spriteId':row['spriteId'],'frame':1,'zoom':24,'cropPixels':row['cropPixels'],
                    'liveMouthSnapshot':row['freezeLiveMouth']}}}}
    inputs={name:artifact(path) for name,path in {'source':EVIDENCE/'source.json','authorization':EVIDENCE/'authorization.json',
        'controller':Path(__file__),'dispatcher':ROOT/'tools/portrait-pilot/promote-direct-portraits-v1.py'}.items()}
    data=seal({'schema':'cf7.native-dog-portrait-render.v1','pillowVersion':PILLOW_VERSION,'inputs':inputs,'entries':entries},'renderDigest')
    if write_files:write(EVIDENCE/'render-report.json',data)
    return data,files

def verify_prior(live_root):
    """Run the exact prior verifier on its original manifest and subject set.

    Its Codex SWF has legitimately advanced. Recover the exact historical bytes
    from Git, rather than weakening the old check or recertifying old decisions.
    """
    config=source();base=read(EVIDENCE/'base-manifest.json');digest(base,'manifestDigest')
    old=module(EVIDENCE/'compatibility/previous-direct-controller.py','cf7_prior_direct_dog_base')
    old.ROOT=ROOT;old.EVIDENCE=ROOT/'tools/portrait-pilot/evidence/direct-portraits-20261013';old.OUTPUT=OUTPUT
    controller=base['directSupplementalPromotion']['inputs']['controller']
    frozen=EVIDENCE/'compatibility/previous-direct-controller.py'
    if sha(frozen.read_bytes())!=controller['sha256'] or frozen.stat().st_size!=controller['bytes']:raise ValueError('prior verifier source drift')
    inputs=base['directSupplementalPromotion']['inputs']
    prior_verify=old.verify
    (ROOT/'tmp').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='dog-portrait-prior-',dir=ROOT/'tmp') as temporary:
        temp=Path(temporary);(temp/'subjects').mkdir()
        for name in config['baseSubjectNames']:
            if Path(name).name!=name:raise ValueError('subject path escape')
            os.link(live_root/'subjects'/name,temp/'subjects'/name)
        for name in ['manifest.json','promotion-receipt.json']:shutil.copyfile(EVIDENCE/('base-'+name),temp/name)
        historical={}
        for i,history in enumerate(config['historicalSources']):
            frozen_swf=temp/('historical-'+str(i)+'.swf')
            frozen_swf.write_bytes(archive(history['archive'],history['sha256']))
            if frozen_swf.stat().st_size!=history['bytes']:raise ValueError('historical SWF length drift')
            historical[(history['sourcePath'],history['sha256'],history['bytes'])]=frozen_swf
        def verify_frozen(record):
            if record==controller:return frozen
            key=(record['path'],record['sha256'],record['bytes'])
            if key in historical:return historical[key]
            return prior_verify(record)
        old.verify=verify_frozen;old.closure_inputs=lambda:inputs
        old.check_manifest(temp/'manifest.json',logical_output=OUTPUT)
    return base

def counts(base):
    result=copy.deepcopy(base['counts'])
    for key in ['identityCount','variantCount','humanAcceptedIdentityCount','humanAcceptedVariantCount']:result[key]+=3
    result['nativeDogSupplementalIdentityCount']=3
    return result

def check_manifest(path,*,logical_output=None):
    value=read(path);digest(value,'manifestDigest');closure=value.get(KEY,{});digest(closure,'closureDigest')
    base=read(EVIDENCE/'base-manifest.json');base_receipt=read(EVIDENCE/'base-promotion-receipt.json')
    data,files=render_data()
    if read(EVIDENCE/'render-report.json')!=data:raise ValueError('native dog render inputs/pixels drift')
    if (set(value)!=set(base)|{KEY} or set(value['entries'])!=set(base['entries'])|set(REFS)):raise ValueError('bounded dog delta contract')
    for ref,entry in base['entries'].items():
        if value['entries'][ref]!=entry:raise ValueError('prior accepted identity changed: '+ref)
    for key,prior in base.items():
        if key not in ['entries','counts','generatedAt','manifestDigest'] and value[key]!=prior:raise ValueError('prior manifest contract changed: '+key)
    expected=seal({'schema':'cf7.native-dog-portrait-supplement.v1','status':'explicitly_authorized_native_crops_integrated',
        'baseManifest':artifact(EVIDENCE/'base-manifest.json'),'baseReceipt':artifact(EVIDENCE/'base-promotion-receipt.json'),
        'renderReport':artifact(EVIDENCE/'render-report.json'),'portraitRefs':sorted(REFS),
        'baseManifestDigest':base['manifestDigest'],'historicalCampaignEvidence':'preserved_without_recertification',
        'separateNewCropPixelReview':False},'closureDigest')
    if closure!=expected or value['counts']!=counts(base):raise ValueError('dog supplement/count drift')
    for ref in REFS:
        if value['entries'][ref]!=data['entries'][ref]:raise ValueError('native dog entry drift: '+ref)
    actual={p.name for p in (path.parent/'subjects').iterdir()}
    if actual!=set(source()['baseSubjectNames'])|set(files):raise ValueError('live subject fileset drift')
    for name,blob in files.items():
        if (path.parent/'subjects'/name).read_bytes()!=blob:raise ValueError('subject bytes drift: '+name)
        if (EVIDENCE/'subjects'/name).read_bytes()!=blob:raise ValueError('immutable dog subject drift: '+name)
    verify_prior(path.parent)
    units=read(ROOT/'data/units/units.json')
    if len({u['id'] for u in units})!=len(units):raise ValueError('duplicate unit id')
    for ref,ident in REFS.items():
        if next(u['spritename'] for u in units if u['id']==ident)!=ref:raise ValueError('unit portrait identity drift')
    receipt=read(path.parent/'promotion-receipt.json');digest(receipt,'receiptDigest')
    expected_receipt=copy.deepcopy(base_receipt);expected_receipt.update(counts=value['counts'],generatedAt=value['generatedAt'],
        manifestDigest=value['manifestDigest'],nativeDogSupplementalClosureDigest=closure['closureDigest'],
        manifest={'path':((logical_output or path.parent)/'manifest.json').relative_to(ROOT).as_posix(),
                  'bytes':path.stat().st_size,'sha256':sha(path.read_bytes())})
    if receipt!=seal(expected_receipt,'receiptDigest'):raise ValueError('manifest-last receipt drift')
    return value

def promote():
    data,files=render_data()
    if read(EVIDENCE/'render-report.json')!=data:raise ValueError('run render before promote')
    live=read(OUTPUT/'manifest.json')
    if KEY in live:check_manifest(OUTPUT/'manifest.json');print('Already integrated');return
    if ((OUTPUT/'manifest.json').read_bytes()!=(EVIDENCE/'base-manifest.json').read_bytes()
        or (OUTPUT/'promotion-receipt.json').read_bytes()!=(EVIDENCE/'base-promotion-receipt.json').read_bytes()):raise ValueError('unknown live base; refuse overwrite')
    base=verify_prior(OUTPUT);value=copy.deepcopy(base);value['entries'].update(data['entries']);value['counts']=counts(base)
    value['generatedAt']=dt.datetime.now(dt.timezone.utc).isoformat().replace('+00:00','Z')
    value[KEY]=seal({'schema':'cf7.native-dog-portrait-supplement.v1','status':'explicitly_authorized_native_crops_integrated',
        'baseManifest':artifact(EVIDENCE/'base-manifest.json'),'baseReceipt':artifact(EVIDENCE/'base-promotion-receipt.json'),
        'renderReport':artifact(EVIDENCE/'render-report.json'),'portraitRefs':sorted(REFS),'baseManifestDigest':base['manifestDigest'],
        'historicalCampaignEvidence':'preserved_without_recertification','separateNewCropPixelReview':False},'closureDigest')
    value=seal(value,'manifestDigest');work=ROOT/'tmp/dog-portraits';work.mkdir(parents=True,exist_ok=True)
    stage=Path(tempfile.mkdtemp(prefix='staging-',dir=work));shutil.copytree(OUTPUT,stage,dirs_exist_ok=True)
    for name,blob in files.items():(stage/'subjects'/name).write_bytes(blob)
    write(stage/'manifest.json',value);receipt=read(EVIDENCE/'base-promotion-receipt.json')
    receipt.update(counts=value['counts'],generatedAt=value['generatedAt'],manifestDigest=value['manifestDigest'],
        nativeDogSupplementalClosureDigest=value[KEY]['closureDigest'],manifest={'path':(OUTPUT/'manifest.json').relative_to(ROOT).as_posix(),
        'bytes':(stage/'manifest.json').stat().st_size,'sha256':sha((stage/'manifest.json').read_bytes())})
    write(stage/'promotion-receipt.json',seal(receipt,'receiptDigest'));check_manifest(stage/'manifest.json',logical_output=OUTPUT)
    publisher=module(ROOT/'tools/portrait-pilot/promote-enemy-portraits-v1.py','cf7_dog_shared_publisher')
    backup=Path(tempfile.mkdtemp(prefix='backup-',dir=work));shutil.copytree(OUTPUT,backup,dirs_exist_ok=True)
    publisher.publish_staged_pack(stage,OUTPUT,backup)
    print(json.dumps({'status':'three_native_dog_portraits_integrated','counts':value['counts']},ensure_ascii=False))

def verify_native():
    config=source();pilot=module(ROOT/'tools/portrait-pilot/prepare_pilot.py','cf7_dog_native_tools')
    java=pilot.find_java_tool('java');javac=pilot.find_java_tool('javac')
    work=ROOT/'tmp/dog-portraits';work.mkdir(parents=True,exist_ok=True)
    out=Path(tempfile.mkdtemp(prefix='native-replay-',dir=work));classes=out/'classes';classes.mkdir()
    bank=out/'source.swf';bank.write_bytes(archive(config['bankArchive'],config['sourceBank']['sha256']))
    cp=os.pathsep.join([str(ROOT/'tools/ffdec/lib/*'),str(ROOT/'tools/ffdec/ffdec.jar')])
    def run(args,key):
        result=subprocess.run([str(x) for x in args],cwd=ROOT,capture_output=True,timeout=180)
        (out/(key+'.stdout.bin')).write_bytes(result.stdout);(out/(key+'.stderr.bin')).write_bytes(result.stderr)
        if result.returncode:raise ValueError('native replay failed: '+key+' '+result.stderr.decode('utf-8',errors='replace')[-600:])
    run([javac,'-encoding','UTF-8','-cp',cp,'-d',classes,verify(config['exporter'])],'compile')
    for row in config['rows']:
        run([java,'-Xmx1024m','-cp',str(classes)+os.pathsep+cp,'DogPortraitExporter',bank,out/row['key'],row['spriteId'],24,str(row['freezeLiveMouth']).lower()],row['key'])
        for ext in ['png','svg']:
            generated=next((out/row['key']/ext).rglob('*.'+ext)).read_bytes()
            if sha(generated)!=row[ext+'Sha256']:raise ValueError('native replay bytes drift: '+row['key']+' '+ext)
    result={'status':'exact_native_png_and_svg_replay','dogs':3,'frames':3,'representations':6,'sourceBankSha256':config['sourceBank']['sha256']}
    write(out/'result.json',result);print(json.dumps({**result,'evidence':str(out)},ensure_ascii=False))

def main():
    parser=argparse.ArgumentParser();parser.add_argument('command',choices=['render','promote','check','verify-native']);args=parser.parse_args()
    if args.command=='render':data,_=render_data(True);print('Rendered '+data['renderDigest'])
    elif args.command=='promote':promote()
    elif args.command=='verify-native':verify_native()
    else:
        value=check_manifest(OUTPUT/'manifest.json');print(json.dumps({'status':'native_dog_delta_and_prior_pack_verified','counts':value['counts']},ensure_ascii=False))
if __name__=='__main__':main()
