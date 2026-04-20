# Lockbox

This directory is the active runtime source for the Lockbox minigame.

- Runtime root: `launcher/web/modules/minigames/lockbox/`
- Shared shell + host bridge live in `launcher/web/modules/minigames/shared/`
- This directory is the only supported runtime source for Lockbox.

Module layout:

- Deterministic gameplay core in `core/index.js`
- Solver in `core/solver.js`
- Generator in `core/generator.js`
- Browser panel shell in `lockbox-panel.js`
- Web audio runtime in `lockbox-audio.js`
- Runtime-specific visuals in `lockbox.css`
- Standalone browser harness in `dev/harness.html`
- Pure logic QA suite in `dev/qa-suite.js`
