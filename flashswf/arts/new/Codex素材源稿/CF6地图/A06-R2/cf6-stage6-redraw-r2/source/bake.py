from pathlib import Path
import xml.etree.ElementTree as ET
from svg_native import render
R=Path(__file__).resolve().parents[1];(R/'baked').mkdir(exist_ok=True)
for p in sorted((R/'parts').glob('bitmap-*.svg')):
 vb=list(map(float,ET.parse(p).getroot().get('viewBox').split()));render(p,round(vb[2]*2),R/'baked'/(p.stem+'.png'))
p=R/'parts/background-1762.svg';render(p,3046,R/'baked/background-1762.png')
