from pathlib import Path
import argparse,hashlib,json
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True);a=parser.parse_args()
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017'
def lp(p):
    value=str(Path(p).resolve());return Path(value if value.startswith('\\\\?\\')else'\\\\?\\'+value)
read=lambda p:lp(p).read_bytes();load=lambda p:json.loads(read(p).decode('utf-8-sig'));sha=lambda b:hashlib.sha256(b).hexdigest()
previous=load(O/'prior-sealed-evidence-verification-20261018.json');checked={};packages=[]
for original in previous:
    path=R/original['path'];data=read(path);assert sha(data)==original['sha256'],str(path)
    manifest=json.loads(data.decode('utf-8-sig'));files=manifest['files'];assert len(files)==original['files']
    for row in files:
        name=(path.parent/row['path']).relative_to(R).as_posix();content=read(R/name)
        assert sha(content)==row['sha256'],name
        if 'bytes'in row:assert len(content)==row['bytes'],name
        if name in checked:assert checked[name]==row['sha256']
        checked[name]=row['sha256']
    packages.append(original)
report={'ok':True,'sealedPackages':len(packages),'uniqueFilesVerified':len(checked),'packages':packages,
    'boundary':'Every prior integrity manifest retains its original hash and every entry still matches; current calibration evidence is sealed separately.'}
with lp(a.output).open('x',encoding='utf8')as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps({'ok':True,'sealedPackages':len(packages),'uniqueFilesVerified':len(checked)}))
