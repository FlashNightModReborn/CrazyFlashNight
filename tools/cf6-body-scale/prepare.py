"""Independent native host for seven real CF6 humanoid RSLs and production initialization."""
from pathlib import Path
import argparse,hashlib,json,shutil,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
NS='http://ns.adobe.com/xfl/2008/'
def build(check=False):
    sys.path.insert(0,str(ROOT/'tools/cf6-field-combat'))
    from check_structure import check as check_structure
    check_structure(HERE/'Cf6BodyScaleNativeTest.as.txt');check_structure(HERE/'Cf6BodyScaleLiveProbe.as.txt')
    source=ROOT/'scripts/Cf6ActorAppearanceNativeHost';dest=ROOT/'scripts/tmp-cf6-body-scale-host';outputs={}
    for p in (source/'LIBRARY').rglob('*'):
        if p.is_file():outputs[dest/p.relative_to(source)]=p.read_bytes()
    rows=json.loads((ROOT/'tools/cf6-prop-layout/generated/body-scale-probe-inputs.json').read_text(encoding='utf-8'))
    unique={r['swf']:r for r in rows};imports=[];instances=[];identities={}
    for i,(url,row) in enumerate(unique.items()):
        raw=(ROOT/url).read_bytes();identities[url]=hashlib.sha256(raw).hexdigest()
        if identities[url]!=row['swfSha256']:raise ValueError('RSL identity changed: '+url)
        owner=ROOT/url[:-4];exports=[]
        for p in (owner/'LIBRARY').glob('*.xml'):
            a=ET.parse(p).getroot().attrib
            if a.get('linkageExportForRS')=='true':exports.append(a['linkageIdentifier'])
        if len(exports)!=1:raise ValueError('ambiguous RSL export')
        name='ImportBody'+str(i);imports.append('<Include href="'+name+'.xml" loadImmediate="false"/>');instances.append('<DOMSymbolInstance libraryItemName="'+name+'" name="__bodyRsl'+str(i)+'"/>')
        outputs[dest/'LIBRARY'/(name+'.xml')]=('<DOMSymbolItem xmlns="'+NS+'" name="'+name+'" linkageImportForRS="true" linkageIdentifier="'+exports[0]+'" linkageURL="'+url+'" linkageExportInFirstFrame="true"><timeline><DOMTimeline name="'+name+'"><layers><DOMLayer name="RSL"><frames><DOMFrame index="0"><elements/></DOMFrame></frames></DOMLayer></layers></DOMTimeline></timeline></DOMSymbolItem>').encode('utf-8')
    document=(source/'DOMDocument.xml').read_text(encoding='utf-8').replace('../scripts/TestLoader.as','../TestLoader.as').replace('</symbols>',''.join(imports)+'</symbols>').replace('</elements>',''.join(instances)+'</elements>')
    outputs[dest/'DOMDocument.xml']=document.encode('utf-8');outputs[dest/'Cf6BodyScaleNativeHost.xfl']=(source/'Cf6ActorAppearanceNativeHost.xfl').read_bytes()
    settings=(source/'PublishSettings.xml').read_text(encoding='utf-8')
    for a,b in [('<PackagePaths>scripts/类定义;scripts;</PackagePaths>','<PackagePaths>类定义;</PackagePaths>'),('<defaultNames>1</defaultNames>','<defaultNames>0</defaultNames>'),('<flashDefaultName>1</flashDefaultName>','<flashDefaultName>0</flashDefaultName>'),('Cf6ActorAppearanceNativeHost.swf','../Cf6BodyScaleNativeHost.swf')]:
        if settings.count(a)!=1:raise ValueError('host settings changed')
        settings=settings.replace(a,b)
    outputs[dest/'PublishSettings.xml']=settings.encode('utf-8')
    # Reuse frozen production bridge includes, never modify or execute the field fixture.
    template=(ROOT/'tools/cf6-field-combat/TestLoader.as.template').read_text(encoding='utf-8-sig').split('trace("FocusedTestRunId cf6-field-combat Start:')[0]
    template+='trace("FocusedTestRunId cf6-body-scale Start: __FOCUSED_RUN_ID__");\n_root.cf6BodyScaleComplete=function():Void {trace("FocusedTestRunId cf6-body-scale Complete: __FOCUSED_RUN_ID__");};\norg.flashNight.arki.unit.Cf6BodyScaleNativeTest.runAllTests();\n'
    outputs[HERE/'TestLoader.as.template']=b'\xef\xbb\xbf'+template.encode('utf-8')
    units=json.loads((ROOT/'data/units/units.json').read_text(encoding='utf-8-sig'))
    def literal(v):
        if isinstance(v,dict):return '{'+','.join(k+':'+literal(x) for k,x in v.items())+'}'
        if isinstance(v,list):return '['+','.join(literal(x) for x in v)+']'
        return json.dumps(v,ensure_ascii=False)
    policy=json.loads((ROOT/'tools/cf6-prop-layout/scale-policy.json').read_text(encoding='utf-8-sig'))
    entries=[]
    for r in rows:
        u=next(u for u in units if u['id']==r['id']);p=next(p for p in policy['humanoids'] if p['unitId']==u['id'])
        if p['heightCm']!=u['height']:raise ValueError('policy/unit height mismatch')
        entries.append({'linkage':u['spritename'],'label':r['standLabel'],'heightCm':u['height'],'name':u['name'],
            'expectedPixels':u['height']*policy['reference']['relaxedStandingBodyPixels']/policy['reference']['heightCm']})
    data='class org.flashNight.arki.unit.Cf6BodyScaleNativeData { public static function rows():Array {return '+literal(entries)+';} public static function anchorCount():Number {return '+str(len(unique))+';} }\n'
    for name,raw in [('Cf6BodyScaleNativeData',data.encode('utf-8')),('Cf6BodyScaleNativeTest',(HERE/'Cf6BodyScaleNativeTest.as.txt').read_bytes()),('Cf6BodyScaleLiveProbe',(HERE/'Cf6BodyScaleLiveProbe.as.txt').read_bytes())]:
        target=ROOT/'scripts/类定义/org/flashNight/arki/unit'/(name+'.as')
        if not target.exists() and not check:shutil.copyfile(target.with_name('UnitUtil.as'),target)
        outputs[target]=b'\xef\xbb\xbf'+raw
    outputs[HERE/'rsl-identities.json']=(json.dumps(identities,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    outputs[HERE/'measurement-contract.json']=(json.dumps({'schema':'cf6-body-alpha-probe.v1','supersample':4,'alphaMinimum':128,
        'as2ApiReferences':['https://open-flash.github.io/mirrors/as2-language-reference/flash/display/BitmapData.html','https://open-flash.github.io/mirrors/as2-language-reference/flash/geom/Rectangle.html','https://open-flash.github.io/mirrors/as2-language-reference/flash/geom/Matrix.html'],
        'heightToleranceLogicalPixels':1,'scaleTolerancePercentagePoints':0.02,'policySha256':hashlib.sha256((ROOT/'tools/cf6-prop-layout/scale-policy.json').read_bytes()).hexdigest(),
        'rows':entries,'basis':'Frozen policy body targets; 4x alpha threshold raster bounds, two boundary quantization plus AA/matrix budget. No tolerance adjustment based on test output.'},ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    for path,raw in outputs.items():
        if path.exists() and path.read_bytes()==raw:continue
        if check or (path.is_relative_to(dest) and path.exists()):raise ValueError('differing owned host '+str(path))
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    print('BodyScale native host '+('checked' if check else 'prepared')+' '+str(len(outputs))+' files')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');build(p.parse_args().check)
