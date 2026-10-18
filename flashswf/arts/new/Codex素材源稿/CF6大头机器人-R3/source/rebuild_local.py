"""Cold-rebuild only the requested R3 local repair. Never launches a full frame run."""
from pathlib import Path
import subprocess,sys,time
R=Path(__file__).resolve().parents[1];t=time.monotonic()
def call(script,*args):subprocess.run([sys.executable,str(R/'source'/script),*args],cwd=R,check=True)
call('restore_references.py');call('build_art.py')
for p in [R/'reference/shapes/929.svg',R/'parts/929.svg']:
 subprocess.run(['inkscape',str(p),'--export-filename='+str(p.with_suffix('.png'))],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
call('assemble.py','--stand-only','--workers','2');call('compare_r3.py');call('verify_local.py')
print('R3 local cold rebuild complete:',round(time.monotonic()-t,2),'seconds. One standing pose; no 183-frame run.')
