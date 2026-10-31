"""Build the native test host with explicit imports from both production libraries."""
import argparse
import json
from pathlib import Path
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'scripts/HuofengNativeHost'
URI = 'http://ns.adobe.com/xfl/2008/'

def node(parent, tag, **attrs):
    return E.SubElement(parent, '{'+URI+'}'+tag, **{k:str(v) for k,v in attrs.items()})

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    imports = [('火凤套装_五段普攻', '../flashswf/arts/new/Codex专用素材.swf'),
               ('女变装-基本脸型', '../flashswf/arts/things0.swf'),
               ('空手攻击火花', '../flashswf/arts/原版素材库-子弹.swf'),
               ('新版人物文字信息', '../flashswf/arts/新版人物文字信息.swf'),
               ('刀-破旧军刀', '../flashswf/arts/things切割.swf'),
               ('常规旋风', '../flashswf/arts/new/瓦巴杰克.swf'),
               ('主角满蓄重劈', '../flashswf/arts/new/雾人整合特效.swf')]
    files = {}
    doc = E.Element('{'+URI+'}DOMDocument', nsmap={None:URI}, width='500', height='500', frameRate='30', xflVersion='2.2', creatorInfo='Adobe Flash Professional CS6', platform='Windows')
    includes = node(doc, 'symbols')
    frames = node(node(node(node(node(doc,'timelines'),'DOMTimeline',name='火凤原生接入测试'),'layers'),'DOMLayer',name='测试与共享库'),'frames')
    first = node(frames,'DOMFrame',index=0,keyMode=9728)
    node(node(first,'Actionscript'),'script').text=E.CDATA('stop();\n#include "../TestLoader.as"')
    # Imports must be reached before TestLoader starts; a stopped frame 1 cannot
    # initialize ImportAssets tags emitted for instances on frame 2.
    elements=node(first,'elements')
    for i,(linkage,url) in enumerate(imports):
        name='HuofengImport'+str(i)
        symbol=E.Element('{'+URI+'}DOMSymbolItem',nsmap={None:URI},name=name,linkageImportForRS='true',linkageExportInFirstFrame='true',linkageIdentifier=linkage,linkageURL=url)
        layer=node(node(node(symbol,'timeline'),'DOMTimeline',name=name),'layers')
        node(node(node(node(layer,'DOMLayer',name='共享导入'),'frames'),'DOMFrame',index=0),'elements')
        files[DEST/'LIBRARY'/f'{name}.xml']=E.tostring(symbol,encoding='utf-8',pretty_print=True)
        node(includes,'Include',href=name+'.xml')
        instance=node(elements,'DOMSymbolInstance',libraryItemName=name)
        node(node(instance,'matrix'),'Matrix',tx=-3000,ty=-3000)
    files[DEST/'DOMDocument.xml']=E.tostring(doc,encoding='utf-8',pretty_print=True)
    files[DEST/'HuofengNativeHost.xfl']=b'PROXY-CS5'
    profile=(ROOT/'scripts/FormerSheriffNativeHost/PublishSettings.xml').read_bytes()
    files[DEST/'PublishSettings.xml']=profile.replace(b'FormerSheriffNativeHost.swf',b'HuofengNativeHost.swf')
    for path,data in files.items():
        if args.check:
            assert path.read_bytes()==data,path
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists() or path.read_bytes()!=data:
                path.write_bytes(data)
    print('Huofeng native host: '+str(len(imports))+' shared imports verified')

if __name__=='__main__':main()
