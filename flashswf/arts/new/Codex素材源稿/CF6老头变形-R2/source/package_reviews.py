from pathlib import Path
import zipfile,hashlib,json
R=Path(__file__).resolve().parents[1];files=sorted(p for p in (R/'previews').rglob('*') if p.is_file());groups=[];group=[];size=0
# Conservative uncompressed budgeting; each archive is an ordinary independent ZIP.
for p in files:
 if group and size+p.stat().st_size>12500000:groups.append(group);group=[];size=0
 assert p.stat().st_size<15000000
 group.append(p);size+=p.stat().st_size
groups.append(group);out=[]
for i,gg in enumerate(groups,1):
 zp=R.with_name(R.name+f'-review-{i:02d}.zip')
 with zipfile.ZipFile(zp,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
  z.write(R/'README.txt','README.txt')
  for p in gg:z.write(p,str(p.relative_to(R)))
 assert zp.stat().st_size<15000000
 out.append({'file':str(zp),'bytes':zp.stat().st_size,'sha256':hashlib.sha256(zp.read_bytes()).hexdigest(),'files':[str(p.relative_to(R)) for p in gg],'ordinaryIndependentZip':True})
(R.parent/(R.name+'-review-delivery.json')).write_text(json.dumps(out,indent=2));print(json.dumps(out,indent=2))
