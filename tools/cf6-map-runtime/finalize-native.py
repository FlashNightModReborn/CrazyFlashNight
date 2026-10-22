"""Set exact publish targets after native CS6 image import; no Flash process control."""
from pathlib import Path
import argparse
import json
from native_xfl import finalize

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--index',type=Path,default=HERE/'generated/runtime-index.json')
parser.add_argument('--check',action='store_true')
parser.add_argument('--map',action='append',dest='maps',help='Only finalize an imported map and its dynamic targets; repeat for a batch')
args=parser.parse_args()
index=json.loads(args.index.read_text(encoding='utf-8'))
targets=[]
for m in index['maps']:
    if args.maps and m['id'] not in args.maps:continue
    dynamic_pngs={layer['png'] for layer in m['layers'] if 'png' in layer}
    # Runtime index lists source inputs in layer order; dynamic output carries sourcePng below.
    dynamic_pngs.update(layer['sourcePng'] for layer in m['layers'] if 'sourcePng' in layer)
    if m['layers'] and not dynamic_pngs:
        raise SystemExit('Regenerate runtime index with explicit dynamic sourcePng before finalizing '+m['id'])
    targets.append((m['xfl'],m['background'].rsplit('/',1)[-1],[row for row in m['inputs'] if row['path'] not in dynamic_pngs]))
    targets.extend((layer['xfl'],layer['url'].rsplit('/',1)[-1],[row for row in m['inputs'] if row['path']==layer['sourcePng']]) for layer in m['layers'])
for relative,swf,inputs in targets:
    source=(ROOT/relative).resolve()
    if not source.is_relative_to(ROOT/'flashswf/backgrounds/cf6') or not source.is_file():
        raise SystemExit('Native CS6 import missing or invalid: '+relative)
    report=finalize(source,swf,inputs,check=args.check)
    report['publishTarget']='flashswf/backgrounds/cf6/'+swf
    print(json.dumps(report,ensure_ascii=False))
