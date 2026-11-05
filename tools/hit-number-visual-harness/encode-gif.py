"""Encode production PNG frames; no rendering or animation rules live here.

Optional dependency: an already installed Pillow. Does not install dependencies.
"""
from pathlib import Path
import sys
from PIL import Image

folder, output, fps = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
paths = sorted(folder.glob('frame-*.png'))
if not paths or fps <= 0:
    raise ValueError('A nonempty production frame sequence and positive FPS are required')
# One palette for the whole sequence prevents per-frame color quantization shimmer.
sheet = Image.new('RGB', (320 * 4, 180 * 2))
for i in range(8):
    with Image.open(paths[min(len(paths)-1, i * (len(paths)-1) // 7)]) as frame:
        sheet.paste(frame.convert('RGB').resize((320, 180)), ((i % 4) * 320, (i // 4) * 180))
palette = sheet.quantize(colors=256)
frames = []
for path in paths:
    with Image.open(path) as frame:
        frames.append(frame.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE))
# GIF duration is in 10ms units; preserve the total 30FPS duration without speeding it up.
durations = [(round((i+1)*100/fps)-round(i*100/fps))*10 for i in range(len(frames))]
frames[0].save(output, save_all=True, append_images=frames[1:], duration=durations,
               loop=0, optimize=True, disposal=1)
