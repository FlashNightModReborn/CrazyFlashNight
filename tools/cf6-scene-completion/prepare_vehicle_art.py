"""Prepare existing vehicle SVGs, native vector fragments and texture-import recipes.

No rendering, native cache fabrication, SWF writing or CS6 process control. The
archived authoring modules are read unchanged; only their pure body/wheel entry
points run. Font relocation is explicit and frozen with its license.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import io
import json
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUT=HERE/'vehicle-art'
ARCHIVE=ROOT/'flashswf/arts/new/Codex素材源稿/CF6地图'


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result


def sha(data):return hashlib.sha256(data).hexdigest()


def build():
    import matplotlib
    from PIL import Image
    from fontTools.ttLib import TTFont
    source=ARCHIVE/'A07-R2/cf6-stage7-redraw-r2/source'
    sys.path.insert(0,str(source))
    artist=module('cf6_preparation_armored',source/'armored_vehicle.py')
    font=OUT/'fonts/DejaVuSerif-Bold.ttf'
    font_source=font if font.is_file() else Path(matplotlib.get_data_path())/'fonts/ttf/DejaVuSerif-Bold.ttf'
    license_source=font.with_name('LICENSE_DEJAVU') if font.is_file() else font_source.with_name('LICENSE_DEJAVU')
    # The original Linux absolute font name maps to an explicit identical family.
    # The precise bytes used here are retained; pixel identity with old renders is not asserted.
    def relocated_font(name):
        if name != '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf':raise ValueError('unexpected authoring font')
        return TTFont(font_source)
    artist.TTFont=relocated_font
    generated={font:font_source.read_bytes(),font.with_name('LICENSE_DEJAVU'):license_source.read_bytes()}
    for cid,w,h,body in [(1806,371,236,artist.make_body()),(1808,45,45,artist.make_wheel())]:
        generated[OUT/f'bitmap-{cid}.svg']=artist.write_part.__globals__['svg']([0,0,w,h],body).encode('utf-8')
    vector=module('cf6_vehicle_native',ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py')
    builder=module('cf6_vehicle_import',ROOT/'tools/cf6-map-runtime/build.py')
    sys.path.insert(0,str(ROOT/'tools/cf6-map-runtime/native-vector'))
    road_adapter=module('cf6_prepared_road_noise',ROOT/'tools/cf6-map-runtime/native-vector/build-a08.py')
    E=vector.E
    inputs={p.relative_to(ROOT).as_posix():sha(p.read_bytes()) for p in [Path(__file__),vector.FONT,
        source/'armored_vehicle.py',source/'svg_native.py',
        ROOT/'tools/tesla-map-assets/native_vector/svg_to_xfl_legacy.py',
        ROOT/'tools/cf6-map-runtime/native-vector/build-a01.py',ROOT/'tools/cf6-map-runtime/build.py',
        ROOT/'tools/cf6-map-runtime/native-vector/build-a08.py',ROOT/'tools/cf6-map-runtime/native-vector/procedural_filter.py']}
    assets=[]
    sources=[('ArmoredBody',OUT/'bitmap-1806.svg'),('ArmoredWheel',OUT/'bitmap-1808.svg'),
             ('PlayerCar',ARCHIVE/'A08-R5/parts/bitmap-1823.svg'),
             ('Road',ARCHIVE/'A08-R5/parts/bitmap-1786.svg')]
    for role,path in sources:
        raw=generated.get(path,path.read_bytes() if path.is_file() else b'')
        if not raw:raise ValueError('missing vector input: '+str(path))
        inputs[path.relative_to(ROOT).as_posix()]=sha(raw)
        root=ET.fromstring(raw);textures={};texture_rows=[]
        for node in root.iter():
            if vector.tag(node)!='image':continue
            href=node.get('href') or node.get('{http://www.w3.org/1999/xlink}href') or ''
            if not href.startswith(('data:image/png;base64,','data:image/jpeg;base64,')):raise ValueError('non-local intrinsic texture')
            content=base64.b64decode(href.split(',',1)[1]);key=sha(content)
            if key in textures:continue
            filename='intrinsic-'+key[:24]+('.jpg' if href.startswith('data:image/jpeg') else '.png')
            target=OUT/'textures'/filename
            with Image.open(io.BytesIO(content)) as picture:size=list(picture.size)
            generated[target]=content;textures[key]={'name':filename,'pixels':size}
            texture_rows.append({'path':target.relative_to(ROOT).as_posix(),'sha256':key,'bytes':len(content),'pixels':size})
        # Parse a private temporary input; --check never rewrites prepared sources.
        # TemporaryDirectory owns cleanup of only this verified named scratch folder.
        with tempfile.TemporaryDirectory(prefix='cf6-scene-preparation-') as scratch:
            scratch_path=Path(scratch).resolve()
            if scratch_path.parent!=Path(tempfile.gettempdir()).resolve():raise ValueError('unexpected scratch root')
            candidate_source=scratch_path/path.name;candidate_source.write_bytes(raw)
            converter_type=road_adapter.A08Candidate if role=='Road' else vector.Candidate
            converter=converter_type(candidate_source,textures=textures,allow_filters=True)
        try:
            elements=converter.walk_native(root)
        except ValueError as error:
            # Keep the authoritative SVG and report the precise missing native feature.
            # Never flatten the entire vehicle to conceal an unsupported construct.
            assets.append({'role':role,'source':path.relative_to(ROOT).as_posix(),
                           'state':'svg-ready; native conversion blocked','reason':str(error)})
            continue
        texture_rows=[r for r in texture_rows if r['sha256'] in converter.used_textures]
        view=vector.base.nums(root.get('viewBox'));name='CF6_A07_'+role+'_Prepared'
        target=ROOT/'flashswf/backgrounds/cf6/preparation'/name
        fragment=OUT/role
        timeline=E('DOMTimeline',{'name':name});layer=E('DOMLayer',{'name':role},E('layers',parent=timeline))
        fr=E('DOMFrame',{'index':'0','duration':'1','keyMode':'9728'},E('frames',parent=layer))
        E('script',parent=E('Actionscript',parent=fr)).text='stop();'
        el=E('elements',parent=fr)
        el.append(converter.instance(elements,'registered-art',(1,0,0,1,-view[0],-view[1])))
        generated[fragment/'timeline.xml']=ET.tostring(timeline,encoding='utf-8',xml_declaration=True)
        for symbol,tree in converter.symbols.items():
            generated[fragment/'LIBRARY'/(symbol+'.xml')]=ET.tostring(tree,encoding='utf-8',xml_declaration=True)
        layers=[{'id':'texture-'+str(i),'png':r['path'],'x':0,'y':0,
                 'width':r['pixels'][0],'height':r['pixels'][1],'depth':i} for i,r in enumerate(texture_rows)]
        recipe=builder.jsfl({'id':name,'nativeBounds':view,'worldScale':1},layers,name,target/(name+'.xfl'))
        generated[fragment/'import-textures.jsfl']=recipe.encode('utf-8')
        assets.append({'role':role,'source':path.relative_to(ROOT).as_posix(),'sourceSha256':sha(raw),
                       'state':'vector-fragments-ready; native texture import/assembly/CS6 still required',
                       'name':name,'targetXfl':(target/(name+'.xfl')).relative_to(ROOT).as_posix(),
                       'intrinsicTextures':texture_rows,'viewBox':view,'symbols':len(converter.symbols),
                       'shapes':converter.shape_count,'filters':converter.filter_reports,
                       'proceduralApproximations':list(road_adapter.noise_reports) if role=='Road' else [],
                       'limits':['native filter region/blur require actual comparison','player car is a static R5 art base; wheels/fire/death are not yet assembled']})
    result={'schema':'cf6-vehicle-art-preparation.v1','state':'source-only; no native texture import performed',
            'fontSha256':sha(generated[font]),'inputs':inputs,'assets':assets,
            'originalAnimationSource':'source-evidence/original.json and archived A07 environment-original-nodes.json',
            'outputs':{p.relative_to(ROOT).as_posix():{'sha256':sha(v),'bytes':len(v)} for p,v in generated.items()}}
    return generated,result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    manifest_path=HERE/'vehicle-art-manifest.json'
    previous=json.loads(manifest_path.read_text(encoding='utf-8')) if manifest_path.is_file() else None
    if previous:
        for name,row in previous['outputs'].items():
            p=ROOT/name
            if not p.is_file() or sha(p.read_bytes())!=row['sha256']:raise ValueError('owned generated file changed: '+name)
    elif OUT.exists() and any(OUT.rglob('*')):
        raise ValueError('existing preparation directory lacks ownership manifest')
    outputs,manifest=build()
    outputs[manifest_path]=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    for path,raw in outputs.items():
        if args.check:
            if not path.is_file() or path.read_bytes()!=raw:raise ValueError('stale vehicle preparation: '+str(path))
        else:
            path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(raw)
    print(json.dumps({'assets':[{k:r[k] for k in ('role','state')} for r in manifest['assets']],
                      'files':len(outputs),'bytes':sum(len(v) for v in outputs.values())}))
