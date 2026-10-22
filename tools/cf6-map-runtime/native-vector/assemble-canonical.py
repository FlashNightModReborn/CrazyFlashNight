"""Archive owned prior CF6 resources and install native XFL closure under canonical names.

Candidate SWFs are never copied. The root must freshly compile the exact canonical
XFL after this source-only transaction. No Flash process or shared task is touched.
"""
from pathlib import Path
import argparse
from datetime import datetime,timezone
import hashlib
import json
import os
import shutil
import sys
import uuid
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
RESOURCE_ROOT=(ROOT/'flashswf/backgrounds/cf6').resolve()
ARCHIVE_ROOT=(HERE/'archive/canonical-predecessors').resolve()
sys.path.insert(0,str(HERE.parent))
from native_xfl import audit,finalize

ROUTE={f'A{i:02}' for i in range(1,23) if i not in (7,21)}
DOORS={'wood1714':'CF6_DoorWood1714','exit1720':'CF6_DoorExit1720','grand1750':'CF6_DoorGrand1750'}
NS={'x':'http://ns.adobe.com/xfl/2008/'}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def safe(path,parent):
    path=path.resolve();parent=parent.resolve()
    if path==parent or not path.is_relative_to(parent):raise ValueError('path outside the exact owned subtree: '+str(path))
    return path
def inventory(base):
    return [{'path':p.relative_to(base).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(base.rglob('*')) if p.is_file()] if base.is_dir() else []
def signature(rows):return hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def closure(candidate,name):
    audit(candidate/(name+'.xfl'))
    root=ET.parse(candidate/'DOMDocument.xml')
    paths={'DOMDocument.xml','PublishSettings.xml',name+'.xfl'}
    for node in root.findall('./x:symbols/x:Include',NS):paths.add('LIBRARY/'+node.get('href'))
    for node in root.findall('./x:media/x:DOMBitmapItem',NS):
        paths.add('LIBRARY/'+node.get('href'));paths.add('bin/'+node.get('bitmapDataHRef'))
    if (candidate/'mimetype').is_file():paths.add('mimetype')
    result=[]
    for relative in sorted(paths):
        p=safe(candidate/relative,candidate)
        if not p.is_file() or p.suffix.lower()=='.swf':raise ValueError('native source closure missing or contains SWF')
        result.append({'path':relative,'bytes':p.stat().st_size,'sha256':sha(p)})
    return result


def resolve(args):
    if args.door:
        target_name=DOORS[args.door];candidate_name=target_name+'_VectorCandidate01';inputs=[];source_manifest=None
    else:
        if args.map not in ROUTE:raise ValueError('only enabled CF6 maps belong to this installer')
        maps=json.loads((ROOT/'tools/cf6-map-source/generated/map-input.json').read_text(encoding='utf-8'))['maps']
        if args.layer not in {layer['id'] for layer in maps[args.map]['layers']}:raise ValueError('layer not in source registry')
        target_name='CF6_'+args.map+'_'+('BG' if args.layer=='background' else args.layer)
        candidate_name='CF6_A01_VectorCandidate01' if args.map=='A01' and args.layer=='background' else target_name+'_VectorCandidate01'
        source_manifest=HERE/'texture-manifest.json' if candidate_name=='CF6_A01_VectorCandidate01' else HERE/'layers'/candidate_name/'texture-manifest.json'
        doc=json.loads(source_manifest.read_text(encoding='utf-8'));inputs=doc['inputs']
        if sha(ROOT/doc['source'])!=doc['sourceSha256']:raise ValueError('authoring source changed since native preparation')
        for item in inputs:
            if sha(ROOT/item['path'])!=item['sha256']:raise ValueError('intrinsic input changed since native preparation')
    candidate=safe(RESOURCE_ROOT/candidate_name,RESOURCE_ROOT);target=safe(RESOURCE_ROOT/target_name,RESOURCE_ROOT)
    audit(candidate/(candidate_name+'.xfl'),inputs)
    return candidate_name,target_name,candidate,target,inputs,source_manifest


def main():
    parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--map');group.add_argument('--door',choices=list(DOORS))
    parser.add_argument('--layer',default='background');parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    candidate_name,name,candidate,target,inputs,source_manifest=resolve(args)
    source_rows=closure(candidate,candidate_name)
    target_swf=safe(RESOURCE_ROOT/(name+'.swf'),RESOURCE_ROOT)
    summary={'target':name,'candidate':candidate_name,'nativeClosureFiles':len(source_rows),
             'oldSourcePresent':target.is_dir(),'oldSwfPresent':target_swf.is_file(),
             'sourceXfl':(target/(name+'.xfl')).relative_to(ROOT).as_posix(),
             'requiredFreshSwf':target_swf.relative_to(ROOT).as_posix(),
             'scope':'source-only canonical assembly; candidate SWF is not copied; no formal runtime promotion'}
    if not args.apply:print(json.dumps(summary,ensure_ascii=False));return
    token=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'-'+uuid.uuid4().hex[:10]
    staging=safe(ROOT/'tmp/cf6-vector-canonical'/token/'source',ROOT/'tmp/cf6-vector-canonical')
    staging.mkdir(parents=True)
    for item in source_rows:
        source=safe(candidate/item['path'],candidate)
        relative=name+'.xfl' if item['path']==candidate_name+'.xfl' else item['path']
        dest=safe(staging/relative,staging);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest)
        if sha(dest)!=item['sha256']:raise ValueError('source changed during snapshot copy')
    finalize(staging/(name+'.xfl'),name+'.swf',inputs)
    if closure(candidate,candidate_name)!=source_rows:raise ValueError('candidate changed during source assembly')
    new_rows=inventory(staging)
    current=inventory(target)
    if current==new_rows:
        summary.update(state='canonical source already matches; existing canonical SWF left unchanged')
        print(json.dumps(summary,ensure_ascii=False));return
    # All recursive move targets are fully resolved and checked before mutation.
    archive=safe(ARCHIVE_ROOT/name/token,ARCHIVE_ROOT);archive.mkdir(parents=True)
    archived_source=safe(archive/'source',ARCHIVE_ROOT)
    archived_swf=safe(archive/(name+'.swf'),ARCHIVE_ROOT)
    record={'schema':'cf6-canonical-native-assembly.v1',**summary,'transaction':token,
            'candidateSource':candidate.relative_to(ROOT).as_posix(),'candidateClosure':source_rows,
            'candidateClosureSha256':signature(source_rows),'canonicalClosure':new_rows,'canonicalClosureSha256':signature(new_rows),
            'oldSource':current,'oldSwf':{'bytes':target_swf.stat().st_size,'sha256':sha(target_swf)} if target_swf.is_file() else None,
            'archive':archive.relative_to(ROOT).as_posix(),'state':'prepared',
            'sourceManifest':source_manifest.relative_to(ROOT).as_posix() if source_manifest else None,
            'sourceManifestSha256':sha(source_manifest) if source_manifest else None}
    receipt=archive/'assembly.json';receipt.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    moved_source=False;moved_swf=False
    try:
        if target.exists():os.replace(target,archived_source);moved_source=True
        if target_swf.exists():os.replace(target_swf,archived_swf);moved_swf=True
        os.replace(staging,target)
        if inventory(target)!=new_rows:raise ValueError('canonical source changed after placement')
        if moved_source and inventory(archived_source)!=current:raise ValueError('archived source identity mismatch')
        if moved_swf and sha(archived_swf)!=record['oldSwf']['sha256']:raise ValueError('archived SWF identity mismatch')
        record['state']='native_source_installed; exact canonical CS6 compile still required'
    except Exception as error:
        record['state']='interrupted; preserve archive and inspect before retry';record['error']=str(error)
        receipt.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        raise
    receipt.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (HERE/'canonical').mkdir(exist_ok=True)
    (HERE/'canonical'/(name+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    summary.update(state=record['state'],archive=record['archive'],canonicalClosureSha256=record['canonicalClosureSha256'])
    print(json.dumps(summary,ensure_ascii=False))


if __name__=='__main__':main()
