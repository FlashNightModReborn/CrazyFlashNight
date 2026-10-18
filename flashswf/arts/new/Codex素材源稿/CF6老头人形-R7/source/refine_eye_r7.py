"""R7: only viewer-right orbit + its lower/nasal transition. Frozen R6 hair preserved."""
from pathlib import Path
import re,json,hashlib
R=Path(__file__).resolve().parents[1];old=(R/'reference/r6-review/963.svg').read_text();svg=old
D='''<linearGradient id="r7socketShadow" gradientUnits="userSpaceOnUse" x1="0" y1="49" x2="0" y2="64"><stop offset="0" stop-color="#1a1b13" stop-opacity=".95"/><stop offset=".33" stop-color="#272a1a" stop-opacity=".9"/><stop offset=".62" stop-color="#454833" stop-opacity=".6"/><stop offset="1" stop-color="#777454" stop-opacity="0"/></linearGradient><linearGradient id="r7nasalReturn" gradientUnits="userSpaceOnUse" x1="74" y1="0" x2="81" y2="0"><stop offset="0" stop-color="#252b1b" stop-opacity=".8"/><stop offset=".43" stop-color="#434a30" stop-opacity=".67"/><stop offset="1" stop-color="#7b7c56" stop-opacity="0"/></linearGradient><radialGradient id="r7lidTurn" cx="68%" cy="52%" r="75%"><stop offset="0" stop-color="#b2af92" stop-opacity=".8"/><stop offset=".55" stop-color="#95977c" stop-opacity=".4"/><stop offset="1" stop-color="#444d32" stop-opacity="0"/></radialGradient>'''
svg=svg.replace('</defs>',D+'</defs>')
def replace_path(prefix,new):
 global svg
 pattern=r'<path d="'+re.escape(prefix)+r'"[^>]*/>'
 svg,n=re.subn(pattern,lambda _:new,svg);assert n==1,(prefix,n)
replace_path('M75 51Q81 48.7 88 50L87 55Q86.6 58 84.8 59.5L84.1 61Q83 59.3 81.5 59.5L80 58Q77 57.5 75 51Z',
'''<g id="r7-right-orbit"><path d="M73.5 50.5Q80 47.8 88.5 49L88 54.8Q87.3 59 84 62.5Q81 63 78.5 59.8L74.5 57.5Z" fill="url(#r7socketShadow)"/><path d="M74 50Q76.5 53.7 75.5 59.2Q75.5 62.7 78.5 66L80 63Q77.5 57.3 79 51Z" fill="url(#r7nasalReturn)"/><path d="M75.2 51.5Q79.2 49.7 83.5 49.9L87.5 50.3Q88 52.2 87 54.8L85.8 54.2L84.6 55.3Q82.2 54.6 81.1 55.5L78.4 54.2Q76.6 54.3 75.2 53Z" fill="#12150f"/><path d="M77.5 54Q78 57.8 81 59.5L80.3 60.3Q77 58.5 76.4 55.5Z" fill="#2e3422" fill-opacity=".7"/></g>''')
replace_path('M78 60Q81 63 84 62L83 66L80 68L77 64Z',
'''<path d="M79 56Q84 57 86 55Q88 60 84.8 65Q82 67 80 63Q78.8 60 79 56Z" fill="url(#r7lidTurn)"/><path d="M81 56.2Q82.7 56.9 84.3 56.1" fill="none" stroke="#7b7d5b" stroke-opacity=".62" stroke-width=".35" stroke-linecap="round"/>''')
(R/'parts/963.svg').write_text(svg)
# All original hair source and hair gradient definitions remain literally identical.
hair_start='<path d="M3 38Q1 23';hair_end='</g><path d='
a=old[old.index(hair_start):old.index(hair_end,old.index(hair_start))];b=svg[svg.index(hair_start):svg.index(hair_end,svg.index(hair_start))];assert a==b
for gid in ['hair','hairlock']:
 pat=r'<radialGradient id="'+gid+r'".*?</radialGradient>';assert re.search(pat,old).group()==re.search(pat,svg).group()
(R/'qa/r7-eye-scope.json').write_text(json.dumps({'edited':'viewer-right eye cavity and minimal lower-lid/nasal transition','replacedOriginalPaths':2,'hairBodyByteIdentical':True,'hairGradientsByteIdentical':True,'source':'frozen R6 963.svg','sha256':hashlib.sha256(svg.encode()).hexdigest()},indent=2))
