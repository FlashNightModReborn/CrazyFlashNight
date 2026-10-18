"""Read-only checks for the remaining content scope while the frozen arena run executes."""
from pathlib import Path
import datetime,hashlib,json,subprocess
R=Path.cwd();O=R/'tmp/cf6-combat-calibration-20261017';out=O/'static-r14';out.mkdir(exist_ok=False)
commands=[]
for family in ['headbot','bladebot']:
    commands.append((family+'-verify',['python','-X','utf8','-B','tools/cf6-'+family+'-assets/verify.py']))
for family in ['guard','manman','soldier','wings','zombie']:
    commands.append((family+'-generated',['python','-X','utf8','-B','tools/cf6-'+family+'-assets/build.py']+([] if family=='zombie' else ['--check'])))
commands.extend([
 ('arena-catalog',['node','tools/derive-arena-unit-catalog.js','--check']),
 ('audio-fixture',['python','-X','utf8','-B','tools/cf6-audio/build-test-fixture.py','--check']),
 ('legacy-audio-fixture',['python','-X','utf8','-B','tools/cf6-audio/build-legacy-test-fixture.py','--check']),
 ('playtest-fixture',['python','-X','utf8','-B','tools/cf6-elder-assets/build-playtest-fixture.py','--check']),
 ('production-class-ownership',['node','tools/audit-as2-class-embedding.js'])
])
bindings=[]
for family in ['headbot','elder','bladebot','guard','manman','soldier','wings','zombie']:
    rel='tools/cf6-'+family+'-assets/native-manifest.json';raw=(R/rel).read_bytes();m=json.loads(raw.decode('utf-8-sig'))
    bindings.append({'path':rel,'sha256':hashlib.sha256(raw).hexdigest()})
    for row in m.get('buildInputs',[]):
        rel=row['path'];b=(R/rel).read_bytes();bindings.append({'path':rel,'sha256':hashlib.sha256(b).hexdigest()})
results=[]
for name,command in commands:
    started=datetime.datetime.now(datetime.timezone.utc).isoformat()
    with (out/(name+'.log')).open('xb') as log:result=subprocess.run(command,cwd=R,stdout=log,stderr=subprocess.STDOUT)
    results.append({'name':name,'command':command,'startedAtUtc':started,'exitCode':result.returncode})
    print(json.dumps({'check':name,'exitCode':result.returncode}),flush=True)
for row in bindings:assert hashlib.sha256((R/row['path']).read_bytes()).hexdigest()==row['sha256'],row['path']
summary={'ok':all(r['exitCode']==0 for r in results),'checks':results,'inputBindings':bindings,'bindingsUnchanged':True,'elderVerification':'../verify-elder-r14.log','boundary':'Static generation, authored formulas and production SWF ownership checks; no game launch, source edits or runtime promotion.'}
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),'utf8')
raise SystemExit(0 if summary['ok'] else 1)
