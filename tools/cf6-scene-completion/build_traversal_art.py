"""Restore full original door timelines as separate back/front/actor-mask XFL.

Uses existing redraw shapes, excludes legacy actor bodies and all inherited AS.
No SWF writer, Flash invocation, or production resource replacement.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json
import re
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEST = ROOT/'flashswf/backgrounds/cf6/preparation'
PROFILES = {
    1720: ('A03-R1/cf6-stage3-redraw-r1', [1715, 1716, 1718, 190]),
    1729: ('A04-R1/cf6-stage4-redraw-r1', [1715, 1716, 1718, 190]),
    1750: ('A05-R3/cf6-stage5-redraw-r3', [86, 1747, 1748, 1749])}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def serialize(node):
    return ET.tostring(node, encoding='utf-8', xml_declaration=True)


def clip_name(full_digest, identities):
    """Short physical/library identity; never merge different full content hashes."""
    name = 'CF6Src/' + full_digest[:24]
    if name in identities and identities[name] != full_digest:
        raise ValueError('truncated clip identity collision: ' + name)
    identities[name] = full_digest
    return name


def legacy_files(root):
    result = set()
    for sprite in (1720, 1729):
        for role in ('Back', 'Front', 'Mask'):
            folder = root/'flashswf/backgrounds/cf6/preparation'/f'CF6_Traversal{sprite}_{role}'/'LIBRARY/CF6SourceClip'
            if not folder.exists():
                continue
            if folder.is_symlink() or folder.is_junction():
                raise ValueError('redirected legacy namespace: ' + str(folder))
            for path in folder.rglob('*'):
                if path.is_dir() and not path.is_symlink() and not path.is_junction():
                    continue
                if not path.is_file() or path.is_symlink() or path.resolve() != path.absolute():
                    raise ValueError('unsupported legacy entry: ' + str(path))
                result.add(path.relative_to(root).as_posix())
    return result


def require_legacy_inventory(root, allowed):
    remaining = legacy_files(root)
    if remaining != set(allowed):
        raise ValueError('legacy namespace residual or unregistered file: ' +
                         repr(sorted(remaining.symmetric_difference(set(allowed)))))


def preflight_retirement(root, previous, outputs):
    """Validate every owned byte and the exact old namespace before any mutation."""
    for relative, identity in previous.items():
        target = root/relative
        if not target.is_file() or digest(target.read_bytes()) != identity['sha256']:
            raise ValueError('owned source was edited; preserve and reconcile: ' + relative)
    current = {path.relative_to(root).as_posix() for path in outputs}
    retired = set(previous) - current
    pattern = r'flashswf/backgrounds/cf6/preparation/CF6_Traversal(?:1720|1729)_(?:Back|Front|Mask)/LIBRARY/CF6SourceClip/[0-9a-f]{64}\.xml'
    for relative in retired:
        target = root/relative
        if not re.fullmatch(pattern, relative) or target.resolve() != target.absolute():
            raise ValueError('refuse retirement outside exact owned clip namespace: ' + relative)
    require_legacy_inventory(root, retired)
    for target in outputs:
        relative = target.relative_to(root).as_posix()
        if target.exists() and relative not in previous:
            raise ValueError('unowned target exists: ' + relative)
    return sorted(retired)


def build():
    path = ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py'
    spec = importlib.util.spec_from_file_location('cf6_traversal_native', path)
    api = importlib.util.module_from_spec(spec);spec.loader.exec_module(api)
    E, N = api.E, api.N
    template = ROOT/'flashswf/backgrounds/cf6/CF6_A01_BG'
    outputs, assets, inputs = {}, [], {}
    symbol_identities = {}
    def remember(path):
        inputs[path.relative_to(ROOT).as_posix()] = digest(path.read_bytes())
    for path in [Path(__file__), ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py',
                 ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py', api.FONT]:
        remember(path)
    for path in [template/'DOMDocument.xml', template/'PublishSettings.xml', template/'CF6_A01_BG.xfl']:
        remember(path)
    for sprite, (package, whitelist) in PROFILES.items():
        package = ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'/package
        node_path = package/'reference/environment-original-nodes.json';remember(node_path)
        nodes = json.loads(node_path.read_text(encoding='utf-8'))['nodes']
        source_frames = nodes[str(sprite)]['frames']
        entry = package/'parts'/('shape-' + str(1718 if sprite != 1750 else 1747) + '.svg')
        converter = api.Candidate(entry)
        parts = {}
        for cid in whitelist:
            replacement = package/'parts'/f'shape-{cid}.svg'
            if replacement.is_file():
                remember(replacement);tree = ET.parse(replacement).getroot()
            else:
                definition = nodes[str(cid)]
                tree = ET.fromstring('<svg xmlns="http://www.w3.org/2000/svg" viewBox="' +
                    ' '.join(map(str, definition['viewBox'])) + '">' + definition['svgInner'] + '</svg>')
            converter.byid = {n.get('id'): n for n in tree.iter() if n.get('id')}
            converter.grads = {n.get('id'): n for n in tree.iter() if api.tag(n) in ('linearGradient', 'radialGradient')}
            parts[cid] = converter.instance(converter.walk_native(tree), 'part-'+str(cid))
        def placed(row):
            node = copy.deepcopy(parts[row['id']]);node.remove(node.find(N+'matrix'))
            api.matrix(node, row['matrix'])
            mult, add = row.get('colorMult', [256]*4), row.get('colorAdd', [0]*4)
            if mult != [256]*4 or add != [0]*4:
                attrs = {channel+'Multiplier': api.base.fmt(mult[i]/256) for i, channel in enumerate(('red','green','blue','alpha'))}
                attrs.update({channel+'Offset': str(add[i]) for i, channel in enumerate(('red','green','blue','alpha'))})
                E('Color', attrs, E('color', parent=node))
            return node
        def clipped(instance, mask_row):
            # Keep the source mask local to the exact covered source depth.
            # Masking the entire Back/Front export would also crop unrelated art.
            root = E('DOMSymbolItem', {'name':'pending', 'symbolType':'graphic'})
            layers = E('layers', parent=E('DOMTimeline', {'name':'SourceClip'}, E('timeline', parent=root)))
            for attrs, element in [
                    ({'name':'Boundary','layerType':'mask','locked':'true'}, placed(mask_row)),
                    ({'name':'Source','parentLayerIndex':'0','locked':'true'}, instance)]:
                layer = E('DOMLayer', attrs, layers)
                frame = E('DOMFrame', {'index':'0','duration':'1','keyMode':'9728'}, E('frames', parent=layer))
                E('elements', parent=frame).append(element)
            key = digest(serialize(root))
            name = clip_name(key, symbol_identities)
            if name not in converter.symbols:
                root.set('name', name)
                converter.symbols[name] = root
            result = E('DOMSymbolInstance', {'libraryItemName':name, 'symbolType':'graphic',
                                            'loop':'single frame','firstFrame':'0'})
            api.matrix(result, [1,0,0,1,0,0])
            return result
        timelines = {role: E('DOMTimeline', {'name': role}) for role in ['Back','Front','Mask']}
        frames_out = {role: E('frames', parent=E('DOMLayer', {'name': role}, E('layers', parent=t))) for role,t in timelines.items()}
        mask_frames = []
        internal_clips = {'Back':[], 'Front':[]}
        for index, frame in enumerate(source_frames):
            actor_depths = [int(d) for d,p in frame.items() if 1013 <= p['id'] <= 1025]
            actor_min = min(actor_depths) if actor_depths else 100000
            split = {'Back': [], 'Front': [], 'Mask': []}
            masks = [(int(d),r) for d,r in frame.items() if 'clipDepth' in r]
            for depth, row in masks:
                if row['id'] not in parts:
                    raise ValueError('source mask missing from retained shape closure: '+str(row['id']))
            for depth, row in sorted(frame.items(), key=lambda item: int(item[0])):
                if row['id'] not in whitelist:
                    continue
                if 'clipDepth' in row:
                    hit = [d for d in actor_depths if int(depth) < d <= row['clipDepth']]
                    if hit and len(hit) != len(actor_depths):
                        raise ValueError('partial-body clip cannot be applied to a modern whole actor')
                    if hit:
                        split['Mask'].append(placed(row));mask_frames.append(index+1)
                    continue
                role = 'Front' if int(depth) > actor_min else 'Back'
                instance = placed(row)
                covering = [(d,r) for d,r in masks if d < int(depth) <= r['clipDepth']]
                for mask_depth, mask_row in sorted(covering, reverse=True):
                    instance = clipped(instance, mask_row)
                    internal_clips[role].append({'frame':index+1,'sourceDepth':int(depth),
                        'sourceId':row['id'],'maskDepth':mask_depth,'maskId':mask_row['id'],
                        'clipDepth':mask_row['clipDepth']})
                split[role].append(instance)
            for role, elements in split.items():
                frame_out = E('DOMFrame', {'index':str(index), 'duration':'1', 'keyMode':'9728'}, frames_out[role])
                E('script', parent=E('Actionscript', parent=frame_out)).text = 'stop();'
                el = E('elements', parent=frame_out)
                for instance in elements:
                    el.append(instance)
        for role, timeline in timelines.items():
            name = f'CF6_Traversal{sprite}_{role}';target = DEST/name
            root = ET.parse(template/'DOMDocument.xml').getroot()
            root.set('width', '600');root.set('height', '500');root.set('frameRate', '30')
            for child in list(root):
                if api.tag(child) in ('media','symbols','timelines','folders'):root.remove(child)
            includes = E('symbols', parent=root)
            for symbol, tree in converter.symbols.items():
                outputs[target/'LIBRARY'/(symbol+'.xml')] = serialize(tree)
                E('Include', {'href':symbol+'.xml','loadImmediate':'false'}, includes)
            E('timelines', parent=root).append(timeline)
            outputs[target/'DOMDocument.xml'] = serialize(root)
            outputs[target/(name+'.xfl')] = (template/'CF6_A01_BG.xfl').read_bytes()
            profile = ET.parse(template/'PublishSettings.xml')
            profile.find('.//PublishFormatProperties/flashFileName').text = name+'.swf'
            outputs[target/'PublishSettings.xml'] = serialize(profile.getroot())
            if (template/'mimetype').is_file():outputs[target/'mimetype'] = (template/'mimetype').read_bytes()
            assets.append({'name': name, 'xfl': (target/(name+'.xfl')).relative_to(ROOT).as_posix(),
                           'frames': len(source_frames), 'role':role, 'sourceSprite':sprite,
                           'registration': 'original symbol origin; do not add viewport offset twice',
                           'maskActiveFrames': sorted(set(mask_frames)) if role == 'Mask' else [],
                           'internalSourceClips':internal_clips.get(role, []),
                           'maskContract': 'attach mask only on active source frames; remove on other frames; actor is supplied by live appearance adapter',
                           'excluded': 'legacy body, weapon, hit markers, arrows, transition/save actions'})
    manifest = {'schema':'cf6-traversal-native-source.v1', 'state':'source-only; not CS6 compiled',
                'inputs':inputs, 'assets':assets,
                'symbolIdentities':symbol_identities,
                'outputs':{p.relative_to(ROOT).as_posix(): {'sha256':digest(data),'bytes':len(data)} for p,data in outputs.items()}}
    return outputs, manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser();parser.add_argument('--check', action='store_true');args = parser.parse_args()
    manifest_path = HERE/'traversal-art-manifest.json'
    outputs, manifest = build()
    previous = json.loads(manifest_path.read_text(encoding='utf-8'))['outputs'] if manifest_path.is_file() else {}
    if args.check:
        require_legacy_inventory(ROOT, set())
        retired = []
    else:
        retired = preflight_retirement(ROOT, previous, outputs)
    manifest_bytes = (json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    # The manifest is written last. Interrupted mutation fails closed on the old identities.
    for path, data in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes() != data:raise ValueError('stale generated source: '+str(path))
        elif not path.exists() or path.read_bytes() != data:
            path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(data)
    for relative in retired:
        path = ROOT/relative
        # Recheck immediately before exact unlink, in case an external writer intervened.
        if digest(path.read_bytes()) != previous[relative]['sha256']:
            raise ValueError('retiring source changed; preserve and reconcile: ' + relative)
        path.unlink()
    for folder in sorted({(ROOT/relative).parent for relative in retired}):
        if not any(folder.iterdir()):folder.rmdir()
    require_legacy_inventory(ROOT, set())
    if args.check:
        if not manifest_path.is_file() or manifest_path.read_bytes() != manifest_bytes:
            raise ValueError('stale generated manifest')
    elif not manifest_path.is_file() or manifest_path.read_bytes() != manifest_bytes:
        manifest_path.write_bytes(manifest_bytes)
    print(json.dumps({'state':'source_checked' if args.check else 'source_built',
                      'assets':len(manifest['assets']), 'files':len(outputs)+1,
                      'retiredFiles':len(retired),
                      'bytes':sum(len(d) for d in outputs.values())+len(manifest_bytes)}))
