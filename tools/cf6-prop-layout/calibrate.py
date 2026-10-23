"""Per-instance native XFL calibration. World anchors are never rescaled here twice."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools/asset-metrology'))
from xfl_geometry import Geometry, bounds, matrix, multiply, point, IDENTITY, NS
KEYS = ('a', 'b', 'c', 'd', 'tx', 'ty')
DOCUMENT_CACHE = {}
GEOMETRY_CACHE = {}
PINNED_XML = {}

class PropGeometry(Geometry):
    """Contour bounds with declared native bitmap bounds and setMask envelope intersection."""
    def __init__(self, library):
        super().__init__(library)
        doc=ET.parse(library.parent/'DOMDocument.xml').getroot()
        self.media={n.get('name'):(float(n.get('frameRight','0'))/20,float(n.get('frameBottom','0'))/20) for n in doc.findall('./x:media/x:DOMBitmapItem',NS)}
    def rectangle(self, box, transform):
        x0,y0,x1,y1=box
        pts=[point(transform,p) for p in [(x0,y0),(x1,y0),(x1,y1),(x0,y1)]]
        return [(pts[i],pts[(i+1)%4]) for i in range(4)]
    def element(self, element, transform, stack):
        if element.tag.endswith('DOMBitmapInstance'):
            local=element.find('./x:matrix/x:Matrix',NS)
            m=multiply(transform,matrix(local.attrib) if local is not None else IDENTITY)
            w,h=self.media[element.get('libraryItemName')]
            self.warnings.add('bitmap extent uses declared native media rectangle')
            yield from self.rectangle((0,0,w,h),m)
        else:
            yield from super().element(element,transform,stack)
    def symbol(self,name,frame=0,transform=IDENTITY,stack=()):
        if name not in self.cache:self.cache[name]=ET.parse(self.library/(name+'.xml')).getroot()
        root=self.cache[name]
        instances=root.findall('.//x:DOMSymbolInstance',NS)
        named={i.get('name'):i for i in instances if i.get('name')}
        scripts=' '.join(n.text or '' for n in root.findall('.//x:script',NS))
        if 'setMask' in scripts and 'content' in named and 'maskShape' in named:
            contours=[list(self.element(named[k],IDENTITY,stack+(name,))) for k in ('content','maskShape')]
            if not all(contours):return
            boxes=[bounds(c) for c in contours]
            box=[max(b[0] for b in boxes),max(b[1] for b in boxes),min(b[2] for b in boxes),min(b[3] for b in boxes)]
            if box[0]>box[2] or box[1]>box[3]:raise ValueError('empty mask envelope')
            self.warnings.add('setMask uses intersected axis-aligned envelopes; not pixel silhouette')
            yield from self.rectangle(box,transform)
        else:yield from super().symbol(name,frame,transform,stack)

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(data):
    return hashlib.sha256(data).hexdigest()

def about_pivot(before, pivot, scale):
    if not math.isfinite(scale) or not 0 < scale <= 2:
        raise ValueError('invalid local visual scale')
    anchor = point(before, pivot)
    a,b,c,d,_,_ = before
    return (a*scale,b*scale,c*scale,d*scale,
            anchor[0] - scale*(a*pivot[0]+c*pivot[1]),
            anchor[1] - scale*(b*pivot[0]+d*pivot[1]))

def holder_matrix(world_linear, pivot):
    a,b,c,d = world_linear
    return (a,b,c,d,-a*pivot[0]-c*pivot[1],-b*pivot[0]-d*pivot[1])

def near(a,b):
    return len(a)==len(b) and all(abs(x-y)<1e-7 for x,y in zip(a,b))

def roots(source):
    return ET.fromstring(source).findall('.//x:DOMSymbolInstance', NS)

def patched_sources(recipe):
    """Pure recipe-to-byte overlay; shared by generators and the measured report builder."""
    outputs={}; originals={}
    for item in recipe['instances']:
        target=ROOT/item['xflDirectory']/item['parentFile']
        original=(HERE/item['baseline']).read_bytes()
        if sha(original)!=item['baselineSha256']:raise ValueError('baseline identity changed')
        if target in originals and originals[target]!=original:raise ValueError('inconsistent parent baselines')
        originals[target]=original
    edits={}
    for item in recipe['instances']:
        target=ROOT/item['xflDirectory']/item['parentFile'];original=originals[target]
        selected=roots(original)[item['instanceIndex']]
        if selected.get('libraryItemName')!=item['symbol']:raise ValueError('symbol selector changed')
        before=matrix(selected.find('./x:matrix/x:Matrix',NS).attrib)
        after=about_pivot(before,item['pivotNative'],item['localVisualScale'])
        match=list(re.finditer(rb'<DOMSymbolInstance\b[^>]*>.*?</DOMSymbolInstance>',original,re.S))[item['instanceIndex']]
        new_matrix=('<Matrix '+' '.join(k+'="'+format(v,'.12g')+'"' for k,v in zip(KEYS,after))+'/>').encode()
        replacement,count=re.subn(rb'<Matrix\b[^>]*/>',new_matrix,match.group(),count=1)
        if count!=1:raise ValueError('missing explicit instance matrix')
        if any(a==match.start() for a,b,c in edits.setdefault(target,[])):raise ValueError('duplicate recipe instance')
        edits[target].append((match.start(),match.end(),replacement))
    for target,changes in edits.items():
        data=originals[target]
        for start,end,replacement in sorted(changes,reverse=True):data=data[:start]+replacement+data[end:]
        outputs[target]=data
    return originals,outputs

def depth_exclusions(calibrated):
    """Remove approved extracted instances from calibrated parent bytes, without raster work."""
    recipe_path=HERE/'depth-recipe.json'
    if not recipe_path.exists():return dict(calibrated)
    depth=read(recipe_path)
    if not depth.get('enabled'):return dict(calibrated)
    recipe=read(HERE/'recipe.json');index={i['id']:i for i in recipe['instances']}
    members=[member for group in depth['groups'] for member in group['memberIds']]
    if len(members)!=len(set(members)):raise ValueError('duplicate depth extraction member')
    removals={};result=dict(calibrated)
    for member in members:
        row=index[member];target=ROOT/row['xflDirectory']/row['parentFile'];data=calibrated[target]
        nodes=roots(data);node=nodes[row['instanceIndex']]
        if node.get('libraryItemName')!=row['symbol']:raise ValueError('depth source selector changed')
        match=list(re.finditer(rb'<DOMSymbolInstance\b[^>]*>.*?</DOMSymbolInstance>',data,re.S))[row['instanceIndex']]
        removals.setdefault(target,[]).append((match.start(),match.end()))
    for target,spans in removals.items():
        data=calibrated[target]
        for start,end in sorted(spans,reverse=True):data=data[:start]+data[end:]
        result[target]=data
    return result

def overlay_outputs(outputs):
    """Pure in-memory generator integration. Does not read target files, measure, or write."""
    originals,calibrated=patched_sources(read(HERE/'recipe.json'));expected=depth_exclusions(calibrated)
    result=dict(outputs)
    for key,data in outputs.items():
        path=Path(key).resolve()
        if path not in expected:continue
        if data not in (originals[path],calibrated[path],expected[path]):raise ValueError('unrecognized generator bytes: '+str(path))
        result[key]=expected[path]
    return result

def path_chain(base, parent, child_index):
    """Find exact display occurrence; fail if a shared parent would change multiple instances."""
    cache = DOCUMENT_CACHE.setdefault(str(base), {})
    found = []
    def visit(rel, chain, transform, stack):
        if rel in stack: raise ValueError('cyclic XFL dependency')
        if rel not in cache: cache[rel]=ET.fromstring(PINNED_XML[base/rel]) if base/rel in PINNED_XML else ET.parse(base/rel).getroot()
        for index, inst in enumerate(cache[rel].findall('.//x:DOMSymbolInstance',NS)):
            local=matrix(inst.find('./x:matrix/x:Matrix',NS).attrib)
            record={'file':rel,'instanceIndex':index,'symbol':inst.get('libraryItemName'),'matrix':local}
            if rel==parent and index==child_index:
                found.append((chain+[record],transform))
                continue
            if rel!=parent:visit('LIBRARY/'+inst.get('libraryItemName')+'.xml',chain+[record],multiply(transform,local),stack+(rel,))
    visit('DOMDocument.xml',[],IDENTITY,())
    if len(found)!=1: raise ValueError('selected occurrence not unique: '+parent+' '+str(len(found)))
    return found[0]

def build(recipe):
    policy=read(ROOT/'tools/cf6-prototype/viewport-policy.json')
    map_scale=max(policy['targetViewport'][i]/policy['sourceViewport'][i] for i in (0,1))
    if policy['actorScale']!=1 or policy['cameraBaseScale']!=1: raise ValueError('actor/camera contract changed')
    maps=read(ROOT/'tools/cf6-map-source/generated/map-input.json')['maps']
    rows=[]
    originals,outputs=patched_sources(recipe)
    PINNED_XML.clear();PINNED_XML.update(originals);DOCUMENT_CACHE.clear();GEOMETRY_CACHE.clear()
    for item in recipe['instances']:
        base=ROOT/item['xflDirectory']; relative=item['parentFile']; target=base/relative
        original=(HERE/item['baseline']).read_bytes()
        if sha(original)!=item['baselineSha256']: raise ValueError('baseline identity changed')
        elements=roots(original); selected=elements[item['instanceIndex']]
        if selected.get('libraryItemName')!=item['symbol']: raise ValueError('symbol selector changed')
        before=matrix(selected.find('./x:matrix/x:Matrix',NS).attrib)
        pivot=item['pivotNative']; local_scale=item['localVisualScale']
        after=about_pivot(before,pivot,local_scale)
        chain,parent_to_asset=path_chain(base,relative,item['instanceIndex'])
        chain[-1]['matrix']=before
        selected_keys={(i['xflDirectory'],i['parentFile'],i['instanceIndex']) for i in recipe['instances']}
        if any((item['xflDirectory'],c['file'],c['instanceIndex']) in selected_keys for c in chain[:-1]):raise ValueError('nested calibrations require one shared assembly pivot; do not scale parent and child independently')
        world_before=multiply(parent_to_asset,before)
        origin=[0,0] if item['mapId']=='TUTORIAL' else maps[item['mapId']]['nativeBounds'][:2]
        native_anchor=point(world_before,pivot)
        native_anchor=[native_anchor[i]+origin[i] for i in (0,1)]
        world_anchor=[v*map_scale for v in native_anchor]
        linear=[v*map_scale*local_scale for v in world_before[:4]]
        art=holder_matrix(linear,pivot)
        if str(base) not in GEOMETRY_CACHE:GEOMETRY_CACHE[str(base)]=PropGeometry(base/'LIBRARY')
        g=GEOMETRY_CACHE[str(base)]
        natural=bounds(list(g.symbol(item['symbol'])))
        before_bounds=bounds(list(g.symbol(item['symbol'],transform=multiply((map_scale,0,0,map_scale,0,0),world_before))))
        world_after=multiply(parent_to_asset,after)
        after_bounds=bounds(list(g.symbol(item['symbol'],transform=multiply((map_scale,0,0,map_scale,0,0),world_after))))
        if not near(point(before,pivot),point(after,pivot)) or not near(point(art,pivot),(0,0)):raise ValueError('pivot drift')
        rows.append({**item,'sourceChain':chain,'nativeBounds':natural,'parentLocalBefore':before,'parentLocalAfter':after,
                     'nativeWorldPivot':native_anchor,'worldPivot':world_anchor,'sortY':world_anchor[1],
                     'artMatrixSpace':'holder-local','artMatrix':art,'holderWorldXY':world_anchor,
                     'currentSizeWorldPx':[before_bounds[2]-before_bounds[0],before_bounds[3]-before_bounds[1]],
                     'targetSizeWorldPx':[after_bounds[2]-after_bounds[0],after_bounds[3]-after_bounds[1]],
                     'contourWarnings':sorted(g.warnings),
                     'consumer':item['xflDirectory']+'.swf'})
    report={'schema':'cf6-prop-instance-layout.v1','mapScale':map_scale,'actorScale':1,'cameraScale':1,
            'coordinateContract':'nativeWorldPivot includes original map origin; worldPivot is final CF7 world coordinate; holder translates once; artMatrix maps pivotNative to zero; no additional mapScale',
            'instances':rows,'state':'native source only; fresh CS6 and game visual acceptance required'}
    outputs=depth_exclusions(outputs)
    depth_path=HERE/'depth-recipe.json'
    if depth_path.exists() and read(depth_path).get('enabled'):
        consumers={member:g['swf'] for g in read(depth_path)['groups'] for member in g['memberIds']}
        for row in rows:
            if row['id'] in consumers:row.update(consumer=consumers[row['id']],excludedFromBackground=True)
    outputs[HERE/'generated/instance-layout.json']=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode()
    return outputs

def main():
    p=argparse.ArgumentParser(); p.add_argument('--apply',action='store_true');p.add_argument('--check',action='store_true')
    args=p.parse_args(); recipe=read(HERE/'recipe.json');outputs=build(recipe)
    for path,expected in outputs.items():
        current=path.read_bytes() if path.exists() else None
        if args.check:
            if current!=expected:raise SystemExit('stale prop calibration: '+str(path))
        elif args.apply:
            if path.suffix=='.xml':
                baselines=[(HERE/i['baseline']).read_bytes() for i in recipe['instances'] if ROOT/i['xflDirectory']/i['parentFile']==path]
                if current!=expected and current not in baselines and current!=patched_sources(recipe)[1][path]:raise SystemExit('unrecognized source edit: '+str(path))
            if current!=expected:
                path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(expected)
    print(json.dumps({'instances':len(recipe['instances']),'files':len(outputs),'mode':'check' if args.check else 'apply' if args.apply else 'preview'}))

if __name__=='__main__':main()
