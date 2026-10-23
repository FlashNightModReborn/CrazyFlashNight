"""Extract approved reachable native prop groups; no SWF bytes or shared Flash process touched."""
from pathlib import Path
import argparse
import copy
import json
import xml.etree.ElementTree as ET
import calibrate as c

Q='{http://ns.adobe.com/xfl/2008/}'
ET.register_namespace('',Q[1:-1])
GROUPS=[{'name':'CF6_Prop_A06_StatueLeft','assemblyId':'A06-00806-g','memberIds':['A06-00806-g']},
        {'name':'CF6_Prop_A06_StatueRight','assemblyId':'A06-01072-g','memberIds':['A06-01072-g']}]

def tag(name,attrs=None,parent=None):
    node=ET.Element(Q+name,attrs or {})
    if parent is not None:parent.append(node)
    return node

def safe(base,relative):
    result=(base/relative).resolve()
    if not result.is_relative_to(base.resolve()):raise ValueError('source closure escaped directory')
    return result

def resource(group,rows):
    bases={r['xflDirectory'] for r in rows}
    if len(bases)!=1:raise ValueError('mixed source libraries need an explicit namespace import')
    source=c.ROOT/next(iter(bases));doc=ET.parse(source/'DOMDocument.xml').getroot()
    target=c.ROOT/'flashswf/backgrounds/cf6/props'/group['name']
    symbols={};media=set()
    def visit(name,stack=()):
        if name in stack:raise ValueError('recursive native symbol')
        if name in symbols:return
        rel='LIBRARY/'+name+'.xml';data=safe(source,rel).read_bytes();root=ET.fromstring(data)
        if root.get('name')!=name:raise ValueError('symbol name mismatch')
        symbols[name]=data
        for n in root.findall('.//x:DOMSymbolInstance',c.NS):visit(n.get('libraryItemName'),stack+(name,))
        for n in root.findall('.//x:DOMBitmapInstance',c.NS):media.add(n.get('libraryItemName'))
        for n in root.findall('.//x:BitmapFill',c.NS):media.add(n.get('bitmapPath'))
    for row in rows:visit(row['symbol'])
    output={target/('LIBRARY/'+n+'.xml'):data for n,data in symbols.items()}
    newdoc=tag('DOMDocument',{'width':'512','height':'512','frameRate':'30','xflVersion':'2.2','creatorInfo':'Adobe Flash Professional CS6','platform':'Windows','versionInfo':doc.get('versionInfo','Saved by Adobe Flash Windows 12.0'),'majorVersion':'12'})
    media_items={n.get('name'):n for n in doc.findall('./x:media/x:DOMBitmapItem',c.NS)}
    newmedia=tag('media',parent=newdoc)
    media_inputs=[]
    for name in sorted(media):
        item=copy.deepcopy(media_items[name]);newmedia.append(item)
        for rel in ['LIBRARY/'+item.get('href'),'bin/'+item.get('bitmapDataHRef')]:
            output[target/rel]=safe(source,rel).read_bytes()
        media_inputs.append({'path':(target/'LIBRARY'/item.get('href')).relative_to(c.ROOT).as_posix(),'sha256':c.sha(output[target/'LIBRARY'/item.get('href')]),'bytes':len(output[target/'LIBRARY'/item.get('href')])})
    includes=tag('symbols',parent=newdoc)
    for name in sorted(symbols):tag('Include',{'href':name+'.xml','loadImmediate':'false'},includes)
    timeline=tag('DOMTimeline',{'name':group['name']},tag('timelines',parent=newdoc));layers=tag('layers',parent=timeline)
    initialize=tag('DOMLayer',{'name':'initialize-native-masks'},layers);frames=tag('frames',parent=initialize)
    frame=tag('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},frames);tag('elements',parent=frame)
    frame=tag('DOMFrame',{'index':'1','duration':'1','keyMode':'9728'},frames);tag('elements',parent=frame)
    tag('script',parent=tag('Actionscript',parent=frame)).text='this._cf6DepthPropReady=true;stop();'
    layer=tag('DOMLayer',{'name':'native-prop-art'},layers)
    frame=tag('DOMFrame',{'index':'0','duration':'2','keyMode':'9728'},tag('frames',parent=layer));elements=tag('elements',parent=frame)
    pivot=rows[0]['worldPivot']
    for row in rows:
        if not c.near(row['worldPivot'],pivot):raise ValueError('group parts do not share world ground pivot')
        original=c.roots((c.HERE/row['baseline']).read_bytes())[row['instanceIndex']]
        instance=copy.deepcopy(original);elements.append(instance)
        node=instance.find('./x:matrix/x:Matrix',c.NS)
        if node is None:raise ValueError('selected native instance has no matrix')
        node.attrib.clear();node.attrib.update({k:format(v,'.12g') for k,v in zip(c.KEYS,row['artMatrix'])})
        for ancestor in row['sourceChain'][:-1]:
            parent=ET.parse(source/ancestor['file']).getroot()
            item=parent.findall('.//x:DOMSymbolInstance',c.NS)[ancestor['instanceIndex']]
            if item.find('./x:color',c.NS) is not None or item.find('./x:filters',c.NS) is not None:
                raise ValueError('ancestor color/filter requires copying its wrapper before extraction')
    output[target/'DOMDocument.xml']=ET.tostring(newdoc,encoding='utf8',xml_declaration=True)
    profile=ET.parse(source/'PublishSettings.xml').getroot()
    for name,value in {'flashFileName':group['name']+'.swf','defaultNames':'0','flashDefaultName':'0','flash':'1','html':'0','projectorWin':'0','projectorMac':'0','gif':'0','jpeg':'0','png':'0','swc':'0'}.items():
        node=profile.find('.//PublishFormatProperties/'+name)
        if node is None:raise ValueError('missing publish setting '+name)
        node.text=value
    output[target/'PublishSettings.xml']=ET.tostring(profile,encoding='utf8',xml_declaration=True)
    entry=next(source.glob('*.xfl'));output[target/(group['name']+'.xfl')]=entry.read_bytes()
    layer={'id':group['name'],'role':'depth-prop','url':'flashswf/backgrounds/cf6/props/'+group['name']+'.swf','x':pivot[0],'y':pivot[1],'sortY':pivot[1],'visualScale':1,'pivot':{'x':0,'y':0}}
    record={**group,'mapId':rows[0]['mapId'],'xfl':(target/(group['name']+'.xfl')).relative_to(c.ROOT).as_posix(),
            'swf':'flashswf/backgrounds/cf6/props/'+group['name']+'.swf','worldPivot':pivot,'layer':layer,'nativeSymbols':len(symbols),'intrinsicBitmaps':len(media),
            'registration':'root local origin is world ground pivot; all per-part holder-local matrices already include map calibration',
            'excludedBackgroundInstances':[{'id':r['id'],'xflDirectory':r['xflDirectory'],'parentFile':r['parentFile'],'instanceIndex':r['instanceIndex'],'symbol':r['symbol']} for r in rows],
            'nativeInputs':media_inputs,'files':[{'path':p.relative_to(c.ROOT).as_posix(),'bytes':len(data),'sha256':c.sha(data)} for p,data in sorted(output.items())]}
    return output,record

def generate():
    layout=c.read(c.HERE/'generated/instance-layout.json');index={r['id']:r for r in layout['instances']}
    reach=c.read(c.HERE/'generated/depth-reachability.json');eligible={r['assemblyId'] for r in reach['groups'] if r['needsDepthSplit']}
    outputs={};records=[]
    for group in GROUPS:
        if group['assemblyId'] not in eligible:raise ValueError('unproven front/back access')
        generated,record=resource(group,[index[i] for i in group['memberIds']]);outputs.update(generated);records.append(record)
    manifest={'schema':'cf6-native-depth-props.v1','state':'native source prepared; fresh CS6 plus actual sorted-holder consumer required','groups':records}
    fragment={'schema':'cf6-depth-props-fragment.v1','coordinateSpace':'final-world; asset root uses holder-local art matrices; no further viewport scaling','maps':{'A06':{'layers':[r['layer'] for r in records]}}}
    outputs[c.HERE/'generated/depth-props-manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    outputs[c.HERE/'generated/depth-props.fragment.json']=(json.dumps(fragment,ensure_ascii=False,indent=2)+'\n').encode()
    return outputs,records

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();outputs,records=generate()
    for path,data in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=data:raise SystemExit('stale depth prop source: '+str(path))
        elif not path.exists() or path.read_bytes()!=data:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    depth={'schema':'cf6-depth-prop-exclusions.v1','enabled':True,'groups':[{'name':r['name'],'memberIds':r['memberIds'],'mapId':r['mapId'],'swf':r['swf']} for r in records]}
    depth_data=(json.dumps(depth,ensure_ascii=False,indent=2)+'\n').encode();path=c.HERE/'depth-recipe.json'
    if args.check:
        if path.read_bytes()!=depth_data:raise SystemExit('stale depth exclusion recipe')
    else:path.write_bytes(depth_data)
    print(json.dumps({'groups':len(records),'nativeFiles':len(outputs)-2,'mode':'check' if args.check else 'build'}))

if __name__=='__main__':main()