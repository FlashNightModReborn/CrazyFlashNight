"""Small deterministic GLB writer for material-batched, vertex-lit display assets."""
import hashlib
import json
import struct
from pathlib import Path

import numpy as np


class GLBWriter:
    def __init__(self):
        self.binary = bytearray()
        self.doc = {'asset': {'version': '2.0', 'generator': 'CF7 desert-runtime first candidate'},
                    'extensionsUsed': ['KHR_materials_unlit'], 'scene': 0, 'scenes': [{'nodes': []}],
                    'nodes': [], 'meshes': [], 'materials': [], 'accessors': [], 'bufferViews': [],
                    'buffers': [{'byteLength': 0}], 'images': [], 'textures': [], 'samplers': []}
        self.image_map = {}
        self.texture_map = {}
        self.material_map = {}
        self.image_audit = []
        self.mesh_audit = []
        self.duplicate_triangles_removed = 0

    def view(self, blob, target=None):
        self.binary.extend(b'\0' * (-len(self.binary) % 4))
        offset = len(self.binary)
        self.binary.extend(blob)
        item = {'buffer': 0, 'byteOffset': offset, 'byteLength': len(blob)}
        if target:
            item['target'] = target
        self.doc['bufferViews'].append(item)
        return len(self.doc['bufferViews']) - 1

    def accessor(self, array, kind, normalized=False, bounds=False, target=34962):
        array = np.ascontiguousarray(array)
        types = {np.dtype('float32'): 5126, np.dtype('uint16'): 5123, np.dtype('uint8'): 5121}
        item = {'bufferView': self.view(array.tobytes(), target), 'componentType': types[array.dtype],
                'count': len(array), 'type': kind}
        if normalized:
            item['normalized'] = True
        if bounds:
            item['min'] = array.min(axis=0).tolist()
            item['max'] = array.max(axis=0).tolist()
        self.doc['accessors'].append(item)
        return len(self.doc['accessors']) - 1

    def texture(self, image, interpolation='Linear', extension='REPEAT'):
        if image.packed_file is None:
            raise RuntimeError('Runtime texture must be packed in the verified source: ' + image.name)
        blob = bytes(image.packed_file.data)
        digest = hashlib.sha256(blob).hexdigest()
        if digest not in self.image_map:
            mime = 'image/png' if blob.startswith(b'\x89PNG') else 'image/jpeg' if blob.startswith(b'\xff\xd8') else None
            if not mime:
                raise RuntimeError('Unsupported packed texture encoding: ' + image.name)
            self.image_map[digest] = len(self.doc['images'])
            self.doc['images'].append({'name': image.name, 'bufferView': self.view(blob), 'mimeType': mime})
            self.image_audit.append({'name': image.name, 'bytes': len(blob), 'sha256': digest, 'size': list(image.size)})
        sampler = {'magFilter': 9728 if interpolation == 'Closest' else 9729,
                   'minFilter': 9984 if interpolation == 'Closest' else 9987,
                   'wrapS': 10497 if extension == 'REPEAT' else 33071,
                   'wrapT': 10497 if extension == 'REPEAT' else 33071}
        key = (digest, tuple(sampler.items()))
        if key not in self.texture_map:
            try:
                sampler_id = self.doc['samplers'].index(sampler)
            except ValueError:
                sampler_id = len(self.doc['samplers'])
                self.doc['samplers'].append(sampler)
            self.texture_map[key] = len(self.doc['textures'])
            self.doc['textures'].append({'source': self.image_map[digest], 'sampler': sampler_id})
        return self.texture_map[key]

    def material(self, texture_id, alpha, double_sided):
        key = (texture_id, alpha, double_sided)
        if key not in self.material_map:
            item = {'name': f'Runtime_Unlit_{len(self.material_map):03d}',
                    'extensions': {'KHR_materials_unlit': {}},
                    'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1},
                    'doubleSided': bool(double_sided), 'alphaMode': 'BLEND' if alpha else 'OPAQUE'}
            if texture_id is not None:
                item['pbrMetallicRoughness']['baseColorTexture'] = {'index': texture_id}
            self.material_map[key] = len(self.doc['materials'])
            self.doc['materials'].append(item)
        return self.material_map[key]

    def batch(self, owner, material_id, position, color, uv, protected, ordinal, submap_index=None):
        # Each input chunk contains <= 60k face-corner vertices, guaranteeing Uint16 indices.
        fields = [position.astype(np.float32), color.astype(np.float32)]
        if uv is not None:
            fields.append(uv.astype(np.float32))
        joined = np.ascontiguousarray(np.concatenate(fields, axis=1), dtype=np.float32)
        if not np.isfinite(joined).all():
            raise RuntimeError('Non-finite runtime geometry: ' + owner)
        unique, inverse = np.unique(joined, axis=0, return_inverse=True)
        if len(unique) > 65535:
            raise RuntimeError('Portable index bound exceeded')
        # Joining same-material source objects can expose identical coplanar faces.
        # The first-pass duplicates are opaque/double-sided, so retain the first
        # winding and all its attributes rather than let Blender silently drop them.
        index_triangles = inverse.reshape(-1, 3)
        _, first = np.unique(np.sort(index_triangles, axis=1), axis=0, return_index=True)
        duplicate_count = len(index_triangles) - len(first)
        if duplicate_count:
            material = self.doc['materials'][material_id]
            if material['alphaMode'] != 'OPAQUE' or not material['doubleSided']:
                raise RuntimeError('Overlapping non-opaque/oriented faces require a separate review: ' + owner)
            index_triangles = index_triangles[np.sort(first)]
            inverse = index_triangles.reshape(-1)
            self.duplicate_triangles_removed += duplicate_count
        attrs = {'POSITION': self.accessor(unique[:, :3], 'VEC3', bounds=True)}
        colors = unique[:, 3:7]
        if protected:
            attrs['COLOR_0'] = self.accessor(colors.astype(np.float32), 'VEC4')
        else:
            attrs['COLOR_0'] = self.accessor(np.rint(np.clip(colors, 0, 1) * 255).astype(np.uint8), 'VEC4', normalized=True)
        if uv is not None:
            attrs['TEXCOORD_0'] = self.accessor(unique[:, 7:9].astype(np.float32), 'VEC2')
        primitive = {'attributes': attrs, 'indices': self.accessor(inverse.astype(np.uint16), 'SCALAR', target=34963),
                     'material': material_id, 'mode': 4}
        name = f'{owner}__runtime_{ordinal:03d}'
        mesh_id = len(self.doc['meshes'])
        self.doc['meshes'].append({'name': name, 'primitives': [primitive]})
        node_id = len(self.doc['nodes'])
        extras = {'placeId': owner, 'runtimeCandidate': True}
        if submap_index is not None:
            extras['submapIndex'] = int(submap_index)
        self.doc['nodes'].append({'name': name, 'mesh': mesh_id, 'extras': extras})
        self.doc['scenes'][0]['nodes'].append(node_id)
        self.mesh_audit.append({'name': name, 'placeId': owner, 'submapIndex': submap_index,
                                'vertices': len(unique), 'triangles': len(inverse) // 3,
                                'duplicateTrianglesRemoved': duplicate_count,
                                'protectedColorFloat': protected, 'material': material_id,
                                'bounds': {'min': position.min(axis=0).tolist(), 'max': position.max(axis=0).tolist()}})

    def anchor(self, place):
        node_id = len(self.doc['nodes'])
        self.doc['nodes'].append({'name': 'ANCHOR_' + place['id'], 'translation': place['worldAnchor'],
                                 'extras': {'placeId': place['id'], 'stageId': place.get('stageId'), 'geographicAnchor': True}})
        self.doc['scenes'][0]['nodes'].append(node_id)

    def save(self, path):
        self.binary.extend(b'\0' * (-len(self.binary) % 4))
        self.doc['buffers'][0]['byteLength'] = len(self.binary)
        if not self.doc['images']:
            for key in ['images', 'textures', 'samplers']:
                self.doc.pop(key)
        encoded = json.dumps(self.doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        encoded += b' ' * (-len(encoded) % 4)
        total = 12 + 8 + len(encoded) + 8 + len(self.binary)
        target = Path(path)
        temporary = target.with_suffix('.partial.glb')
        with temporary.open('wb') as stream:
            stream.write(struct.pack('<4sII', b'glTF', 2, total))
            stream.write(struct.pack('<II', len(encoded), 0x4E4F534A))
            stream.write(encoded)
            stream.write(struct.pack('<II', len(self.binary), 0x004E4942))
            stream.write(self.binary)
        temporary.replace(target)
        return {'bytes': total, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                'meshes': len(self.doc['meshes']), 'materials': len(self.doc['materials']),
                'images': len(self.doc.get('images', [])),
                'triangles': sum(mesh['triangles'] for mesh in self.mesh_audit),
                'vertices': sum(mesh['vertices'] for mesh in self.mesh_audit), 'allIndicesUint16': True}
