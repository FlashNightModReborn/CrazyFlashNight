SHARED SOIL MATERIAL — recipe 2.1.0

What it is
  A deterministic procedural raster material, embedded into an otherwise
  editable SVG assembly. This soil is not represented as hand-drawn vectors.
  The generator never opens or samples the original game artwork. Reference
  images were used separately for visual and frequency/lighting comparisons.

Dependencies tested
  Python 3.12
  NumPy 2.3.5
  SciPy 1.17.0
  Pillow 12.3.0

Recipe structure
  1. Broad, continuous low-contrast soil lighting, without large hard islands.
  2. Uneven compacted pockets and short, low-relief directional abrasion.
  3. A mixed-scale bed of fine sand, independent chipped grains and gravel.
  4. Consistent bright upper grain edges and dark brown interstices, with
     quieter mineral variation and almost-neutral grey/gold bright grains.
  5. True 4x physical-scale construction, then antialiased 1x/2x output.

The structure is generated at physical pixel scales. Increasing output size
does not stretch a 1x bitmap, change random seed, or add thousands of SVG paths.
Horizontal correlated fields and particles wrap. The original four stage-2
fill positions and their approximately 5–7 px overlaps are unchanged.

Rebuild stage 2 (from the source directory or anywhere)
  python source/soil_material.py

This writes parts/bitmap-1611.svg with a self-contained 648x600 PNG in the
original 324x300 coordinate system. It also generates optional 1x/2x/4x PNG
caches under source/materials. Those caches are not needed to open the SVG
and can be omitted from the source ZIP to keep it below the size limit.

Shared Python API
  from soil_material import generate
  image = generate((324, 300), seed=1611, profile="stage2")
  image = generate((1296, 1200), seed=1611, profile="stage2")
  image = generate((1600, 904), seed=1580, profile="stage1")

generate returns a Pillow RGB image. Profile can also be a dictionary:
  {"base": "stage1", "contrast": .94, "grain_scale": 1.0,
   "world_size": (800, 452), "broad_strength": 3.4}

Optional palette is a sequence of normalized-y RGB lighting stops:
  [(0.0, (r,g,b)), ..., (1.0, (r,g,b))]

Stage 1 uses its own ground-horizon transition, shallow oblique shelf and
right-hand hollow. It does not reuse stage 2's full-height illumination ramp.
It is intended to be clipped by the existing stage-1 soil mask. Metallic
floor transition, original lamp geometry and separate glow remain independent.

Checks completed
  Visual review of original and R1 at native size and 4x nearest-neighbor crops.
  Pass 1: found insufficient fine contrast after antialiased downsampling.
  Pass 2: restored fine and medium contrast; found overly connected ridges.
  Pass 3/final: independent particle relief, slightly shorter/wider grain
  distribution, neutralized highlights and separate stage-1 illumination.
  Deterministic repeat, output dimensions, four-fill seam proof and frequency
  metrics are recorded in qa/soil-material-validation.json.

Proofs
  previews/soil-final-original-r1-r2.png
  previews/soil-stage1-original-profile.png
  previews/soil-four-fill-seams.png
  Earlier pass proofs are retained only as review material.

All scene assembly changes are performed by each stage's integration scripts.
This module owns only the soil recipe and the stage-2 bitmap-1611 material.
