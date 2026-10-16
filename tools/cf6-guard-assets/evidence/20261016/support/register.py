"""Scoped source-map generation using the canonical linkage scanner's XFL reader."""
import argparse
import re
from lxml import etree as E
import build


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
    scanner=build.module('guard_linkage_scanner',build.ROOT/'tools/linkage_scanner/scan_linkage.py')
    scanner.scan_xfl(str(build.OWNER))
    unique,duplicates,conflicts,orphans=scanner.classify_results()
    assert not duplicates and not conflicts and not orphans
    assert set(unique)=={build.ANCHOR,build.LINKAGE}
    path=build.ROOT/'data/items/asset_source_map.xml'
    original=path.read_text('utf8');text=original
    for linkage,(swf,symbol,orphan) in sorted(unique.items()):
        expected=E.Element('asset',id=linkage,swf=swf)
        if symbol!=linkage:expected.set('symbolName',symbol)
        root=E.fromstring(text.encode('utf8'))
        matches=[e for e in root if e.get('id')==linkage]
        if matches:
            assert len(matches)==1 and matches[0].tag=='asset' and matches[0].attrib==expected.attrib, 'Existing linkage has a different owner'
            continue
        line='  '+E.tostring(expected,encoding='unicode').replace('/>',' />')+'\n'
        following=next((e for e in root if e.tag=='asset' and e.get('id')>linkage),None)
        if following is not None:
            anchor='  <asset id="'+scanner.xml_safe(following.get('id'))+'"'
            index=text.index(anchor)
        else:
            last=list(re.finditer(r'^  <asset .*?/>\n',text,re.MULTILINE))[-1]
            index=last.end()
        text=text[:index]+line+text[index:]
    count=len(E.fromstring(text.encode('utf8')).findall('asset'))
    text,n=re.subn(r'<!-- \d+ unique assets -->',f'<!-- {count} unique assets -->',text)
    assert n==1
    if args.write and original!=text:path.write_text(text,'utf8',newline='\n')
    assert path.read_text('utf8')==text, 'Run register.py --write to update this library registration'
    print('Scoped linkage registration verified: '+', '.join(sorted(unique)))


if __name__=='__main__':main()
