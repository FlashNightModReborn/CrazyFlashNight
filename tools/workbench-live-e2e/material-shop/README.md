# Material Archive ↔ NPCShop A5 candidate journey

This directory is the dedicated A5 adapter for the ADR A4b option-2 route. It combines the Crafting source contract, the NPCShop production closure, an exact current-dirty-tree overlay, isolated save slots, project Agent Runtime guarded input, WGC captures, trusted JSONL sessions, and fresh-process readback.

It does not call `Bridge`, `Panels`, or a game business API. The current route starts the project trusted runner in slot `cf7_agent_a5_material_shop_run`, opens the allow-listed Materials panel through structured `panel.open`, and then uses only fresh WGC `observation_px` frames plus guarded `input.click` / `input.press_key` / `input.type_text`. Closing stdin is the trusted shutdown boundary: both first and restart sessions must exit cleanly with one validated completion, transcript, and controller ledger. Codex Computer Use, operator-attested admission, CDP input, passive Playwright/Host logs, `SAFEEXIT`, and `supported_shutdown` belong only to legacy raw-replay evidence; they are not current live admission.

## Current accepted candidate

Run `a5-0814-h3` reached `e2e_verified / NOT_DEPLOYED` on 2026-08-14. Its acceptance SHA-256 is `db130a3e90e52232985a16adb1e115669dd003c9fae1158cfdc4a9cf516298e5`; the three-viewport static gate is `c4ad4248b192cc07650c6d0adfd97720bcdb730f2279fb0315625815ceb2b0b4`, and the independent 16-PNG / 14-claim visible review receipt is `fde13e7c9a068c79f5ff0d10a474f378cd5e61537f81761013a4a9e45f3ebca0`. This closes the A5 source/candidate gate only. No worktree release, cloud consensus, promotion, DLL write, or formal-entry replay has been performed.

## Current-data applicability

`applicability.js` derives the result from the current material catalog, all 35 NPC shop files, ItemData prices, AS2/Host purchase-limit authorities, and exact JSON plus complete owned-SOL sets for four existing `cf7_agent_*` fixtures. The current inventory has 224 materials, 104 shop occurrences / 101 unique shop materials, and all 416 seed×occurrence pairs afford quantity one. There are no material `requiredInfo`, configured `purchaseLimit`, or seed material quantities at the default 999999 limit. Therefore the unlocked quantity-one route is required; locked and max live routes are recorded as `not_applicable_current_data`, never as passed. A future `requires_seed_probe` result blocks live admission until a separate seed-resolved artifact exists.

The only source fixture is `cf7_agent_character_build_b4`. `candidate-lifecycle.js` copies its JSON bytes without transformation into `cf7_agent_a5_material_shop_seed`; target and recovery remain the dedicated `cf7_agent_a5_material_shop_run` and `cf7_agent_a5_material_shop_recovery` slots. The canonical fixture is never changed. The frozen unlocked target is `shopId=厨师`, `catalogIndex=24`, `itemName=食用油`, static base price 300, initial owned 0; live settlement still trusts the authoritative snapshot `unitPrice`.

Live replay keeps the two roots intentionally distinct. Material catalog, NPC shop/item data, AS2/Host authority bytes, candidate modules, clone mutation, locks, and recovery come only from the protected materialized `resources` Worktree. The four fixture JSON files and their complete owned-SOL sets come only from the canonical preparation root. Before the live operation lease is acquired, the canonical runner re-derives applicability and seals a fixture-authority binding; the materialized lifecycle replays that binding without treating its own `Common.CANONICAL_ROOT` as fixture authority, rejects an authority path equal to or inside `resources`, and records the full binding in raw lifecycle evidence. Raw verification independently requires that binding root to be the canonical root and replays the exact JSON/SOL artifact sets again.

## Offline gates

```powershell
node tools/workbench-live-e2e/material-shop/test-visible-review-contract.js
node tools/workbench-live-e2e/material-shop/test-materialized-path-budget.js
node tools/workbench-live-e2e/material-shop/test-agent-runtime-portrait-evidence.js
node tools/workbench-live-e2e/material-shop/test-agent-runtime-keyboard-recipe-evidence.js
node tools/workbench-live-e2e/material-shop/self-test.js
node tools/workbench-live-e2e/material-shop/verify-run.js --check
```

`--check` captures the current closure twice, normalizes recursive timestamp fields, verifies current-tree bytes, and re-derives applicability. It also binds the protected canonical `launcher/perf/package-lock.json` to the installed `playwright-core` package manifest plus exact `lib/utilsBundle.js` and `lib/utilsBundleImpl/index.js` bytes. Preparation never persists `node_modules` in the materialized Worktree. The later static gate, after validating the release ignored-output inventory, copies only the Playwright files named by the sealed browser-module inventory and temporarily substitutes only the inventory-bound crafting dev harness fixture; it runs the materialized browser bootstrap, then restores the fixture byte-for-byte and removes the Playwright projection in the same process before returning. Candidate product modules and assets are never substituted. None of these offline commands builds, launches, drives, or deploys a candidate.

## Candidate commands

1. Materialize the exact current dirty scope over a detached HEAD Git worktree named `resources` and freeze the v4 Agent Runtime plan. The result retains `.git`, HEAD, index, and a successful `Get-Cf7RuntimeBuildIdentityV2 -Mode Worktree` receipt. This command does not build. `--agent-runtime-jsonl` is mutually exclusive with Computer Use capability files and CDP fallback.

```powershell
node tools/workbench-live-e2e/material-shop/prepare.js --run-id <closed-run-id> --agent-runtime-jsonl --authorize-quantity-one-purchase
```

Before creating even the owned run directory, `prepare` projects every file in the full sealed scope
onto the actual canonical `materialized/<runId>/resources` destination. Because the Launcher is not
declared `longPathAware`, every absolute physical path must be at most 259 characters (the 260th
`MAX_PATH` character is the terminating NUL). A rejection reports the longest relative/absolute
path, projected length, and safe run-ID maximum; the materializer repeats the same pure gate before
any marker, Git worktree, or candidate side effect. In the current canonical root, 13-character run
IDs project the longest hash-named shop portrait to 259 and are admissible; 14 characters project to
260 and fail closed. The historical 36-character t1903 ID projects that same path to 282 and is not
eligible for a fresh run.

Production materialization writes `materialization-create-intent.json` in the exact run directory
before `git worktree add`. It binds the canonical root/commonDir, detached HEAD, exact destination,
scope path set, and argv-form cleanup command. Before the first Git side effect, the same producer
also acquires a CreateNew, fsynced `materialization-producer-lease.json` bound to the intent,
run/destination, PID, and process start identity. Successful resolution archives the creation intent
before atomically turning that lease into `materialization-producer-terminal-<hash>.json`; a killed
producer leaves the active lease in place. A verified materialization archives the intent as
`materialization-create-resolved-<hash>.json`; this is not a preparation, build, or E2E claim. If
preparation fails before `preparation.json` exists, preserve the run directory and use only:

```powershell
node tools/workbench-live-e2e/material-shop/materialize.js --inspect-materialization-producer --run-dir <exact-run-dir>
node tools/workbench-live-e2e/material-shop/materialize.js --recover-stale-materialization-producer --run-dir <exact-run-dir> --acknowledge-stale-materialization-producer
node tools/workbench-live-e2e/material-shop/materialize.js --cleanup-failed-materialization --run-dir <exact-run-dir> --acknowledge-remove-failed-worktree
node tools/workbench-live-e2e/material-shop/materialize.js --finalize-stale-preparation --run-dir <exact-run-dir> --acknowledge-stale-preparation-finalization
```

Cleanup derives its target solely from the sealed marker. It refuses markerless/sibling paths, an
existing preparation, reparse or split filesystem/Git state, foreign HEAD/commonDir/backpointers,
staged bytes, and dirty or ignored paths outside the sealed scope. An active producer whose exact
owner is still present or cannot be verified blocks cleanup; only a definite missing owner or PID
reuse can be explicitly archived as stale, after which cleanup repeats the producer and tree probes.
The cleanup v2 receipt binds that terminal/stale producer marker and its exact lease/artifact SHA.
It invokes only argv-form exact
`git worktree remove --force`; it never prunes or recursively deletes. The intent's `removeCommand`
is authorization, not proof that removal ran. Receipt failure after removal resumes with the same
command; terminal evidence is `materialization-cleanup.json` plus
`materialization-cleanup-resolved-<hash>.json`. Never retroactively create a marker for an older orphan.
If all preparation artifacts and `preparation.json` were durably written but the producer died before
the creation marker was resolved, cleanup is forbidden: recover only a definitely stale producer,
then use the typed stale-preparation finalizer above. It replays the full preparation, materialization,
scope, and producer evidence before resolving the marker and emits
`preparation-materialization-finalization.json`; a current build loader accepts that path only through
this exact receipt. An active or unverifiable owner, foreign output, or incomplete preparation remains
a stop-line.

2. Inspect the exact build command, then explicitly execute it. Build input is the materialized Git worktree, not the canonical dirty workspace.

```powershell
node tools/workbench-live-e2e/material-shop/build-candidate.js --preparation <run-dir>/preparation.json
node tools/workbench-live-e2e/material-shop/build-candidate.js --preparation <run-dir>/preparation.json --execute-build
```

The executed command is exactly the materialized `resources/automation/dev.ps1 -ForceBuild -BuildOnly -CandidateLeaf a5`. The protected PowerShell driver closure explicitly binds `automation/dev.ps1`, `automation/start.ps1`, `launcher/build.ps1`, `tools/verify-runtime-bundle-v2.ps1`, and their live dot-source dependencies `tools/runtime-build-common.ps1` and `tools/dotnet-runtime-detect.ps1`; every member is required and a HEAD-stale byte fails the materialized scope. The adapter independently derives the only admissible root as `resources/tmp/runtime-candidates/v2/a5`, requires it to be one direct child, and checks the exact runtimeconfig probe is shorter than 260 characters before spawning PowerShell. The materialized Worktree is unique per run, while an existing `a5` in the same run remains immutable and is never replaced. Ignored files are split into exact `protected_scope_input` and `generated_output` classes: the four ignored seed fixtures are admitted only because their exact paths, byte counts, and hashes are already bound by the protected scope; no `saves/**` prefix is allowed. Inventory v3 additionally admits only the preparation-bound seed/target/recovery JSON files, exact `.launcher-version-marker.json`, `bootstrap.log` / `launcher.log` / `perf-latest.jsonl`, and the two exact WebView2 userdata roots. Generated 0-byte files are still SHA-256 sealed; near prefixes, extra logs, foreign saves, and offline recovery receipts remain foreign. The producer's structured result, active pointer, exact command, success receipt, candidate binding, ignored-output inventory, and release closure must all resolve to that exact root. Output remains `candidate_built`; it is not candidate execution or E2E.

During `--execute-build`, any path-budget rejection before spawn, producer error/non-zero/signal, or validation failure after an exit-zero producer publishes exactly one CreateNew `candidate-build-failure.json`. It binds preparation/materialization, the exact command and candidate root, projected/max path lengths, full stdout/stderr byte counts and hashes with bounded UTF-8 tails, and an exact `failureStage=preflight|producer|postspawn_acceptance`. The postspawn form records `commandExecuted=true`, `producerExitCode=0`, whether the expected direct candidate directory was observed, the bounded validation error, and fixed `candidateAcceptance=false`; every form remains `diagnosticOnly=true / candidateBuilt=false` and is rejected by the success-receipt loader. Never pass this file to the live runner or overwrite it to retry; retain the Worktree for diagnosis and start a fresh run after the owned failure is resolved.

If a sealed `candidate_built` run has never entered candidate execution and contains no control, admission, lifecycle, transcript, raw, clone-lock/recovery, JSON, or SOL side effect, discard it only through the dedicated full-context command below. It replays the preparation/build/materialization, protected scope, exact candidate outputs, all three empty dedicated slots, two fresh process/filesystem/Git probes, and a durable removal intent before the exact `git worktree remove --force`. Live and discard share one CreateNew per-run operation lease: a run with terminal/stale live history cannot execute again, any live history forbids built-never-executed disposal, and an active/resolved discard marker or receipt permanently blocks live entry. Fresh discard is allowed only when no discard intent exists; its v2 intent seals the exact active lease bytes/hash and all preexisting built-only history, while the finalizer accepts only that sealed history plus the bound lease's single terminal or stale-recovered outcome. A crash before removal is a manual stop and cannot acquire another destructive lease; a crash after exact removal may use the bare finalizer only after the bound stale lease is explicitly recovered. The legacy preparation/build schema accepted here exists only to recover pre-toolchain built runs; current build/live loaders continue to reject it. The finalizer never removes a present Worktree.

```powershell
node tools/workbench-live-e2e/material-shop/discard-built-run.js --discard-built-never-executed --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --acknowledge-built-never-executed-discard
node tools/workbench-live-e2e/material-shop/run-operation-lease.js --inspect --run-dir <run-dir>
node tools/workbench-live-e2e/material-shop/run-operation-lease.js --recover-stale --run-dir <run-dir> --acknowledge-stale-operation-recovery
node tools/workbench-live-e2e/material-shop/discard-built-run.js --finalize-built-discard --run-dir <run-dir>
```

One historical failure shape has a separate, narrower recovery route: a candidate was built, the old live runner entered its operation lease, then canonical seed/SOL audit failed with exact `material_shop_seed_audit_incomplete` before lifecycle preparation or candidate start. `discard-seed-audit-failed-run.js` accepts only that exact retained runner stderr, zero-byte stdout/transcript, the three exact empty control directories, one bound live terminal, zero admission/raw/clone/lifecycle/process/slot side effects, the historical root-coupling source bytes, and the full materialization/build/protected-scope closure. It does not widen generic built-only discard to arbitrary live history. The full-context command writes a durable intent, repeats the entire destructive probe, and removes only the exact Git worktree. A failure before intent may leave a bound built-only terminal/stale outcome; a failure after intent may leave an active generation. After explicit stale-lease recovery when needed, rerun the same full-context command: it seals every prior exact archive byte/SHA into an append-only operation chain and performs two fresh probes before removal. Foreign/missing/whitespace-drifted outcomes fail before deletion. The bare finalizer still refuses a present filesystem or Git worktree.

```powershell
node tools/workbench-live-e2e/material-shop/discard-seed-audit-failed-run.js --discard-seed-audit-pre-candidate-failure --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --acknowledge-seed-audit-failure-discard
node tools/workbench-live-e2e/material-shop/run-operation-lease.js --inspect --run-dir <run-dir>
node tools/workbench-live-e2e/material-shop/run-operation-lease.js --recover-stale --run-dir <run-dir> --acknowledge-stale-operation-recovery
node tools/workbench-live-e2e/material-shop/discard-seed-audit-failed-run.js --finalize-seed-audit-failure-discard --run-dir <run-dir>
```

A current runner failure before the first business control has one separate disposal route only when
`run-live-journey.js` already persisted exact `pre-control-failure-cleanup.json`. That receipt binds the
single live terminal, original error, authenticated candidate shutdown and stable clean residue,
released clone, unchanged sealed baseline/target, completed admission if a runtime was assigned, and
zero control/raw/evidence/recovery side effects. Missing or invalid receipt is rejected before a new
operation lease or marker is created. The full-context discard writes a durable removal intent, uses
two exact safety probes, and on a failed remove resumes by appending a bound mutex/terminal chain;
resume-marker bytes and the complete marker digest are fenced before removal and sealed into the final
receipt. The bare finalizer never removes a present worktree. Older failures without this persisted
receipt remain retained stop-lines and are not eligible for this command.

```powershell
node tools/workbench-live-e2e/material-shop/discard-pre-control-failed-run.js --discard-pre-control-failure --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --acknowledge-pre-control-failure-discard
node tools/workbench-live-e2e/material-shop/run-operation-lease.js --inspect --run-dir <run-dir>
node tools/workbench-live-e2e/material-shop/run-operation-lease.js --recover-stale --run-dir <run-dir> --acknowledge-stale-operation-recovery
node tools/workbench-live-e2e/material-shop/discard-pre-control-failed-run.js --finalize-pre-control-failure-discard --run-dir <run-dir>
```

3. Start the raw candidate journey exactly once for a fresh run. The runner checks discard state before and after acquiring the shared operation lease, before any materialized require, clone, transcript, or process start; it rejects prior live terminal/stale history and any discard state. If a discard marker wins only the acquisition race, exact-owner pre-execution cancellation removes the new lease without producing live terminal evidence; once execution is marked started, cancellation is forbidden. The lease remains held through raw/evidence persistence, clone release, and durable release receipt, then becomes terminal evidence consumed by verification and acceptance. The runner prepares the dedicated clones and owns two project trusted JSONL sessions (`first`, `restart`) for the exact candidate.

Each session starts the trusted runner for candidate leaf `a5`; readiness and candidate identity are
validated before control. For this exact A5 slot only, Host credential publication stays closed until
the current attempt has produced the real `bootstrap_reveal_ready` title receipt (the watchdog never
counts), Host has sent the single fixed `_root.agentEnterResolvedSave()` transition, and the same
attempt/slot is confirmed by both `s:1|ga:<attemptId>` and `agent_runtime_status.loaded=true`.
The JSONL client cannot supply console text or request this transition. The trusted Core keeps the
four historical slots at their fixed 30-second credential-acquisition deadline and gives only this
exact A5 slot 60 seconds for the real-title/entry/readiness gate. The outer harness gives only the
initial `session.status` a 90-second startup budget covering wrapper verification, Guardian creation,
and that credential gate; all later RPC and write calls keep the ordinary 30-second deadline.
`panel.open {panel:"materials"}`
is the only structured opener after that gate. Visible
actions consume a fresh WGC frame, derive panel-local `observation_px`, and receive a terminal guarded
input receipt; capture-required steps persist Agent capture receipts and PNG hashes. EOF/closed stdin
requests trusted shutdown. After the first clean completion the archive save is sealed, a fresh runner
starts the same candidate for readback, and the restart session closes by the same trusted EOF path.

```powershell
node tools/workbench-live-e2e/material-shop/run-live-journey.js --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json
```

The runner verifies the frozen 24-step current-data route. After `panel.open materials`, guarded
`input.press_key` receipts cover the default authored archive, drilldown tree, sort menu, grid and
detail path without click/type substitution. The exact first material `军用帆布` then opens
`{category:"属性武器",recipeIndex:0,productName:"二阶复合防御组件"}`, persists a visible destination
capture, closes by guarded Escape, and reopens Materials before the existing shop route continues.
A known navigable `食用油` card/CTA is followed by ordinary shop close,
`食用油` → `厨师` catalog card `#24`, Enter quantity-one/zero-sale intent, guarded checkout click,
settlement, one authorized
commit, return, first trusted shutdown, fresh restart/readback/close, and final trusted shutdown.
Baseline/archive/restart target-save JSON bytes are copied unchanged into `save-state-artifacts/`
and each stage keeps its own exact byte SHA. Replay proves `食用油 0→1`,
`money = baseline - authoritative buyTotal`, exact target-to-restart byte binding, and full-save
archive/restart semantic equality after removing only the root `lastSaved` timestamp and sorting the
four registered set-like source-cache arrays. Both session completions, transcripts, ledgers,
WGC/PNG receipts, authorization, and save projections are replayed before clone release. Current
controls bind every action intent (`role/method/arguments/actionId`) as one globally unique ordered
projection onto its terminal receipt hash and exact trusted-session ledger RPC; a capture alone cannot satisfy the keyboard or exact
recipe proof. The independent PNG review signs visible content only;
it does not authenticate input provenance by itself. If a failure may have dispatched commit authority,
the target clone is preserved behind a recovery blocker rather than reseeded or released.
The current one-shot `purchase-authorization.v2` also binds the exact run id, applicability digest,
and `{shopId,catalogIndex,itemName}` (`厨师`, `24`, `食用油`); generic plans and exact historical
t1903 replay retain v1 only. A close dispatch is not treated as a completed close. Current evidence
binds each Escape/ordinary-close receipt to the immediately following first-session structured
Materials open and its first visible WebOverlay `observation.capture` plus exact `content.read`.
That successor can be admitted only after the prior tracked visual is stable-idle.
The frozen t1903 post-release adapter, finalizer, acceptance, and release replay may use one ephemeral
bootstrap ticket that revalidates the exact legacy blocker and official inspect-receipt bytes before
Build verification; the ticket is never persisted as authority, does not replace the strict
eligibility/finalization marker, and does not add the receipt prefix to the ordinary ignored-output policy.
The exact t1903 eligibility and active finalization marker are immutable historical artifacts. Its
one-time ordinal-inventory continuation therefore writes neither a replacement eligibility nor a
replacement marker: clone-release v4 nests a digest-sealed continuation witness that binds both old
files byte-for-byte, their frozen five-program descriptor set, the current adapter/build/finalizer/
materializer/verifier bytes, the exact 456-path locale-independent ordinal inventory projection,
plus the new inventory digest. Only this exact t1903 marker can use v4;
ordinary and historical clone-release v3 receipts retain their existing replay contract.
A process-crash-complete, digest-named staged v4 receipt is file-flushed and validated in full before
atomic promotion on re-entry; the canonical receipt and resolved marker are also file-flushed. An
incomplete, foreign, duplicate, or digest-mismatched stage remains preserved and fails closed. Windows
does not expose a usable directory-metadata `fsync` through this Node path, so this is not evidence of
arbitrary power-loss durability; after an unclean machine reset, re-inspect the exact immutable artifacts
before invoking the finalizer and never infer completion from a missing stage alone.

```powershell
node tools/workbench-live-e2e/material-shop/finalize-clone-release.js --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json --intent <run-dir>/clone-release-intent.json --out <run-dir>/release.json
```

The runner's strongest result is `CANDIDATE_CAPTURED`, with `e2eVerified=false` until the independent acceptance layer closes.

4. Replay the persisted verifier without driving the UI:

```powershell
node tools/workbench-live-e2e/material-shop/verify-run.js --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json
```

5. Run the three-viewport/material-shop production browser gate from the exact materialized candidate source. The command projects the sealed canonical Playwright toolchain and the single inventory-bound crafting dev harness fixture only for the synchronous browser child, then restores/removes both before writing the receipt; candidate product modules/assets remain materialized. A pre-existing destination, byte drift, callback failure, or cleanup residue fails closed. This starts only the existing headless Edge harness, not Launcher, Flash, or the game candidate.

```powershell
node tools/workbench-live-e2e/material-shop/accept-run.js --capture-static-gate --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json --release <run-dir>/release.json --out <run-dir>/static-gate.json
```

6. Generate the immutable PNG review request. A new Agent Runtime run emits `workbench-live-e2e.material-shop.review-request.v4`; v3 is retained only as an explicit legacy non-Agent replay schema and is never silently reinterpreted as an Agent request. A different reviewer inspects every bound Agent capture and supplies one `workbench-live-e2e.material-shop.review-receipt.v1` whose ordered verdicts exactly match `claims`, with `reviewMethod=independent_visible_png_review`, `reviewScope=visible_png_content_only_not_runtime_interaction_or_capture_provenance`, `independenceAttested=true`, `businessApiCalls=0`, and an exact `reviewReceiptSha256` over the receipt before that digest field is added. The request binds the two trusted-runner completion/transcript/ledger hashes; it does not ask the PNG reviewer to infer native/runtime identity, pointer or keyboard/input provenance, restart provenance, close transitions, persistence, or shutdown from still images.

The v4 Agent claim set contains only visible terminal content. Its step union must cover all 16 `requiresCapture=true` steps exactly once: the two initial material-archive layout frames; visible default `军用帆布` detail; two visible exact recipe-destination frames; the visibly reopened archive; all enemy-drop occurrences; reachable enemy and shop portraits; Chef shop catalog destination; second archive catalog/source frame; Food Oil catalog card; quantity-one cart; zero-sale settlement; visible post-settlement balance; archive owned-species count; and Food Oil owned-one/recipe-usage frame. `reachable_enemy_and_shop_portraits_visible` is mandatory: any visible missing/broken enemy or shop portrait requires a failing verdict, and because every claim must pass, the run cannot be accepted. These claims do not assert how focus moved, that Escape closed a panel, or that the recipe tuple was mechanically exact; raw verifier evidence owns those conclusions.

Current Agent raw replay emits `journey-evidence.v9`. Its portrait projection records only
`capturePresent=true`, `resolutionStatus=pending_independent_visible_png_review`, and the mandatory
independent-review boundary; capture presence can never become an enemy/shop resolution verdict.
The old v6 shape is readable and reproducible only for exact historical t1903 run/plan/evidence
digests. Its misleading `enemyResolved/shopResolved` labels mean only that the old verifier saw the
bound capture; they do not override the PNG review and cannot sign another run. Since the t1903 v4
release also seals its then-current program closure, changing Protocol/JourneyVerifier does not claim
that release can be replayed across program drift. t1903 remains unaccepted and no review receipt is
generated or inferred by this compatibility path.

```powershell
node tools/workbench-live-e2e/material-shop/accept-run.js --create-review-request --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json --release <run-dir>/release.json --static-gate <run-dir>/static-gate.json --out <run-dir>/review-request.json
```

7. Accept and then replay the acceptance. Only this layer may produce `e2e_verified / NOT_DEPLOYED`; it binds the build/candidate identities, both trusted JSONL sessions, raw journey, Agent PNG set, clone release, static gate, review request, and independent review receipt. It never claims promotion or standard-entry verification.

```powershell
node tools/workbench-live-e2e/material-shop/accept-run.js --accept --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json --release <run-dir>/release.json --static-gate <run-dir>/static-gate.json --review-request <run-dir>/review-request.json --review-receipt <independent-review-receipt.json> --out <run-dir>/acceptance.json
node tools/workbench-live-e2e/material-shop/accept-run.js --verify-acceptance --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json --release <run-dir>/release.json --static-gate <run-dir>/static-gate.json --review-request <run-dir>/review-request.json --review-receipt <independent-review-receipt.json> --acceptance <run-dir>/acceptance.json
```

No material-specific formal runner is shipped in this source batch. Runtime promotion and a generic formal-entry smoke may verify the deployed Launcher identity, but neither may be used to claim the material-shop 24-step journey or close `PG-MAT-RELEASE-01`.

8. After acceptance and evidence retention, explicitly release the isolated dirty worktree. This is the only destructive adapter command; it replays the full preparation/build/raw/semantic/static/review/acceptance closure, requires both clean trusted-runner completions plus exact target/restart bytes and archive/restart full-save semantic equality, re-verifies the detached materialization and mechanically discovered shared-producer closure, and replays the schema-bound ignored-output inventory (v3 exact A5 runtime outputs; historical v2 remains verifiable). It refuses recovery blockers, clone locks/recovery records, any foreign ignored path, active Launcher processes, or a pre-existing canonical output. Before removal it durably writes `worktree-removal-intent.json`; only then does it run `git worktree remove --force <exact-owned-resources>`, never global `git worktree prune`. Receipt writing and intent archival are idempotent; successful finalization leaves `worktree-release.json` plus `worktree-removal-resolved-<hash>.json`.

```powershell
node tools/workbench-live-e2e/material-shop/release-worktree.js --preparation <run-dir>/preparation.json --build <run-dir>/candidate-build.json --raw <run-dir>/raw-candidate-journey.json --evidence <run-dir>/journey-evidence.json --clone-release <run-dir>/release.json --static-gate <run-dir>/static-gate.json --review-request <run-dir>/review-request.json --review-receipt <independent-review-receipt.json> --acceptance <run-dir>/acceptance.json --materialization <run-dir>/materialization.json --out <run-dir>/worktree-release.json --acknowledge-discard-isolated-worktree
```

If interruption occurs after the durable intent is written but before exact removal completes,
repeat the same full release command. It replays every acceptance, identity, scope, ignored-output,
clone-lock, and process gate; the fresh clone inspection is reduced only to a stable state projection
for intent comparison (`observedAt` and its receipt digest remain independently validated but are not
part of that projection). Resume requires a byte-exact intent and both the filesystem and Git to report
the same worktree. The finalizer never deletes an existing worktree.
If exact worktree removal completed but receipt writing or marker archival failed, do not recreate
the worktree or rerun the full release command. Resume only the sealed intent:

```powershell
node tools/workbench-live-e2e/material-shop/release-worktree.js --finalize-removal --run-dir <run-dir>
```

Stop on any identity, scope, trusted-session, control, capture, restart, seed, save, operation-lease, or recovery mismatch. Never repair a failed live run by editing the canonical fixture, materialized clone, raw artifact, operation/discard marker, or receipt, and never rerun live execution under the same run id. A crashed operation lease requires the explicit read-only inspection and acknowledged stale-recovery command above; recovery is admitted only when the owner PID is definitely absent or its exact process-start identity proves PID reuse. Spawn/query/access/parse failures and non-Windows external owners that cannot be verified remain `unverifiable` and keep the lease active. Stale recovery only archives the lease and never authorizes deletion or live retry. If a failure may have reached purchase authority while the clone is still owned, the runner writes `recovery-blocker-*.json`; do not retry, reseed, release the worktree, or edit the target. Run only the exact command recorded in that blocker. An intact clone records the read-only inspection below. If the clone is already released and only receipt durability failed, `release-finalization-required.json` records its resumable clone finalizer. If the resources worktree is already absent and `worktree-removal-intent.json` remains, run only the worktree finalizer above. Acceptance/release remain blocked until their respective marker is sealed and archived.

Legacy retained runs remain replayable through their v2 plan/raw schemas and old recovery commands. That compatibility is `legacy replay` only: do not create a new operator-attested Computer Use/CDP/Playwright/SAFEEXIT run from this README.

```powershell
node <resources>/tools/workbench-live-e2e/lib/offline-clone-recovery.js inspect --slot cf7_agent_a5_material_shop_run
```

Any restore/clear mode requires the exact lock/recovery digests printed by that inspection plus its explicit offline-recovery authorization flag.
