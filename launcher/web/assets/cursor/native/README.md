# Native Cursor Canvas

Native cursor PNGs are runtime assets for `CursorOverlayForm`.

Contract:

- Source canvas is `64x64` pixels at 1x.
- The cursor hotspot is always pixel `(16,16)`.
- PNGs must use an alpha channel with transparent corners; opaque RGB exports
  or baked-in review backgrounds are invalid.
- The hotspot pixel must be visibly occupied by the active cursor point, not
  just a barely antialiased edge.
- Every state PNG must place its visual pointing point on that hotspot:
  - hand states: fingertip or active grip point
  - `attack`: weapon/reticle point
  - `openDoor`: arrow or door interaction point
- Runtime code may scale the whole canvas for DPI/readability, but must not carry per-state offsets.

Run `node tools/audit-native-cursor-assets.js` after changing these PNGs.

Optional vector-style postprocess:

```powershell
powershell -ExecutionPolicy Bypass -File tools/postprocess-native-cursor-vector.ps1 `
  -SourcePath <source-review-sheet.png>
```

The script writes a review set first; pass `-Apply` only after human review.
