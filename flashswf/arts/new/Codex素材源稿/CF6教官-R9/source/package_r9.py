from pathlib import Path
import json,zipfile,hashlib
B=Path(__file__).resolve().parents[1]
keep=['README.md','parts','variants','reference/r8','reference/R8_PROVENANCE.md','reference/baseline/CF6特种兵-R3/parts/487.svg','reference/timelines.json','reference/238.svg']
keep+=['source/'+n for n in ['assemble.py','build_r9.py','validate_r9.py','compose_r9_review.py','package_r9.py']]
keep+=['qa/'+n for n in ['r9-change-scope.json','validation-r9.json','cold-rebuild-r9.json']]
for stem in ['教官R9-R8领胸近景','教官R9-R8同姿四格对照','教官R9-100pct双背景','instructor-unshielded','instructor-shielded']:
 for ext in ['svg','png']:keep.append('art/'+stem+'.'+ext)
files=[]
for n in keep:
 p=B/n
 if p.exists():files.extend([p] if p.is_file() else [x for x in p.rglob('*') if x.is_file() and '__pycache__' not in x.parts])
m={str(p.relative_to(B)):{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(set(files))};(B/'MANIFEST.json').write_text(json.dumps(m,ensure_ascii=False,indent=2));files.append(B/'MANIFEST.json')
out=B/'CF6-CT教官-R9-领扣暖铜呼应-完整可编辑源包.zip'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(set(files)):z.write(p,p.relative_to(B))
print(out,len(set(files)),out.stat().st_size)
