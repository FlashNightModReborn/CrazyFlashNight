"""One-time source-bound outline extraction; runtime never loads font programs or XFL bitmaps."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'launcher/src/Guardian/Hud/PlayerInfo/Assets/live'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--font', type=Path, required=True)
    parser.add_argument('--images', type=Path, required=True)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    font = TTFont(args.font)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    assert font['OS/2'].fsType == 0 and font['head'].unitsPerEm == 1024
    # FFDec's TTF header timestamps vary between exports. Bind the glyph paths
    # against B0 in addition to the exact source SWF, rather than header time.
    parts=[]
    for ch in '0123456789/%MP-':
        pen=SVGPathPen(glyphs); glyphs[cmap[ord(ch)]].draw(pen)
        parts.append(ch.encode()+b'\0'+pen.getCommands().encode())
    assert hashlib.sha256(b'\0'.join(parts)).hexdigest().upper() == 'F27C8B0FF43DAC9287E40F234775F5E4951DE9A50BC15E0BB38A082B06FBA769'
    rows = []
    for key, label in [('skill-label','Skill'), ('sp-label','SP.')]:
        cursor = 0
        shapes = []
        for ch in label:
            name = cmap[ord(ch)]
            pen = SVGPathPen(glyphs)
            glyphs[name].draw(pen)
            color = '#000000' if key == 'skill-label' else '#FFFFFF'
            shapes.append(f'<path transform="matrix(1 0 0 1 {cursor} 0)" d="{pen.getCommands()}" fill="{color}"/>')
            cursor += font['hmtx'].metrics[name][0]
        em = font['head'].unitsPerEm
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {cursor} {em}" width="{cursor}" height="{em}"><g transform="matrix(1 0 0 -1 0 {font["hhea"].ascent})">{"".join(shapes)}</g></svg>\n'
        path = OUT/(key+'.svg')
        path.write_text(svg,encoding='utf-8',newline='\n')
        rows.append({'id':key,'path':path.relative_to(ROOT).as_posix(),'sha256':sha(path),'label':label,
                     'unitsPerEm':em,'advance':cursor,'ascent':font['hhea'].ascent})
    # The two original HUD bitmap fills are only 6x9 and 7x9. Preserve exact opaque
    # pixel runs as vector rectangles; no resampling, tracing, or new illustration.
    for path in sorted(args.images.glob('*.png')):
        image = Image.open(path).convert('RGBA')
        if image.size not in [(6,9),(7,9)]: continue
        key = 'ammo-round' if image.width == 6 else 'ammo-magazine'
        spans=[]
        for y in range(image.height):
            x=0
            while x<image.width:
                color=image.getpixel((x,y)); end=x+1
                while end<image.width and image.getpixel((end,y))==color:end+=1
                if color[3]:
                    shape=f'<rect x="{x}" y="{y}" width="{end-x}" height="1" fill="#{color[0]:02X}{color[1]:02X}{color[2]:02X}"/>'
                    spans.append(shape if color[3]==255 else f'<g opacity="{color[3]/255:.8g}">{shape}</g>')
                x=end
        svg=f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {image.width} {image.height}" width="{image.width}" height="{image.height}">{"".join(spans)}</svg>\n'
        out=OUT/(key+'.svg');out.write_text(svg,encoding='utf-8',newline='\n')
        rows.append({'id':key,'path':out.relative_to(ROOT).as_posix(),'sha256':sha(out),
                     'sourcePngSha256':sha(path),'pixelSize':list(image.size)})
    assert len(rows)==4
    provenance={'version':1,'generator':{'path':Path(__file__).relative_to(ROOT).as_posix(),'sha256':sha(Path(__file__))},
        'fontSource':{'repositoryCommit':'891d9b08dbd826d8b2624c6bdc59082b3db57ecd',
                      'swf':'flashswf/UI/玩家信息界面.swf',
                      'swfSha256':'450B1F9A8B445EE3E28C63682EA00124A191F56D05D759B8590210FC0066A615',
                      'fontSha256':sha(args.font),'font':'Aero','distribution':'derived paths only'},
        'bitmapSources':[{'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(p)}
                         for p in sorted((ROOT/'flashswf/UI/玩家信息界面/bin').glob('*.dat'))],
        'bitmapSwfSha256':sha(ROOT/'flashswf/UI/玩家信息界面.swf'),'assets':rows}
    (ROOT/'tools/player-info-hud/live-symbols.provenance.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Derived',len(rows),'source-bound labels and pixel icons')

if __name__=='__main__': main()
