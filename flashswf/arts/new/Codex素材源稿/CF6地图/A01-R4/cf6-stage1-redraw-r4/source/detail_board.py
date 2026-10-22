from pathlib import Path
from PIL import Image,ImageDraw
R=Path(__file__).resolve().parents[1];out=Image.new('RGB',(1800,1200),'#e8e9e4');d=ImageDraw.Draw(out)
for k,cid in enumerate([1591,1442]):
 im=Image.open(R/f'previews/prop-{cid}-original-vs-redraw.png').convert('RGB');im.thumbnail((1760,560));out.paste(im,((1800-im.width)//2,40+k*580))
d.text((25,15),'CF6 A1 PROPS / ORIGINAL LEFT / R2 RIGHT / MATCHED REGISTRATION',fill='#243029');out.save(R/'previews/props-detail-board.png')
board=Image.new('RGB',(1800,1300),'#e8e9e4')
for j,cid in enumerate(range(1436,1442)):
 p=R/f'previews/prop-{cid}-original-vs-redraw.png'
 if not p.exists():continue
 im=Image.open(p).convert('RGB');im.thumbnail((880,410));board.paste(im,(j%2*900+(900-im.width)//2,j//2*430+(430-im.height)//2))
board.save(R/'previews/crate-fragments-original-vs-redraw.png')
