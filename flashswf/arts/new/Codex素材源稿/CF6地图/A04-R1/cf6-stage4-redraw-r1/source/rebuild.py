from pathlib import Path
import sys,subprocess
R=Path(__file__).resolve().parent
for n in ['parts','previews','baked','qa']:(R.parent/n).mkdir(exist_ok=True)
for n in ['interior_materials.py','lamps.py','doors.py','barrel.py','assemble_interior.py','state_boards.py','bake.py','verify.py']:
 subprocess.run([sys.executable,str(R/n)],check=True)
