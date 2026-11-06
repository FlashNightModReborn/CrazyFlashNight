"""Guard first-frame size jumps and preserve motion outside the initial pose."""
from pathlib import Path
import importlib.util
import sys
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
spec=importlib.util.spec_from_file_location('shared_icon_canvas',ROOT/'tools/bake-icons-offline.py')
tool=importlib.util.module_from_spec(spec);sys.modules[spec.name]=tool;spec.loader.exec_module(tool)

def rectangle(box):
    im=Image.new('RGBA',(40,40));ImageDraw.Draw(im).rectangle(box,fill=(230,210,70,255));return im

front=rectangle((10,10,29,29));side=rectangle((18,10,21,29))
frames=tool.normalize_shared_animation_canvas([front,side,front],front,(20,20),128)
assert frames[0].tobytes()==frames[2].tobytes()
assert frames[0].getbbox()==(0,0,128,128)
assert frames[1].getbbox()[0]>frames[0].getbbox()[0]
moving=rectangle((24,10,39,29))
motion=tool.normalize_shared_animation_canvas([front,moving,front],front,(20,20),128)
assert motion[0].tobytes()==motion[2].tobytes()
assert motion[0].getbbox()[0]<motion[1].getbbox()[0]
assert motion[0].getbbox()[2]<128 and motion[1].getbbox()[2]==128
transparent=Image.new('RGBA',(40,40))
assert not any(im.getbbox() for im in tool.normalize_shared_animation_canvas([transparent]*2,transparent,None,128))
print('Shared animation canvas: stable loop endpoints, motion preserved, transparent cycle handled')
