# Native Cursor Canvas

Native cursor PNGs are runtime assets for `CursorOverlayForm`.

Contract:

- Source canvas is `64x64` pixels at 1x.
- The cursor hotspot is always pixel `(16,16)`.
- Every state PNG must place its visual pointing point on that hotspot:
  - hand states: fingertip or active grip point
  - `attack`: weapon/reticle point
  - `openDoor`: arrow or door interaction point
- Runtime code may scale the whole canvas for DPI/readability, but must not carry per-state offsets.

Run `node tools/audit-native-cursor-assets.js` after changing these PNGs.
