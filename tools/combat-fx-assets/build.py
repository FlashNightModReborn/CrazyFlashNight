#!/usr/bin/env python3
"""Deterministic casing/muzzle atlas from the existing Flash source and published SWF.

--check verifies source/recipe/tool/output hashes and catalog bounds without
rerendering. A full build uses the installed FFDec renderer in a temporary folder.
Frame scripts are classified here, never evaluated by FFDec or the runtime.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import runpy
import shutil
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
LIB = ROOT / 'flashswf/arts/原版素材库-子弹/LIBRARY'
SWF = ROOT / 'flashswf/arts/原版素材库-子弹.swf'
OUT = ROOT / 'data/combat_visuals'
CATALOG = OUT / 'effects.v1.json'
ATLAS = OUT / 'effects-atlas.png'
NS = '{http://ns.adobe.com/xfl/2008/}'
ZOOM = 2
MUZZLES = ('冲锋枪枪火', '反器材枪火', '发射器枪火', '巴雷特枪火', '战斗步枪枪火',
           '枪火', '突击步枪枪火', '紧凑手枪枪火', '霰弹枪枪火', '马格南手枪枪火')
IMPACTS = ('火花', '击中金属', '无声火花', '拼刀火花', '战术巴雷特击中特效', '铁枪能量弹火花', '屎花')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def record(path):
    return {'path': Path(path).relative_to(ROOT).as_posix(), 'sha256': digest(path)}


def exports():
    helper = runpy.run_path(str(ROOT / 'tools/swf-audit/swfscan.py'))
    raw = SWF.read_bytes()
    if raw[:3] not in (b'CWS', b'FWS'):
        raise ValueError('Unsupported SWF compression')
    data = zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw[8:]
    bits = helper['Bits'](data)
    width = bits.u(5)
    for _ in range(4):
        bits.s(width)
    bits.align()
    pos = bits.byte + 4
    result = {}
    while pos < len(data) - 1:
        head, = struct.unpack_from('<H', data, pos)
        pos += 2
        code, size = head >> 6, head & 63
        if size == 63:
            size, = struct.unpack_from('<I', data, pos)
            pos += 4
        end = pos + size
        if end > len(data):
            raise ValueError('Truncated SWF')
        if code == 56:
            count, = struct.unpack_from('<H', data, pos)
            at = pos + 2
            for _ in range(count):
                char_id, = struct.unpack_from('<H', data, at)
                name, at = helper['read_string'](data, at + 2)
                if name in result:
                    raise ValueError('Duplicate exported linkage: ' + name)
                result[name] = char_id
            if at != end:
                raise ValueError('Invalid ExportAssets length')
        pos = end
        if code == 0:
            break
    return result


def recipe():
    source_files = set()
    def read(path):
        path = path.resolve()
        if not path.is_relative_to(LIB.resolve()) or not path.is_file():
            raise ValueError('Missing or escaping source symbol: ' + str(path))
        if path in source_files:
            return ET.parse(path).getroot()
        source_files.add(path)
        root = ET.parse(path).getroot()
        for node in root.iter(NS + 'DOMSymbolInstance'):
            read(LIB / (node.get('libraryItemName') + '.xml'))
        return root
    plans = []
    shell_paths = sorted((LIB / '弹壳').glob('*.xml'))
    if len(shell_paths) != 18:
        raise ValueError('Review casing whitelist when its source set changes')
    roots = shell_paths + [LIB / '特效-枪火组' / (n + '.xml') for n in MUZZLES]
    roots += [LIB / '特效-击中效果组' / (n + '.xml') for n in IMPACTS]
    for path in roots:
        root = read(path)
        name = root.get('linkageIdentifier')
        if root.get('linkageExportForAS') != 'true' or not name:
            raise ValueError('Source has no AS linkage: ' + str(path))
        is_shell = path.parent.name == '弹壳'
        scripts, labels = [], {}
        for frame in root.iter(NS + 'DOMFrame'):
            index = int(frame.get('index', '0'))
            if frame.get('name'):
                labels[frame.get('name')] = index
            for script in frame.iter(NS + 'script'):
                scripts.append((index, re.sub(r'\s+', '', ''.join(script.itertext()))))
        removal_scripts = {'this.removeMovieClip();', 'stop();this.removeMovieClip();', 'this.removeMovieClip();stop();'}
        removals = sorted({i for i, s in scripts if s in removal_scripts})
        skip_zero = False
        if is_shell:
            if scripts or any(int(f.get('index', '0')) or int(f.get('duration', '1')) != 1
                              for f in root.iter(NS + 'DOMFrame')):
                raise ValueError('Casing is not static: ' + name)
            variants = [[0]]
        elif any('random(' in s for _,s in scripts):
            selectors = [(i,s) for i,s in scripts if s not in removal_scripts]
            if len(selectors) != 1 or selectors[0][0] != 0:
                raise ValueError('Unknown random animation selector: ' + name)
            selector=selectors[0][1]
            guard='if(this._y==0){this.removeMovieClip();}'
            if selector.startswith(guard):
                skip_zero=True; selector=selector[len(guard):]
            direct=re.fullmatch(r'gotoAndPlay\("a"\+random\(([1-8])\)\);',selector)
            variable=re.fullmatch(r'vara="a"\+random\(([1-8])\);gotoAndPlay\(a\);',selector)
            selected=direct or variable
            if selected is None: raise ValueError('Unknown random animation script: ' + name)
            variants = []
            for label in ('a'+str(i) for i in range(int(selected.group(1)))):
                begin = labels[label]
                finish = min(i for i in removals if i > begin)
                variants.append(list(range(begin, finish)))
        else:
            if not removals or any(s not in removal_scripts for _, s in scripts):
                raise ValueError('Unknown effect behavior: ' + name)
            variants = [list(range(min(removals)))]
        if any(not v or len(v) > 60 for v in variants):
            raise ValueError('Invalid animation duration')
        kind='casing' if is_shell else ('impact' if name in IMPACTS else 'muzzle')
        plans.append({'index': len(plans), 'linkage': name, 'kind': kind,
                      'variants': variants, 'skipOriginYZero': skip_zero,
                      'worldLit':is_shell or name=='屎花'})
    root_set={p.resolve() for p in roots}
    for p in source_files-root_set:
        if any(True for _ in ET.parse(p).getroot().iter(NS+'script')):
            raise ValueError('Nested behavior needs explicit adaptation: '+str(p))
    return plans, sorted(source_files)


def java_tool(name):
    found = shutil.which(name)
    candidates = [Path(found)] if found else []
    if os.environ.get('JAVA_HOME'):
        candidates.append(Path(os.environ['JAVA_HOME']) / 'bin' / (name + '.exe'))
    for env in ('ProgramFiles', 'ProgramFiles(x86)'):
        root = Path(os.environ.get(env, 'C:/Program Files')) / 'Adobe'
        if root.is_dir():
            candidates.extend(sorted(root.glob('Adobe Animate */jre/bin/' + name + '.exe'), reverse=True))
    return next(p for p in candidates if p.is_file())


def verify():
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    if catalog['schema'] != 'cf7-combat-fx.v1':
        raise ValueError('Unsupported catalog')
    for item in catalog['sources'] + catalog['tools']:
        if digest(ROOT / item['path']) != item['sha256']:
            raise ValueError('Stale combat effect input: ' + item['path'])
    if digest(ATLAS) != catalog['atlas']['sha256'] or ATLAS.stat().st_size > 4 * 1024 * 1024:
        raise ValueError('Atlas integrity/size check failed')
    plans, files = recipe()
    if plans != catalog['recipe']:
        raise ValueError('Stale effect recipe')
    if {p.relative_to(ROOT).as_posix() for p in files} | {SWF.relative_to(ROOT).as_posix()} != {s['path'] for s in catalog['sources']}:
        raise ValueError('Source closure changed')
    # Policy checks only need the hashed PNG's header; do not require Java/Pillow on a verifier.
    png=ATLAS.read_bytes()
    if png[:16] != b'\x89PNG\r\n\x1a\n\0\0\0\rIHDR' or png[24:29] != bytes((8,6,0,0,0)):
        raise ValueError('Expected an 8-bit RGBA PNG')
    w,h=struct.unpack('>II',png[16:24])
    if [w,h] != [catalog['atlas']['width'],catalog['atlas']['height']] or min(w,h)<1 or max(w,h)>4096:
        raise ValueError('Invalid atlas dimensions')
    if len(catalog['styles']) != len(plans): raise ValueError('Style set differs from recipe')
    for style,plan in zip(catalog['styles'],plans):
        for key in ('index','linkage','kind','skipOriginYZero','worldLit'):
            if style[key] != plan[key]:raise ValueError('Style differs from recipe: '+key)
        actual=[[style['frames'][i]['sourceFrame'] for i in v] for v in style['variants']]
        if actual!=plan['variants']:raise ValueError('Animation differs from script adapter')
        for frame in style['frames']:
            x,y,fw,fh=frame['rect']
            if min(x,y)<0 or min(fw,fh)<1 or x+fw>w or y+fh>h:
                raise ValueError('Atlas frame out of bounds')
    verify_lights()
    print(f'Combat FX check OK: {len(plans)} styles, {sum(len(s["frames"]) for s in catalog["styles"])} frames, {w}x{h}, {ATLAS.stat().st_size} bytes')


def build():
    from PIL import Image, __version__ as pillow_version
    plans, sources = recipe()
    names = exports()
    classpath = os.pathsep.join([str(ROOT / 'tools/ffdec/lib/*'), str(ROOT / 'tools/ffdec/ffdec.jar')])
    with tempfile.TemporaryDirectory(prefix='cf7-combat-fx-') as tmp_name:
        temp = Path(tmp_name)
        classes = temp / 'classes'; classes.mkdir()
        subprocess.run([str(java_tool('javac')), '-encoding', 'UTF-8', '-cp', classpath,
                        '-d', str(classes), str(HERE / 'CombatSpriteExporter.java')], check=True, timeout=120)
        plan_path = temp / 'plan.tsv'
        plan_path.write_text('\n'.join(str(p['index'])+'\t'+str(names[p['linkage']])+'\t'+
            ','.join(str(f) for f in sorted({f for v in p['variants'] for f in v})) for p in plans), encoding='utf-8')
        raster = temp / 'raster'
        subprocess.run([str(java_tool('java')), '-Xmx2g', '-cp', str(classes)+os.pathsep+classpath,
                        'CombatSpriteExporter', str(SWF), str(plan_path), str(raster), str(ZOOM)], check=True, timeout=240)
        images, meta = [], {}
        for line in (raster / 'frames.tsv').read_text(encoding='utf-8').splitlines():
            cols = line.split('\t'); style, frame = map(int, cols[:2]); xmin, ymin, xmax, ymax = map(int, cols[2:6])
            with Image.open(cols[6]) as img:
                image = img.convert('RGBA'); box = image.getbbox()
                if box is None:
                    box = (0, 0, 1, 1); image = Image.new('RGBA', (1, 1))
                else:
                    image = image.crop(box)
                if image.width > 2044 or image.height > 2044:
                    raise ValueError('Effect exceeds atlas size budget')
                meta[(style, frame)] = {'sourceFrame': frame, 'offset': [xmin/20+box[0]/ZOOM, ymin/20+box[1]/ZOOM]}
                images.append((style, frame, image.copy()))
        print('Rasterized pixels:', sum(image.width*image.height for _,_,image in images))
        # Deterministic shelf pack with transparent padding for bilinear filtering.
        images.sort(key=lambda v: (-v[2].height, -v[2].width, v[0], v[1]))
        placements=[]; x=2; y=2; row=0; atlas_width=2048; identical={}
        for style, frame, image in images:
            identity=(image.size,hashlib.sha256(image.tobytes()).digest())
            if identity in identical:
                meta[(style,frame)]['rect']=identical[identity]
                continue
            if x+image.width+2 > atlas_width:
                x=2; y+=row+4; row=0
            placements.append((x,y,image)); meta[(style,frame)]['rect']=[x,y,image.width,image.height]
            identical[identity]=meta[(style,frame)]['rect']
            x+=image.width+4; row=max(row,image.height)
        # D3D11 accepts non-power-of-two atlases. Keep eight-row alignment without
        # retaining almost half a texture of transparent padding.
        atlas_height=((y+row+2+7)//8)*8
        if atlas_height > 4096: raise ValueError('Atlas exceeds GPU budget')
        atlas=Image.new('RGBA',(atlas_width,atlas_height))
        print('Unique raster frames:',len(placements),'of',len(images))
        for x,y,image in placements: atlas.paste(image,(x,y))
        OUT.mkdir(parents=True,exist_ok=True)
        atlas.save(ATLAS,optimize=False,compress_level=9)
        styles=[]
        for p in plans:
            source_frames=sorted({f for v in p['variants'] for f in v})
            styles.append({'index':p['index'],'linkage':p['linkage'],'kind':p['kind'],
                'skipOriginYZero':p['skipOriginYZero'],
                'worldLit':p['worldLit'],
                'frames':[meta[(p['index'],f)] for f in source_frames],
                'variants':[[source_frames.index(f) for f in v] for v in p['variants']]})
        result={'schema':'cf7-combat-fx.v1','pixelsPerUnit':ZOOM,'ticksPerSecond':30,
                'atlas':{'path':'data/combat_visuals/effects-atlas.png','width':atlas_width,'height':atlas_height,'sha256':digest(ATLAS)},
                'sources':[record(p) for p in sources]+[record(SWF)],
                'tools':[record(HERE/'build.py'),record(HERE/'CombatSpriteExporter.java')]
                    +[record(p) for p in sorted((ROOT/'tools/ffdec').rglob('*.jar'))],
                'rasterizer':{'pillowVersion':pillow_version,'pixelsPerUnit':ZOOM,'duplicateFrames':'exact-rgba-sha256'},
                'recipe':plans,'styles':styles}
        CATALOG.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    verify()


def verify_lights():
    def unique(pairs):
        value={}
        for key,item in pairs:
            if key in value:raise ValueError('Duplicate local-light key: '+key)
            value[key]=item
        return value
    p=ROOT/'data/combat_visuals/local_lights.v1.json'
    data=json.loads(p.read_text(encoding='utf-8'),object_pairs_hook=unique)
    if data['schema']!='cf7-combat-local-lights.v1' or set(data['muzzles'])!=set(MUZZLES):
        raise ValueError('Local light preset set differs from muzzle whitelist')
    def number(v,lo,hi):
        return type(v) in (int,float) and math.isfinite(v) and lo<=v<=hi
    if not number(data['maximumResponse'],0,.8):raise ValueError('Invalid light response limit')
    for name,light in data['muzzles'].items():
        if not number(light['radius'],16,256) or not number(light['energy'],0,2):
            raise ValueError('Invalid light radius/energy: '+name)
        if type(light['ticks']) is not int or not 1<=light['ticks']<=6 or not re.fullmatch(r'#[0-9a-fA-F]{6}',light['color']):
            raise ValueError('Invalid light duration/color: '+name)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    verify() if args.check else build()
