"""Small editable-SVG helpers. Artwork is authored in per-symbol native coordinates."""
from pathlib import Path
from xml.etree import ElementTree as ET
import subprocess,re
NS='http://www.w3.org/2000/svg'
def svg(viewbox,content):
    return f'<svg xmlns="{NS}" viewBox="'+ ' '.join(map(str,viewbox))+'">'+content+'</svg>'
def write_part(path,viewbox,content):
    p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(svg(viewbox,content),encoding='utf-8');ET.parse(p);return p
def inner(path,prefix):
    root=ET.parse(path).getroot();content=''.join(ET.tostring(e,encoding='unicode') for e in root)
    ids=re.findall(r'\bid="([^"]+)"',content)
    for old in sorted(ids,key=len,reverse=True):
        new=prefix+'_'+old;content=content.replace('id="'+old+'"','id="'+new+'"').replace('url(#'+old+')','url(#'+new+')').replace('href="#'+old+'"','href="#'+new+'"')
    return content
def assemble(viewbox,layers,destination):
    chunks=[]
    for n,layer in enumerate(layers):
        m=layer.get('matrix',[1,0,0,1,0,0]);chunks.append('<g id="layer_'+str(n)+'" transform="matrix('+ ' '.join(map(str,m))+')">'+inner(layer['path'],'l'+str(n))+'</g>')
    return write_part(destination,viewbox,''.join(chunks))
def render(path,width,destination=None):
    path=Path(path);dest=Path(destination) if destination else path.with_suffix('.png')
    # PATCHED(cf6-map-source): Windows 无 fcntl/Inkscape 时的工具发现；几何/输出参数不变
    try:
        from svgrender import render as _discover_render
    except ImportError:
        _discover_render=None
    if _discover_render is not None:
        _discover_render(path,int(width),dest)
    else:
        subprocess.run(['inkscape',str(path),'--export-width='+str(width),'--export-filename='+str(dest)],check=True,capture_output=True)
    return dest
