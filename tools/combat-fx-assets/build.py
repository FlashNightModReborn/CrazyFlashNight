#!/usr/bin/env python3
"""Deterministic casing/muzzle atlas from the existing Flash source and published SWF.

--check verifies source/recipe/tool/output hashes and catalog bounds without
rerendering. A full build uses the installed FFDec renderer in a temporary folder.
Frame scripts are classified here, never evaluated by FFDec or the runtime.
"""
from __future__ import annotations
import argparse
import hashlib
import io
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
import wave
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
_recipe_module = runpy.run_path(str(HERE / 'source_recipes.py'))
SOURCE_LIBRARIES = _recipe_module['SOURCE_LIBRARIES']
MUZZLES = _recipe_module['MUZZLES']
METADATA_KEYS = _recipe_module['METADATA_KEYS']
TIMELINE_SOUNDS = _recipe_module['TIMELINE_SOUNDS']
recipe = _recipe_module['recipe']
LIB = ROOT / 'flashswf/arts/原版素材库-子弹/LIBRARY'
SWF = ROOT / 'flashswf/arts/原版素材库-子弹.swf'
OUT = ROOT / 'data/combat_visuals'
CATALOG = OUT / 'effects.v1.json'
ATLAS = OUT / 'effects-atlas.png'
NS = '{http://ns.adobe.com/xfl/2008/}'
ZOOM = 2
SOUND_DIRECTORY = 'sounds/export/特效'
SOUND_FILE_LIMIT = 256 * 1024
SOUND_TOTAL_LIMIT = 2 * 1024 * 1024


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def record(path):
    return {'path': Path(path).relative_to(ROOT).as_posix(), 'sha256': digest(path)}


def exports(swf=SWF):
    helper = runpy.run_path(str(ROOT / 'tools/swf-audit/swfscan.py'))
    raw = swf.read_bytes()
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


def swf_audio(swf):
    """Read tag identities/events only; no AVM1 evaluation or SWF mutation."""
    helper = runpy.run_path(str(ROOT / 'tools/swf-audit/swfscan.py'))
    raw = swf.read_bytes()
    if raw[:3] not in (b'CWS', b'FWS'): raise ValueError('Unsupported SWF compression')
    data = zlib.decompress(raw[8:]) if raw[:3] == b'CWS' else raw[8:]
    bits = helper['Bits'](data); width = bits.u(5)
    for _ in range(4): bits.s(width)
    bits.align()
    def tags(body, pos):
        frame = 0
        while pos < len(body) - 1:
            head, = struct.unpack_from('<H', body, pos); pos += 2
            code, size = head >> 6, head & 63
            if size == 63:
                size, = struct.unpack_from('<I', body, pos); pos += 4
            if pos + size > len(body): raise ValueError('Truncated SWF audio tag')
            yield code, body[pos:pos+size], frame
            pos += size
            if code == 1: frame += 1
            if code == 0: break
    sprites, sounds = {}, {}
    for code, body, _ in tags(data, bits.byte + 4):
        if code == 39:
            character, = struct.unpack_from('<H', body)
            sprites[character] = list(tags(body, 4))
        elif code == 14:
            character, = struct.unpack_from('<H', body)
            if character in sounds: raise ValueError('Duplicate SWF sound')
            sounds[character] = body
    def child_id(code, body):
        if code == 4: return struct.unpack_from('<H', body)[0]
        if code not in (26, 70, 94): return None
        flags = body[0]; flags2 = body[1] if code != 26 else 0
        pos = 3 if code == 26 else 4
        if code != 26 and ((flags2 & 8) or ((flags2 & 16) and (flags & 2))):
            _, pos = helper['read_string'](body, pos)
        return struct.unpack_from('<H', body, pos)[0] if flags & 2 else None
    def events(character, visited=None):
        visited = set() if visited is None else visited
        if character in visited: return []
        visited.add(character); result = []
        for code, body, frame in sprites.get(character, []):
            if code == 15:
                sound_id, = struct.unpack_from('<H', body)
                result.append((character, frame, sound_id, body[2:]))
            elif code in (19, 89):
                raise ValueError('Unreviewed stream/class audio in effect sprite: ' + str(character))
            elif code in (18, 45):
                # CS6 emits empty SoundStreamHead2 settings on ordinary sprites.
                if len(body) != 4 or body[1:] != b'\0\0\0':
                    raise ValueError('Unreviewed streamed audio in effect sprite: ' + str(character))
            child = child_id(code, body)
            if child in sprites: result += events(child, visited)
        return result
    return sounds, events


def published_sound_plan(plans):
    """Cross-check every exported effect and child against the finite XFL audio map."""
    definitions = {}
    for library in SOURCE_LIBRARIES:
        swf = ROOT / library['swf']; names = exports(swf); sounds, events = swf_audio(swf)
        for plan in (p for p in plans if p['sourceKey'] == library['key']):
            character = names[plan['renderLinkage']]
            expected = []
            for frame, _, sound_id in TIMELINE_SOUNDS.get(plan['linkage'], ()):
                info = b'\x08\x01' + struct.pack('<IHH', 0, 32769, 32769) if plan['linkage'] == '火花' else b'\0'
                expected.append((character, frame, sound_id, info))
                body = sounds[sound_id]
                if len(body) < 10 or body[2] >> 4 != 2:
                    raise ValueError('Expected published MP3 event sound: ' + str(sound_id))
                rate = (5512, 11025, 22050, 44100)[(body[2] >> 2) & 3]
                count, seek = struct.unpack_from('<Ih', body, 3)
                channels = 2 if body[2] & 1 else 1
                if not 0 <= seek <= 4096 or not 0 < count * 2 * channels + 44 <= SOUND_FILE_LIMIT:
                    raise ValueError('Published sound exceeds reviewed PCM bounds')
                sound = {'id': 'cfnfx-stock-' + str(sound_id) + '.wav', 'sourceKey': library['key'],
                         'sourceSoundId': sound_id, 'sourceSeekSamples': seek,
                         'sampleRate': rate, 'sampleFrames': count, 'channels': channels, 'pcmBits': 16}
                sound['path'] = SOUND_DIRECTORY + '/' + sound['id']
                if sound_id in definitions: raise ValueError('Duplicate reviewed event sound')
                definitions[sound_id] = sound
            if events(character) != expected:
                raise ValueError('Published audio differs from reviewed variant births: ' + plan['linkage'])
    if len(definitions) != 20: raise ValueError('Review the twenty-sound audio closure')
    return [definitions[key] for key in sorted(definitions)]


def verify_sound_assets(catalog, plans):
    expected = published_sound_plan(plans)
    actual = catalog.get('soundAssets')
    if not isinstance(actual, list) or len(actual) != len(expected): raise ValueError('Missing authored sound assets')
    total = 0
    for item, source in zip(actual, expected):
        if {k: v for k, v in item.items() if k not in ('sha256', 'bytes')} != source:
            raise ValueError('Authored sound identity differs from published SWF')
        path = ROOT / source['path']; payload = path.read_bytes(); total += len(payload)
        if len(payload) != item['bytes'] or not 44 < len(payload) <= SOUND_FILE_LIMIT or digest(path) != item['sha256']:
            raise ValueError('Authored sound integrity/size mismatch: ' + source['id'])
        with wave.open(io.BytesIO(payload)) as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getnframes(), wav.getcomptype()) != (
                    source['channels'], 2, source['sampleRate'], source['sampleFrames'], 'NONE'):
                raise ValueError('Authored sound PCM differs from published duration: ' + source['id'])
            if len(wav.readframes(wav.getnframes())) != source['sampleFrames'] * source['channels'] * 2:
                raise ValueError('Truncated authored PCM')
    if total > SOUND_TOTAL_LIMIT: raise ValueError('Authored sound pack exceeds size budget')
    if {p.name for p in (ROOT / SOUND_DIRECTORY).glob('cfnfx-stock-*')} != {s['id'] for s in expected}:
        raise ValueError('Unexpected generated authored sound file')
    # Match AudioCoordinator's direct-file, full-basename SFX discovery. A source
    # linkage or a file in a nested/non-preloaded directory is not a playable cue.
    available = {p.name for pack in ('武器', '特效', '人物')
                 if (ROOT / 'sounds/export' / pack).is_dir()
                 for p in (ROOT / 'sounds/export' / pack).iterdir() if p.is_file()}
    for plan in plans:
        if plan['soundAtBirth'] != bool(plan['variantSounds']): raise ValueError('Invalid birth sound flag')
        for cue in plan['variantSounds']:
            if cue not in available: raise ValueError('SFX cue has no exact preloaded filename: ' + cue)
    return total


def export_sounds(plans, temp, classes, classpath):
    expected = published_sound_plan(plans)
    destination = temp / 'sound-raster'
    subprocess.run([str(java_tool('java')), '-Xmx1g', '-cp', str(classes)+os.pathsep+classpath,
                    'CombatSoundExporter', str(SWF), ','.join(str(s['sourceSoundId']) for s in expected),
                    str(destination)], check=True, timeout=120)
    rows = {int(cols[0]): list(map(int, cols[1:])) for cols in
            (line.split('\t') for line in (destination / 'sounds.tsv').read_text(encoding='utf-8').splitlines())}
    result = []
    for sound in expected:
        sound_id = sound['sourceSoundId']
        if rows.get(sound_id) != [sound[k] for k in ('sourceSeekSamples', 'sampleFrames', 'sampleRate', 'channels')]:
            raise ValueError('FFDec sound decode identity differs from published tag')
        with wave.open(str(destination / ('sound-' + str(sound_id) + '.wav')), 'rb') as wav:
            if (wav.getnchannels(), wav.getsampwidth(), wav.getframerate(), wav.getcomptype()) != (
                    sound['channels'], 2, sound['sampleRate'], 'NONE') or wav.getnframes() < sound['sampleFrames']:
                raise ValueError('Invalid FFDec decoded PCM: ' + str(sound_id))
            # SeekSamples was removed by FFDec. Trim encoder tail to the published
            # DefineSound sample count, keeping the event's original duration.
            pcm = wav.readframes(sound['sampleFrames'])
        encoded = io.BytesIO()
        with wave.open(encoded, 'wb') as wav:
            wav.setnchannels(sound['channels']); wav.setsampwidth(2); wav.setframerate(sound['sampleRate'])
            wav.writeframes(pcm)
        path = ROOT / sound['path']; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(encoded.getvalue())
        result.append({**sound, 'sha256': digest(path), 'bytes': path.stat().st_size})
    return result


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
    if catalog['sourceLibraries'] != list(SOURCE_LIBRARIES):
        raise ValueError('Unreviewed effect source libraries')
    if plans != catalog['recipe']:
        raise ValueError('Stale effect recipe')
    if {p.relative_to(ROOT).as_posix() for p in files} | {s['swf'] for s in SOURCE_LIBRARIES} != {s['path'] for s in catalog['sources']}:
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
        for key in METADATA_KEYS:
            if style.get(key) != plan.get(key): raise ValueError('Style adapter differs from recipe: ' + key)
        actual=[[style['frames'][i]['sourceFrame'] for i in v] for v in style['variants']]
        if actual!=plan['variants']:raise ValueError('Animation differs from script adapter')
        for frame in style['frames']:
            x,y,fw,fh=frame['rect']
            if min(x,y)<0 or min(fw,fh)<1 or x+fw>w or y+fh>h:
                raise ValueError('Atlas frame out of bounds')
    sound_bytes = verify_sound_assets(catalog, plans)
    verify_lights()
    print(f'Combat FX check OK: {len(plans)} styles, {sum(len(s["frames"]) for s in catalog["styles"])} frames, {w}x{h}, {ATLAS.stat().st_size} bytes; 20 birth sounds, {sound_bytes} PCM WAV bytes')


def build():
    from PIL import Image, __version__ as pillow_version
    plans, sources = recipe()
    source_swfs = {s['swf']: digest(ROOT/s['swf']) for s in SOURCE_LIBRARIES}
    classpath = os.pathsep.join([str(ROOT / 'tools/ffdec/lib/*'), str(ROOT / 'tools/ffdec/ffdec.jar')])
    scratch = ROOT / 'tmp/combat-fx-assets'; scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='export-', dir=scratch) as tmp_name:
        temp = Path(tmp_name)
        classes = temp / 'classes'; classes.mkdir()
        subprocess.run([str(java_tool('javac')), '-encoding', 'UTF-8', '-cp', classpath,
                        '-d', str(classes), str(HERE / 'CombatSpriteExporter.java'),
                        str(HERE / 'CombatSoundExporter.java')], check=True, timeout=120)
        sound_assets = export_sounds(plans, temp, classes, classpath)
        raster_rows = []
        for library in SOURCE_LIBRARIES:
            selected = [p for p in plans if p['sourceKey'] == library['key']]
            swf = ROOT / library['swf']; names = exports(swf)
            plan_path = temp / (library['key'] + '-plan.tsv')
            plan_path.write_text('\n'.join(str(p['index'])+'\t'+str(names[p['renderLinkage']])+'\t'+
                ','.join(str(f) for f in sorted({f for v in p['variants'] for f in v}))+'\t'+
                (p['renderChild'] or '-')+'\t'+p['renderMode'] for p in selected), encoding='utf-8')
            raster = temp / ('raster-' + library['key'])
            subprocess.run([str(java_tool('java')), '-Xmx2g', '-cp', str(classes)+os.pathsep+classpath,
                            'CombatSpriteExporter', str(swf), str(plan_path), str(raster), str(ZOOM)], check=True, timeout=240)
            raster_rows.extend((raster / 'frames.tsv').read_text(encoding='utf-8').splitlines())
        images, meta = [], {}
        for line in raster_rows:
            cols = line.split('\t'); style, frame = map(int, cols[:2]); xmin, ymin, xmax, ymax = map(int, cols[2:6])
            with Image.open(cols[6]) as img:
                image = img.convert('RGBA'); box = image.getbbox()
                if plans[style]['renderMode'] in ('padded', 'nested-scaled'):
                    alpha = image.getchannel('A'); w, h = image.size
                    if any(alpha.crop(edge).getbbox() is not None for edge in
                           ((0, 0, w, 1), (0, h-1, w, h), (0, 0, 1, h), (w-1, 0, w, h))):
                        raise ValueError('Filtered effect reaches export viewport: ' + plans[style]['linkage'])
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
        if source_swfs != {s['swf']: digest(ROOT/s['swf']) for s in SOURCE_LIBRARIES}:
            raise ValueError('Source SWF changed during read-only export')
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
                **{key:p[key] for key in METADATA_KEYS if key in p},
                'frames':[meta[(p['index'],f)] for f in source_frames],
                'variants':[[source_frames.index(f) for f in v] for v in p['variants']]})
        result={'schema':'cf7-combat-fx.v1','pixelsPerUnit':ZOOM,'ticksPerSecond':30,
                'atlas':{'path':'data/combat_visuals/effects-atlas.png','width':atlas_width,'height':atlas_height,'sha256':digest(ATLAS)},
                'soundAssets': sound_assets,
                'sourceLibraries':list(SOURCE_LIBRARIES),
                'sources':[record(p) for p in sources]+[record(ROOT/s['swf']) for s in SOURCE_LIBRARIES],
                'tools':[record(HERE/'build.py'),record(HERE/'source_recipes.py'),record(HERE/'CombatSpriteExporter.java'),
                         record(HERE/'CombatSoundExporter.java'),record(ROOT/'tools/swf-audit/swfscan.py')]
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
