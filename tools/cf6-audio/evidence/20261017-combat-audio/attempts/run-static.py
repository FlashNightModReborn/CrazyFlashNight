from pathlib import Path
import concurrent.futures,json,subprocess,sys
ROOT=Path.cwd();OUT=ROOT/'tmp/cf6-combat-audio-20261017'/(sys.argv[1] if len(sys.argv)>1 else 'static-pass1');OUT.mkdir(exist_ok=False)
jobs=[]
for family in ['headbot','elder','bladebot','zombie','manman','wings','soldier','guard']:
    jobs.append((family,['python','-X','utf8','-B','tools/cf6-'+family+'-assets/verify.py']))
jobs.extend([('audio-exact',['python','-X','utf8','-B','tools/cf6-audio/extract.py','--source-swf','tmp/cf6-headbot-20261016/original-source.swf']),
    ('legacy-exact',['python','-X','utf8','-B','tools/cf6-audio/restore-legacy.py']),
    ('arena-derived',['node','tools/derive-arena-unit-catalog.js','--check'])])
def run(job):
    name,cmd=job
    with (OUT/(name+'.log')).open('xb') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
    return {'name':name,'command':cmd,'exitCode':r.returncode}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:rows=list(pool.map(run,jobs))
(OUT/'results.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n','utf8')
print(json.dumps(rows,ensure_ascii=False));raise SystemExit(1 if any(r['exitCode'] for r in rows) else 0)
