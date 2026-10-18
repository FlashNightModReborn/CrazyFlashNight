"""R7 right-orbit-only review; no full animation batches."""
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
for folder in ['parts','previews','qa']:(R/folder).mkdir(exist_ok=True)
subprocess.run([sys.executable,str(R/'source/refine_eye_r7.py')],check=True)
subprocess.run(['inkscape',str(R/'parts/963.svg'),'--export-filename='+str(R/'parts/963.png')],check=True)
subprocess.run([sys.executable,str(R/'source/assemble.py'),'--stand-only'],check=True)
subprocess.run([sys.executable,str(R/'source/compare_r7.py')],check=True)
