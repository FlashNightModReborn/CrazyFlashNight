from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parents[1]
for script,args in [('build_art.py',[]),('assemble.py',['--stand-only','--parts','--workers','3']),('compare_r7.py',[])]:
 subprocess.run([sys.executable,str(r/'source'/script)]+args,check=True)
