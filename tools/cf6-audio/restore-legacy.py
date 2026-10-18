"""Restore hash-bound missing native SFX files without changing original authoring assets."""
from pathlib import Path
import argparse,hashlib,json,zlib
from lxml import etree as E
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
NS={'x':'http://ns.adobe.com/xfl/2008/'}
parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
config=json.loads((HERE/'legacy-assets.json').read_text('utf8'))
for row in config['files']:
    source=ROOT/row['source'];target=ROOT/row['target'];data=source.read_bytes()
    assert hashlib.sha256(data).hexdigest()==row['sha256'] and len(data)==row['bytes']
    assert zlib.crc32(data)&0xffffffff==row['sourceCrc32']
    metadata=E.parse(str(ROOT/row['sourceMetadata'])).find('.//x:DOMSoundItem[@name="'+source.name+'"]',NS)
    assert int(metadata.get('externalFileCRC32'))==row['sourceCrc32'] and int(metadata.get('externalFileSize'))==row['bytes']
    if args.write:
        if target.exists():assert target.read_bytes()==data,'Preserve an independently supplied SFX'
        else:
            with target.open('xb') as f:f.write(data)
    assert target.read_bytes()==data
print(json.dumps({'ok':True,'restoredFiles':len(config['files']),'bytes':sum(r['bytes'] for r in config['files'])}))
