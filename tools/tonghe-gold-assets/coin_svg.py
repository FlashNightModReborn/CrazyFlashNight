"""Project the actual R3 B coin mesh into compact, editable R4-style SVG.

Body rings come from the supplied .blend. Hidden/back-facing mesh faces are
removed, adjacent faces in each lathe band are merged into paths, and original
logo Bezier paths are affinely projected. No rendered image is embedded/traced.
"""
import argparse
import hashlib
import html
import json
import math
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
NATIVE = 28.0

def rotate(p, angle):
    c, s = math.cos(angle), math.sin(angle)
    return (p[0]*c-p[1]*s, p[0]*s+p[1]*c, p[2])

def fmt(n):
    return f'{n:.4f}'.rstrip('0').rstrip('.') if abs(n) > 0.00005 else '0'

def hex_color(rgb):
    return '#'+''.join(f'{max(0,min(255,round(v))):02x}' for v in rgb)

def blend(a,b,t):
    return [a[i]*(1-t)+b[i]*t for i in range(3)]

def color(s):
    return [int(s[i:i+2],16) for i in (1,3,5)]

def hull(points):
    p = sorted(set((round(x,6),round(y,6)) for x,y in points))
    def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    low=[]
    for v in p:
        while len(low)>1 and cross(low[-2],low[-1],v)<=0:low.pop()
        low.append(v)
    high=[]
    for v in reversed(p):
        while len(high)>1 and cross(high[-2],high[-1],v)<=0:high.pop()
        high.append(v)
    return low[:-1]+high[:-1]

def path_d(points):
    points=simplify_closed(points,.008)
    return 'M'+'L'.join(fmt(x)+','+fmt(y) for x,y in points)+'Z'

def simplify_line(points, tolerance):
    if len(points)<=2:return points
    a,b=points[0],points[-1]
    dx,dy=b[0]-a[0],b[1]-a[1]
    denom=dx*dx+dy*dy
    best,index=0,0
    for i,p in enumerate(points[1:-1],1):
        t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/denom)) if denom else 0
        distance=math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
        if distance>best:best,index=distance,i
    if best<=tolerance:return [a,b]
    return simplify_line(points[:index+1],tolerance)[:-1]+simplify_line(points[index:],tolerance)

def simplify_closed(points,tolerance):
    if len(points)<8:return points
    half=len(points)//2
    return simplify_line(points[:half+1],tolerance)[:-1]+simplify_line(points[half:]+points[:1],tolerance)[:-1]

def boundary_loops(faces):
    edge_map={}
    for face in faces:
        ids=face['vertices']
        for a,b in zip(ids,ids[1:]+ids[:1]):
            key=tuple(sorted((a,b)))
            if key in edge_map:del edge_map[key]
            else:edge_map[key]=(a,b)
    links=defaultdict(list)
    for a,b in edge_map.values():links[a].append(b)
    loops=[]
    while links:
        start=next(iter(links));cur=start;loop=[]
        while True:
            loop.append(cur)
            if cur not in links:raise ValueError('Open mesh patch boundary')
            nxt=links[cur].pop()
            if not links[cur]:del links[cur]
            cur=nxt
            if cur==start:break
        loops.append(loop)
    return loops

class Coin:
    def __init__(self, model, logo, style):
        self.model=json.loads(Path(model).read_text(encoding='utf-8'))
        self.style=json.loads(Path(style).read_text(encoding='utf-8'))
        self.logo_source=Path(logo).read_bytes()
        self.logo=ET.fromstring(self.logo_source)
        contract=self.model['original_mark_contract']
        if hashlib.sha256(self.logo_source).hexdigest()!=contract['svg_sha256']:
            raise ValueError('Original mark differs from the model contract; re-extract/review the mark mapping first')
        self.mark_bounds=contract['path_bounds']
        self.verts=self.model['body']['vertices']
        self.local=self.model['body']['local_vertices']
        self.faces=self.model['body']['faces']
        self.camera=self.model['camera']['inverse_world_matrix']
        self.scale=NATIVE/self.model['camera']['ortho_scale']
        # The original lathe rings have a constant local Z and preserve vertex
        # ordering. Derive their membership from mesh data, not hard-coded radii.
        rings={}
        self.ring_id=[]
        for p in self.local:
            key=round(p[2],6)
            # Coplanar profile rings may share z: distinguish their radius too.
            radius=round(math.hypot(p[0],p[1]),3)
            if abs(radius-1)<.01:radius=1.0  # sidewall reeds belong to one ring
            key=(key,radius)
            if key not in rings:rings[key]=len(rings)
            self.ring_id.append(rings[key])
        self.groups=defaultdict(list)
        for f in self.faces:
            key=tuple(sorted(set(self.ring_id[i] for i in f['vertices'])))
            self.groups[key].append(f)
        self.profile=[]
        for rid in range(len(rings)):
            ids=[i for i,r in enumerate(self.ring_id) if r==rid]
            self.profile.append({'ring':rid,'radius':max(math.hypot(*self.local[i][:2]) for i in ids),'depth_local':sum(self.local[i][2] for i in ids)/len(ids)})

    def project(self,p):
        q=[sum(self.camera[j][k]*p[k] for k in range(3))+self.camera[j][3] for j in range(3)]
        return (14+q[0]*self.scale,14-q[1]*self.scale,q[2])

    def shade(self, material, angle, role):
        # Global continuous appearance rule fitted to the R4 screen palette.
        # Both original faces carry the same mark, so the style repeats at 180°.
        t=.5+.5*math.sin(2*angle)
        pal=self.style['palette']
        base=blend(color(pal[role+'_shadow']),color(pal[role+'_light']),t)
        return hex_color(blend(base,color(pal['highlight']),.19)),hex_color(base),hex_color(blend(base,color(pal['shade']),.10))

    def side_texture(self, visible, proj, angle, prefix, band_name):
        """Recover the modeled reed facets lost by merging the sidewall band.

        Compare each actual radial facet normal with its smooth-cylinder normal.
        This gives a deterministic highlight/shadow pattern bound to the mesh,
        including groove taper. The same paths are used at every display size.
        """
        if abs(math.sin(angle))<1e-6:
            return '',0
        buckets=defaultdict(list)
        view_strength=abs(math.sin(angle))
        for face in visible:
            vs=[self.local[i] for i in face['vertices']]
            x=sum(p[0] for p in vs)/len(vs)
            y=sum(p[1] for p in vs)/len(vs)
            radius=math.hypot(x,y)
            normal=face['normal']
            radial=math.hypot(normal[0],normal[2])
            if radial<1e-6:continue
            actual=rotate((normal[0]/radial,0,normal[2]/radial),angle)
            smooth=rotate((x/radius,0,y/radius),angle)
            # Fixed studio direction: chiefly above, slightly toward the camera.
            delta=(actual[2]-smooth[2])*3.4-(actual[1]-smooth[1])*.8
            groove=sum(max(0,1-math.hypot(p[0],p[1])) for p in vs)/len(vs)
            groove/=self.model['parameters']['edge_depth']
            value=max(-1,min(1,delta-groove*.13))
            bucket=max(-4,min(4,round(value*4)))
            if bucket:buckets[bucket].append(face)
        markup=[]
        for bucket,faces in sorted(buckets.items()):
            loops=boundary_loops(faces)
            d=''.join(path_d([(proj[i][0],proj[i][1]) for i in loop]) for loop in loops)
            ink=self.style['palette']['highlight' if bucket>0 else 'cut_shadow']
            opacity=abs(bucket)/4*self.style['side_reed_contrast']*view_strength
            markup.append(f'<path d="{d}" fill="{ink}" fill-opacity="{fmt(opacity)}" fill-rule="evenodd"/>')
        if not markup:return '',0
        return '<g id="'+prefix+'-'+band_name+'-reeds" data-model-reed-count="'+str(self.model['parameters']['edge_reeds'])+'">'+''.join(markup)+'</g>',sum(len(faces) for faces in buckets.values())

    def svg(self,degrees,size=28,prefix='coin',logo_contrast=None):
        degrees=degrees%360
        angle=math.radians(degrees)
        world=[rotate(p,angle) for p in self.verts]
        proj=[self.project(p) for p in world]
        outline=hull([(p[0],p[1]) for p in proj])
        outline_d=path_d(outline)
        defs=[f'<clipPath id="{prefix}-silhouette"><path d="{outline_d}"/></clipPath>']
        patches=[]
        reed_facets=0
        for key,faces in self.groups.items():
            visible=[]
            for f in faces:
                normal=rotate(f['normal'],angle)
                dot=sum(self.camera[2][i]*normal[i] for i in range(3))
                if dot>1e-6:visible.append(f)
            if not visible:continue
            loops=boundary_loops(visible)
            d=''.join(path_d([(proj[i][0],proj[i][1]) for i in loop]) for loop in loops)
            used=set(i for f in visible for i in f['vertices'])
            depth=sum(proj[i][2] for i in used)/len(used)
            mat=visible[0]['material']
            role=['field','rim','cut','side'][mat]
            name='band-'+'-'.join(str(i) for i in key)
            grad=f'{prefix}-{name}'
            a,b,c=self.shade(mat,angle,role)
            defs.append(f'<linearGradient id="{grad}" gradientUnits="userSpaceOnUse" x1="4" y1="2" x2="23" y2="27"><stop offset="0" stop-color="{a}"/><stop offset=".48" stop-color="{b}"/><stop offset="1" stop-color="{c}"/></linearGradient>')
            markup=f'<path id="{prefix}-{name}-shape" data-material="{role}" d="{d}" fill="url(#{grad})" fill-rule="evenodd" stroke="url(#{grad})" stroke-width=".035" stroke-linejoin="round"/>'
            if role=='side':
                texture,facets=self.side_texture(visible,proj,angle,prefix,name)
                markup+=texture
                reed_facets+=facets
            patches.append((depth,markup,role,key))
        mark_count=0
        # The original 132.75 x 227.85 path bounds correspond to the actual
        # mesh mark. Use its measured world bounds for scale and translation.
        cosine=math.cos(angle)
        if abs(cosine)>1e-6:
            reverse=cosine<0
            mark=self.model['marks'][1 if reverse else 0]
            lo,hi=mark['min_world'],mark['max_world']
            x0,y0,x1,y1=self.mark_bounds
            mid_x,mid_y=(x0+x1)/2,(y0+y1)/2
            sx=(hi[0]-lo[0])/(x1-x0)
            sz=(hi[2]-lo[2])/(y1-y0)
            # Preserve the original front/back orientation from the .blend.
            sign=-1 if reverse else 1
            depth=hi[1] if reverse else lo[1]
            p0=self.project(rotate((sign*(-mid_x)*sx,depth,mid_y*sz),angle))
            px=self.project(rotate((sign*(1-mid_x)*sx,depth,mid_y*sz),angle))
            py=self.project(rotate((sign*(-mid_x)*sx,depth,(mid_y-1)*sz),angle))
            matrix=[px[0]-p0[0],px[1]-p0[1],py[0]-p0[0],py[1]-p0[1],p0[0],p0[1]]
            shade_t=.5+.5*math.sin(2*angle)
            pal=self.style['palette']
            ink=hex_color(blend(color(pal['mark_shadow']),color(pal['mark_light']),shade_t))
            if logo_contrast is not None:
                ink=hex_color(blend(color(ink),color(pal['outline']),logo_contrast))
            paths=[]
            for el in self.logo.iter():
                if el.tag.rsplit('}',1)[-1]!='path':continue
                attrs={k:v for k,v in el.attrib.items() if k in ['d','fill','stroke','stroke-width','stroke-linecap','stroke-linejoin','fill-rule']}
                for a in ['fill','stroke']:
                    if attrs.get(a) not in [None,'none']:attrs[a]=ink
                paths.append('<path '+' '.join(k+'="'+html.escape(v,quote=True)+'"' for k,v in attrs.items())+'/>')
            mtx=' '.join(fmt(v) for v in matrix)
            markup=f'<g id="{prefix}-original-mark" data-source-sha256="{hashlib.sha256(self.logo_source).hexdigest()}" transform="matrix({mtx})" fill-rule="nonzero">'+''.join(paths)+'</g>'
            centroid=self.project(rotate((0,depth,0),angle))[2]
            patches.append((centroid,markup,'mark',()))
            mark_count=len(paths)
        patches.sort(key=lambda p:p[0])
        # Stroke is clipped to the mesh silhouette, giving an inside outline
        # without changing the original 28px canvas or alpha geometry.
        # Force isolated group compositing so repeated patch/outline coverage
        # does not accumulate antialias alpha along the clip edge at 28px.
        # .9999 still rounds opaque interior pixels to alpha 255 in 8-bit PNG.
        body='<g opacity=".9999" clip-path="url(#'+prefix+'-silhouette)"><path d="'+outline_d+'" fill="'+self.style['palette']['side_shadow']+'"/>'+''.join(p[1] for p in patches)
        body+=f'<path d="{outline_d}" fill="none" stroke="{self.style["palette"]["outline"]}" stroke-width="{fmt(2*self.style["outline_native_px"])}" stroke-linejoin="round"/></g>'
        title=f'Tonghe gold coin, {degrees:g} degrees'
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 28 28" role="img" aria-labelledby="{prefix}-title"><title id="{prefix}-title">{title}</title><desc>Actual Blender mesh projection; R4 palette; original unredrawn SVG mark. No embedded images.</desc><defs>'+''.join(defs)+'</defs>'+body+'</svg>\n'
        info={'angle_degrees':degrees,'body_patches':len(patches)-(1 if mark_count else 0),'original_mark_paths':mark_count,
              'shared_across_display_sizes':True,
              'side_reed_count':self.model['parameters']['edge_reeds'],
              'textured_visible_side_facets':reed_facets,
              'body_boundary_vertices':len(outline),'svg_bytes':len(svg.encode()),'canvas':[28,28],
              'projected_bbox':[min(p[0] for p in outline),min(p[1] for p in outline),max(p[0] for p in outline),max(p[1] for p in outline)]}
        return svg,info

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--model',default=str(HERE/'model.json'))
    ap.add_argument('--logo',default=str(HERE/'original_node.svg'))
    ap.add_argument('--style',default=str(HERE/'style.json'))
    ap.add_argument('--out',required=True)
    ap.add_argument('--angles',default='0,45,90,135,180')
    ap.add_argument('--size',type=int,default=28)
    ap.add_argument('--logo-contrast',type=float)
    ap.add_argument('--animation',action='store_true')
    args=ap.parse_args()
    asset=Coin(args.model,args.logo,args.style)
    out=Path(args.out);out.mkdir(parents=True,exist_ok=True)
    result=[]
    angles=[i*11.25 for i in range(32)] if args.animation else [float(a) for a in args.angles.split(',')]
    for i,angle in enumerate(angles):
        svg,info=asset.svg(angle,args.size,logo_contrast=args.logo_contrast)
        filename=f'frame_{i:02d}.svg' if args.animation else f'gold_{angle:07.3f}'.replace('.','_')+'.svg'
        (out/filename).write_text(svg,encoding='utf-8')
        info['file']=filename;result.append(info)
    (out/'generation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()
