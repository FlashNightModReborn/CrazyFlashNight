"""Read-only native XFL first-keyframe renderer for the CF7 tyrant reference.
Adaptation of the already-reviewed local xfl-ui-svg converter. No donor SVG input.
Only writes into render/. Python stdlib + existing Inkscape.
"""
from pathlib import Path
from collections import defaultdict
import argparse, copy, hashlib, json, subprocess, xml.etree.ElementTree as ET
import xfl_to_svg_base as base

NS=base.NS
# Preserve native matrix precision instead of the UI exporter's 4 decimal rounding.
base.f=lambda v: format(float(v), '.15g') if float(v) else '0'

def split_chains(segs):
    out=[]
    for s in segs:
        if not out or out[-1][-1][-1] != s[0]: out.append([s])
        else: out[-1].append(s)
    return out

def joined_paths(segs):
    """Join directed edges per fill. Never fabricate straight closing gaps."""
    chains=split_chains(segs)
    closed=[]; graph=defaultdict(list)
    for chain in chains:
        if chain[0][0] == chain[-1][-1]: closed.append(chain)
        else: graph[chain[0][0]].append(chain)
    def walk(curr, origin, visited):
        for i,ch in enumerate(graph[curr]):
            nxt=ch[-1][-1]
            if nxt==origin:
                graph[curr].pop(i); return ch
            if nxt not in visited:
                result=walk(nxt, origin, visited|{nxt})
                if result is not None:
                    graph[curr].pop(i); return ch+result
        return None
    for origin in list(graph):
        while graph[origin]:
            ch=graph[origin].pop()
            result=walk(ch[-1][-1],origin,{origin,ch[-1][-1]})
            if result is None:
                raise ValueError('Open fill contour at '+str(origin)+' ending '+str(ch[-1][-1]))
            closed.append(ch+result)
    return ''.join(base.segments_to_d(ch)+'Z' for ch in closed)

class NativeRenderer(base.Renderer):
    def __init__(self, library):
        super().__init__(library, [])
        self.removed=[]; self.layer_records=[]; self.only_character_root=None
    def load(self,name):
        # Fail closed on missing dependencies, unlike the UI tool's placeholder policy.
        if not (self.library/(name+'.xml')).exists(): raise FileNotFoundError(name)
        return super().load(name)
    def frame_elements(self,root,frame,where):
        for li,layer,els in super().frame_elements(root,frame,where):
            name=layer.get('name','')
            if where==self.only_character_root and name!='人物层':
                if els is not None and len(els): self.removed.append({'where':where,'layer':name,'reason':'root character-only extraction'})
                continue
            if name.lower() in ('area','hud','shadow') or name in ('影子','阴影','血条','血量条','碰撞区域'):
                self.removed.append({'where':where,'layer':name,'reason':'non-character layer'})
                continue
            self.layer_records.append({'where':where,'layerIndex':li,'layer':name,'layerType':layer.get('layerType'),'frame':frame})
            yield li,layer,els
    def element_to_svg(self,el,where,ct=base.CT_IDENTITY):
        ln=el.get('libraryItemName',''); name=el.get('name','')
        if name.lower() in ('area','hud','shadow') or ln.rsplit('/',1)[-1] in ('影子','阴影','血条','血量条','area'):
            self.removed.append({'where':where,'symbol':ln,'instance':name,'reason':'non-character instance'})
            return ''
        return super().element_to_svg(el,where,ct)
    def _mask_index_of(self,layers,li):
        seen=set()
        while True:
            try: pi=int(layers[li].get('parentLayerIndex'))
            except (TypeError, ValueError): return None
            if pi in seen or pi<0 or pi>=len(layers): return None
            seen.add(pi)
            if layers[pi].get('layerType')=='mask': return pi
            li=pi
    def filters_to_attr(self,filt,where):
        if filt is None: return ''
        filt=copy.deepcopy(filt)
        for child in list(filt):
            if child.tag.rsplit('}',1)[-1]=='AdjustColorFilter' and all(float(v)==0 for k,v in child.attrib.items() if k in ('brightness','contrast','saturation','hue')) and not any(k not in ('brightness','contrast','saturation','hue') for k in child.attrib):
                self.warnings.add(where+': identity AdjustColorFilter (all adjustments zero); omitted without color change')
                filt.remove(child)
        return super().filters_to_attr(filt,where)
    def gradient_def(self, spec):
        """Use unit gradient coordinates with the identical native affine map.

        Inkscape 1.4 can drop parts of otherwise opaque gradient-filled paths
        when the Flash +/-819.2 gradient domain is combined with very small
        affine coefficients. Reparameterize q = 819.2*u: M(q) = M*S(u).
        Only the linear matrix coefficients change; source stops, translations,
        and the gradient field are unchanged. This is not a geometry repair.
        """
        fmt = base.f
        body = ''.join(
            '<stop offset="%s" stop-color="%s"%s/>' % (
                fmt(g['ratio']), g['color'],
                '' if g['alpha'] >= 1 else ' stop-opacity="%.4f"' % g['alpha'])
            for g in spec['entries'])
        spread = {'extend': 'pad', 'reflect': 'reflect', 'repeat': 'repeat'}.get(spec['spread'])
        sm = ' spreadMethod="%s"' % spread if spread else ''
        normalized = tuple(v * base.GRADIENT_HALF if i < 4 else v
                           for i, v in enumerate(spec['matrix']))
        tr = ' gradientTransform="%s"' % base.fmt_matrix(normalized)
        if spec['kind'] == 'linear':
            inner = ('<linearGradient gradientUnits="userSpaceOnUse" '
                     'x1="-1" y1="0" x2="1" y2="0"%s%s>%s</linearGradient>'
                     % (tr, sm, body))
        else:
            foc = ' fx="%s"' % fmt(spec['focal']) if spec['focal'] else ''
            inner = ('<radialGradient gradientUnits="userSpaceOnUse" '
                     'cx="0" cy="0" r="1"%s%s%s>%s</radialGradient>'
                     % (foc, tr, sm, body))
        key = ('gradient', inner)
        if key in self._def_dedup:
            return self._def_dedup[key]
        self._def_id += 1
        gid = 'g%d' % self._def_id
        self._def_dedup[key] = gid
        self.defs.append(inner.replace('<linearGradient', '<linearGradient id="%s"' % gid, 1)
                         .replace('<radialGradient', '<radialGradient id="%s"' % gid, 1))
        return gid

    def fill_buckets(self,shape):
        fills=defaultdict(list); strokes=defaultdict(list)
        for e in shape.findall('./x:edges/x:Edge',NS):
            if not e.get('edges'):
                continue
            segs=base.edge_segments(e.get('edges'))
            f0,f1,st=(e.get(k,'0') for k in ('fillStyle0','fillStyle1','strokeStyle'))
            if f1 != '0' and f1 != f0: fills[f1].extend(segs)
            if f0 != '0' and f1 != f0: fills[f0].extend(base.reverse_segments(segs))
            if st != '0': strokes[st].extend(segs)
        return fills,strokes
    def shape_to_d(self,shape,where,m=base.IDENTITY):
        fills,_=self.fill_buckets(shape)
        parts=[]
        for segs in fills.values():
            if m != base.IDENTITY: segs=[tuple(base.transform_point(m,p) for p in s) for s in segs]
            parts.append(joined_paths(segs))
        return ''.join(parts)
    def shape_to_svg(self,shape,tr,where,ct=base.CT_IDENTITY):
        fills={fs.get('index'):base.parse_fill_style(fs) for fs in shape.findall('./x:fills/x:FillStyle',NS)}
        strokes={ss.get('index'):base.parse_stroke_style(ss) for ss in shape.findall('./x:strokes/x:StrokeStyle',NS)}
        fb,sb=self.fill_buckets(shape); out=[]
        for idx,segs in fb.items():
            paint,extra=self.paint_attr(fills[idx],where,ct=ct)
            if paint: out.append('<path d="%s" %s%s/>'%(joined_paths(segs),paint,extra))
        for idx,segs in sb.items():
            spec=strokes.get(idx)
            if spec is None: continue
            paint,extra=self.paint_attr(spec['fill'],where,stroke=True,stroke_spec=spec,ct=ct)
            d=''.join(base.segments_to_d(ch)+('Z' if ch[0][0]==ch[-1][-1] else '') for ch in split_chains(segs))
            if paint: out.append('<path d="%s" fill="none" %s%s/>'%(d,paint,extra))
        return '<g%s fill-rule="nonzero">%s</g>'%(tr,''.join(out)) if out else ''

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser();p.add_argument('--library',type=Path,required=True);p.add_argument('--symbol',required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--name',default='tyrant-native-idle');p.add_argument('--frame',type=int,default=0);p.add_argument('--width',type=int,default=1600);p.add_argument('--root-character-only',action='store_true')
    a=p.parse_args();a.out.mkdir(exist_ok=True,parents=True)
    r=NativeRenderer(a.library)
    if a.root_character_only: r.only_character_root=a.symbol
    body=r.render_symbol(a.symbol,a.frame,a.symbol)
    if r.unsupported: raise ValueError(json.dumps(r.unsupported,ensure_ascii=False))
    svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="-1000 -1000 2000 2000" width="2000" height="2000"><metadata>Native XFL local registration (0,0); no donor SVG; static first keyframe; Flash raster equivalence unverified.</metadata><defs>'+''.join(r.defs)+'</defs><g id="character">'+body+'</g></svg>'
    sp=a.out/(a.name+'.svg');sp.write_text(svg)
    query=subprocess.run(['inkscape',str(sp),'--query-id=character','--query-x','--query-y','--query-width','--query-height'],capture_output=True,text=True,check=True)
    vals=[float(x) for x in query.stdout.strip().splitlines()]
    # query values are document coordinates including viewBox origin normalization.
    x,y,w,h=vals;x-=1000;y-=1000
    margin=2.0;view=(x-margin,y-margin,w+2*margin,h+2*margin)
    svg=svg.replace('viewBox="-1000 -1000 2000 2000" width="2000" height="2000"','viewBox="%s" width="%s" height="%s"'%(' '.join(base.f(v) for v in view),base.f(view[2]),base.f(view[3])))
    sp.write_text(svg)
    png=a.out/(a.name+'.png');subprocess.run(['inkscape',str(sp),'--export-type=png','--export-filename='+str(png),'--export-width='+str(a.width),'--export-background-opacity=0'],capture_output=True,text=True,check=True)
    manifest={'sourceCommit':'951145190cd45646abdfd4ebde1fbe68a4dd38ff','sourceSymbol':a.symbol,'frameIndex':a.frame,'registration':[0,0],'viewBox':view,'inkscapeQueryOriginal':vals,'sources':[{'path':str(s.relative_to(r.library)), 'sha256':sha(s)} for s in sorted(r.sources)],'outputs':{sp.name:sha(sp),png.name:sha(png)},'tools':{Path(__file__).name:sha(Path(__file__)),Path(base.__file__).name:sha(Path(base.__file__))},'removed':list({json.dumps(x,sort_keys=True,ensure_ascii=False):x for x in r.removed}.values()),'unsupported':r.unsupported,'warnings':sorted(r.warnings),'selectedLayers':list({json.dumps(x,sort_keys=True,ensure_ascii=False):x for x in r.layer_records}.values()),'fidelity':'Native vector geometry, layers, masks, matrices, colors. No Flash Player execution, no ActionScript/tween interpolation, antialiasing may differ.'}
    (a.out/(a.name+'.json')).write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
    print(json.dumps({'svg':str(sp),'png':str(png),'viewBox':view,'sourceCount':len(r.sources),'removed':r.removed,'warnings':sorted(r.warnings)},ensure_ascii=False))

if __name__=='__main__': main()
