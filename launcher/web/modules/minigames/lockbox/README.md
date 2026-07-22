# Lockbox

This directory contains the standalone Lockbox minigame. It is not connected to map-chest loot authority.

## Runtime boundary

- Runtime root: `launcher/web/modules/minigames/lockbox/`
- Shared shell and host bridge: `launcher/web/modules/minigames/shared/`
- Lazy panel registration: `launcher/web/modules/panels-lazy-registry.js`
- Debug entry: `LOCKBOX_TEST`

The active module consists of:

- deterministic gameplay core in `core/index.js`;
- solver in `core/solver.js`;
- generator in `core/generator.js`;
- browser panel shell in `lockbox-panel.js`;
- Web audio runtime in `lockbox-audio.js`;
- visuals in `lockbox.css`;
- ordinary browser harness in `dev/harness.html`;
- pure logic QA suite in `dev/qa-suite.js`.

## Retired map-chest experiment

The former resource-chest S0 bootstrap, adapter, actual wire, browser harness, AS2 bridge and Host runtime were removed on 2026-07-22. They formed a second authority/state machine ahead of the real `LootContainerService` and are not retained behind a feature flag.

Do not add map-chest markers, S0 environment gates or chest result handling to this module. If a production Lockbox reward flow is proposed later, it requires a separate protocol and ADR. It must integrate with the then-current loot authority rather than revive the deleted S0 experiment.

## Validation

```powershell
node launcher/tools/run-minigame-qa.js --game lockbox
node launcher/tools/validate-minigame-final-state.js
```

The browser harness remains useful for visual and input checks, but it does not prove an AS2/Host reward flow. Ordinary Lockbox `minigame_session` telemetry must remain fixed-redacted; raw payloads must not be logged.
