"""Compact independently rebuildable R3 local-source package, no animation archive."""
from pathlib import Path
import zipfile,hashlib,json,re,base64
R=Path(__file__).resolve().parents[1];ids=[926,928,929,930,931,932,939,940]+list(range(941,951));files={'README.txt'}
files|={f'source/{s}' for s in ['build_art.py','assemble.py','compare_r3.py','verify_local.py','rebuild_local.py','restore_references.py','package_local.py','art-manifest.json']}
files|={str(p.relative_to(R)) for p in (R/'art').iterdir() if p.suffix in ['.svg','.txt']}
files|={f'parts/{i}.svg' for i in ids};files|={f'reference/shapes/{i}.svg' for i in ids}
files|={f'reference/{s}' for s in ['shape-manifest.json','timelines.json','keyposes.json','bitmaps/927.png','r2-review/929.png','r2-review/stand.png']}
files|={str(p.relative_to(R)) for p in (R/'previews').glob('*-original-r2-r3.png')}
files|={f'qa/{s}' for s in ['local-check.json','source-evidence.json','frame-coverage.json']}
contents={name:(R/name).read_bytes() for name in sorted(files)};bitmaps={hashlib.sha256(contents['reference/bitmaps/927.png']).hexdigest():'reference/bitmaps/927.png'};mapping={};hashes={};n=0
for name,bb in list(contents.items()):
 if not(name.startswith('reference/shapes/') and name.endswith('.svg')):continue
 hashes[name]=hashlib.sha256(bb).hexdigest()
 def repl(m):
  global n
  b=base64.b64decode(m.group(2));h=hashlib.sha256(b).hexdigest();file=bitmaps.get(h,f'reference/embedded-bitmaps/{h}.png');contents[file]=b;mapping[h]={'file':file,'prefix':m.group(1)};n+=1;return 'cf6-bitmap://'+h
 contents[name]=re.sub(r'(data:image/png;base64,)([A-Za-z0-9+/=]+)',repl,bb.decode()).encode()
contents['reference/embedded-bitmap-map.json']=json.dumps(mapping,indent=2).encode();contents['reference/source-svg-checksums.json']=json.dumps(hashes,indent=2).encode()
contents['qa/package-file-checksums.json']=json.dumps({n:hashlib.sha256(b).hexdigest() for n,b in sorted(contents.items())},indent=2).encode()
zpath=R.with_name(R.name+'-local-source.zip')
with zipfile.ZipFile(zpath,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for name,b in sorted(contents.items()):z.writestr(R.name+'/'+name,b)
assert zpath.stat().st_size<15000000
report={'file':str(zpath),'bytes':zpath.stat().st_size,'sha256':hashlib.sha256(zpath.read_bytes()).hexdigest(),'files':len(contents),'sourcePngReferencesLosslesslyDeduplicated':n,'uniqueEmbeddedPngs':len(mapping),'scope':'R3 local source and one standing pose; no full animation rerun','selfContainedLocalRebuild':True}
(R.parent/(R.name+'-delivery.json')).write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
