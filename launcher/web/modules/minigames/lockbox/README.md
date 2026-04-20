# Lockbox

This directory is the active runtime source for the Lockbox minigame.

- Runtime root: `launcher/web/modules/minigames/lockbox/`
- Shared shell + host bridge live in `launcher/web/modules/minigames/shared/`
- Legacy flat files in `launcher/web/modules/lockbox-*.js` are deprecated compatibility shims for one migration cycle.

Module layout:

- Deterministic gameplay core in `core/index.js`
- Solver in `core/solver.js`
- Generator in `core/generator.js`
- Browser panel shell in `lockbox-panel.js`
- Web audio runtime in `lockbox-audio.js`
- Runtime-specific visuals in `lockbox.css`
- Standalone dev harness in `dev/harness.html`
