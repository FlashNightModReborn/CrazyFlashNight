from pathlib import Path
import subprocess,sys,shutil
R=Path(__file__).resolve().parents[1]
for d in ['parts','previews','review','qa','baked']:(R/d).mkdir(exist_ok=True)
for p in (R/'reference/reused').glob('*.svg'):shutil.copy2(p,R/'parts'/p.name)
for s in ['lab_materials.py', 'lab_state_qa.py', 'assemble_scene.py', 'bake.py', 'verify.py']:subprocess.run([sys.executable,str(R/"source"/s)],check=True)
