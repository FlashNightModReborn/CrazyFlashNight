"""Refresh the changed owner using the canonical scanner and writer.

Preserves other owners from the existing map; a full repository scan remains
available through tools/linkage_scanner/scan_linkage.py --xml-only.
"""
from pathlib import Path
import argparse,importlib.util,tempfile
import xml.etree.ElementTree as E

ROOT=Path(__file__).resolve().parents[2]
OWNER='flashswf/arts/new/Codex专用素材.swf'
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    spec=importlib.util.spec_from_file_location('dog_linkage_scanner',ROOT/'tools/linkage_scanner/scan_linkage.py')
    scanner=importlib.util.module_from_spec(spec);spec.loader.exec_module(scanner)
    path=ROOT/'data/items/asset_source_map.xml';before=path.read_text(encoding='utf-8')
    tree=E.fromstring(before)
    for row in tree:
        if row.tag=='asset':sources=[row]
        elif row.tag in ('duplicate','conflict'):sources=list(row)
        else:raise ValueError('Unknown source-map entry: '+row.tag)
        lid=row.get('id')
        for source in sources:
            swf=source.get('swf')
            if swf==OWNER:continue
            scanner.results.setdefault(lid,set()).add((swf,source.get('symbolName',lid),source.get('orphan')=='true'))
    scanner.scan_xfl(str(ROOT/'flashswf/arts/new/Codex专用素材'))
    for lid in ('敌人-制式军警犬','敌人-盗贼撕咬犬'):
        rows=scanner.results[lid]
        assert len(rows)==1 and next(iter(rows))[0]==OWNER
    # Reuse the canonical output format in a scratch destination first.
    with tempfile.TemporaryDirectory(prefix='cf7-two-dogs-map-') as temp:
        scanner.OUTPUT_XML=str(Path(temp)/'map.xml');scanner.write_xml()
        after=Path(scanner.OUTPUT_XML).read_text(encoding='utf-8')
    old={r.get('id'):E.tostring(r) for r in tree}
    newtree=E.fromstring(after);new={r.get('id'):E.tostring(r) for r in newtree}
    # Whole-map semantic comparison prevents unrelated owners from drifting.
    for lid,raw in old.items():
        if lid not in ('敌人-制式军警犬','敌人-盗贼撕咬犬'):assert new[lid]==raw,('Unrelated mapping drift',lid)
    if args.check:assert before==after,'Regenerate the changed owner source map'
    else:path.write_text(after,encoding='utf-8',newline='\n')
    print('Two dogs source map: changed owner rescanned; other mappings preserved')
if __name__=='__main__':main()
