"""Reuse R2/R5 authoring sources in this lane's directory, without editing the originals."""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import io
import json
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ARCHIVE = ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'
R2 = ARCHIVE/'A07-R2/cf6-stage7-redraw-r2'
R5 = ARCHIVE/'A08-R5'
OUT = HERE/'source/redraw'
NS = '{http://www.w3.org/2000/svg}'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def image_svg(image, size, title):
    stream = io.BytesIO()
    image.save(stream, format='PNG')
    data = base64.b64encode(stream.getvalue()).decode('ascii')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+str(size[0])+' '+str(size[1])+'">'
            '<title>'+title+'</title><image width="'+str(size[0])+'" height="'+str(size[1])
            +'" href="data:image/png;base64,'+data+'"/></svg>').encode('utf-8')


def build(check=False):
    inputs = [Path(__file__), R2/'source/sky_material.py', R2/'source/river_arcade.py',
              R2/'source/svg_native.py', R2/'reference/environment-original-nodes.json',
              R2/'reference/environment-shape-details.json', R5/'parts/bitmap-1823.svg',
              R5/'parts/bitmap-1786.svg', ROOT/'tools/cf6-scene-completion/vehicle-art/bitmap-1806.svg',
              ROOT/'tools/cf6-scene-completion/vehicle-art/bitmap-1808.svg']
    outputs = {}
    # R5 includes separately grouped wheels. Remove those groups from the body before applying
    # the original two independent 1800 timelines: otherwise every pose would contain four tires.
    player = ET.parse(R5/'parts/bitmap-1823.svg').getroot()
    selected = []
    for parent in player.iter():
        for child in list(parent):
            transform = child.get('transform', '')
            if transform.startswith('translate(80.3 102.1)') or transform.startswith('translate(313.7 102.1)'):
                selected.append(copy.deepcopy(child))
                parent.remove(child)
    if len(selected) != 2:
        raise ValueError('R5 player wheel grouping changed')
    outputs[OUT/'player-body.svg'] = ET.tostring(player, encoding='utf-8', xml_declaration=True)
    for index, (wheel, center) in enumerate(zip(selected, [(80.3,102.1),(313.7,102.1)])):
        doc = ET.Element(NS+'svg', {'viewBox':'-30.5 -31 61 62'})
        for defs in player.iter(NS+'defs'):
            doc.append(copy.deepcopy(defs))
        parent = ET.SubElement(doc, NS+'g', {'transform':'translate('+str(-center[0])+' '+str(-center[1])+')'})
        parent.append(wheel)
        outputs[OUT/('player-wheel-'+str(index)+'.svg')] = ET.tostring(doc, encoding='utf-8', xml_declaration=True)
    for name, source in [('armored-body.svg',inputs[-2]),('armored-wheel.svg',inputs[-1]),('asphalt.svg',inputs[-3])]:
        outputs[OUT/name] = source.read_bytes()
    # The reviewed A07 R2 authors deliberately use original alpha only, never original RGB, for
    # the river architecture silhouettes. Extract those exact reference images into our own root.
    originals = json.loads((R2/'reference/environment-original-nodes.json').read_text(encoding='utf-8-sig'))['nodes']
    for bitmap, shape in [(1784,1785),(1789,1790)]:
        node = ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">'+originals[str(shape)]['svgInner']+'</svg>')
        images = [n for n in node.iter() if n.tag.split('}')[-1] == 'image']
        if len(images) != 1:
            raise ValueError('architecture alpha reference changed')
        href = images[0].get('href') or images[0].get('{http://www.w3.org/1999/xlink}href')
        outputs[OUT/'reference'/(str(bitmap)+'.png')] = base64.b64decode(href.split(',',1)[1])
    # The pure R2 functions write only to their explicit R variable. It is rebound to this owned
    # output directory before invocation; their original source directories remain untouched.
    for folder in [OUT, OUT/'parts', OUT/'reference']:
        if not check:
            folder.mkdir(parents=True, exist_ok=True)
    for p, raw in outputs.items():
        if p.parent.name == 'reference' and not check:
            p.write_bytes(raw)
    sys.path.insert(0,str(R2/'source'))
    river = module('vehicle_r2_river', R2/'source/river_arcade.py')
    river.R = OUT
    if not check:
        river.bridge()
        river.arcade()
    for filename in ['bitmap-1784.svg','bitmap-1789.svg']:
        p = OUT/'parts'/filename
        if not p.is_file():
            raise ValueError('R2 architecture source has not been generated')
        outputs[p] = p.read_bytes()
    sky = module('vehicle_r2_sky', R2/'source/sky_material.py')
    sky.R = OUT
    if check:
        outputs[OUT/'sky.svg'] = (OUT/'sky.svg').read_bytes()
        outputs[OUT/'sky-extension.svg'] = (OUT/'sky-extension.svg').read_bytes()
    else:
        full = sky.make_material()
        outputs[OUT/'sky.svg'] = image_svg(full.crop((0,0,2400,561)), [800,187], 'Original A07 R2 procedural cloud source')
        outputs[OUT/'sky-extension.svg'] = image_svg(sky.make_extension(full), [800,66.5], 'Original A07 R2 cloud continuity extension')
    manifest = {'schema':'cf6-vehicle-redraw.v1','inputs':{p.relative_to(ROOT).as_posix():sha(p.read_bytes()) for p in inputs},
                'authority':'R2 armored/architecture/cloud and R5 player/asphalt; vehicle animation comes from pinned original matrices',
                'playerWheels':'R5 body wheels removed and independently re-used in original rear/front animated slots',
                'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(raw),'bytes':len(raw)} for p,raw in outputs.items()}}
    record = HERE/'redraw-manifest.json'
    if check:
        previous = json.loads(record.read_text(encoding='utf-8'))
        if previous != manifest:
            raise ValueError('redraw manifest/input drift; preserve and rebuild explicitly')
        for p, raw in outputs.items():
            if p.read_bytes() != raw:
                raise ValueError('redraw source mismatch '+str(p))
    else:
        for p, raw in outputs.items():
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(raw)
        record.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'files':len(outputs),'bytes':sum(map(len,outputs.values())),'state':'checked' if check else 'prepared'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    build(parser.parse_args().check)
