"""Assemble stopped door timelines from CS6-native bitmap imports; never edit SWF."""
import argparse
import copy
import json
from pathlib import Path
from lxml import etree as E
from native_xfl import NS,parse,finalize

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
Q='{'+NS['x']+'}'


def signature(node):
    return (node.tag,tuple(sorted(node.attrib.items())),(node.text or '').strip(),tuple(signature(child) for child in node))


def timeline(doc,row):
    instances={node.get('libraryItemName'):node for node in doc.findall('.//x:DOMBitmapInstance',NS)}
    media={Path(node.get('href')).name:node.get('name') for node in doc.findall('./x:media/x:DOMBitmapItem',NS)}
    result=E.Element(Q+'timelines')
    tl=E.SubElement(result,Q+'DOMTimeline',name=row['name'])
    layers=E.SubElement(tl,Q+'layers');layer=E.SubElement(layers,Q+'DOMLayer',name='isolated door frames')
    frames=E.SubElement(layer,Q+'frames')
    for i,item in enumerate(row['inputs']):
        frame=E.SubElement(frames,Q+'DOMFrame',index=str(i),keyMode='9728')
        if i==0:
            action=E.SubElement(frame,Q+'Actionscript');script=E.SubElement(action,Q+'script');script.text=E.CDATA('stop();')
        elements=E.SubElement(frame,Q+'elements')
        elements.append(copy.deepcopy(instances[media[Path(item['path']).name]]))
    return result


def process(row,check=False):
    source=(ROOT/row['xfl']).resolve()
    if not source.is_relative_to(ROOT/'flashswf/backgrounds/cf6') or not source.is_file():
        raise ValueError('Native door import missing: '+str(source))
    report=finalize(source,Path(row['swf']).name,row['inputs'],check=check)
    doc=parse(source.parent/'DOMDocument.xml')
    old=doc.find('./x:timelines',NS);new=timeline(doc,row)
    if check:
        # Compare expanded XML names; native namespace prefixes/whitespace are irrelevant.
        if signature(old)!=signature(new):
            raise ValueError('Door timeline is not finalized: '+row['id'])
    else:
        doc.getroot().replace(old,new)
        doc.write(str(source.parent/'DOMDocument.xml'),encoding='utf-8',xml_declaration=False)
    report['sequenceFrames']=row['frames'];report['publishTarget']=row['swf']
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--kind',action='append');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    rows=json.loads((HERE/'generated/door-runtime-index.json').read_text(encoding='utf-8'))['sets']
    for row in rows:
        if args.kind and row['id'] not in args.kind:continue
        print(json.dumps(process(row,args.check),ensure_ascii=False))
