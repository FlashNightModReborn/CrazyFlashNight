"""Import r06 ammunition artwork as native XFL shapes; SWFs are published by CS6."""
from __future__ import annotations
import argparse,hashlib,json,math,re,sys
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/tesla-map-assets'))
sys.path.insert(0,str(ROOT/'tools/asset-metrology'))
from native_vector import svg_to_xfl_legacy as base
from native_vector.vector_shapes import ShapeConverter
from xfl_geometry import Geometry,bounds,IDENTITY
N='{'+base.NS+'}'
CONFIG=Path(__file__).with_name('assembly.json')
NS={'x':base.NS}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def item_id(name):return '6acd0600-'+hashlib.sha256(name.encode('utf8')).hexdigest()[:8]
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def xml_bytes(root):
    ET.indent(root,space='  ')
    return ET.tostring(root,encoding='utf-8',xml_declaration=True)+b'\n'
def E(tag,attrs=None,parent=None):return base.E(tag,attrs,parent)

def graphic(row,config):
    source=ROOT/config['source_folder']/'svg'/(row['id']+'.svg')
    assert sha(source)==row['source_sha256'],'Frozen artwork changed: '+row['id']
    svg=ET.parse(source).getroot();vb=base.nums(svg.get('viewBox'))
    assert vb==[0,0,1254,1254]
    converter=ShapeConverter(svg)
    scale=128/vb[2]
    shapes=converter.flatten(svg,matrix=(scale,0,0,scale,-64,-64))
    assert shapes and not any('fallback' in k and v for k,v in converter.stats.items()),converter.stats
    root=E('DOMSymbolItem',{'name':row['graphic'],'itemID':item_id(row['graphic']),'symbolType':'graphic'})
    layers=E('layers',parent=E('DOMTimeline',{'name':row['graphic'].split('/')[-1]},E('timeline',parent=root)))
    elements=E('elements',parent=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},
                 E('frames',parent=E('DOMLayer',{'name':'r06矢量','color':'#6C9C89'},layers))))
    elements.extend(shapes)
    geo=Geometry(ROOT/row['owner']/'LIBRARY')
    contour=[segment for shape in shapes for segment in geo.element(shape,IDENTITY,())]
    box=bounds(contour);assert box and all(math.isfinite(v) for v in box)
    return root,box,dict(converter.stats)

def instance(row,fit,box):
    length=max(box[2]-box[0],box[3]-box[1]);scale=fit['fit_longest_side_px']/length
    cx,cy=(box[0]+box[2])/2,(box[1]+box[3])/2
    tx=fit['fit_center_px'][0]-cx*scale;ty=fit['fit_center_px'][1]-cy*scale
    inst=E('DOMSymbolInstance',{'libraryItemName':row['graphic'],'symbolType':'graphic','loop':'single frame','firstFrame':'0'})
    E('Matrix',{'a':base.fmt(scale),'d':base.fmt(scale),'tx':base.fmt(tx),'ty':base.fmt(ty)},E('matrix',parent=inst))
    E('Point',parent=E('transformationPoint',parent=inst))
    return inst

def wrapper(row,box):
    path=ROOT/row['wrapper']
    if row['id']=='06' and not path.exists():
        root=E('DOMSymbolItem',{'name':row['symbol'],'itemID':item_id(row['symbol']),
                 'linkageExportForAS':'true','linkageIdentifier':row['linkage']})
        layers=E('layers',parent=E('DOMTimeline',{'name':row['symbol'].split('/')[-1]},E('timeline',parent=root)))
        E('elements',parent=E('DOMFrame',{'index':'0','keyMode':'9728'},
                 E('frames',parent=E('DOMLayer',{'name':'图标','color':'#6C9C89'},layers))))
    else:
        root=ET.parse(path).getroot()
    assert root.get('linkageIdentifier')==row['linkage'] and root.get('name')==row['symbol']
    layers=root.findall('./x:timeline/x:DOMTimeline/x:layers/x:DOMLayer',NS)
    if row['id']=='22':
        assert len(layers)==4 and layers[1].get('layerType')=='mask'
        assert 'stop();' in ''.join(root.itertext()) and layers[2].get('parentLayerIndex')=='1'
        targets=[(layers[2].find('./x:frames/x:DOMFrame[@index="0"]/x:elements',NS),row['fits'][0]),
                 (layers[3].find('./x:frames/x:DOMFrame[@index="1"]/x:elements',NS),row['fits'][1])]
    else:
        assert layers and root.find('.//x:Actionscript',NS) is None
        targets=[]
        for index,layer in enumerate(layers):
            assert layer.get('layerType') not in ['mask','folder','guide']
            frames=layer.findall('./x:frames/x:DOMFrame',NS)
            assert len(frames)==1 and frames[0].get('index')=='0' and frames[0].get('duration','1')=='1'
            targets.append((frames[0].find('./x:elements',NS),row['fits'][0] if index==0 else None))
    for elements,fit in targets:
        assert elements is not None
        for old in list(elements):elements.remove(old)
        if fit is not None:elements.append(instance(row,fit,box))
    return root

def update_document(path,rows):
    text=path.read_text(encoding='utf-8-sig')
    parsed=ET.fromstring(text)
    folders={e.get('name') for e in parsed.findall('./x:folders/x:DOMFolderItem',NS)}
    entries=[]
    for name in ['Codex','Codex/弹药r06']:
        if name not in folders:entries.append(f'    <DOMFolderItem name="{name}" itemID="{item_id(name)}"/>')
    if entries:
        assert text.count('</folders>')==1
        text=text.replace('</folders>','\n'.join(entries)+'\n  </folders>',1)
    includes={e.get('href') for e in parsed.findall('./x:symbols/x:Include',NS)}
    new=[]
    for row in rows:
        names=[row['graphic']]+([row['symbol']] if row['id']=='06' else [])
        for name in names:
            href=name+'.xml'
            if href not in includes:new.append(f'    <Include href="{href}" loadImmediate="false" itemID="{item_id(name)}"/>')
    if new:
        assert text.count('</symbols>')==1
        text=text.replace('</symbols>','\n'.join(new)+'\n  </symbols>',1)
    return text.encode('utf8')

def item_xml_bytes():
    p=ROOT/'data/items/消耗品_弹夹.xml';raw=p.read_bytes();text=raw.decode('utf-8-sig')
    pattern=r'(<name>高温自锐式针弹</name>\s*<displayname>高温自锐式针弹</displayname>\s*<icon>)([^<]+)(</icon>)'
    matches=re.findall(pattern,text);assert len(matches)==1 and matches[0][1] in ['机枪贫铀穿甲弹','高温自锐式针弹']
    text=re.sub(pattern,lambda m:m[1]+'高温自锐式针弹'+m[3],text)
    return (b'\xef\xbb\xbf' if raw.startswith(b'\xef\xbb\xbf') else b'')+text.encode('utf8')

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--report',type=Path);a=p.parse_args()
    config=read(CONFIG);rows=config['items'];assert len(rows)==22 and len({r['linkage'] for r in rows})==22
    outputs={};report=[]
    # Build all intended bytes before touching the source tree.
    for row in rows:
        art,box,stats=graphic(row,config)
        outer=wrapper(row,box)
        outputs[ROOT/row['owner']/'LIBRARY'/(row['graphic']+'.xml')]=xml_bytes(art)
        outputs[ROOT/row['wrapper']]=xml_bytes(outer)
        report.append({'id':row['id'],'graphic_bounds_128':box,'stats':stats,'linkage':row['linkage'],'fits':row['fits']})
    for owner in sorted({r['owner'] for r in rows}):
        path=ROOT/owner/'DOMDocument.xml'
        outputs[path]=update_document(path,[r for r in rows if r['owner']==owner])
    outputs[ROOT/'data/items/消耗品_弹夹.xml']=item_xml_bytes()
    differences=[p for p,data in outputs.items() if not p.exists() or p.read_bytes()!=data]
    if a.check:
        assert not differences,'Source drift: '+', '.join(str(p.relative_to(ROOT)) for p in differences)
    else:
        for p in differences:p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(outputs[p])
    # The installed closure must contain no imported bitmap or script in the artwork.
    for row in rows:
        art=ET.parse(ROOT/row['owner']/'LIBRARY'/(row['graphic']+'.xml')).getroot()
        assert art.get('symbolType')=='graphic'
        assert not any(art.findall('.//x:'+name,NS) for name in ['DOMBitmapInstance','BitmapFill','DOMSymbolInstance','Actionscript'])
        outer=ET.parse(ROOT/row['wrapper']).getroot()
        assert outer.get('linkageIdentifier')==row['linkage']
        doc=ET.parse(ROOT/row['owner']/'DOMDocument.xml').getroot()
        for name in [row['graphic'],row['symbol']]:
            includes=[i for i in doc.findall('./x:symbols/x:Include',NS) if i.get('href')==name+'.xml']
            assert len(includes)==1
    result={'mode':'check' if a.check else 'build','count':22,'changed_files':len(differences),'items':report,
            'files':[{'path':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in outputs],
            'swf_written':False}
    if a.report:a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'mode':result['mode'],'count':22,'changed_files':len(differences),'native_shapes':sum(r['stats']['native_shapes'] for r in report)},ensure_ascii=False))
if __name__=='__main__':main()
