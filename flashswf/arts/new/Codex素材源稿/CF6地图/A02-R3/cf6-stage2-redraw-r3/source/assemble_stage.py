from pathlib import Path
import json
from svg_native import write_part,inner,assemble,render
from PIL import Image,ImageDraw,ImageFont
def _cf6_font(size):
    # PATCHED(cf6-map-source): 硬编码 Linux 字体路径在 Windows 不存在；仅影响预览标注
    cands=[R/'reference/fonts'/'DejaVuSans.ttf']
    try:
        import matplotlib as _mpl, os as _os
        cands.append(Path(_os.path.join(_os.path.dirname(_mpl.__file__),'mpl-data','fonts','ttf','DejaVuSans.ttf')))
    except Exception:
        pass
    for _c in cands:
        if Path(_c).is_file():return ImageFont.truetype(str(_c),size)
    return ImageFont.load_default()
R=Path(__file__).resolve().parents[1]
records=json.loads((R/'reference/shape-details.json').read_text())+json.loads((R/'reference/root-layer-details.json').read_text())
for obj in records:
 cid=obj['id']
 if cid not in [1596,1598,1601,1605,1612]:continue
 fills=[f for f in obj['fills'] if f['type']=='bitmap'];bids=sorted({f['bitmapId'] for f in fills});defs='<defs>'
 for bid in bids:defs+=f'<g id="bitmap{bid}">'+inner(R/f'parts/bitmap-{bid}.svg',f'b{bid}')+'</g>'
 defs+='</defs>';s=defs
 for k,f in enumerate(fills):
  s+=f'<clipPath id="fill{k}"><path d="{f["path"]}"/></clipPath><g clip-path="url(#fill{k})"><use href="#bitmap{f["bitmapId"]}" transform="matrix('+ ' '.join(map(str,f['matrix']))+')"/></g>'
 if cid==1605:
  # Artist-authored far-plane finish reduces tiny window-frame contrast before the unchanged original RGB multiplier.
  s='<defs><filter id="farPlaneFinish" x="-.01" y="-.05" width="1.02" height="1.1" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values=".82 0 0 0 .012 0 .82 0 0 .012 0 0 .82 0 .012 0 0 0 1 0"/><feGaussianBlur stdDeviation=".28"/></filter></defs><g filter="url(#farPlaneFinish)">'+s+'</g>'
 write_part(R/f'parts/shape-{cid}.svg',obj['viewBox'],s)
# Original author-defined depth order and RGB multiplier preserved.
leaves=json.loads((R/'reference/render-manifest.json').read_text())['renders'][0]['leaves']
for mode in ['original','new']:
 s='<defs><filter id="farDark" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values=".62890625 0 0 0 0 0 .62890625 0 0 0 0 0 .62890625 0 0 0 0 0 1 0"/></filter></defs>'
 for j,(cid,m,path,alpha,mult,add) in enumerate(leaves):
  p=R/f'parts/shape-{cid}.svg' if mode=='new' else R/f'reference/original-shapes/{cid}.svg'
  extra=' filter="url(#farDark)"' if mult[0]!=1 else ''
  s+='<g transform="matrix('+' '.join(map(str,m))+')"'+extra+'>'+inner(p,'leaf'+str(j))+'</g>'
 bg=write_part(R/f'previews/background-{mode}.svg',[-716.95,-183,1330.9,469.8],s)
 render(bg,1997,R/f'previews/background-{mode}.png')
 if mode=='new':write_part(R/'parts/background-1613.svg',[-716.95,-183,1330.9,469.8],s)
 for view,x,y in [('initial',0,0),('middle',-325,-50),('right',-650,-100)]:
  sky=R/'parts/shape-1596.svg' if mode=='new' else R/'reference/original-shapes/1596.svg'
  city=R/'parts/shape-1598.svg' if mode=='new' else R/'reference/original-shapes/1598.svg'
  crate=R/'reference/stage1-crate/prop-1442.svg' if mode=='new' else R/'reference/original-shapes/prop-1442.svg'
  cityx=-.75 if view=='initial' else x/2;cityy=-1 if view=='initial' else y
  layers=[{'path':sky},{'path':city,'matrix':[1,0,0,1,cityx,cityy]},{'path':bg,'matrix':[1.000030517578125,0,0,1,673.5*1.000030517578125+x,207.1+y]},{'path':crate,'matrix':[1.000030517578125,0,0,1,488.55*1.000030517578125+x,274.4+y]}]
  p=assemble([0,0,600,350],layers,R/f'previews/scene-{view}-{mode}.svg');render(p,1200)
font=_cf6_font(20)
for view in ['initial','middle','right']:
 out=Image.new('RGB',(2400,740),'#252b26');d=ImageDraw.Draw(out)
 for j,mode in enumerate(['original','new']):
  im=Image.open(R/f'previews/scene-{view}-{mode}.png').convert('RGBA');out.paste(im,(1200*j,40),im);d.text((1200*j+10,10),('Original CF6' if mode=='original' else 'R3 editable source / baked preview')+' | '+view,font=font,fill='white')
 out.save(R/f'previews/scene-{view}-original-new.png')
# Same-size transparent wide background comparison, neutral canvas solely for reviewing assets.
ims=[Image.open(R/f'previews/background-{m}.png').convert('RGBA') for m in ['original','new']];w,h=ims[0].size;out=Image.new('RGB',(w,h*2+70),'#333a35');d=ImageDraw.Draw(out)
for j,im in enumerate(ims):out.paste(im,(0,j*(h+35)+35),im);d.text((10,j*(h+35)+7),['Original background 1613 | transparent sky','R3 background 1613 | same native registration'][j],font=font,fill='white')
out.save(R/'previews/background-original-new.png')
