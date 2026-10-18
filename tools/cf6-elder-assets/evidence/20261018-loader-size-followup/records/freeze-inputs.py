from pathlib import Path
import datetime, hashlib, json, subprocess, sys, zipfile
R=Path.cwd()
D=R/'tmp/cf6-combat-calibration-20261017/loader-size-followup'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
phase=sys.argv[1]
names=subprocess.check_output(['git','ls-files','-z']).decode('utf8').split('\0')
names=sorted(n for n in names if n and (
    n.startswith('scripts/') and (n.endswith(('.as','.template','.ps1','.jsfl')) or n.startswith('scripts/asLoader/'))
    or n in ['tools/assemble-collapsed-frame.js','tools/swf-function-sizes.js','tools/swf-metadata.js','tools/audit-as2-class-embedding.js']))
rows=[{'path':n,'bytes':(R/n).stat().st_size,'sha256':sha(R/n)} for n in names]
data={'createdAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
      'baseCommit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
      'bindings':rows,'scratchOriginalSha256':sha(R/'scripts/TestLoader.as')}
if phase=='before':
    with zipfile.ZipFile(D/'actual-as2-source.zip','x',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for n in names:z.write(R/n,n)
    data['archiveSha256']=sha(D/'actual-as2-source.zip')
else:
    prior=json.loads((D/'inputs-before.json').read_text('utf8'))
    data['unchanged']=rows==prior['bindings'] and data['scratchOriginalSha256']==prior['scratchOriginalSha256']
    assert data['unchanged'],'Build/test source changed or scratch unrestored'
with (D/f'inputs-{phase}.json').open('x',encoding='utf8') as f:json.dump(data,f,ensure_ascii=False,indent=2)
print(json.dumps({'phase':phase,'files':len(rows),'sourceUnchanged':data.get('unchanged'),'scratchOriginalSha256':data['scratchOriginalSha256']}))
