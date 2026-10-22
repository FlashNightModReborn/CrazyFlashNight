from pathlib import Path
import shutil
R=Path(__file__).resolve().parents[1]
for p in (R/'reference/stage1-crate').glob('*.svg'):shutil.copyfile(p,R/'parts'/p.name)
