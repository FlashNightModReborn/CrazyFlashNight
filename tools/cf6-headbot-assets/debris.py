"""Split the large torso into nine complementary vector pieces without redrawing it."""
from pathlib import Path
import tempfile
from lxml import etree as E

ROOT = Path(__file__).resolve().parents[2]
SVG = '{http://www.w3.org/2000/svg}'


def torso_parts(vector, original, prefix):
    source = E.parse(str(original),E.XMLParser(strip_cdata=False))
    left,top,width,height = map(float,source.getroot().get('viewBox').split())
    xs = [left,left+width/3,left+width*2/3,left+width]
    ys = [top,top+height/3,top+height*2/3,top+height]
    symbols, pieces, reports = {}, [], []
    # This directory only contains generated clipping inputs owned by this invocation.
    parent = (ROOT/'tmp').resolve()
    with tempfile.TemporaryDirectory(prefix='cf6-torso-',dir=parent) as folder:
        scratch = Path(folder).resolve()
        if scratch.parent != parent:
            raise ValueError('Unexpected generated-input root')
        for row in range(3):
            for col in range(3):
                tree = E.fromstring(E.tostring(source.getroot()))
                defs = tree.find(SVG+'defs')
                if defs is None:
                    defs = E.SubElement(tree,SVG+'defs')
                key = f'cf6TorsoCut{row}{col}'
                clip = E.SubElement(defs,SVG+'clipPath',id=key,clipPathUnits='userSpaceOnUse')
                E.SubElement(clip,SVG+'path',d=f'M{xs[col]} {ys[row]} H{xs[col+1]} V{ys[row+1]} H{xs[col]} Z')
                group = E.Element(SVG+'g',{'clip-path':'url(#'+key+')'})
                for child in list(tree):
                    if child.tag not in (SVG+'defs',SVG+'title',SVG+'desc',SVG+'metadata'):
                        tree.remove(child);group.append(child)
                tree.append(group)
                file = scratch/(key+'.svg')
                file.write_bytes(E.tostring(tree,encoding='utf8',xml_declaration=True))
                center = [(xs[col]+xs[col+1])/2,(ys[row]+ys[row+1])/2]
                name = prefix+'躯干分裂/'+str(row*3+col+1)
                converted,report = vector.NativePart(file,name,center).build()
                symbols.update(converted);pieces.append({'name':name,'center':center})
                reports.append({'piece':name,'clip':[xs[col],ys[row],xs[col+1],ys[row+1]],**report})
    return symbols,pieces,reports
