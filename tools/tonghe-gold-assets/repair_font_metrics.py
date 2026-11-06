"""Restore advances lost when exporting no-layout Font3 subsets as TrueType.

The old library's DefineText2 records use GlyphAdvance/TextHeight == 1 for all
characters in these three families. JPEXS guesses advances from each contour's
bounds because the embedded Font3 tags omit layout tables; those guesses must
not be used for a source-library rebuild. Requires fontTools only when rebuilding
the checked-in font subset files, not for ordinary publication.
"""
from pathlib import Path
import argparse
import hashlib
import json

def repair(directory):
    from fontTools.ttLib import TTFont
    changes=[]
    for path in sorted(directory.glob('*.ttf')):
        font=TTFont(path,recalcTimestamp=False)
        family=font['name'].getDebugName(1)
        # Original DefineText2 YOffset / TextHeight ratios, expressed in the
        # 1024-unit em. Flash rounds the baseline to whole source pixels.
        ascent={'STXingkai':751,'STFangsong':853,'STLiti':768}[family]
        font['hhea'].ascent=ascent
        font['OS/2'].usWinAscent=ascent
        font['OS/2'].sTypoAscender=ascent
        cmap=font.getBestCmap();updated=[]
        for code,name in cmap.items():
            if not 0x4e00<=code<=0x9fff:continue
            old,lsb=font['hmtx'].metrics[name]
            advance=font['head'].unitsPerEm
            font['hmtx'].metrics[name]=(advance,lsb)
            updated.append({'character':chr(code),'old_advance':old,'restored_advance':advance})
        if 'DSIG' in font:del font['DSIG']
        font.save(path)
        changes.append({'file':path.name,'restored':updated,'restored_ascent':ascent,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
    return changes

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
    print(json.dumps(repair(a.directory),ensure_ascii=False,indent=2))
