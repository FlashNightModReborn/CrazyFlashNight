#!/usr/bin/env python3
"""Stage 4 bitmap 1731: hand-authored editable burgundy steel barrel.
Coordinates are original bitmap pixels; native dimensions and transparent margins
are unchanged. The centered Flash symbol is supplied by the assembler, not here.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
from svg_native import write_part, render
ROOT=Path(__file__).resolve().parents[1]
PART=ROOT/'parts/bitmap-1731.svg'
PREVIEW=ROOT/'previews'
QA=ROOT/'qa'
PREVIEW.mkdir(exist_ok=True); QA.mkdir(exist_ok=True)
outline='M25.8 .35 C37.1 .25 47.6 2.65 50.65 5.4 Q51.8 6.5 51.65 8.5 Q51.65 10.7 49.75 11.55 L49.65 27.55 Q51.6 28.8 51.65 30.55 Q51.5 32 49.65 33.15 L49.65 57.95 Q51.65 59.15 51.6 61.05 Q51.6 62.7 49.65 63.65 L49.65 78.05 Q51.65 79.2 51.7 81.25 C51.4 85.25 39.2 88.6 25.65 88.65 C12.1 88.65 .6 85.1 .25 81.25 Q.2 79.4 1.8 78.1 L1.85 63.6 Q.2 62.7 .2 61 Q.15 59.4 1.85 58.15 L1.85 33.15 Q.1 32 .15 30.45 Q.1 28.8 1.85 27.55 L1.85 11.7 Q.15 10.65 .15 8.3 Q-.05 6.6 1.25 5.4 C4.3 2.7 14.5 .35 25.8 .35 Z'
content='''<title>Dark burgundy flammable steel drum, bitmap 1731</title>
<desc>Editable native vector. Original 52 by 89 pixel coordinates. Two rolled body bands, corrugated head and foot, elliptical lid, two bung caps and ochre flame placard.</desc>
<defs>
 <linearGradient id="barrel-paint" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#211211"/><stop offset=".10" stop-color="#472424"/><stop offset=".30" stop-color="#66332f"/><stop offset=".58" stop-color="#693732"/><stop offset=".80" stop-color="#5e292d"/><stop offset=".93" stop-color="#421d20"/><stop offset="1" stop-color="#251313"/></linearGradient>
 <linearGradient id="barrel-top" x1="0" y1="1" x2=".28" y2="0"><stop stop-color="#3a1c1c"/><stop offset=".5" stop-color="#674541"/><stop offset="1" stop-color="#926761"/></linearGradient>
 <linearGradient id="barrel-ring" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#493330"/><stop offset=".13" stop-color="#aa8376"/><stop offset=".48" stop-color="#745349"/><stop offset=".78" stop-color="#987063"/><stop offset="1" stop-color="#37211e"/></linearGradient>
 <linearGradient id="barrel-label" x1="0" y1="0" x2="1" y2=".3"><stop stop-color="#796b1c"/><stop offset=".55" stop-color="#ada023"/><stop offset="1" stop-color="#95831d"/></linearGradient>
 <linearGradient id="barrel-cap" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#b3a89a"/><stop offset="1" stop-color="#665a4e"/></linearGradient>
 <clipPath id="barrel-silhouette"><path d="'''+outline+'''"/></clipPath>
</defs>
<g id="barrel-outer-volume">
 <path id="barrel-outline" d="'''+outline+'''" fill="#130e0c"/>
 <g clip-path="url(#barrel-silhouette)">
  <path id="barrel-cylindrical-paint" d="M1.3 7.5H50.8V82C49.9 86.25 36.7 88.25 25.8 88.25S2 85.8 1.2 81.5Z" fill="url(#barrel-paint)"/>
  <path id="barrel-left-soft-sheen" d="M6.1 13Q8.2 14 10.2 14.4L9.8 80.6Q8.3 80.4 6.4 79.5Z" fill="#bc7660" opacity=".075"/>
  <path id="barrel-right-reflected-plane" d="M39.1 13.5Q44 12.7 46.4 11.8L46.5 80.9Q44.2 82 40.2 82.7Z" fill="#b45b5f" opacity=".08"/>
  <path id="barrel-right-dark-seam" d="M48.65 10.1Q49.5 10 50.3 9.7V81.3Q49.6 83.25 47.6 84.05L48.2 12Z" fill="#180e0e" opacity=".55"/>
'''
# Pressed shallow circumferential corrugations are open native paths.
for name,ys in [('head',[12.6,16.2,19.8,23.4]),('foot',[64.0,67.65,71.3,74.95,78.6])]:
    content+=f'<g id="barrel-{name}-corrugations">'
    for i,y in enumerate(ys):
        content+=f'<path id="barrel-{name}-groove-{i}" d="M2.05 {y} C11.9 {y+4.45} 38.55 {y+4.8} 49.6 {y-.15}" fill="none" stroke="#241112" stroke-opacity=".72" stroke-width=".85" stroke-linecap="round"/>'
        shine=f'M2.5 {y+1.05} C13.2 {y+5.35} 38.6 {y+5.55} 49.15 {y+.9}'
        if (name,i) in [('head',1),('foot',2)]:
            shine=f'M2.5 {y+1.05} C8 {y+3.25} 15 {y+4.2} 21 {y+4.35} M24 {y+4.45} C34 {y+4.65} 43 {y+3.65} 49.15 {y+.9}'
        content+=f'<path id="barrel-{name}-ridge-{i}" d="{shine}" fill="none" stroke="#9a5e50" stroke-opacity=".25" stroke-width=".45"/>'
    content+='</g>'
content+='''
  <g id="barrel-upper-rolled-band">
   <path d="M1.8 28.55C10.7 33.8 39.7 34.65 49.7 28.45L51.4 30.1C43 36.65 10 36.25 .45 30.35Z" fill="#281715"/>
   <path d="M.6 29.85C11.2 36.1 39.35 36.2 51.3 29.65" fill="none" stroke="url(#barrel-ring)" stroke-width="1.05"/>
   <path d="M2.3 31.6C13.9 37.25 39.5 36.7 49.65 31.6" fill="none" stroke="#190d0e" stroke-width=".65"/>
  </g>
  <g id="barrel-lower-rolled-band">
   <path d="M1.85 58.75C11.2 64 39.85 64.55 49.6 58.65L51.3 60.65C40.85 66.85 10.9 66.65 .45 60.65Z" fill="#2b1715"/>
   <path d="M.55 60.35C11.7 66.7 39.9 66.4 51.25 60.25" fill="none" stroke="url(#barrel-ring)" stroke-width="1.1"/>
   <path d="M2.3 62.45C12.85 68 39.4 67.1 49.5 62.3" fill="none" stroke="#21100f" stroke-width=".65"/>
  </g>
  <g id="barrel-foot-seam">
   <path d="M.65 80.8C10.4 86.85 40.1 87.6 51.3 80.8L51.35 83.15C41.4 90.1 10 90.1 .7 83.15Z" fill="#291816"/>
   <path d="M.65 81.9C11 88.8 39.95 88.6 51.25 81.75" fill="none" stroke="url(#barrel-ring)" stroke-width="1.2"/>
   <path d="M3.4 85C14.15 89.1 37.9 89.1 48.6 84.95" fill="none" stroke="#170e0c" stroke-width=".7"/>
  </g>
 </g>
</g>
<g id="barrel-lid">
 <path id="barrel-top-chime" d="M.45 7.2C.5 3.1 12.45 .55 25.8 .55S51.2 3.15 51.25 7.1L51.2 9.2C48.6 13.8 10.2 16.1 .55 9.25Z" fill="#211211" stroke="#130d0c" stroke-width=".55"/>
 <ellipse id="barrel-lid-plane" cx="25.8" cy="6.5" rx="24.6" ry="5.4" fill="url(#barrel-top)" stroke="#4c2c2b" stroke-width=".75"/>
 <path id="barrel-lid-inset" d="M3.3 6.5C6.8 2.4 19.2 1.9 25.8 1.9S44.8 2.8 48.4 6.4C43.5 9.9 11.2 11.45 3.3 6.5Z" fill="none" stroke="#7f554e" stroke-width=".55"/>
 <path id="barrel-lid-front-edge" d="M1.9 8.1C10.5 13.7 41.55 13.5 49.8 8" fill="none" stroke="#97695e" stroke-width=".7"/>
 <path d="M2.6 10.1C13.1 15 40.6 14.35 49.4 10" fill="none" stroke="#1b1010" stroke-width=".7"/>
 <g id="barrel-large-bung">
  <path d="M28.35 3.05L29.9 1.85L36.55 1.65L38.55 2.6L38.5 5.05Q33.5 6.65 28.4 5.25Z" fill="#211813" stroke="#130f0b" stroke-width=".65"/>
  <path d="M28.7 2.85L30.1 1.95L36.5 1.75L38.15 2.6L37.8 3.95L30 4.35L28.65 3.7Z" fill="url(#barrel-cap)" stroke="#58453a" stroke-width=".45"/>
  <path d="M30.65 2.55L35.75 2.35" fill="none" stroke="#d4c7ad" stroke-opacity=".6" stroke-width=".5"/>
 </g>
 <g id="barrel-small-bung">
  <path d="M9.6 8.25L10.55 7.2L13.7 7.1L15.1 8.25L15.05 10.5L9.65 10.6Z" fill="#211713" stroke="#160f0c" stroke-width=".55"/>
  <path d="M9.9 8.1L10.65 7.25L13.65 7.2L14.65 8.1L14.2 9.05L10.55 9.15Z" fill="url(#barrel-cap)" stroke="#514438" stroke-width=".4"/>
 </g>
</g>
<g id="barrel-flammable-placard">
 <path id="barrel-sign-shadow" d="M27.6 23.75Q28.15 23.45 28.55 24.2L44.9 53.3Q45.4 54.1 44.3 54.35L11.65 54.4Q10.7 54.2 11.2 53.2Z" fill="#24180c" opacity=".85"/>
 <path id="barrel-sign-border" d="M27.35 23.45L44.2 52.65Q44.8 53.7 43.6 53.8L11.75 53.75Q10.65 53.65 11.15 52.65L26.55 23.55Q27 22.75 27.35 23.45Z" fill="#352c0c" stroke="#21170c" stroke-width=".65"/>
 <path id="barrel-sign-yellow-face" d="M27.03 25.75L42.38 51.93L13.03 51.93Z" fill="url(#barrel-label)"/>
 <path id="barrel-flame-pictogram" d="M25.25 49.1C21.7 48.35 20.25 45.55 21.1 42.55C21.8 40.05 23.75 38.3 23.3 36.55Q25.3 37.1 25.7 39.25C27.65 36.15 25.95 33.6 27.85 31.6C27.5 35.2 30.95 36.4 30.4 40.4Q31.7 39.4 31.8 38.4C33.5 41.1 34.35 43.1 33.35 45.95C32.7 47.7 31.05 48.75 29.4 49.15C30.5 47.75 30.6 46.3 29.65 44.8C29.45 46 28.65 46.8 28.1 47.05C28.85 44.5 27.25 43.6 27.55 41.7C25.5 43.9 25.45 44.7 25.6 46.4Q24.55 45.95 24.2 44.95C23.55 46.7 24 48.05 25.25 49.1Z" fill="#231b0c"/>
</g>
'''
write_part(PART,[0,0,52,89],content)
render(PART,52,PREVIEW/'barrel-native.png')
render(PART,416,PREVIEW/'barrel-redraw-8x.png')
original=Image.open(ROOT/'reference/bitmap-1731-original.png').convert('RGBA')
redraw=Image.open(PREVIEW/'barrel-native.png').convert('RGBA')
# A readable same-scale comparison, rendered from the true native coordinates.
board=Image.new('RGB',(960,850),'#746c63');d=ImageDraw.Draw(board)
d.text((58,20),'ORIGINAL 1731 | 8x',fill='white');d.text((518,20),'NATIVE VECTOR REDRAW | 8x',fill='white')
board.paste(original.resize((416,712),Image.Resampling.NEAREST),(28,60),original.resize((416,712),Image.Resampling.NEAREST))
large=Image.open(PREVIEW/'barrel-redraw-8x.png').convert('RGBA');board.paste(large,(508,60),large)
d.text((28,802),'Both: 52 x 89 px; original artwork coordinates; symbol registration (-26, -44.5).',fill='white')
board.save(PREVIEW/'barrel-original-redraw-8x.png')
board.save(PREVIEW/'barrel-original-new.png')
small=Image.new('RGB',(440,155),'#746c63');d=ImageDraw.Draw(small)
d.text((30,12),'ORIGINAL',fill='white');d.text((240,12),'VECTOR',fill='white')
small.paste(original,(47,42),original);small.paste(redraw,(258,42),redraw);small.save(PREVIEW/'barrel-original-redraw-native.png')
# Machine-verifiable geometry / authorship properties, separate from visual QA.
from xml.etree import ElementTree as ET
svg=ET.parse(PART).getroot();tags=[e.tag.split('}')[-1] for e in svg.iter()]
a=original.getchannel('A'); b=redraw.getchannel('A')
import numpy as np
ma=np.array(a)>=128;mb=np.array(b)>=128
info={'bitmap_id':1731,'source_size':[52,89],'viewBox':[0,0,52,89],'symbol_1732_origin_px':[26,44.5], 'bitmap_matrix_for_shape_1732':[1,0,0,1,-26,-44.5], 'native_render_size':list(redraw.size),'embedded_raster_count':tags.count('image'),'native_path_count':tags.count('path'),'has_text_objects':tags.count('text'),'original_alpha_bbox':a.getbbox(),'redraw_alpha_bbox':b.getbbox(),'silhouette_iou_threshold_128':round(float((ma&mb).sum()/(ma|mb).sum()),5),'notes':['All artwork is editable vector paths, ellipses, gradients and one vector clip path.','Original explosion clip paths and transforms are intentionally outside this file and remain unchanged.','No new holes or added bolts.']}
(QA/'barrel-geometry.json').write_text(json.dumps(info,indent=2)+'\n')
print(json.dumps(info,indent=2))
