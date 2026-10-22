from pathlib import Path
import sys,subprocess
R=Path(__file__).resolve().parent
for name in ['parts','previews','baked','qa']:(R.parent/name).mkdir(exist_ok=True)
for name in ['reuse.py','cars.py','terrain_sky.py','soil_material.py','ruins.py','wreck_props.py','assemble_stage.py','boards.py','bake.py','panorama.py','blade_review.py','verify.py']:
 subprocess.run([sys.executable,str(R/name)],check=True)
