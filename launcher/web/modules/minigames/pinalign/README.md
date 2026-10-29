# Pin Alignment

This directory is the active runtime source for the pin alignment minigame.

- Runtime root: `launcher/web/modules/minigames/pinalign/`
- Shared shell + host bridge live in `launcher/web/modules/minigames/shared/`
- Legacy prototype reference only: `reference/porcelain-match-v11.snapshot.html`
- Legacy authoring area `scripts/类定义/org/flashNight/hana` is no longer the active implementation path for this minigame.

Authority order for this module:

1. User freeze / handoff notes in the current Codex task
2. `scripts/类定义/org/flashNight/hana/GPT5.4Pro.md`
3. `reference/porcelain-match-v11.snapshot.html`
4. `scripts/类定义/org/flashNight/hana/Gemini3DeepThink.md`
5. `scripts/类定义/org/flashNight/hana/Kimi2.5Agents集群.md`

MVP boundaries:

- Pure deterministic core in `core/index.js`
- Browser panel shell in `pinalign-panel.js`
- 3D Safe V2 Dual-Route runtime in `safe-v2/` (`puzzles.mjs`, `mechanisms.mjs`, `scene.mjs`, `gestures.mjs`, `manual-data.mjs`, `runtime.mjs`):
  - **1-Step Visual Reasoning (`puzzles.mjs`)**: Raven 2×2 matrix (`matrix`), Bongard 6-tile odd-one-out (`odd`), and Cardano rotating grille (`grille`), each yielding a 3-digit code (`100–999`) with inline SVG and red-pencil deduction overlay (`solvedSvg`).
  - **T1 + T2 Bipolar Mechanical Cutaway (`mechanisms.mjs`, `scene.mjs`, `gestures.mjs`)**: 3×3×2×2 (`36` combinations) across `A0–A2` × `B0–B2` with reversible polarity (`aDir`, `bDir`), brass stopper pins, jammed micro-travel (`~12%` when pulling `B` before `A` releases), and two-stage detent snap.
- DOM-only adapter in `adapter/dom-adapter.js`
- Simulation and replay tools in `dev/`
- Browser harness and QA chrome are built on `../shared/dev/`
- Host session reporting goes through `../shared/host-bridge.js`
- Unit & QA verification:
  - `node --test launcher/web/modules/minigames/pinalign/safe-v2/core.test.mjs`
  - `node launcher/tools/run-minigame-qa.js --game pinalign`
