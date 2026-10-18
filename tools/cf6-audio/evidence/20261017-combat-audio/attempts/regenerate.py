from pathlib import Path
import subprocess,sys,json,datetime
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
attempt=HERE/(sys.argv[1] if len(sys.argv)>1 else 'regeneration-pass1')
attempt.mkdir(exist_ok=False)
rows=[]
for key in ['headbot','elder','bladebot','manman','wings','soldier','guard','zombie']:
 script=ROOT/f'tools/cf6-{key}-assets/build.py'
 compile(script.read_bytes(),str(script),'exec')
 args=[sys.executable,'-X','utf8','-B',str(script),'--import-approved']
 print('building',key,flush=True)
 with (attempt/(key+'.log')).open('w',encoding='utf8') as out:
  result=subprocess.run(args,cwd=ROOT,stdout=out,stderr=subprocess.STDOUT)
 rows.append({'unit':key,'exitCode':result.returncode})
 (attempt/'results.json').write_text(json.dumps(rows,indent=2)+'\n','utf8')
 if result.returncode:
  print((attempt/(key+'.log')).read_text('utf8')[-7000:]);sys.exit(result.returncode)
 print('generated',key,flush=True)
