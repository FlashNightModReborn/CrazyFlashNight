from pathlib import Path
import subprocess,sys,shutil
R=Path(__file__).resolve().parents[1]
for d in ['parts','previews','qa','baked']:(R/d).mkdir(exist_ok=True)
subprocess.run([sys.executable,str(R/'source/sky_material.py')],check=True)
for s in ['asphalt.py','river_arcade.py','armored_vehicle.py','assemble_scene.py','bake.py','verify.py']:subprocess.run([sys.executable,str(R/'source'/s)],check=True)
