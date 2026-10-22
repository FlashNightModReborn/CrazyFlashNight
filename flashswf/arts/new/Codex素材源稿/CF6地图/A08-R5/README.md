# CF6 eighth playable a8 · R5 cockpit and weapon-depth candidate

Rebuild offline: python source/rebuild.py. Python3/Pillow/NumPy/SciPy/fontTools/Inkscape. All references and typeface inputs included. No original SWF, external directory or network needed. Editable native SVG plus independent procedural bitmap micro-textures; static material PNGs baked at2x. Runtime/production integration not tested.

Actual a7 -> s5 -> a8, root108/world1841. Logical1150x410, viewport600x350. All environment placements and bitmap fills, masks, color transforms remain from original audited nodes. Full view and fixed cameras are static authored-coordinate illustrations, not running screenshots. No root scenery layer in this map.

New1404 vent/1405 stains/1414&1415 damaged circuit cavities/1817 wall/1820 ladder/1821 graffiti;1420 sliding door,1823 armed sports car,1828 suspended camera,1833 biohazard barrel. Reused1786 asphalt and six crate shape1436–1441. R3 changes only bitmap1823 artwork: solid rear aero planes and curved stiffeners, project M134 vehicle adaptation, and smooth native vector car/tire outlines. The car no longer uses the old low-resolution source alpha. Other materials retain the R2 artwork/masks. M134 barrel paths are imported from the fixed project-native XFL; the receiver/motor and vehicle mounts are newly drawn from the same reference. Original car/R2 PNGs are comparison-only inputs.

Full59-frame1430 door,147-frame1832 suspended camera and16-frame1838 barrel remain in reference timelines. Key original/new samples1430 1/5/15/30/44/59;1832 1/40/80/147;1838 1/2/7/10/13/16. Barrel RGB flashes, fragment clips and mirrored camera preserved. Wide fragment view prevents off-center pieces being cropped. All gameplay logic/actors remain original and are not installed by this package.

Known differences: sports-car shading and wheel geometry remain cleaner than source; cavity circuits are more regular, graffiti more graphic, wall/asphalt grain more uniform. Static comparisons and offline rebuilding are verified; no full-playthrough claim.

Packaging validation: preview SVG intermediates are removed after rasterization; PNG reviews are retained. Source references and fonts are bundled. Run python source/rebuild.py to regenerate editable shapes, the full environment, baked PNGs and comparisons. Native material/shape coordinates are unchanged; the original gameworld root matrix is applied once to the assembled static environment.

R2 revision: source/camera_r2.py runs after vehicles_props.py to replace only bitmap1828. Both camera views and all three mirrored/front-facing clip states retain their original matrices and exact alpha. The sports car is rebuilt from the revised car() source.

R5 details: README-R5.txt. R5 replaces opaque cockpit paint with an opaque interior plus separate transparent glazing; far gun renders behind the body and near gun in front. Prior R3 rear aero and wheel/body styling is retained. QA is static and no runtime test is claimed.

R5 source-raster-guided windshield front lower corner and hood boundary correction; matching near/far triangular support. Original anchor estimates are visual, not recovered vector geometry.
