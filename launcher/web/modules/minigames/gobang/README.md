# Gobang

This directory is the active runtime source for the Gobang minigame.

- Runtime root: `launcher/web/modules/minigames/gobang/`
- Shared shell + host bridge live in `launcher/web/modules/minigames/shared/`
- AI move evaluation is delegated to Launcher `GomokuTask` / Rapfi through the panel bridge.
- The Web core remains the authority for move legality and final game state.

Module layout:

- Deterministic gameplay core and rules in `core/index.js`
- Browser panel shell in `gobang-panel.js`
- Runtime-specific visuals in `gobang.css`
- Standalone browser harness in `dev/harness.html`
- Pure logic QA suite in `dev/qa-suite.js`

Rulesets:

- `casual`: no forbidden moves; five or more in a row wins.
- `renju`: black overline, double-three, and double-four are forbidden; white five or more wins.

QA:

```powershell
node launcher/tools/run-minigame-qa.js --game gobang
```
