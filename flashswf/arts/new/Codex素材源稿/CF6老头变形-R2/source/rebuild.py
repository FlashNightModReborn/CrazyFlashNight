from pathlib import Path
import subprocess,sys,argparse,time
R=Path(__file__).resolve().parents[1];p=argparse.ArgumentParser();p.add_argument('--workers',default='4');a=p.parse_args();t=time.monotonic()
for script,args in [('assemble.py',['--workers',a.workers]),('verify.py',[]),('previews.py',[])]:subprocess.run([sys.executable,str(R/'source'/script),*args],check=True,cwd=R)
print('Full283-frame cold reconstruction completed in',round(time.monotonic()-t,2),'seconds.')
