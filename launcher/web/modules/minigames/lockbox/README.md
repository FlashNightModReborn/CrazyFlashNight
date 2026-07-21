# Lockbox

**Document role**: Lockbox runtime/module source of truth and local verification entry; resource-chest S0 decisions remain governed by the linked ADR.
**Last checked code baseline**: HEAD / `origin/main` `2d19cd6681a0219749a58501271b6f1bd23cc28f` (2026-07-21, rechecked after power-loss recovery), plus the current unpromoted S0/S1/S2 worktree.
**S0 decision boundary**: [resource-chest S0 ADR](../../../../../docs/地图资源箱-S0无奖励编排-ADR-2026-07-17.md).

This directory contains the active Lockbox minigame and the resource-chest S0 adapter, actual wire, and dormant production bootstrap. The S0 source wire is integrated and `asLoader.swf` has been published, but its two development gates remain closed and the S0 Host runtime has not been promoted.

- Runtime root: `launcher/web/modules/minigames/lockbox/`
- Shared shell and host bridge: `launcher/web/modules/minigames/shared/`
- This directory is the only supported runtime source for Lockbox.

Module layout:

- Deterministic gameplay core in `core/index.js`
- Solver in `core/solver.js`
- Generator in `core/generator.js`
- Browser panel shell in `lockbox-panel.js`
- Web audio runtime in `lockbox-audio.js`
- Runtime-specific visuals in `lockbox.css`
- Resource-chest S0 state adapter in `chest-s0-adapter.js`
- S0 Host/Web protocol binding in `chest-s0-actual-wire.js`
- Dormant production bootstrap in `chest-s0-dev-bootstrap.js`; it lazy-loads the adapter and actual wire only after an exact Host arm
- Ordinary standalone browser harness in `dev/harness.html`
- S0-only browser harness in `dev/s0-harness.html` and `dev/s0-harness.js`
- Pure logic QA suite in `dev/qa-suite.js`

Keep the S0 state in four distinct layers:

1. **Source wire**: AS2 socket/production callbacks, the Host `DevLockboxS0Runtime` and tracked PanelHost queue, and the production overlay bootstrap/actual wire are connected in source. The AS2 exact fixture-marker gate and the Host dev-repository plus `CF7_DEV_LOCKBOX_S0 === "1"` gate are closed by default. Ordinary Lockbox and `LOCKBOX_TEST` do not arm this path.
2. **Automated evidence**: Launcher clean full is **1220/1220**; focused S0 Host Runtime + Coordinator remains **84/84**, the targeted race/flake gate **25/25**, the adapter **20/20**, actual wire **31/31**, static wiring **454/454**, and the cross-stack verifier **61/61**. The four Rock Park `TEMP` fixtures have been restored; the current stage audit is **41/41**, with **28 declarations / 27 nodes / 26 identities**, Rock Park **active 1 / commented 8**, and rollout **1**. Runtime Lane C is **420/420**, but it only proves release guardrails. Fresh CS6 runId `b455c11660714346ab58c18e8e740670` records Arbiter **13/13 / 53 assertions**, `ChestSessionService` **13 cases / 41 passed**, Socket **10 cases / 18 passed**, Supplemental **4 cases / 18 passed**, Production **4 cases / 12 passed**, all **0 failed**, Compiler Errors **0/0**, and BOM **227/227**.
3. **Real candidate evidence**: all earlier `a8a760a3`, `AE1FC1EF… / 172A85C6…`, merge-time diagnostic candidates, and `FCA19BA5… / B2AF3BEF… / 231388D7…` are retired. The current final-worktree isolated candidate is `tmp/runtime-candidates/v2/c-2a0cddb077b7-08846e81b3-20260721t100014612z-f32a40a3`, with native build identity `2A0CDDB077B760328B3141EFFFEEE3996841FA1CE49AD09E5D7339417F60A107`, payload closure `3B837DCDBC69AA47074E635DACACAE3B80263023E6032AC1FDF209768B1C150C`, and Core SHA-256 `0F58BF864B8DE9C7FCEA098D7E1EEA1996BDE38D85D87E844B047B53F5247232`. Its preflight, HTTP/XMLSocket/WebView2/Flash handshake, dedicated-save load, post-watermark fresh handoff, real `bootstrap_reveal_ready` without watchdog, single enter helper, and exact-attempt same-packet `s:1|ga:<attemptId>` receipt succeeded, and the same process completed the S1/S2 organizer plus ordinary suspend/same-anchor content-preserving reopen/final-claim chain, so that single-canary loot slice is `e2e_verified / NOT_DEPLOYED`. The candidate then shut down cleanly while Flash CS6 stayed open, but the S0 gates stayed closed and no exact S0 fixture or direct-hit panel flow ran; neither that loot run nor the external Web files loaded from `projectRoot/launcher/web` count as S0 actual-feature cross-stack evidence.
4. **Deployment**: upstream formally promoted runtime v2, but that B643/FA1 production Core does not contain this local S0/loot Host work. The current isolated candidate comes from a dirty, non-immutable worktree and is unsigned, with no request, production receipt, signer/faultDomain quorum, promotion, or standard-entry verification. `scripts/asLoader.swf` has been published at **1,041,903 bytes**, SHA-256 `AD799970A8A2AFD0F9A402C704934F08985A3144FA608A7564E17BC4899C815E`, Git blob `3dd59f73f9fc71128da99c2eb03796290df1e010`, while the S0 Host runtime and actual feature flow remain unpromoted. Source, automated green status, and startup handshake must not be described as player-reachable or production-complete S0.

Run verification from the repository root:

```powershell
node tools/test-lockbox-chest-s0-adapter.js
node tools/test-lockbox-chest-s0-actual-wire.js
node tools/test-lockbox-chest-s0-cross-stack-verifier.js
node launcher/tools/run-minigame-qa.js --game lockbox
node launcher/tools/validate-minigame-final-state.js
powershell -ExecutionPolicy Bypass -File tools/test-chest-s0-wiring.ps1
powershell -ExecutionPolicy Bypass -File launcher/tests/run_tests.ps1
powershell -ExecutionPolicy Bypass -File scripts/run-chest-s0-tests.ps1 -TimeoutSeconds 300
```

The primary pause proof is established in AS2. In the same call stack and before sending begin, `ChestS0SocketBridge` synchronously invokes `webPanelPause` and verifies that `_webPanelPauseLease` actually exists. The exact begin payload must contain `pauseAcquired:true`, and Host fails closed when it is missing or false. Runtime's generation-bound pause write before tracked enqueue and PanelHost's UI-time `AssertWebPanelPause` are defense-in-depth only; neither can replace the AS2 lease proof. Any Host-side failure still cancels exactly, emits `openFailed`, stops before native/Web visual side effects, and can never report `OpenPosted`.

The dedicated S0 browser entry is `node tools/run-lockbox-chest-s0-harness.js`; it currently passes W04/W05 **2/2**, while `--case W04` and `--case W05` each pass **1/1**. It uses the production panels lazy registry, required Icons gate, and real Lockbox DOM/core, and fails on validation, page, request, HTTP, console, or server errors. Its evidence deliberately reports `executionMode=browser-host-shim`, `actualCrossStack=false`, and `productionHost=false`: it does not prove the real C# Host, AS2 socket, tracked queue, origin, global pause/focus/reconnect, or an actual cross-stack flow.

The recovery contract is identity-preserving, state-driven, and fail-closed. Begin atomically consumes the capability, reserves the attempt, and publishes the active identity; begin and its execute gate reject while navigation is pending. A reconnect capability with `resumeActive=true` cannot be consumed by begin and remains reserved for authority convergence. A tracked S0 open must first acquire the real global pause: WebOverlay `AssertWebPanelPause` returns the actual boolean, and PanelHost `requireTrackedDelivery` fails closed before any `CaptureBackdrop`, `ResumeForPanel`, or `TryPostToWeb` visual/Web side effect; a `false` return or exception can never report `OpenPosted`. Host reconciliation branches on the current coordinator state rather than assuming a one-shot delivery succeeded. An unknown result causes an immediate Host→AS2 causal query and timer retries without depending on Web `result_query`; terminal authority projections are cached and replayed to Web. Each reconciliation tick registers itself as in flight and rechecks the exact identity, reconciliation generation, and non-releasing state before every side effect. `TryRelease` defers while any tick is in flight; the tick's `finally` drops the count and only then retries release, so an old tick cannot cross into a fresh-arm identity. The exact identity/generation check and reconcile-timer publication are atomic under the same Runtime lock, so a stale attempt cannot replace or dispose a fresh identity's timer. In `KnownTerminal`, an initial `false` return or exception from the `releaseTrackedPause` callback retains the terminal flow for timer-driven reconciliation; it must neither reset nor fresh-arm. Only a successful callback emits `pause_release` and then fresh-arms. Generic-unpause validation and its generation-bound socket write are linearized with begin under the Runtime lock; a failed write remains pending, and reconnect/Web-ready may not fresh-arm until the pending unpause succeeds. While either a tracked reservation or tracked lease exists, PanelHost rejects every generic open/close under its queue lock; forced teardown uses exact-identity close. If Web's exact `close_ack` is lost, Host sends `close_query`; a failed native exact-close is retried independently, and Web re-attests an already-completed teardown without reopening the DOM. `NavigationStarting` clears WebOverlay readiness before Runtime captures the active identity; with no active flow it immediately invalidates an old idle arm. A successfully loaded new document stays not-ready until its own `ready`; failed or same-document navigation restores the old readiness and fresh-arms, while old-document teardown is accepted only when that non-zero `NavigationId` has reached `ContentLoading` and then completes successfully. A normal `resumeActive=false` bootstrap settles a begin-in-flight orphan as known-no-write. Pause releases only after AS2 terminal authority, Web DOM teardown, and native PanelHost close are independently proven. Navigation revokes before result or queries after result without replaying a write, and a panel-busy begin receives a fresh arm only after PanelHost reports idle.
