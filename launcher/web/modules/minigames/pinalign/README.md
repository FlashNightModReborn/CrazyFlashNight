# Pin Alignment

This directory is the active runtime source for the pin alignment minigame.

- Runtime root: `launcher/web/modules/minigames/pinalign/`
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
- DOM-only adapter in `adapter/dom-adapter.js`
- Simulation and replay tools in `dev/`
- No score win condition
- No gameplay `Math.random()`
- No direct special activation
- No special combo
- No kiln / flow / seal
