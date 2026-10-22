"""Cold rebuild from bundled native vector authoring + immutable original references."""
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parent
for name in ['background.py','props.py','build_scene.py','compare_background.py','compare_r4.py','detail_board.py','bake_static.py','verify.py']:
 p=R/name
 if not p.exists():
  if name=='crate_fragments.py':continue
  raise FileNotFoundError(p)
 subprocess.run([sys.executable,str(p)],check=True)
