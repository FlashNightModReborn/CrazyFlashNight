from pathlib import Path
import sys,subprocess
R=Path(__file__).resolve().parent
for n in ['parts','previews','baked','qa']:(R.parent/n).mkdir(exist_ok=True)
for n in ['interior_materials.py','lamps.py','reuse_grille.py','grand_door.py','statue.py','decor.py','statue_r3.py','carpet_r3.py','painting_r2.py','assemble_interior.py','state_boards.py','bake.py','verify.py']:
 subprocess.run([sys.executable,str(R/n)],check=True)
