"""Frozen CF6 transition timeline with the current CF7 tyrant's native parts."""
from pathlib import Path
import copy
import hashlib
import json
from lxml import etree as E
from clipped_vector import ClippedPart

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6光头保安-变身-R2'
TYRANT = ROOT/'flashswf/arts/new/Codex专用素材/LIBRARY'
MANIFEST = ROOT/'tools/gamma-echo-assets/native-manifest.json'
NS = {'x':'http://ns.adobe.com/xfl/2008/'}


def verify_archive():
    receipt=json.loads((ARCHIVE/'archive-origin.json').read_text('utf8'))
    for row in receipt['members']:
        data=(ARCHIVE/row['path']).read_bytes()
        assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'], row['path']


def current_parts():
    variants=json.loads(MANIFEST.read_text('utf8'))['variants']
    parts=next(v['parts'] for v in variants if v['linkage']=='敌人-完全体克隆兽')
    assert {p['id'] for p in parts}==set(range(262,275))
    trees={}
    def visit(name):
        if name in trees:return
        tree=E.parse(str(TYRANT/(name+'.xml')),E.XMLParser(strip_cdata=False)).getroot()
        assert not tree.findall('.//x:DOMBitmapInstance',NS) and not tree.findall('.//x:BitmapFill',NS)
        assert not tree.findall('.//x:script',NS), 'Current tyrant drawing must remain pure art'
        trees[name]=tree
        for child in tree.iter():
            ref=child.get('libraryItemName')
            if ref:visit(ref)
    for row in parts:visit(row['name'])
    return parts,trees


def input_paths():
    _,trees=current_parts()
    return [MANIFEST,ARCHIVE/'archive-origin.json',
        *[TYRANT/(name+'.xml') for name in sorted(trees)],
        *sorted((ARCHIVE/'transition-parts').glob('*.svg'))]


def add_parts(build,result,parts,stats):
    verify_archive()
    native,vector=build.native,build.vector
    current,trees=current_parts()
    rename={name:build.PREFIX+'变身/现役暴君/'+name.split('/完全体/',1)[1] for name in trees}
    for old,tree in trees.items():
        item=copy.deepcopy(tree);name=rename[old]
        item.set('name',name);item.set('itemID',native.item_id(name))
        for attr in list(item.attrib):
            if attr.startswith('linkage'):del item.attrib[attr]
        item.find('x:timeline/x:DOMTimeline',NS).set('name',name.rsplit('/',1)[-1])
        for child in item.iter():
            ref=child.get('libraryItemName')
            if ref:child.set('libraryItemName',rename[ref])
        result[name]=item
    for row in current:parts[row['id']]=rename[row['name']]
    for cid in (880,882,883,884,885,886):
        name=build.PREFIX+'变身/撕裂衣服/'+str(cid)
        converted,report=ClippedPart(ARCHIVE/'transition-parts'/(str(cid)+'.svg'),name,(0,0)).build()
        for key,item in converted.items():
            if key in result:assert native.xml_bytes(result[key])==native.xml_bytes(item), key
        result.update(converted);parts[cid]=name;stats.append({'id':cid,**report})
    # Original 878 contains only the historical bitmap gun. Keep its grip and
    # authored flight matrices, replacing the image with the same native SPAS12.
    parts[878]=parts[593]
    return {'timeline':887,'authoredFrames':75,'spawnFrame':70,'retireAfterReady':True,
        'currentTyrantParts':[{'id':row['id'],'source':row['name'],'private':parts[row['id']]} for row in current],
        'sourceArchive':ARCHIVE.relative_to(ROOT).as_posix(),
        'successor':{'unitId':460,'linkage':'敌人-完全体克隆兽','height':230,
            'inheritedCombatFields':['等级'],'inheritedDisplayFields':['名字','称号'],'freshCombatState':True},
        'deathOptions':{'noCount':True,'noCorpse':True}}
