"""Read Blender's existing base-colour graph without changing source materials."""
import numpy as np
import hashlib
from mathutils import Euler

ALPHA_EQUIVALENCE_CACHE = {}


def equivalent_alpha(color_node, alpha_node):
    """Narrow audited sign-atlas case: same UV/sampler and exactly equal decoded alpha."""
    color_image, alpha_image = color_node.image, alpha_node.image
    if tuple(color_image.size) != tuple(alpha_image.size):
        raise RuntimeError('Emission/alpha image dimensions differ')
    if color_node.inputs['Vector'].is_linked or alpha_node.inputs['Vector'].is_linked:
        raise RuntimeError('Separate emission/alpha images require explicit UV equivalence')
    if (color_node.interpolation, color_node.extension) != (alpha_node.interpolation, alpha_node.extension):
        raise RuntimeError('Emission/alpha image samplers differ')
    color_hash = hashlib.sha256(bytes(color_image.packed_file.data)).hexdigest()
    alpha_hash = hashlib.sha256(bytes(alpha_image.packed_file.data)).hexdigest()
    key = (color_hash, alpha_hash)
    if key not in ALPHA_EQUIVALENCE_CACHE:
        channels = []
        for image in [color_image, alpha_image]:
            values = np.empty(len(image.pixels), dtype=np.float32)
            image.pixels.foreach_get(values)
            channels.append(values.reshape(-1, 4)[:, 3].copy())
            del values
        if not np.array_equal(channels[0], channels[1]):
            raise RuntimeError('Emission/alpha images have different decoded alpha')
        ALPHA_EQUIVALENCE_CACHE[key] = {'colorImage': color_image.name, 'alphaImage': alpha_image.name,
            'colorImageSha256': color_hash, 'alphaImageSha256': alpha_hash,
            'decodedAlphaSha256': hashlib.sha256(channels[0].tobytes()).hexdigest(),
            'maxAlphaDifference': 0.0, 'size': list(color_image.size), 'sameActiveUV': True,
            'sampler': [color_node.interpolation, color_node.extension], 'pass': True}
    return ALPHA_EQUIVALENCE_CACHE[key]


def rgba(value):
    if hasattr(value, '__len__'):
        values = list(value)
        return values[:4] if len(values) >= 4 else values[:3] + [1.0]
    return [float(value)] * 3 + [1.0]


class MaterialPlan:
    def __init__(self, material):
        self.material = material
        self.name = material.name if material else '__default__'
        self.textures = []
        self.warnings = []
        self.baked = False
        self.alpha_linked = False
        self.double_sided = not bool(material and material.use_backface_culling)
        self.color = ('constant', rgba(material.diffuse_color if material else (0.55, 0.52, 0.45, 1)))
        self.alpha = ('constant', [1, 1, 1, 1])
        self.image_node = None
        self.has_normal_map = False
        self.emission_folded = False
        self.source_emission_strength = 0.0
        self.alpha_image_equivalence = None
        color_nodes = []
        alpha_nodes = []
        if material and material.use_nodes:
            nodes = material.node_tree.nodes
            self.baked = any(node.type == 'EMISSION' for node in nodes) or 'Baked' in self.name
            self.has_normal_map = any(node.type == 'NORMAL_MAP' for node in nodes)
            output = next((node for node in nodes if node.type == 'OUTPUT_MATERIAL' and node.is_active_output), None)
            shader = output.inputs['Surface'].links[0].from_node if output and output.inputs['Surface'].is_linked else None
            if shader and shader.type == 'BSDF_PRINCIPLED':
                self.color = self.expression(shader.inputs['Base Color'])
                emission = shader.inputs.get('Emission Color')
                strength = shader.inputs.get('Emission Strength')
                self.source_emission_strength = float(strength.default_value) if strength and not strength.is_linked else 0.0
                base_white_probe = self.evaluate(self.color, 1, lambda name: np.ones((1, 4), dtype=np.float32))
                if emission and self.source_emission_strength > 0 and float(base_white_probe[0, :3].max()) < 1e-7:
                    # Active P4/P8 windows and signs use black Base Color plus emission.
                    # Export their visible emission into the unlit base path, retaining alpha.
                    self.textures.clear()
                    self.color = ('emission', self.source_emission_strength, self.expression(emission))
                    self.emission_folded = True
                    self.baked = True
                color_nodes = list(self.textures)
                self.textures.clear()
                self.alpha = self.expression(shader.inputs['Alpha'])
                alpha_nodes = list(self.textures)
                self.textures = color_nodes + alpha_nodes
                self.alpha_linked = shader.inputs['Alpha'].is_linked or shader.inputs['Alpha'].default_value < 0.999
            else:
                emission = next((node for node in nodes if node.type == 'EMISSION'), None)
                if emission:
                    self.color = self.expression(emission.inputs['Color'])
                else:
                    self.warnings.append('No supported surface shader; diffuse fallback')
        distinct = {}
        for node in self.textures:
            if node.image:
                key = hashlib.sha256(bytes(node.image.packed_file.data)).hexdigest() if node.image.packed_file else str(node.image.as_pointer())
                distinct.setdefault(key, node)
        if len(distinct) > 1:
            if self.emission_folded and len(color_nodes) == 1 and len(alpha_nodes) == 1:
                self.alpha_image_equivalence = equivalent_alpha(color_nodes[0], alpha_nodes[0])
                distinct = {'audited-emission-alpha': color_nodes[0]}
            else:
                raise RuntimeError('Multiple base-colour images need an explicit bake: ' + self.name)
        if distinct:
            self.image_node = next(iter(distinct.values()))

    def expression(self, socket, depth=0):
        if depth > 16:
            raise RuntimeError('Material graph cycle: ' + self.name)
        if not socket.is_linked:
            return ('constant', rgba(socket.default_value))
        link = socket.links[0]
        node = link.from_node
        if node.type == 'TEX_IMAGE':
            if node not in self.textures:
                self.textures.append(node)
            return ('texture', link.from_socket.name)
        if node.type in ['VERTEX_COLOR', 'ATTRIBUTE']:
            name = getattr(node, 'layer_name', getattr(node, 'attribute_name', ''))
            return ('attribute', name, link.from_socket.name)
        if node.type in ['RGB', 'VALUE']:
            return ('constant', rgba(link.from_socket.default_value))
        if node.type in ['MIX', 'MIX_RGB']:
            if node.type == 'MIX':
                factor, a, b = node.inputs[0], node.inputs[6], node.inputs[7]
            else:
                factor, a, b = node.inputs[0], node.inputs[1], node.inputs[2]
            return ('mix', node.blend_type, self.expression(factor, depth + 1),
                    self.expression(a, depth + 1), self.expression(b, depth + 1))
        if node.type == 'REROUTE':
            return self.expression(node.inputs[0], depth + 1)
        raise RuntimeError('Unsupported base-colour node: ' + self.name + '/' + node.type)

    def evaluate(self, expression, count, attributes):
        kind = expression[0]
        if kind == 'constant':
            return np.broadcast_to(np.asarray(expression[1], dtype=np.float32), (count, 4)).copy()
        if kind == 'texture':
            return np.ones((count, 4), dtype=np.float32)
        if kind == 'emission':
            result = self.evaluate(expression[2], count, attributes)
            result[:, :3] *= expression[1]
            return result
        if kind == 'attribute':
            values = attributes(expression[1])
            if expression[2] == 'Alpha':
                values = np.repeat(values[:, 3:4], 4, axis=1)
            return values
        if kind == 'mix':
            _, blend, factor, a, b = expression
            f = self.evaluate(factor, count, attributes)[:, :1]
            av = self.evaluate(a, count, attributes)
            bv = self.evaluate(b, count, attributes)
            if blend == 'MULTIPLY':
                return av * (1 - f + f * bv)
            if blend == 'MIX':
                # Used with constant factors in the source. Texture-bearing fractional
                # mixes are surfaced in the report because glTF has one base texture.
                if self.image_node and np.any((f > 1e-6) & (f < 1 - 1e-6)):
                    self.warnings.append('Fractional texture MIX represented by vertex modulation')
                return av * (1 - f) + bv * f
            if blend == 'ADD':
                return av + f * bv
            if blend == 'SUBTRACT':
                return av - f * bv
            if blend == 'SCREEN':
                return av * (1 - f) + (1 - (1 - av) * (1 - bv)) * f
            raise RuntimeError('Unsupported colour blend: ' + self.name + '/' + blend)
        raise RuntimeError('Invalid material expression')

    def uv(self, mesh, loops):
        def source_uv(name=''):
            layer = mesh.uv_layers.get(name) if name else mesh.uv_layers.active
            if layer is None:
                if self.image_node:
                    raise RuntimeError('Textured mesh lacks UV layer: ' + self.name + '/' + name)
                return np.zeros((len(loops), 3), dtype=np.float32)
            values = np.empty(len(mesh.loops) * 2, dtype=np.float32)
            layer.data.foreach_get('uv', values)
            result = np.zeros((len(loops), 3), dtype=np.float32)
            result[:, :2] = values.reshape(-1, 2)[loops]
            return result

        def vector(socket):
            if not socket.is_linked:
                return source_uv()
            node = socket.links[0].from_node
            if node.type == 'UVMAP':
                return source_uv(node.uv_map)
            if node.type == 'TEX_COORD':
                if socket.links[0].from_socket.name != 'UV':
                    raise RuntimeError('Generated texture coordinates require bake: ' + self.name)
                return source_uv()
            if node.type == 'MAPPING':
                values = vector(node.inputs['Vector'])
                scale = np.asarray(node.inputs['Scale'].default_value, dtype=np.float32)
                rotation = np.asarray(Euler(node.inputs['Rotation'].default_value).to_matrix(), dtype=np.float32)
                location = np.asarray(node.inputs['Location'].default_value, dtype=np.float32)
                if node.vector_type != 'POINT':
                    raise RuntimeError('Unsupported texture mapping mode: ' + self.name + '/' + node.vector_type)
                return (values * scale) @ rotation.T + location
            raise RuntimeError('Unsupported UV node: ' + self.name + '/' + node.type)

        if not self.image_node:
            return None
        values = vector(self.image_node.inputs['Vector'])[:, :2]
        # Blender UV v increases upwards; glTF raster sampling starts at the top.
        values[:, 1] = 1 - values[:, 1]
        return values
