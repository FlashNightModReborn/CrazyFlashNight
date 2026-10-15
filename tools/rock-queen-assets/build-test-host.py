"""Build the native test host with explicit imports from both production libraries."""
import argparse
import json
from pathlib import Path
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'scripts/RockQueenNativeHost'
URI = 'http://ns.adobe.com/xfl/2008/'

def node(parent, tag, **attrs):
    return E.SubElement(parent, '{'+URI+'}'+tag, **{k:str(v) for k,v in attrs.items()})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    clips = json.loads((Path(__file__).parent/'manifest.json').read_text('utf-8'))['clips']
    imports = [(c['linkage'], '../flashswf/arts/things0.swf') for c in clips]
    imports += [(v, '../flashswf/arts/new/fs配置素材.swf') for v in ['刀-主唱光剑','刀-键盘镰刀','枪-长枪-吉他喷火器']]
    imports += [('新版人物文字信息', '../flashswf/arts/新版人物文字信息.swf')]
    files = {}
    doc = E.Element('{'+URI+'}DOMDocument', nsmap={None:URI}, width='500', height='500', frameRate='30', xflVersion='2.2', creatorInfo='Adobe Flash Professional CS6', platform='Windows')
    includes = node(doc, 'symbols')
    frames = node(node(node(node(node(doc,'timelines'),'DOMTimeline',name='摇滚女皇原生接入测试'),'layers'),'DOMLayer',name='测试与共享库'),'frames')
    first = node(frames,'DOMFrame',index=0,keyMode=9728)
    node(node(first,'Actionscript'),'script').text=E.CDATA('stop();\n#include "../TestLoader.as"')
    # Imports must be reached before TestLoader starts; a stopped frame 1 cannot
    # initialize ImportAssets tags emitted for instances on frame 2.
    elements=node(first,'elements')
    for i,(linkage,url) in enumerate(imports):
        name='RockImport'+str(i)
        symbol=E.Element('{'+URI+'}DOMSymbolItem',nsmap={None:URI},name=name,linkageImportForRS='true',linkageExportInFirstFrame='true',linkageIdentifier=linkage,linkageURL=url)
        layer=node(node(node(symbol,'timeline'),'DOMTimeline',name=name),'layers')
        node(node(node(node(layer,'DOMLayer',name='共享导入'),'frames'),'DOMFrame',index=0),'elements')
        files[DEST/'LIBRARY'/f'{name}.xml']=E.tostring(symbol,encoding='utf-8',pretty_print=True)
        node(includes,'Include',href=name+'.xml')
        instance=node(elements,'DOMSymbolInstance',libraryItemName=name)
        node(node(instance,'matrix'),'Matrix',tx=-3000,ty=-3000)
    files[DEST/'DOMDocument.xml']=E.tostring(doc,encoding='utf-8',pretty_print=True)
    files[DEST/'RockQueenNativeHost.xfl']=b'PROXY-CS5'
    profile=(ROOT/'scripts/FormerSheriffNativeHost/PublishSettings.xml').read_bytes()
    files[DEST/'PublishSettings.xml']=profile.replace(b'FormerSheriffNativeHost.swf',b'RockQueenNativeHost.swf')
    for path,data in files.items():
        if args.check:
            assert path.read_bytes()==data,path
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists() or path.read_bytes()!=data:
                path.write_bytes(data)
    print('Rock Queen native host: '+str(len(imports))+' shared imports verified')

if __name__=='__main__':main()
