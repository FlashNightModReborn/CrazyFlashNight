"""Create separate door-frame source/render assets; no main scene preview inputs."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
from PIL import Image
from door_art import DoorArt,ROOT,ARCHIVE

HERE=Path(__file__).resolve().parent
PROFILE={
    'wood1714':{'package':'A03-R1/cf6-stage3-redraw-r1','sprite':1714,'frames':list(range(1,10)),
        'viewBox':[-85,-100,170,240],'rootWhitelist':None},
    'exit1720':{'package':'A03-R1/cf6-stage3-redraw-r1','sprite':1720,'frames':list(range(1,51)),
        'viewBox':[-85,-100,170,240],'rootWhitelist':[1715,1716,1718]},
    'grand1750':{'package':'A05-R3/cf6-stage5-redraw-r3','sprite':1750,'frames':list(range(1,41)),
        'viewBox':[-200,-110,400,280],'rootWhitelist':[86,1747,1748,1749]}}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--render',action='store_true');parser.add_argument('--check',action='store_true');parser.add_argument('--kind',action='append',help='Restrict rendering to these sets; validate all sets');args=parser.parse_args()
    renderer=None
    if args.render:
        spec=importlib.util.spec_from_file_location('cf6_svg_render',ROOT/'tools/cf6-map-source/pydeps/svgrender.py')
        renderer=importlib.util.module_from_spec(spec);spec.loader.exec_module(renderer)
    manifest={'schema':'cf6-door-art.v1','purpose':'isolated door/environment frames; no character, weapon, collision marker or gameplay script','sets':[]}
    for name,config in PROFILE.items():
        art=DoorArt(ARCHIVE/config['package']);folder=HERE/'assets/doors'/name
        row=dict(config,id=name,frames=[])
        cache={};pixel_size=(config['viewBox'][2]*2,config['viewBox'][3]*2)
        for index in config['frames']:
            path=folder/f'frame-{index:03}.svg';text=art.frame(config['sprite'],index,config['viewBox'],config['rootWhitelist']);content=text.encode()
            if args.check:assert path.read_bytes()==content,'stale '+str(path)
            else:folder.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
            digest=hashlib.sha256(content).hexdigest();png=path.with_suffix('.png');kind='not-rendered'
            if args.render and (not args.kind or name in args.kind):
                if digest in cache:
                    png.write_bytes(cache[digest][0].read_bytes());kind=cache[digest][1]
                else:
                    kind=renderer.render(path,pixel_size[0],png);cache[digest]=(png,kind)
            if png.is_file():
                with Image.open(png) as image:
                    assert image.size==pixel_size,'wrong raster dimensions'
                    assert image.convert('RGBA').getextrema()[3][1]>0,'empty door frame'
                png_info={'png':png.relative_to(ROOT).as_posix(),'pngSha256':hashlib.sha256(png.read_bytes()).hexdigest(),'pixelSize':list(pixel_size)}
            else:png_info={}
            row['frames'].append({'sourceFrame':index,'svg':path.relative_to(ROOT).as_posix(),'svgSha256':digest,**png_info})
        row['sourceInputs']=[{'path':path,'sha256':digest} for path,digest in sorted(art.inputs.items())]
        row['renderPolicy']='native-shape/matrix source; existing Chrome/Edge fallback is a candidate raster, requires consumer verification'
        manifest['sets'].append(row)
    path=HERE/'generated/door-art.manifest.json';content=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    if args.check:assert path.read_bytes()==content,'stale door manifest'
    else:path.write_bytes(content)
    print('prepared door sets: '+', '.join(row['id'] for row in manifest['sets']))


if __name__=='__main__':main()
