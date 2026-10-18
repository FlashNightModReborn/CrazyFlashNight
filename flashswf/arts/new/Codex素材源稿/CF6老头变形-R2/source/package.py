from pathlib import Path
import json,hashlib,zipfile
R=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def select(p):
 q=p.relative_to(R);s=q.parts
 if '__pycache__' in s:return False
 if s[0] in ['source','reference','parts','audio']:return q.suffix in ['.py','.json','.svg','.txt','.bin','.png','.mp3']
 if s[0]=='qa':return len(s)==2 and q.suffix in ['.json','.txt'] and q.name!='package-checksums.json'
 return q.name=='README.txt'
files=[p for p in sorted(R.rglob('*')) if p.is_file() and select(p)];(R/'qa/package-checksums.json').write_text(json.dumps({str(p.relative_to(R)):sha(p) for p in files},indent=2));files.append(R/'qa/package-checksums.json');z=R.with_name(R.name+'-source.zip')
with zipfile.ZipFile(z,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as f:
 for p in files:f.write(p,R.name+'/'+str(p.relative_to(R)))
assert z.stat().st_size<15000000
out={'file':str(z),'bytes':z.stat().st_size,'sha256':sha(z),'files':len(files),'selfContained':True};(R.parent/(R.name+'-source-delivery.json')).write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
