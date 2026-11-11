"""Build a shared-import native host; independent loadClip dictionaries are insufficient."""
from pathlib import Path
import argparse
from lxml import etree as E

ROOT=Path(__file__).resolve().parents[2]
DEST=ROOT/'MovementDirectionHost'
X='http://ns.adobe.com/xfl/2008/'
def node(parent,tag,**attrs):return E.SubElement(parent,'{'+X+'}'+tag,{k:str(v) for k,v in attrs.items()})
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    imports=[('技能容器-小跳','flashswf/arts/things0.swf'),
             ('技能容器-闪现','flashswf/arts/things0.swf'),
             ('战技容器-战技小跳','flashswf/arts/things0.swf'),
             ('技能容器-拔刀术','flashswf/arts/things0.swf')]
    files={}
    doc=E.Element('{'+X+'}DOMDocument',nsmap={None:X},width='500',height='400',frameRate='30',xflVersion='2.2',creatorInfo='Adobe Flash Professional CS6',platform='Windows')
    includes=node(doc,'symbols')
    frames=node(node(node(node(node(doc,'timelines'),'DOMTimeline',name='位移原生时间轴专项'),'layers'),'DOMLayer',name='测试与共享库'),'frames')
    f=node(frames,'DOMFrame',index=0,keyMode=9728)
    node(node(f,'Actionscript'),'script').text=E.CDATA('stop();\n#include "../scripts/TestLoader.as"')
    elements=node(f,'elements')
    for i,(linkage,url) in enumerate(imports):
        name='MovementImport'+str(i)
        symbol=E.Element('{'+X+'}DOMSymbolItem',nsmap={None:X},name=name,linkageImportForRS='true',linkageExportInFirstFrame='true',linkageIdentifier=linkage,linkageURL=url)
        layers=node(node(node(symbol,'timeline'),'DOMTimeline',name=name),'layers')
        node(node(node(node(layers,'DOMLayer',name='共享导入'),'frames'),'DOMFrame',index=0),'elements')
        files[DEST/'LIBRARY'/(name+'.xml')]=E.tostring(symbol,encoding='utf-8',pretty_print=True)
        node(includes,'Include',href=name+'.xml')
        inst=node(elements,'DOMSymbolInstance',libraryItemName=name)
        node(node(inst,'matrix'),'Matrix',tx=-3000,ty=-3000)
    files[DEST/'DOMDocument.xml']=E.tostring(doc,encoding='utf-8',pretty_print=True)
    files[DEST/'MovementDirectionHost.xfl']=b'PROXY-CS5'
    files[DEST/'PublishSettings.xml']=(ROOT/'scripts/FormerSheriffNativeHost/PublishSettings.xml').read_bytes().replace(b'FormerSheriffNativeHost',b'MovementDirectionHost').replace('<PackagePaths>类定义;</PackagePaths>'.encode('utf-8'),'<PackagePaths>scripts/类定义;</PackagePaths>'.encode('utf-8'))
    for path,data in files.items():
        if args.check:assert path.read_bytes()==data,path
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            if not path.exists() or path.read_bytes()!=data:path.write_bytes(data)
    print('Movement native host: 4 shared imports verified')
if __name__=='__main__':main()
