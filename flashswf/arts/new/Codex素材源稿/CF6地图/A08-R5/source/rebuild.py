from pathlib import Path
import subprocess,sys,shutil
R=Path(__file__).resolve().parents[1]
for d in ['parts','previews','qa','baked']:(R/d).mkdir(exist_ok=True)
shutil.copy2(R/'reference/reused/bitmap-1786.svg',R/'parts/bitmap-1786.svg')
for s in ['street_materials.py','vehicles_props.py','camera_r2.py']:
 subprocess.run([sys.executable,str(R/'source'/s)]+(['r5'] if s=='vehicles_props.py' else []),check=True)
# Preserve the exact R2 camera override and keep generic R3 preview names honest.
for scale in [1,4]:
 shutil.copy2(R/f'previews/camera-1828-r2-{scale}x.png',R/f'previews/vehicles-props-1828-r5-{scale}x.png')
from vehicles_props import compare
compare(1828,'r5')
subprocess.run([sys.executable,str(R/'source/vehicles_props.py'),'--audit','r5'],check=True)
for s in ['assemble_scene.py','bake.py','verify.py','car_r5_qa.py']:
 subprocess.run([sys.executable,str(R/'source'/s)],check=True)
