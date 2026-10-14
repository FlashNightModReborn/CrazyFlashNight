"""Authored native corrections for claw sockets, gum roots and neck bone plates.

The R3 handoff stays immutable. Corrections are native shapes in the owned XFL;
this recipe makes an explicitly requested re-import reproduce the same artwork.
"""

PATCHED = (267, 268, 269, 271, 272, 273, 274)


def drawings(ident, full_power):
    skin, shade, light = ('#844a49', '#663333', '#8b4e4c') if full_power else ('#4c4242', '#3b3333', '#625050')
    ink = '#191616'
    if ident == 267:
        return f'''<path fill="{skin}" d="M22 34 L27 27 L35 21 L43 15 L49 10 L57 9 L60 16 L51 24 L42 28 L31 35 Z"/>
          <path fill="{shade}" d="M25 31 L32 25 L40 20 L48 15 L55 13 L57 18 L47 25 L36 31 L28 36 Z"/>
          <path fill="none" stroke="{ink}" stroke-width=".8" d="M22 34 L27 27 L35 21 L43 15 L49 10 L57 9"/>'''
    if ident == 268:
        return '''<path fill="#7d1616" d="M43 33 Q48 30 52 34 L53 40 Q48 42 44 40 Z"/>
          <path fill="none" stroke="#271518" stroke-width=".7" d="M48 40 Q51 41 53 40"/>'''
    if ident == 269:
        return f'''<path fill="{shade}" d="M84 69 Q89 68 93 72 L94 76 L88 77 L85 73 Z"/>
          <path fill="none" stroke="{ink}" stroke-width=".7" d="M85 73 L88 77 L94 76"/>'''
    if ident == 272:
        return f'''<path fill="{skin}" d="M12 37 Q21 39 30 38 Q41 37 49 38 L52 43 L51 47 L44 48 L36 47 L25 46 L13 46 Z"/>
          <path fill="{light}" d="M15 39 Q23 40 30 40 L43 39 L48 41 L46 43 L35 42 L25 43 L15 42 Z"/>
          <path fill="none" stroke="{ink}" stroke-width=".85" d="M12 39 L12 46 M25 41 L25 45 M36 41 L36 46 M46 41 L46 46 M51 41 L52 46"/>'''
    if ident == 273:
        return f'''<path fill="{skin}" d="M21 36 L30 32 L39 25 L49 19 L55 19 L57 23 L51 29 L43 35 L34 42 L26 46 L21 45 Z"/>
          <path fill="{light}" d="M25 36 L34 31 L43 25 L51 21 L53 23 L42 31 L32 38 L25 41 Z"/>
          <path fill="none" stroke="{ink}" stroke-width=".8" d="M21 39 L21 45 M32 33 L34 38 M41 27 L44 31 M50 21 L53 24"/>'''
    if ident == 274:
        return f'''<path fill="{skin}" d="M29 53 Q38 48 45 47 Q55 43 64 43 Q71 43 73 48 L75 55 L65 61 L56 66 L44 71 L31 68 Q32 61 29 57 Z"/>
          <path fill="{shade}" d="M31 58 Q38 55 43 56 L46 63 L39 68 L31 66 Z M49 52 Q55 49 61 50 L63 57 L55 61 L49 59 Z M64 46 Q69 45 72 48 L73 53 L66 56 L63 53 Z"/>
          <path fill="{light}" d="M33 54 Q40 51 44 52 L44 56 Q38 54 34 58 Z M50 48 Q56 46 61 47 L61 50 Q55 49 51 53 Z M64 45 L69 45 L71 48 L65 49 Z"/>
          <path fill="none" stroke="{ink}" stroke-width=".9" d="M30 56 Q33 61 31 68 M44 52 Q48 57 47 63 M60 47 Q64 51 62 58 M70 45 Q74 49 74 54"/>'''
    return ''


def apply(api, symbols, live, origins, full_power):
    ns = api['NS']
    report = []
    def keep_body(edges):
        candidates = list(edges)
        if len(candidates) < 2:
            return 0
        def area(edge):
            x0, y0, x1, y1 = api['geo'].bounds(list(api['geo'].segments(edge.get('edges'))))
            return (x1-x0)*(y1-y0)
        body = max(candidates, key=area)
        for edge in candidates:
            if edge is not body:
                edges.remove(edge)
        return len(candidates)-1
    for ident in PATCHED:
        name = live[ident]
        root = symbols[name]
        elements = root.find('x:timeline/x:DOMTimeline/x:layers/x:DOMLayer/x:frames/x:DOMFrame/x:elements', ns)
        shapes = elements.findall('x:DOMShape', ns)
        # First fill and first outline are traced skin. All following shapes are
        # the separately authored bone paths and must retain every contour.
        removed = 0
        for shape in shapes[:2]:
            edges = shape.find('x:edges', ns)
            removed += keep_body(edges)
        for helper_name, helper in symbols.items():
            if not helper_name.startswith(name + '-遮罩'):
                continue
            for mask in helper.findall('.//x:DOMLayer[@layerType="mask"]//x:DOMShape/x:edges', ns):
                removed += keep_body(mask)
        content = drawings(ident, full_power)
        additions = api['death'].shapes(api, content, origins[ident]) if content else []
        at = list(elements).index(shapes[2]) if len(shapes) > 2 else len(elements)
        for offset, shape in enumerate(additions):
            shape.set('isDrawingObject', 'true')
            elements.insert(at + offset, shape)
        report.append({'partId': ident, 'nativeShapesAdded': len(additions), 'tracedIslandContoursRemoved': removed})
    return report
