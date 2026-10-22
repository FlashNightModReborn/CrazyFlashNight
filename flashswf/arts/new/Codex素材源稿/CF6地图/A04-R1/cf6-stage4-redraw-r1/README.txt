CF6 FOURTH PLAYABLE STAGE A4 — R1 ARTWORK CANDIDATE

Scope
Actual progression is a3 exit 1720 -> a4 (root frame 82, gameworld 1737), without a new comic scene. This is a second arrangement of the interior introduced in stage 3.
The six approved stage-3 materials 1701, 1702, 1704, 1708, 1717, 1724 are regenerated unchanged. New artwork: red flammable barrel bitmap 1731. The three barrel placements use one shared material. Original barrel fragment clip paths and transforms are retained in shapes 1733–1735. The environment includes two wood doors, exit gate 1720, arrival sequence 1729, four background wall lights and four foreground chandeliers.

Source and baking
Run: python source/rebuild.py
Requires Python 3, Pillow, NumPy, SciPy and Inkscape on PATH. Tested environment versions are recorded in qa/budget-and-scope.json.
Parts are editable SVG. Wood and wallpaper contain deterministic procedural raster substrates, with editable vector seams and ornaments; the wallpaper ornament topology was calibrated from retained original masks. This is a hybrid-source project, not a claim of entirely hand-drawn vector restoration. Door, lamp and barrel replacements are native vector artwork. Reference materials are included for rebuild and registration.
Original-size PNG bitmap replacements and separate back/front layer PNGs are in baked/. Original bitmap-fill matrices and fragment masks remain in the node/reference data.

Composition and camera
Logical map 1300 x 450; original viewport 600 x 350. Foreground chandelier layer follows world x and y at 1.2 times. Full panorama uses a fixed authored foreground phase. The load-derived viewport uses world (0, -77.2), foreground (0, -92.64), inferred only from the load formula at the authored player placement. Arrival sprite 1729 frames 1–3 writes the real player to (668.45,226.95) and disables it; frame 122 restores its state. Event-order/runtime interaction has not been executed, so the load-formula view is not a validated initial screen. These images are static artwork comparisons, not screenshots from an executed game.
All world environment placements are read from original timeline-1737.json in depth order. Hidden map/collision/spawn markers and battle actors/HUD are omitted equally from original/new environment previews. The original ground gun and arrow are retained. Original Andy art in the lift state samples is retained and is not a new character redraw.

State coverage
Wood door 1714: original 9 frames retained, sample 1/4/9.
Exit gate 1720: original 174 frames retained, sample 1/25/90/150/174.
Arrival 1729: original 174 frames retained, sample 1/25/50/90/130/150/174.
Barrel 1736: original 16 frames retained, sample 1/7/10/13/16. Frames 1–6 full barrel; 7–9 first fragments; 10–12 second fragments; 13–15 final fragments; 16 empty. Existing effect 359 at frame 7 retained. Runtime explosion/damage behavior is unchanged and has not been executed or revalidated here.
Original frame transforms, color transforms and depth masks are used for static reconstruction. This is not a full ActionScript player, full-animation acceptance or integration/performance test.

Remaining visual differences
The reused interior inherits stage-3 candidate differences: wood grain is finer/smoother than the original; wall-foot floral trim is simplified; grille joints and lamp/door surfaces are more regular and clean. Scope of this release is the next actual layout and its new barrel material, not another revision of the approved room.
