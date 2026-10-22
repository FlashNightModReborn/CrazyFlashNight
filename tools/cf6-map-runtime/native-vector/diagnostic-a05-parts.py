"""Magnified A05 vector statue/painting next to existing reference PNGs, same dark backing."""
from pathlib import Path
import importlib.util
import json
import shutil
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('vector_api',HERE/'build-a01.py');api=importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
E=api.E;N=api.N;NS={'x':api.base.NS}
PACKAGE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图/A05-R3/cf6-stage5-redraw-r3'
NAME='CF6_A05_PartsDiagnostic01';target=ROOT/'flashswf/backgrounds/cf6'/NAME;target.mkdir(exist_ok=True)
template=ROOT/'flashswf/backgrounds/cf6/CF6_A05_BG_VectorCandidate01'
manifest=json.loads((HERE/'layers/CF6_A05_BG_VectorCandidate01/texture-manifest.json').read_text(encoding='utf-8'))
c=api.Candidate(PACKAGE/'parts/bitmap-1740.svg',textures=manifest['textures'],allow_filters=True)
elements=[]
for cid,x,scale in [(1740,20,2),(1743,340,4)]:
    svg=ET.parse(PACKAGE/'parts'/('bitmap-'+str(cid)+'.svg')).getroot()
    c.byid={n.get('id'):n for n in svg.iter() if n.get('id')}
    c.grads={n.get('id'):n for n in svg.iter() if api.tag(n) in ('linearGradient','radialGradient')}
    drawing=c.walk_native(svg);elements.append(c.instance(drawing,'vector-'+str(cid),(scale,0,0,scale,x,45)))
doc=ET.parse(template/'DOMDocument.xml');root=doc.getroot();root.set('width','970');root.set('height','500')
for node in list(root):
    if api.tag(node) in ('symbols','timelines','folders'):root.remove(node)
for bitmap in root.findall('./x:media/x:DOMBitmapItem',NS):
    for prefix,key in [('LIBRARY','href'),('bin','bitmapDataHRef')]:
        relative=Path(prefix)/bitmap.get(key);dest=target/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(template/relative,dest)
symbols=E('symbols',parent=root)
for name,tree in c.symbols.items():
    path=target/'LIBRARY'/(name+'.xml');path.parent.mkdir(parents=True,exist_ok=True);ET.ElementTree(tree).write(path,encoding='utf-8',xml_declaration=True);E('Include',{'href':name+'.xml','loadImmediate':'false'},symbols)
frame=E('DOMFrame',{'index':'0','keyMode':'9728'},E('frames',parent=E('DOMLayer',{'name':'A05 actual source parts'},E('layers',parent=E('DOMTimeline',{'name':NAME},E('timelines',parent=root))))))
els=E('elements',parent=frame)
for node in c.primitive(ET.Element('{http://www.w3.org/2000/svg}rect',{'width':'970','height':'500'}),{'fill':'#202020'})+elements:els.append(node)
base='../../arts/new/Codex素材源稿/CF6地图/A05-R3/cf6-stage5-redraw-r3/baked/'
E('script',parent=E('Actionscript',parent=frame)).text='''stop();
var tf=new TextFormat();tf.font="Arial";tf.size=13;tf.color=0xFFFFFF;
this.createTextField("labels",1,15,10,950,28);labels.setNewTextFormat(tf);labels.text="VECTOR (+multiply fix)       EXISTING PNG        VECTOR PAINTING                 EXISTING PNG";
var statue=this.createEmptyMovieClip("referenceStatue",2);statue._x=180;statue._y=45;
var painting=this.createEmptyMovieClip("referencePainting",3);painting._x=650;painting._y=45;
var loader=new MovieClipLoader();var listener={};
listener.onLoadInit=function(mc){if(mc._name=="referenceStatue"){mc._width=130;mc._height=422;}else{mc._width=288;mc._height=356;}};
loader.addListener(listener);this.__referenceLoader=loader;this.__referenceListener=listener;
loader.loadClip(%s,statue);loader.loadClip(%s,painting);
'''%(json.dumps(base+'bitmap-1740.png',ensure_ascii=False),json.dumps(base+'bitmap-1743.png',ensure_ascii=False))
doc.write(target/'DOMDocument.xml',encoding='utf-8',xml_declaration=True)
(target/(NAME+'.xfl')).write_bytes((template/(template.name+'.xfl')).read_bytes())
profile=ET.parse(template/'PublishSettings.xml');profile.find('.//PublishFormatProperties/flashFileName').text=NAME+'.swf';profile.write(target/'PublishSettings.xml',encoding='utf-8',xml_declaration=True)
print(json.dumps({'target':str(target/(NAME+'.xfl')),'symbols':len(c.symbols),'blendModes':c.blend_reports,'comparison':'same dark backing; references load existing PNGs, no new raster output'},ensure_ascii=False))
