"""Three native copies of the actual A03 halo: raw / filter / native Color transform."""
from pathlib import Path
import copy
import importlib.util
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('vector_api',HERE/'build-a01.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
E=api.E;N=api.N
source=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/A03-R1/cf6-stage3-redraw-r1/parts/background-1706.svg'
c=api.Candidate(source,allow_filters=True)
group=next(n for n in c.root.iter() if n.get('filter')=='url(#col5)')
path=next(n for n in group if api.tag(n)=='path')
paint=c.primitive(path,api.base.style(path))
panels=[]
for label,x in [('raw',130),('filtered',390),('transformed',650)]:
    panel=c.instance(copy.deepcopy(paint),label,(1,0,0,1,x,140),script=c.filter_script('col5') if label=='filtered' else 'stop();',name=label)
    if label=='transformed':E('Color',{'redMultiplier':'0','redOffset':'255','greenMultiplier':'0','greenOffset':'255','blueMultiplier':'0','blueOffset':'153','alphaMultiplier':'1'},E('color',parent=panel))
    panels.append(panel)
background=c.primitive(ET.Element('{http://www.w3.org/2000/svg}rect',{'width':'780','height':'260'}),{'fill':'#080808'})
name='CF6_A03_GlowDiagnostic01';target=ROOT/'flashswf/backgrounds/cf6'/name;target.mkdir(exist_ok=True)
template=ROOT/'flashswf/backgrounds/cf6/CF6_A01_VectorCandidate01';doc=ET.parse(template/'DOMDocument.xml');root=doc.getroot();root.set('width','780');root.set('height','260')
for node in list(root):
    if api.tag(node) in ('media','symbols','timelines','folders'):root.remove(node)
symbols=E('symbols',parent=root)
for symbol,tree in c.symbols.items():
    p=target/'LIBRARY'/(symbol+'.xml');p.parent.mkdir(parents=True,exist_ok=True);ET.ElementTree(tree).write(p,encoding='utf-8',xml_declaration=True);E('Include',{'href':symbol+'.xml','loadImmediate':'false'},symbols)
frame=E('DOMFrame',{'index':'0','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'three actual halo cases'},E('layers',parent=E('DOMTimeline',{'name':'A03 halo diagnostic'},E('timelines',parent=root))))))
elements=E('elements',parent=frame)
for element in background+panels:elements.append(element)
E('script',parent=E('Actionscript',parent=frame)).text='''stop();
var tf=new TextFormat();tf.font="Arial";tf.size=14;tf.color=0xFFFFFF;
this.createTextField("labels",1,20,10,750,30);labels.setNewTextFormat(tf);labels.text="RAW GRADIENT                 COLOR MATRIX FILTER                 NATIVE COLOR";
this.createTextField("info",2,20,225,750,30);info.setNewTextFormat(tf);
this.onEnterFrame=function(){info.text="constructor="+typeof flash.filters.ColorMatrixFilter+"; filters="+filtered.filters.length+"; raw="+raw._width+"x"+raw._height+"; filtered="+filtered._width+"x"+filtered._height;delete this.onEnterFrame;};'''
doc.write(target/'DOMDocument.xml',encoding='utf-8',xml_declaration=True)
(target/(name+'.xfl')).write_bytes((template/'CF6_A01_VectorCandidate01.xfl').read_bytes())
profile=ET.parse(template/'PublishSettings.xml');profile.find('.//PublishFormatProperties/flashFileName').text=name+'.swf';profile.write(target/'PublishSettings.xml',encoding='utf-8',xml_declaration=True)
print(target/(name+'.xfl'))
