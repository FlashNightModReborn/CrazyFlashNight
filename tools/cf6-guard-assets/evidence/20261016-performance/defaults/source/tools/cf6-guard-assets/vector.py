"""Native gradients, clips and shared vector-atlas crops for the CF6 guard."""
from pathlib import Path
import copy
import hashlib
import importlib.util
import xml.etree.ElementTree as SE

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('guard_wings_vector', ROOT / 'tools/cf6-wings-assets/vector.py')
wings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wings)
base, gamma = wings.base, wings.gamma


class NativePart(wings.NativePart):
    shared_references = {}

    def __init__(self, path, name, origin):
        super().__init__(path, name, origin)
        # The guard limb crops translate the path inside clipPath. The base
        # mask writer consumes the clipPath transform, so lift the single
        # path's transform to that parent without changing the archived SVG.
        for clip in self.svg.iter():
            if base.tag(clip) != 'clipPath':
                continue
            transformed = [child for child in clip if child.get('transform')]
            if not transformed:
                continue
            if len(clip) != 1 or base.tag(transformed[0]) != 'path':
                raise ValueError('Compound transformed clip requires a separate review')
            child = transformed[0]
            matrix = base.mul(base.transform(clip.get('transform')), base.transform(child.get('transform')))
            clip.set('transform', 'matrix('+' '.join(map(str,matrix))+')')
            child.attrib.pop('transform')

    def contents(self, element, inherited=None, matrix=base.I):
        if base.tag(element) != 'use':
            return super().contents(element, inherited, matrix)
        ref = element.get('href', element.get('{http://www.w3.org/1999/xlink}href', ''))
        if not ref.startswith('#') or ref[1:] not in self.by_id:
            raise ValueError('Only resolved local vector-atlas references are supported')
        if any(element.get(k) for k in ('width', 'height')):
            raise ValueError('Unexpected viewport-sized use element')
        source = copy.deepcopy(self.by_id[ref[1:]])
        transform = base.mul(matrix, base.transform(element.get('transform')))
        transform = base.mul(transform, (1, 0, 0, 1, float(element.get('x', '0')), float(element.get('y', '0'))))
        seen = {ref}
        # Torn-suit drawings have a local use alias in front of the same atlas.
        while base.tag(source) == 'use':
            alias = source.get('href', source.get('{http://www.w3.org/1999/xlink}href', ''))
            if alias in seen or not alias.startswith('#') or alias[1:] not in self.by_id:
                raise ValueError('Unresolved or cyclic vector-atlas alias')
            if any(source.get(k) for k in ('width', 'height')):
                raise ValueError('Unexpected viewport-sized atlas alias')
            seen.add(alias)
            transform = base.mul(transform, base.transform(source.get('transform')))
            transform = base.mul(transform, (1, 0, 0, 1, float(source.get('x', '0')), float(source.get('y', '0'))))
            source = copy.deepcopy(self.by_id[alias[1:]])
        if base.tag(source) != 'g' or any(base.tag(child) == 'use' for child in source.iter()):
            raise ValueError('Expected one non-recursive vector-atlas group')
        source.attrib.pop('id', None)
        digest = hashlib.sha256(SE.tostring(source)).hexdigest()
        name = 'Codex/光头保安/共用矢量图集/' + digest[:16]
        if digest not in self.shared_references:
            child = copy.copy(self)
            child.name, child.symbols, child.serial, child.masks = name, {}, 0, 0
            drawing = child.contents(source)
            child.symbols[name] = gamma.symbol(name, [gamma.layer('冻结身体材质', [gamma.frame(elements=drawing)])])
            self.shared_references[digest] = child.symbols
        self.symbols.update(self.shared_references[digest])
        return [gamma.instance(name, matrix=transform)]
