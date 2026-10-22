from pathlib import Path
from doors import grille_art
from svg_native import write_part
R=Path(__file__).resolve().parents[1]
write_part(R/'parts/bitmap-1717.svg',[0,0,101,179],grille_art())
