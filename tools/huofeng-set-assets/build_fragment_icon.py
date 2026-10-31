"""Generate the two-frame native fragment icon; integration/publish stays explicit.

Palette follows Huofeng's R2 chest and hem (A20133, 490C26, dark violet metal).
Uses the set's existing 24 px mask/shadow and independent torn plate/cloth art.
"""
from pathlib import Path
import argparse
from lxml import etree as E

URI = 'http://ns.adobe.com/xfl/2008/'
NAME = 'Codex/火凤套装/图标/火凤装备碎片'
BODY = 'Codex/火凤套装/图标/火凤碎片画稿'
SHADOW = 'Codex/火凤套装/图标/共同遮罩底影'
POLYGONS = [
    ('#181824', [(-10,-4),(-6,-9),(3,-7),(5,-2),(10,0),(7,6),(3,5),(2,10),(-2,7),(-7,9),(-6,3),(-10,2)]),
    ('#39394E', [(-9,-3),(-5,-7),(0,-5),(-1,1),(3,6),(-2,7),(-6,8),(-5,2)]),
    ('#A20133', [(-6,-6),(-4,-7),(-1,-5),(0,1),(4,5),(3,7),(-2,2),(-3,-3)]),
    ('#E36B8A', [(-5,-6),(-4,-6),(-2,-4),(-1,1),(3,5),(2,5),(-2,1),(-3,-4)]),
    ('#55566D', [(-1,-9),(6,-10),(10,-7),(8,-3),(11,0),(6,2),(1,0),(-2,-4)]),
    ('#9297AF', [(-1,-9),(6,-10),(10,-7),(8,-6),(5,-8),(0,-7)]),
    ('#292A3B', [(0,-6),(5,-7),(8,-5),(7,-2),(9,0),(5,1),(1,-1)]),
    ('#A20133', [(3,-7),(5,-7),(7,-5),(6,-1),(4,0),(4,-3)]),
    ('#BCC0CF', [(0,-5),(1,-6),(2,-5),(1,-4)]),
    ('#777D91', [(6,-3),(7,-4),(8,-3),(7,-2)]),
]

def node(parent, tag, **attrs):
    return E.SubElement(parent, '{'+URI+'}'+tag, **{k:str(v) for k,v in attrs.items()})

def symbol(name, item_id, linkage=None):
    root=E.Element('{'+URI+'}DOMSymbolItem',nsmap={None:URI},name=name,itemID=item_id)
    if linkage:
        root.set('linkageExportForAS','true');root.set('linkageExportInFirstFrame','true')
        root.set('linkageIdentifier',linkage)
    return root,node(node(node(root,'timeline'),'DOMTimeline',name=name.rsplit('/',1)[-1]),'layers')

def instance(parent,name,scale=1):
    inst=node(parent,'DOMSymbolInstance',libraryItemName=name,symbolType='graphic',loop='single frame',firstFrame=0)
    node(node(inst,'matrix'),'Matrix',a=scale,d=scale,tx=0,ty=0)

def build(output):
    body,layers=symbol(BODY,'78f40000-00000001')
    elements=node(node(node(node(layers,'DOMLayer',name='碎甲与织物'),'frames'),'DOMFrame',index=0,keyMode=9728),'elements')
    for color,points in POLYGONS:
        shape=node(elements,'DOMShape',isFloating='true')
        node(node(node(shape,'fills'),'FillStyle',index=1),'SolidColor',color=color)
        stroke=node(node(node(shape,'strokes'),'StrokeStyle',index=1),'SolidStroke',weight='.45',scaleMode='normal',caps='round',joints='round')
        node(node(stroke,'fill'),'SolidColor',color='#10101A')
        coords=[(round(x*20),round(y*20)) for x,y in points]
        edges='!%s %s'%coords[0]+''.join('|%s %s'%p for p in coords[1:]+coords[:1])
        node(node(shape,'edges'),'Edge',edges=edges,fillStyle0=1,strokeStyle=1)
    icon,layers=symbol(NAME,'78f40000-00000002','图标-火凤装备碎片')
    for label,attrs,content in [
        ('24px 遮罩',{'layerType':'mask','locked':'true'},SHADOW),
        ('碎片特写',{'parentLayerIndex':'0','locked':'true'},BODY),
        ('原版底影',{},SHADOW),
        ('地面完整展示',{},None),
    ]:
        frames=node(node(layers,'DOMLayer',name=label,**attrs),'frames')
        for index in range(2):
            frame=node(frames,'DOMFrame',index=index,duration=1,keyMode=9728)
            if label=='24px 遮罩':node(node(frame,'Actionscript'),'script').text=E.CDATA('stop();')
            elements=node(frame,'elements')
            if index==0 and content:instance(elements,content)
            if index==1 and content is None:instance(elements,BODY,2)
    for name,root in [(BODY,body),(NAME,icon)]:
        dest=output/'LIBRARY'/(name+'.xml');dest.parent.mkdir(parents=True,exist_ok=True)
        dest.write_bytes(E.tostring(root,encoding='utf-8',xml_declaration=True,pretty_print=True))
    print(output)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
    build(parser.parse_args().output)
