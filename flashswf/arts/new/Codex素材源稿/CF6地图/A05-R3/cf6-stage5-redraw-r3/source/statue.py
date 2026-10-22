"""Editable reconstruction of CF6 bitmap 1740, in its original 65 x 211 registration.

HYBRID SOURCE DISCLOSURE: The alpha silhouette is fitted to the supplied bitmap.
The anatomical planes, drapery, face, stone support, and all material marks are
new editable vector shapes. Curves use the image as a pose/structure reference;
a low-frequency reference relief map supplies broad occlusion/volume shadows.
There is no embedded raster or per-pixel colour vectorization. The map is
explicitly reference-derived, not claimed as freehand artwork. The fixed-seed
mineral marks are procedural and can be disabled with TEXTURE = False.
"""
from pathlib import Path
import os, math, random, json
os.environ.setdefault('MPLCONFIGDIR','/tmp/cf6-statue-mpl')
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import gaussian_filter
import matplotlib; matplotlib.use('Agg')
import matplotlib.pyplot as plt
from svg_native import write_part, render
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'reference/bitmap-1740-original.png'
OUT=ROOT/'parts/bitmap-1740.svg'
TEXTURE=True
REVISION='r6'

def rdp(p,eps=.16):
    if len(p)<3:return p
    a,b=p[0],p[-1]; v=b-a
    if np.linalg.norm(v)<1e-6: d=np.linalg.norm(p-a,axis=1)
    else:d=np.abs(v[0]*(a[1]-p[:,1])-v[1]*(a[0]-p[:,0]))/np.linalg.norm(v)
    i=np.argmax(d)
    if d[i]>eps:return np.vstack((rdp(p[:i+1],eps)[:-1],rdp(p[i:],eps)))
    return np.vstack((a,b))

def contour_path():
    a=np.asarray(Image.open(REF).convert('RGBA'))[:,:,3]/255
    z=np.pad(a,2)
    cs=plt.contour(np.arange(-1.5,67.5),np.arange(-1.5,213.5),z,levels=[.35])
    paths=[]
    for seg in cs.allsegs[0]:
        seg=rdp(seg,.13)
        if len(seg)<4: continue
        paths.append('M'+' L'.join(f'{x:.3f},{y:.3f}' for x,y in seg)+' Z')
    plt.close()
    return ' '.join(paths)


def smooth_closed_path(seg):
    """Editable cubic contour with limited curvature; never a pixel-cell mosaic."""
    seg=rdp(seg,.22)
    if len(seg)>1 and np.linalg.norm(seg[0]-seg[-1])<.01:seg=seg[:-1]
    if len(seg)<3:return ''
    d=f'M{seg[0][0]:.2f},{seg[0][1]:.2f}'
    n=len(seg)
    for i in range(n):
        p0,p1,p2,p3=seg[(i-1)%n],seg[i],seg[(i+1)%n],seg[(i+2)%n]
        c1=p1+(p2-p0)/7.5;c2=p2-(p3-p1)/7.5
        d+=f' C{c1[0]:.2f},{c1[1]:.2f} {c2[0]:.2f},{c2[1]:.2f} {p2[0]:.2f},{p2[1]:.2f}'
    return d+'Z'

def reference_relief():
    """Fifteen broad fitted isophotes, heavily denoised before curve extraction.
    This explicitly reference-derived tonal reconstruction protects sculptural
    facial modelling and occlusion. It is separate from all manually editable
    anatomy and may be removed by deleting this single SVG group.
    """
    im=np.asarray(Image.open(REF).convert('RGBA')).astype(float)
    alpha=im[:,:,3]/255
    lum=(im[:,:,:3]*np.array([.2126,.7152,.0722])).sum(axis=2)
    # Alpha-normalized diffusion avoids accidental dark halos at the silhouette.
    den=gaussian_filter(alpha,.60)
    low=gaussian_filter(lum*alpha,.60)/np.maximum(den,.001)
    high=gaussian_filter(lum*alpha,.18)/np.maximum(gaussian_filter(alpha,.18),.001)
    yy,xx=np.mgrid[0:211,0:65]
    selective=np.zeros_like(lum)
    # Preserve deliberate chisel breaks at head/neck, hand/cloth, crossed knee.
    # Elsewhere the broad abdominal/limb modelling stays softly diffused.
    for cx,cy,rx,ry in [(27,33,13,14),(34,61,22,11),(33,148,10,14)]:
        selective=np.maximum(selective,np.exp(-1.8*(((xx-cx)/rx)**4+((yy-cy)/ry)**4)))
    lum=low*(1-selective*.9)+high*(selective*.9)
    lum=np.where(den>.02,lum,0)
    bands=np.arange(18,231,15)
    z=np.pad(lum,1)
    cs=plt.contour(np.arange(-.5,66.5),np.arange(-.5,212.5),z,levels=bands)
    chunks=['<g id="reference-derived-broad-relief" opacity=".92" filter="url(#reliefSoft)">', '<rect width="65" height="211" fill="#100b05"/>']
    n_contours=0
    for value,segs in zip(bands,cs.allsegs):
        ds=[]
        for seg in segs:
            if len(seg)<4: continue
            area=abs(np.dot(seg[:,0],np.roll(seg[:,1],1))-np.dot(seg[:,1],np.roll(seg[:,0],1)))/2
            if area < (.45 if float(seg[:,1].mean())<75 else 1.3):continue
            d=smooth_closed_path(seg)
            if d:ds.append(d);n_contours+=1
        t=min(1,(value+6)/226)**1.08
        rgb=[round(a+(b-a)*t) for a,b in zip((9,6,2),(241,230,206))]
        color='#'+''.join(f'{v:02x}' for v in rgb)
        chunks.append(f'<path fill="{color}" fill-rule="evenodd" d="'+ ' '.join(ds)+'"/>')
    chunks.append('</g>');plt.close()
    return ''.join(chunks),n_contours

S=[]
def path(d,fill,opacity=1,stroke=None,sw=.3,extra=''):
    st=f' stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"' if stroke else ''
    S.append(f'<path d="{d}" fill="{fill}" opacity="{opacity}"{st} {extra}/>')
def line(d,color,sw=.3,opacity=1):path(d,'none',opacity,color,sw)
def ellipse(cx,cy,rx,ry,fill,opacity=1):S.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}" opacity="{opacity}"/>')

def build():
    S.clear()
    silhouette=contour_path()
    S.extend(['''<title>CF6 fifth scene: classical carved stone figure</title>
<desc>Reference-assisted silhouette; newly drawn editable anatomy, drapery and mineral surface. Original registration 65 by 211. Fifteen reference-derived broad relief bands. No embedded image.</desc>
<defs>
 <linearGradient id="stone" x1="0" y1="0" x2="1" y2=".25"><stop stop-color="#d1caba"/><stop offset=".36" stop-color="#b1aa9b"/><stop offset=".68" stop-color="#bcb4a1"/><stop offset="1" stop-color="#686455"/></linearGradient>
 <linearGradient id="arm" x1="0" y1="0" x2="1" y2=".1"><stop stop-color="#d9d2bd"/><stop offset=".28" stop-color="#bab29c"/><stop offset=".6" stop-color="#aaa28b"/><stop offset="1" stop-color="#6f695a"/></linearGradient>
 <linearGradient id="leg" x1="0" y1="0" x2="1" y2=".35"><stop stop-color="#9e9681"/><stop offset=".18" stop-color="#d2c9b2"/><stop offset=".52" stop-color="#c5bca5"/><stop offset=".82" stop-color="#a49c86"/><stop offset="1" stop-color="#746c5a"/></linearGradient>
 <linearGradient id="rearLeg" x1="0" y1="0" x2="1" y2=".2"><stop stop-color="#bcb29b"/><stop offset=".43" stop-color="#9c927e"/><stop offset=".78" stop-color="#827864"/><stop offset="1" stop-color="#514b3d"/></linearGradient>
 <linearGradient id="neck" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#787460"/><stop offset=".35" stop-color="#b9b09a"/><stop offset=".7" stop-color="#d2c8af"/><stop offset="1" stop-color="#9a927c"/></linearGradient>
 <radialGradient id="body" cx=".28" cy=".34" r=".8"><stop stop-color="#d3cbb8"/><stop offset=".4" stop-color="#bab39e"/><stop offset=".75" stop-color="#a19882"/><stop offset="1" stop-color="#6e6959"/></radialGradient>
 <radialGradient id="face" cx=".32" cy=".35" r=".82"><stop stop-color="#e0d9c3"/><stop offset=".42" stop-color="#c9c1a9"/><stop offset=".77" stop-color="#a79d83"/><stop offset="1" stop-color="#766c55"/></radialGradient>
 <linearGradient id="cloth" x1="0" y1="0" x2=".15" y2="1"><stop stop-color="#e3dac1"/><stop offset=".3" stop-color="#b9af95"/><stop offset=".55" stop-color="#d6ccb2"/><stop offset=".81" stop-color="#8a8069"/><stop offset="1" stop-color="#57503f"/></linearGradient>
 <linearGradient id="rock" x1="0" y1="0" x2="1" y2=".1"><stop stop-color="#a29a86"/><stop offset=".3" stop-color="#aca38d"/><stop offset=".68" stop-color="#8b816c"/><stop offset="1" stop-color="#5a5243"/></linearGradient>
 <linearGradient id="base" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#beb39a"/><stop offset=".25" stop-color="#b1a58c"/><stop offset=".4" stop-color="#8c8068"/><stop offset=".68" stop-color="#655943"/><stop offset="1" stop-color="#443b2c"/></linearGradient>
 <radialGradient id="shade"><stop stop-color="#544b39" stop-opacity=".76"/><stop offset="1" stop-color="#544b39" stop-opacity="0"/></radialGradient>
 <radialGradient id="light"><stop stop-color="#eee4c9" stop-opacity=".6"/><stop offset="1" stop-color="#eee4c9" stop-opacity="0"/></radialGradient>
 <filter id="reliefSoft"><feGaussianBlur stdDeviation=".13"/></filter>
 <filter id="soft"><feGaussianBlur stdDeviation=".55"/></filter>
 <filter id="broadSoft"><feGaussianBlur stdDeviation="1.1"/></filter>
''',f'<clipPath id="outer"><path d="{silhouette}" clip-rule="evenodd"/></clipPath></defs>', '<g clip-path="url(#outer)">'])
    path(silhouette,'url(#stone)')
    # Base, support, and deep rear planes. These remain behind the anatomical curves.
    path('M.1 191 C4 187 13 186 20 187 C31 184 45 184 51 188 C60 191 64 193 65 198 L65 211 L0 211Z','url(#base)')
    ellipse(34,196.4,32,8.9,'#b9ad91',.75)
    path('M1 198 C12 204 26 205 38 202 C51 202 61 200 65 197 L64 204 C46 210 17 210 2 203 Z','#7a6d55',.7)
    line('M3 201 C16 206 41 207 60 201','#d0c3a6',.7,.35)
    path('M.8 185 C6 173 7 162 9 153 C10 149 14 146 17 142 C20 139 22 140 25 144 C29 153 31 167 34 177 C36 185 35 192 34 197 C27 204 12 204 3 198 Z','url(#rock)')
    path('M23 142 C26 155 27 172 29 183 C31 191 31 196 27 200 C30 200 34 198 36 195 L36 179 L29 151Z','#554d3e',.46)
    path('M4 187 C9 182 12 179 14 172 C14 162 17 150 20 144 C15 153 14 166 10 173 C8 178 4 181 4 187Z','#c1b79d',.6)
    path('M52 116 C58 120 61 124 60 132 C60 137 64 146 63 153 C65 159 61 161 57 159 C53 157 49 152 45 145 L42 137Z','url(#rock)')
    path('M53 121 C57 126 56 133 58 135 C60 142 58 149 61 154 L55 157 L47 144Z','#5b5141',.65)
    line('M52 128 Q57 132 58 135 M53 141 Q59 144 60 149','#b0a187',.65,.55)
    # Rear leg and planted foot.
    path('M21 94 C24 98 31 101 37 106 C37 111 34 118 32 124 C30 133 27 142 27 148 C29 158 34 171 37 181 C39 185 45 189 51 191 C54 192 59 191 62 194 C58 197 47 197 43 195 C35 190 32 183 29 173 C23 159 22 153 20 145 C18 140 19 135 19 131 C18 122 17 113 18 104Z','url(#rearLeg)')
    path('M29 112 C32 118 29 132 25 140 C23 145 22 147 23 152 C20 147 20 140 21 134 C22 124 23 115 23 109Z','#c4baa0',.3)
    line('M22 142 C24 146 25 151 25 155','#635a47',.8,.65)
    # Front hip, bent knee and crossing lower leg.
    path('M51 92 C57 95 56 102 54 109 C51 119 46 127 42 135 C40 140 38 144 39 149 C42 156 46 164 48 171 C50 178 52 181 54 184 C57 187 61 190 62 193 C59 195 55 194 51 192 C46 189 45 182 42 177 C37 169 32 163 30 156 C28 151 27 147 28 141 C29 131 32 122 35 114 C37 107 43 99 51 92Z','url(#leg)')
    path('M46 106 C43 116 37 128 33 140 C31 146 31 150 33 154 C29 151 29 146 30 141 C32 128 35 118 39 110Z','#e0d5b9',.39)
    path('M53 101 C52 113 45 126 41 137 C38 144 37 146 40 151 C36 148 35 144 38 136 C43 122 48 115 49 105Z','#786f59',.33)
    ellipse(34.4,147.9,6.8,7.2,'url(#light)',.65)
    path('M33 149 C36 148 39 150 40 154 C41 158 41 161 43 164 C39 161 36 158 35 155Z','#aaa17f',.48)
    path('M42 166 C44 173 46 178 49 181 C48 178 47 173 47 169 C46 167 45 166 42 166Z','#e2d6b5',.24)
    path('M49 180 C51 183 52 188 55 191 C58 192 60 192 62 193 C57 195 53 192 51 190 C49 187 48 183 49 180Z','#6f624c',.55)
    line('M54 189 Q57 190 60 191 M52 190 Q55 192 57 192','#4b422f',.38,.55)
    # Pelvis and torso: broad round planes, no polygonal facet shading.
    path('M24 57 C30 54 44 55 55 56 C60 63 58 69 57 75 C58 82 56 89 52 96 C49 100 44 101 40 104 C38 108 37 111 35 113 C32 114 29 110 30 106 C25 105 22 102 20 98 C18 93 21 86 21 80 C20 74 19 66 24 57Z','url(#body)')
    path('M23 72 C24 77 24 80 24 85 C23 91 22 94 24 97 C27 102 31 103 36 103 C30 100 28 96 27 91 C26 84 28 76 26 71Z','#e3d8bc',.34)
    path('M49 61 C50 68 48 72 51 78 C53 84 49 90 47 95 C51 93 54 90 54 85 C55 75 57 69 55 63Z','#776e58',.27)
    ellipse(36.3,81.2,13.4,17.5,'url(#light)',.47)
    ellipse(44.2,87.1,10.8,15.4,'url(#shade)',.29)
    path('M29 73 C32 72 36 73 38 75 C39 79 40 81 39 85 C37 80 35 78 31 77Z','#f0e4c8',.17)
    path('M34 96 C39 96 43 94 47 91 C43 97 40 101 34 101 C30 100 27 98 26 97 C29 98 31 98 34 96Z','#6e634d',.27)
    path('M26 99 C30 103 33 103 36 103 C39 102 43 100 46 97 C43 102 39 104 36 105 C33 106 28 103 26 99Z','#e2d5b6',.46)
    ellipse(37.6,85.3,1.35,1.8,'url(#shade)',.8)
    path('M37.6 84.7 Q38.7 84.9 38.0 86.2 Q37.0 86.6 37.2 85.5Z','#61533e',.7)
    line('M38.2 86.2 Q37.4 87.0 36.6 86.9','#eee0c0',.45,.63)
    path('M30 105 C32 106 35 107 36 108 C35 109 33 110 33 112 C31 110 29 108 30 105Z','#70614a',.75)
    path('M33 110 Q37 111 36 114 Q33 115 31 113Z','#65513b',.75)
    # Raised arm, including oblique forearm and the visible vertical upper-arm mass.
    path('M42 44 C47 42 48 37 48 30 L48.4 15 C47.7 13 47 10 48 7 C49 3 51 1 53 .4 C56 .6 58 3 58.7 6 C59.9 10 60 17 60 23 L60.7 42 C60.4 46 62 50 61.8 54 C57 57 51 53 48 49Z','url(#arm)')
    path('M48.5 5 C45 9 41 12 37 16 C35 18 33 20 31 22 L36 26 C40 22 44 18 49 14 C51 13 53 10 53 8Z','url(#arm)')
    path('M49 9 C45 13 42 14 39 18 C37 21 35 22 34 23 L37 25 C42 21 44 18 48 16 C51 14 52 11 52 10Z','#756b54',.65)
    path('M53 7 C51 13 51 22 52 29 C52.6 36 54 43 57 47 C54 38 55 31 55 23 C55 17 56 11 55 6Z','#ded4b7',.32)
    path('M57 12 C58 18 57 26 57.7 33 C58 37 59 41 60 44 L60 20 C60 16 59 12 57 12Z','#716954',.45)
    path('M48 35 C49 41 49 47 52 50 C50 51 47 48 46 47Z','#716650',.52)
    line('M51 5 Q53 3 54 4 M50 7 L52 5','#ebe0c3',.6,.7)
    # Neck, shoulder girdle and the left upper arm.
    path('M28 37 C30 42 29 45 27 47 C23 45 19 43 17 47 C13 50 13 54 14 59 C18 62 22 62 27 59 C33 56 44 55 52 55 C51 51 45 48 42 45 L39 35Z','url(#neck)')
    path('M32 41 C33 44 34 47 38 49 C37 45 39 41 39 38Z','#6e634e',.45)
    path('M18 47 C15 50 15 55 15 58 C18 56 19 52 23 50 C25 49 29 50 33 50 C28 47 23 45 18 47Z','#dcd4bc',.6)
    path('M15 54 C13 59 14 65 12 69 C11 73 8 77 7.5 81 C8 85 11 86 14 84 C18 80 19 75 20 70 C21 67 25 65 27 64 L26 60 C22 59 19 61 17 64 C16 61 17 57 15 54Z','url(#arm)')
    path('M11 75 C12 71 15 66 17 65 C19 64 20 65 21 66 C18 67 17 72 16 75 C14 79 12 82 11 82 C9 81 10 78 11 75Z','#d7ceb7',.7)
    path('M16 69 C16 75 13 79 11 82 C13 82 15 80 16 78 C18 73 18 70 19 68Z','#746a54',.53)
    # Cloth ribbon across chest, with curved rolled edges.
    path('M19 54 C24 51 31 51 37 51 C44 50 50 49 55 51 C58 52 61 55 60 58 C52 55 46 55 39 56 C30 57 24 57 19 60 C17 60 17 56 19 54Z','url(#cloth)')
    line('M20 54 C30 51 40 52 48 50.8 C53 50.3 56 51.2 58 53','#f1e7ce',.7,.73)
    path('M19 59 C27 56 33 57 40 56 C47 55 54 56 59 57 C57 59 55 60 51 60 C45 59 42 60 39 61 C31 62 25 61 20 63Z','url(#cloth)')
    line('M23 60 C32 59 38 59.3 44 58.2 C49 57.5 54 57.7 57 58.4','#e7d9b9',.65,.7)
    line('M22 61.7 C28 60.8 35 62 41 60.6 C48 59.2 52 60.3 57 59','#5c5140',.7,.72)
    path('M42 61 C42 65 42 68 40 70 C43 68 45 64 45 61Z','#5f543f',.43)
    # The near hand lies across the chest, fingers directed toward the right.
    path('M18.3 65 C21 62 23 61 26 62 C28 63 29 64 31 65 L37 67 C39 67 40 69 38 69.7 L32 69 C29 68 27 68 25 67 C27 69 30 70 32 71 C28 71 25 69 22 68 C20 69 18 69 18.3 65Z','url(#face)')
    path('M24 62 C26 60.6 28 61.7 30 62.1 L36 62.8 Q38 63.6 37 64.2 L29 64 C27 64 25 63 24 62Z','#c9bca0')
    line('M27 64 C30 65 33 66 37 66.8 M25 65.7 C29 67 32 68 36 68.4 M25 68 C27 69 30 70 32 70.4','#75664e',.4,.8)
    line('M24 63 C27 64 30 64.6 33 65.2','#e9ddbd',.48,.62)
    # Hair cap and turned face. Soft low-relief curls are carved, not outlined.
    path('M17.5 31 C16.5 27 18 23 20 21 C24 18 28 17 33 18 C37 19 39 22 40 25 C43 28 45 33 42 36 C43 40 40 43 36 43 C31 43 24 41 20 37Z','#857a61')
    path('M21 25 C23 23 27 23 30 24 C34 24 37 28 38 31 C38 35 35 40 31 42 C29 43 25 40 23 38 L20 35 C19 34 19 33 20 31 C19 29 20 27 21 25Z','url(#face)')
    path('M29 25 C30 28 30 30 28 32 C30 35 31 36 35 36 C34 39 32 40 31 42 C35 40 39 35 38 31 C36 28 34 25 29 25Z','#9f9376',.47)
    path('M22 28 C24 27 27 28 28 30 C25 29 23 30 22 30Z','#897c61',.5)
    line('M21.4 29.6 Q23.2 28.5 24.7 30.2','#5f553e',.62,.8)
    line('M22.6 28.6 Q24.6 28.8 25.4 30.1','#e7ddc1',.55,.7)
    path('M21.9 30 C21 31.4 19.5 32.5 19.8 33.5 L22.3 34.1 L23.5 33.4 C22 32.8 23 31.2 23 30Z','#dfd2b1')
    path('M20.3 33.6 Q21.7 34.8 23.1 34.1','#6d5e43',.74)
    line('M22 35.6 Q23.8 35 25 36.2 Q23.8 37 22.6 36.5','#66573f',.53,.78)
    line('M23 37.2 Q24.3 37.7 25.5 37.2','#eee0bd',.5,.6)
    path('M22 38 C24 40 27 41 29 41 C27 42 24 40 22 38Z','#817155',.48)
    path('M34.4 29 C36.7 28.1 38.1 31.2 36.2 33.1 C35.3 33.8 34.5 32.1 35.1 31.2Z','#baac8e')
    line('M35.7 30 Q36.8 31 35.5 32','#73664e',.4,.75)
    # Crown curls: eighteen broad sculpted curls. Their rhythm follows the cap.
    curls=[(19.8,24,1.6,1.7),(21.3,21.5,1.9,1.6),(24.7,20,2,1.6),(28,19.6,2,1.7),(31.8,20.5,2,1.9),(35.4,22,1.8,2),(38,24.6,1.9,2.1),(39.5,28,1.6,2.2),(40.7,31.8,1.7,2.1),(40.4,35.7,1.5,2),(38.7,38.9,1.5,1.7),(18.5,27.5,1.2,1.7),(18.8,31,1.1,1.5),(22.6,24.1,1.5,1.3),(26,22.8,1.8,1.3),(29.5,23.5,1.5,1.6),(33.4,25.1,1.4,1.5),(37.1,27.7,1.4,1.5)]
    for i,(x,y,rx,ry) in enumerate(curls):
        ellipse(x+.2,y+.25,rx,ry,'#655b44',.43)
        path(f'M{x-rx*.8:.2f} {y+.2:.2f} C{x-rx:.2f} {y-ry:.2f} {x+rx*.6:.2f} {y-ry:.2f} {x+rx*.75:.2f} {y:.2f} C{x+rx*.5:.2f} {y+ry*.5:.2f} {x-rx*.3:.2f} {y+ry*.4:.2f} {x-rx*.2:.2f} {y:.2f}', 'none',.85,'#c8bda0',.8)
    # Chisel striations are sparse strokes, placed on the supports only.
    rng=random.Random(1740)
    if TEXTURE:
        S.append('<g id="procedural-mineral-marks">')
        for i in range(135):
            y=rng.uniform(147,198); x=rng.uniform(1,28)
            if x<8+(198-y)*.17 and rng.random()<.65:continue
            dx=rng.uniform(.6,2.4);dy=rng.uniform(-1.6,.3)
            line(f'M{x:.2f} {y:.2f} q{dx*.6:.2f} {dy:.2f} {dx:.2f} {dy*.8:.2f}', '#d8ccb1' if i%3 else '#5f5747',rng.uniform(.16,.42),rng.uniform(.1,.32))
        # Fine low-contrast mineral fissures on anatomical surfaces.
        veins=[('M54 17 q-.7 2 -.4 4 t-.2 3',.12),('M53 31 q1 2 .5 4',.14),('M48 69 q-1 2 -.4 4 t-.9 2',.1),('M30 78 q.6 1.8 -.1 3',.1),('M33 90 q1 1 2 .5',.12),('M43 116 q-1 2 -.6 4',.12),('M36 131 q.5 1 -.4 2.5',.13),('M40 159 q1 2 1.4 3',.13),('M23 118 q-.4 1.3 .2 3',.12)]
        for d,o in veins:line(d,'#655e4c',.23,o)
        S.append('</g>')
    relief,n_contours=reference_relief()
    S.append(relief)
    # Explicit sculpture refinements after the broad reference relief. These are
    # hand-placed curved marks, not a general contrast/filter operation.
    S.append('<g id="sculptural-occlusion-refinements" opacity=".42">')
    # Correct the facial landmarks from an enlarged coordinate study. The near
    # eye is low, at (23, 33), rather than the forehead-level eye of pass 1.
    path('M20.4 30 C21.8 30.1 23.4 30.8 24.5 31.4 L23.8 32 C22.9 31.3 21.4 31 20.4 30.7Z','#78684b',.78)
    path('M23 32.3 Q24.1 32.1 24.3 33 Q23.9 33.5 23.4 33.4 L23.1 32.9Z','#30291c',.68)
    line('M22.8 31.5 Q24.1 31.6 24.7 32.3','#eee2c2',.55,.78)
    path('M20.2 30.5 C20 31.6 19 32.2 18.9 33.5 L20.1 34.8 L21.4 34.5 C20.1 33.4 21 32 21.4 31.4Z','#e6d6b4',.78)
    path('M20.1 34.6 Q21.1 35.2 22.2 34.5 L21.7 35.5 L20.5 35.4Z','#5a452d',.66)
    path('M25.1 32 C26.7 31.6 28.5 32.4 29 33.8 C28.8 35.2 27.8 36 25.9 36.3 L24.4 35.5 C24.9 34.7 25.1 33.8 25.1 32Z','#d7c9a9',.42)
    line('M22.2 36.4 Q23.3 36.9 24.1 37.7','#57432e',.4,.64)
    line('M23 37.5 Q23.9 38.2 24.8 38.2','#e1cfaa',.28,.5)
    path('M26.4 39.8 Q29 40.1 32.8 38.4 L32.1 39.3 Q29.1 40.6 27.2 40.4Z','#716044',.45)
    path('M29.6 41 C30.8 41.8 32.2 42.5 33.2 43.3 C33 44.5 32.6 45.2 32.9 46 C31.1 44.7 30.5 43 29.6 41Z','#51422d',.67)
    path('M37 35.2 Q36.9 39.1 36.2 42.5 L36.8 44.6 Q35.1 42.1 36.2 38Z','#c9b795',.27)
    # Deep throat turn and arm-to-chest junction, kept irregular and short.
    path('M26.9 41.3 C28.1 42 30 43.3 30.9 45.1 C31.8 46.5 32.5 47.1 32.2 48.1 C30.8 47 29.2 45.5 28.5 43.9Z','#514833',.27)
    path('M29.1 60.7 C33 60.1 36 59.6 40.8 59.5 C40 61.2 39.1 62.1 38.4 64 C37 64 35.7 63.3 34 63.2 C32 62.3 31 61.9 29.1 60.7Z','#3b3224',.42)
    path('M26.2 68.2 C29.7 69.4 34.4 70.7 38.1 69.3 C37.6 71.5 34 73.9 31.4 74 C30.2 73.8 28.5 72.8 27.4 72Z','#3e3527',.33)
    # Selectively crisp carved cloth edges. Intervals and strengths vary; there
    # is no uniform stroke outlining the whole statue.
    path('M20.1 56.6 C23.8 54.3 27.2 53.7 31.2 52.7 C36.8 52.2 41.4 51.9 46.4 51.1 L46.7 51.8 C41.6 52.9 36.2 52.8 31.6 53.5 C27.1 54.2 23.4 55.4 20.1 57.4Z','#4f442f',.73)
    line('M23 54.4 C27 52.9 31.8 52.1 37.5 51.8','#e3d6b5',.6,.68)
    path('M29.8 57.2 C33.9 57.6 37.1 58.1 40.2 57.5 C45.9 55.9 51.3 55.8 55.4 56.8 L54.8 57.7 C49.8 57.1 46 57.3 40.5 58.8 C37.1 59.1 34.2 58.4 31.3 58.2Z','#41331f',.88)
    line('M35.2 55.4 C41 55.3 45.5 54.1 50 54.6','#ded0ad',.65,.74)
    # A broad connected wrist/palm with three tapering finger planes. The dark
    # spaces are below the fingers, preserving their pressure against the cloth.
    path('M20.8 62.3 C23.5 61.4 25.7 61.8 28.3 63.3 C30.4 64.8 31.7 66.1 31.9 67.5 C29.8 67.6 28.2 66.6 26.4 66.4 C24.3 65.1 22 65 20.7 65.5Z','#b2a181',.63)
    path('M27.2 62.3 C29.9 62.8 32.3 64.4 34.7 64.8 C36 65.2 37.3 65 37.5 65.8 C36.1 66.2 34.2 65.8 32.8 65.4 C30.1 64.7 28.5 63.5 27.2 62.3Z','#d2c19f',.86)
    path('M28.2 64.8 C30.5 65.8 32.7 66.9 35.8 67.2 C36.8 67.5 36.7 68.2 35.8 68.3 C32.6 68 29.7 66.3 28.2 64.8Z','#c5b18d',.88)
    path('M27.1 66.9 C29.6 68.2 31.7 68.9 34 69.1 C35.5 69.5 35.1 70.1 33.8 70.1 C30.9 69.8 28.7 68.5 27.1 66.9Z','#bba47f',.81)
    path('M31.9 65.7 C33.5 66 35.5 66.5 37.6 66.2 L37.8 66.9 C36 67.2 33.9 66.6 31.9 65.7Z','#44331e',.8)
    line('M30.1 68.1 Q33.4 69.3 35.5 68.8','#46321c',.5,.78)
    path('M22.5 68.2 C26 70 28.9 71 32.5 71.5 C34.2 71.6 35.8 71.2 37.3 70.6 C36.1 72.5 33.7 73 31.7 72.7 C28.3 72.2 25.2 70.9 22.5 69.7Z','#342718',.65)
    # Crossed leg: broad lit knee, rolled rather than ruled-edge shading.
    ellipse(34.3,146.1,4.2,5.8,'url(#light)',.18)
    path('M39.8 156 C42.2 162.7 45.6 168.5 46.8 173.9 C47 176.8 48.4 180.7 50 183 C46.7 179.8 46 175.5 44.5 172.9 C42.4 168.1 39.8 162.8 38.8 158.7Z','#594d36',.19)
    path('M37 182 C38.5 186 41 189.4 46 191.5 C42 192 38.8 190.3 36 187.8Z','#3c3223',.27)
    # Rolled front-knee rim and a hard cast shadow where it crosses the rear leg.
    path('M29.8 139 C28.3 143 27.2 145.1 27.8 148 C28 150.1 29.1 151.9 30.6 153 L30.9 151.7 C29.9 150.2 29.4 148.7 29.2 147 C28.9 144.8 29.5 141.9 29.8 139Z','#ded0b0',.72)
    path('M30.3 151.1 C32.3 151.8 34 150.9 35.3 149.9 C34.7 152 34.6 153.4 35.5 155.6 C33.5 154.7 31.7 153.1 30.3 151.1Z','#807052',.62)
    path('M26 148.9 C27.3 151.8 27.5 153.9 29.6 155.8 C31.5 157.7 32.3 160.2 33.8 161.8 L33.3 163 C30.7 161 29.7 158.6 28 156.5 C26.5 154.2 25.7 151.5 25.5 149.7Z','#362918',.76)
    path('M40.7 140.9 C39.1 144 39.2 146.9 41.1 149.1 L40.1 150 C38.2 147.2 38.4 144.1 40.7 140.9Z','#3a2b1a',.73)
    line('M34.9 150.1 C36.4 151.5 37.5 154.5 38.4 156.6','#c4b18a',.75,.48)
    S.append('</g>')
    S.append('</g>')
    write_part(OUT,[0,0,65,211],''.join(S))
    render(OUT,520,ROOT/f'previews/statue-{REVISION}-8x.png')
    render(OUT,65,ROOT/f'previews/statue-{REVISION}-1x.png')


def comparisons():
    orig=Image.open(REF).convert('RGBA'); new=Image.open(ROOT/f'previews/statue-{REVISION}-1x.png').convert('RGBA')
    # Identical resampling and backdrops ensure shape, registration and apparent size comparisons.
    for scale in (1,4,8):
        pad=12 if scale==1 else 24;label=22;w,h=65*scale,211*scale
        board=Image.new('RGB',(w*2+pad*3,h+label+pad*2),'#383b3e')
        dr=ImageDraw.Draw(board)
        for j,(name,im) in enumerate([('Original',orig),('R1 / pass '+REVISION[1:],new)]):
            x=pad+j*(w+pad);dr.text((x,pad),name,fill='#eee9dc')
            board.paste(im.resize((w,h),Image.Resampling.LANCZOS),(x,pad+label),im.resize((w,h),Image.Resampling.LANCZOS))
        board.save(ROOT/f'qa/statue-compare-{REVISION}-{scale}x.png')
    import shutil
    shutil.copyfile(ROOT/f'qa/statue-compare-{REVISION}-4x.png',ROOT/'previews/statue-original-new.png')
    # Raw native render and reference share exact width/height; alpha statistics are repeatable.
    aa=np.asarray(orig)[:,:,3]/255; bb=np.asarray(new)[:,:,3]/255
    a=aa>.35;b=bb>.35
    metrics={'revision':REVISION,'native_size':[65,211],'alpha_iou':round(float((a&b).sum()/(a|b).sum()),5),'reference_alpha_area':int(a.sum()),'redraw_alpha_area':int(b.sum()),'relative_alpha_area_change':round(float(b.sum()/a.sum()-1),5),'source_technique':'Reference-assisted fitted alpha silhouette; hand-authored editable organic anatomical paths and smooth gradients; seeded sparse mineral strokes. Fifteen smoothed reference-derived broad relief isophotes preserve volume/occlusion. No raster image or pixel-colour mosaic; explicitly hybrid, not pure freehand.'}
    (ROOT/f'qa/statue-{REVISION}-metrics.json').write_text(json.dumps(metrics,indent=2))
    print(json.dumps(metrics,indent=2))

if __name__=='__main__':build();comparisons()
