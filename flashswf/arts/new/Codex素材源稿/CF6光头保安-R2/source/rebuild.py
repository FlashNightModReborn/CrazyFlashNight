from pathlib import Path
import subprocess,sys,argparse
R=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--assets-only',action='store_true');a=p.parse_args()
steps=['refine_core.py','refine_limbs.py','build_art.py','build_adaptations.py','verify.py']
if not a.assets_only:steps+=['render_all.py','make_previews.py','compare_revisions.py','check_fragments.py','audit_visual_outputs.py']
for name in steps:
 print('RUN',name,flush=True);subprocess.run([sys.executable,str(R/'source'/name)],check=True)
print('Rebuild complete. Runtime and CS6 verification not performed.')
