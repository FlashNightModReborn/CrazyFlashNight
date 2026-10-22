CF6 FIFTH PLAYABLE STAGE A5 — R3 STATUE AND CARPET CANDIDATE

Revision scope
Only statue1740 and carpet1742 are refined from frozen R2. The accepted R2 floral painting1743, room materials and grand door remain unchanged. Statue reference is Michelangelo's Dying Slave, using the public-domain photograph by Marie-Lan Nguyen/Jastrow; the game asset's specific photographic source remains unidentified and its original camera/registration is preserved. The Met Aubusson carpet is a style reference, not the same carpet. Source-specific reconstruction and licensing records accompany the new generators.

Actual scene
A4 exit 1720 requires 22 kills and targets a5 directly: root frame 86 / world 1752. This is the next room in the same interior setting. New materials are statue 1740, perspective red carpet 1742, framed floral painting 1743 and grand double door 1746. The two statues and two pictures use the original repeated/mirrored instances. There are no stage-4 explosive barrels here. The approved crate is reused through its original fragment clipping.

Rebuilding
Run python source/rebuild.py with Python, Pillow, NumPy, SciPy, Matplotlib and Inkscape on PATH. All necessary references and static timeline nodes are included. Parts are editable SVG; baked/ contains original-size PNG material replacements and separate background/foreground PNGs with registration.json.
This is hybrid artwork. The reused wood and wallpaper contain deterministic raster substrates and editable vector elements; wallpaper ornament topology was calibrated from original reference masks. Statue1740 combines a retained AI-reconstructed non-nude upper-body bitmap with editable lower-body anatomical curves, shading and public-domain marble material crops. The generated upper-body file and its prompt/source hashes are retained; offline assembly is deterministic, while regenerating the AI image is not promised reproducible. It is not a pure SVG drawing or an unaltered photograph. Carpet1742 uses editable continuous botanical ornaments, documented flower crops from the Met public-domain Aubusson reference, and a deterministic fine woven substrate. Its original transparency and already-projected 901x145 footprint are preserved. The Met carpet is not the identified game carpet. Painting1743 uses an editable vector frame and a separately maintainable raster flower composition based on documented public-domain botanical references. Full generation methods are recorded in their source scripts and QA records. No claim is made that every texture is entirely hand-drawn vector or that full SVG rendering has been performance-tested in the game.

Preserved layout
Five actually used materials from the approved interior are reproduced unchanged: 1701,1702,1704,1717,1724. World placements are read in depth order from timeline-1752.json. In background 1745, right statue 1741 remains depth16; left statue, two pictures and carpet remain in original 1744 at depth24. Materials are not merged across these depth boundaries.
Carpet bitmap 1742 already contains its original perspective; its shape matrix remains scale0.375396728515625. No second perspective transform is applied. Both painting placements remain mirrored. Door leaves 1747/1748 and frame1749 use original cuts of the new1746 material.
Background combined viewBox [-684.75,-240.5,1516.75,483.3] includes the leftward lamp glow; world placement (673.5,207.1). Foreground chandeliers 1727 retain their original placement and 1.2x camera parallax.

Preview meaning
Logical map1300x450, viewport600x350. The full panorama uses a fixed authored foreground phase, and static viewport images use shared original/new coordinates. They are artwork comparisons, not game screenshots.
The authored player placement produces load-formula world(0,-77.2), but arrival1729 overwrites the actual player's position to(1190.45,231.4). The ActionScript/event order was not executed, so this is not a verified initial camera. Main overview and fixed middle/right views should be used for artwork assessment.
Battle actors/HUD and invisible gameplay areas are omitted equally from the original/new environment views. Original ground gun and arrows are retained. Original player art inside door/lift static state samples is retained, not redrawn for this room.

State coverage
Grand door1750:40 original frames retained, samples1/5/10/20/30/40. No new mask or gameplay changes; original frame depth orders are used.
Arrival1729:174 original frames retained, samples1/25/50/90/130/150/174, including original masks and actor references.
Crate1442:11 original frames retained, samples1/2/4/6/8/11 using approved crate art and original fragment clips.
Static reconstruction and source integrity checks do not constitute all-animation/runtime/gameplay/performance acceptance.

Remaining candidate differences
Statue upper-body clarity improves substantially over R2, but its face is slightly more frontal and fingers more downturned than the original; the editable lower body remains more simplified than the upper photo-like region. Carpet corner medallions, dense flower groups and continuous foliage are improved, while leaf rhythm remains more regular and woven relief weaker than the original. The painting is a new reference-based floral composition fitted to the original image; it is not a recovered high-resolution original. The grand door is cleaner and its wood grain more regular. These are reviewable art candidates.

Package size and generated composites
The source ZIP omits only the redundant generated parts/background-1745.svg and parts/shape-1744.svg, which repeat embedded high-resolution painting pixels. Run source/rebuild.py to recreate these exact assembly SVGs offline. Individual editable materials, source crop tiles, original registration/timelines, baked PNGs and all generation scripts are included.
