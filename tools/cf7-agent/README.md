# CF7 Agent Runtime clients

This directory contains the dependency-free Node.js v1 client shared by the
JSONL CLI and MCP stdio adapter. It uses only Node 20 standard-library modules;
do not create or commit `node_modules`.

F7 froze this client and the Host contract on 2026-07-31 at source commit C1
`dd84230a1d262c6478591cae2d11051b7a8aa7b1`. The ADR filename retains its
initial 2026-07-30 freeze date to avoid canonical-path and link churn. This
documentation-only D1 records its immutable parent C1; it cannot record its own
not-yet-created commit hash. At that D1 C1 had not reached
`candidate_executed`, `e2e_verified`, or `promoted`; the formal runtime is
unchanged. That identity remains historical evidence.

The F8 implementation freeze is source `53caabc90941826ddacf626f536b0f473adbf049`, tree
`5ac63ec05fbbc9b89aa14f7f0b5ab25698f9742d`, immutable candidate `c-0f4c92f237ab-98ebd18146-20260731t022411220z-20da007a`, build identity
`0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C`, payload closure `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0`, and Core
SHA-256 `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD`. Its pure-MCP acceptance report is
`tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.json` and transcript is `tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.jsonl`. The exact identity
reached `e2e_verified / NOT_DEPLOYED` at that historical candidate stage.

The current formal release is source `6f3d50a52413c747b05b74be88d6ee46650f4597`,
tree `253e57f6d20a90fef6addfa744d0487d88f00dfb`, tag
`runtime-build-v2/20260731-agent-runtime-wings-f8-v1`, and request
`A9B33601805709DBB5EAE6DAF312C2B7B0B502096FDD3BDCEA9CBE26D8B1299C`.
Local X509 plus GitHub Hosted OIDC/Sigstore run `30602046108` promoted the same
identity and closure. The no-candidate-id report
`tmp/manual-agent-acceptance/formal-f8/agent-runtime-help-20260731T040942Z.json`
binds `runtimeMode=formal_runtime`, 57 MCP calls, trusted shutdown, unchanged
saves, and no residual delta; this narrow journey reached
`standard_entry_verified`.

Both developer entrypoints discover the Launcher through the current-user
rendezvous document and verify its PID/start-time/lifecycle/ticket tuple; they do
not establish executable-path provenance. They then connect to the project-owned
Windows named pipe, perform `runtime.hello`, and enforce the closed
method-to-capability registry in
`launcher/contracts/agent-runtime/v1/method-registry.v1.json`.
`PipeOptions.CurrentUserOnly` proves only the current user; the Host independently
validates the pipe peer's OS token for the Windows session and elevation/integrity.
For trusted unattended operation, executable path and exact process incarnation
come from the selected Core runner/bootstrap evidence and the Host's final pipe
peer binding, not from the ordinary Node client.

Configuration is explicit. A stable opaque client instance ID is always
required; neither adapter creates a random identity:

```powershell
$env:CF7_AGENT_CLIENT_INSTANCE_ID = '<22-128 character enrolled client ID>'
node tools/cf7-agent/cli.js `
  --project-root . `
  --capability session.status
```

After the Launcher has explicitly enrolled that developer client, both
entrypoints locate its same-user protected credential at the exact
`PersistentDeveloperEnrollmentStore` path under `%LOCALAPPDATA%`, validate the
bounded v1 document, and use its proof only in memory. The credential proof is
never written to stdout or stderr. `--client-instance-id` is equivalent to
`CF7_AGENT_CLIENT_INSTANCE_ID`.

An explicit `--credential-proof` or `CF7_AGENT_CREDENTIAL_PROOF` takes priority
over the protected file, but the stable client ID remains mandatory. This is
useful only when a caller already owns the proof through another protected
channel; do not place the proof in scripts, logs, or rendezvous files.

The same options and the same credential loader apply to `mcp.js`.
`--capability` is repeatable; `--capabilities a,b` and environment variable
`CF7_AGENT_CAPABILITIES` are also accepted. Optional
`--expected-lifecycle-id` pins discovery to one lifecycle. The adapters never
default to the full capability set.

## First observation grant

The hidden Hello intentionally does not expose a full session descriptor or target
inventory. After authentication, both adapters use the same F4 bootstrap:

1. Call `session.status` with `{}` and retain its opaque `lifecycleRef`.
2. Call `observation.grant.issue` with that lifecycle reference and exactly one of
   `targetKinds` or `targetIds`.
3. Read `sessionScope.sessionId`, `sessionScope.lifecycleGeneration`, and the exact
   `targetScope` from the successful grant.
4. Use those values for `window.list`, capture, or a later grant narrowed by exact
   target ID.

For the first grant, `targetKinds` avoids requiring target IDs that are intentionally
hidden before authorization. The closed kinds are `launcher`, `flash`,
`web_overlay`, `native_hud`, `wings_shell`, and `business_modal`. The Host resolves
them only inside the unique current logical session to registered
`RuntimeOwned` targets authorized by the authenticated principal. In production,
`business_modal` always resolves to an empty, non-disclosing scope: the internally
registered `BusinessModal` is a human-only security surface and cannot be observed
or controlled. The complete
credential `AllowedTargets` set is not a wire request field and cannot be overridden
by the client. The protected enrollment file contains an issuer-produced copy for
credential validation, but the adapter never forwards that array as authority.
`targetIds` is for an already discovered exact target scope; it is not an HWND,
title, path, or global discovery mechanism. Every resolved grant is non-empty and
capped at 32 targets.

F8 production advertises the embedded Flash target as metadata-only with exact
`observationModes:[]` and `inputModes:[]`. A pixel-authorized grant does not add
a producer: `observation.capture` against that target must fail exactly with
`unsupported_for_surface`; never substitute a Flash keyframe, parent-window crop,
or native input. Launcher, WebOverlay, and NativeHud use only
`window_graphics_capture` (WGC) for production pixel observation. The type-level
registry still describes potential capabilities, but an actual tool also needs
the granted session capability and a matching current surface mode. In
particular, F8 production neither grants nor lists `window.activate` and has an
empty activator map.

Start the JSONL client with only the capabilities the workflow needs:

```powershell
node tools/cf7-agent/cli.js `
  --project-root . `
  --capability session.status `
  --capability observation.grant.manage `
  --capability window.list
```

`observation.grant.issue` and `observation.grant.revoke` are wire methods.
Their shared handshake capability is `observation.grant.manage`; method names
that differ from their required capability must not be copied into
`--capability`.

The first JSONL request is:

```json
{"jsonrpc":"2.0","id":"status-request-0000001","method":"session.status","params":{}}
```

After reading its actual `lifecycleRef`, issue a kind-scoped grant (the placeholder
below must be replaced by that exact opaque value):

```json
{"jsonrpc":"2.0","id":"grant-request-00000001","method":"observation.grant.issue","params":{"lifecycleRef":"<exact lifecycleRef from status response>","targetKinds":["flash"],"dataScopes":["window_metadata"],"requestedTtlMs":60000,"allowEphemeralKeyframes":false,"allowPersistence":false,"allowExport":false}}
```

Then call `window.list` with the returned session and grant IDs:

```json
{"jsonrpc":"2.0","id":"windows-request-000001","method":"window.list","params":{"sessionId":"<sessionScope.sessionId>","observationGrantId":"<observationGrantId>","dataScope":"window_metadata"}}
```

MCP follows the identical sequence with `tools/call` names `session.status`,
`observation.grant.issue`, and `window.list`; it does not expose Welcome as a tool.
If no unique current session exists, the status result has no usable lifecycle
reference and the caller must wait for Host lifecycle state to change rather than
guess a session or target.

## F8 structured Launcher panel action

F8 gives the Host-owned `panel.open` callback its own non-native write boundary.
An F8-matched client requests `kind:"structured_action"`; it must not request
`gui_input`, infer native-input authority from the capability, or require the
Launcher surface to advertise an input mode. The only F8 structured lease is
exactly one `panel.open` action against exactly one current `RuntimeOwned`
`Launcher` target, with a TTL no greater than 30 seconds. This developer flow
therefore starts the JSONL client with only the capabilities it uses:

```powershell
node tools/cf7-agent/cli.js `
  --project-root . `
  --capability session.status `
  --capability observation.grant.manage `
  --capability observation.capture `
  --capability window.list `
  --capability lease.acquire `
  --capability panel.open
```

First call `session.status` as shown above. Substitute its exact `lifecycleRef`
into a Launcher-scoped pixels grant; the additional `window_metadata` scope is
used only to select one exact registered Launcher target:

```json
{"jsonrpc":"2.0","id":"launcher-grant-request-01","method":"observation.grant.issue","params":{"lifecycleRef":"<exact lifecycleRef from status response>","targetKinds":["launcher"],"dataScopes":["window_metadata","pixels"],"requestedTtlMs":60000,"allowEphemeralKeyframes":false,"allowPersistence":false,"allowExport":false}}
{"jsonrpc":"2.0","id":"launcher-list-request-001","method":"window.list","params":{"sessionId":"<grant.sessionScope.sessionId>","observationGrantId":"<grant.observationGrantId>","dataScope":"window_metadata"}}
```

Select one exact surface whose `kind` is `launcher`, whose `targetId` is in the
grant's `targetScope`, and whose current state is eligible for the operation.
This is selection of one authorized target, not an assertion that the logical
session globally contains only one Launcher target. If the intended target
cannot be selected without ambiguity, stop. Capture a fresh before-observation;
Flash snapshot fallback is inapplicable and remains explicitly disabled:

```json
{"jsonrpc":"2.0","id":"launcher-capture-request1","method":"observation.capture","params":{"observationGrantId":"<grant.observationGrantId>","sessionId":"<grant.sessionScope.sessionId>","targetId":"<exact Launcher targetId>","dataScope":"pixels","allowValidatedFlashKeyframeFallback":false}}
```

Acquire the one-shot structured lease from the same session and exact target.
The request must contain no domain transaction fields and no client-supplied
operation binding:

```json
{"jsonrpc":"2.0","id":"panel-lease-request-0001","method":"lease.acquire","params":{"sessionId":"<before.sessionId>","kind":"structured_action","capabilities":["panel.open"],"targetScope":["<before.targetId>"],"requestedTtlMs":30000,"requestedActionLimit":1}}
```

The returned descriptor must have `purpose:"structured_action"`, exact
`capabilities:["panel.open"]`, the same singleton target, `maximumActions:1`,
and no `renewAfter`. Any mismatch is a terminal client-side validation failure.
Use only values copied from the before-observation and lease response:

```json
{"jsonrpc":"2.0","id":"panel-open-request-00001","method":"panel.open","params":{"actionId":"<fresh opaque action ID>","idempotencyKey":"<fresh opaque idempotency key>","deadlineMs":30000,"sessionId":"<before.sessionId>","observationGrantId":"<before.observationGrantId>","leaseId":"<lease.leaseId>","observationId":"<before.observationId>","expectedLifecycleGeneration":1,"targetId":"<before.targetId>","expectedSurfaceEpoch":1,"expectedCoordinateSpaceVersion":1,"expectedFocusEpoch":1,"expectedModalEpoch":1,"frameId":"<exact Launcher frameId from before.frames>","operation":"panel.open","arguments":{"panel":"help"},"reason":"Open the allow-listed help panel"}}
```

The generation values shown as `1` are type-correct JSON examples, not
constants; replace each with the exact corresponding integer from the
before-observation. When the before-observation contains `attemptId` plus
`attemptGeneration`, `panelInstanceId`, or `documentGeneration`, copy them
exactly as `expectedAttemptId` plus `expectedAttemptGeneration`,
`expectedPanelInstanceId`, and `expectedDocumentGeneration`; omit an optional
binding only when the authoritative observation omits it. Do not invent,
normalize, or carry a binding from an older observation.

An `input_dispatched` / `broker_dispatch` receipt proves only that the trusted
Launcher router accepted the allow-listed request. It does not prove that the
WebOverlay became visible. After that receipt, issue a new grant rather than
expanding or reusing the Launcher grant:

```json
{"jsonrpc":"2.0","id":"web-grant-request-000001","method":"observation.grant.issue","params":{"lifecycleRef":"<same still-current lifecycleRef>","targetKinds":["web_overlay"],"dataScopes":["window_metadata","pixels"],"requestedTtlMs":60000,"allowEphemeralKeyframes":false,"allowPersistence":false,"allowExport":false}}
{"jsonrpc":"2.0","id":"web-list-request-0000001","method":"window.list","params":{"sessionId":"<fresh grant.sessionScope.sessionId>","observationGrantId":"<fresh grant.observationGrantId>","dataScope":"window_metadata"}}
{"jsonrpc":"2.0","id":"web-capture-request-0001","method":"observation.capture","params":{"observationGrantId":"<fresh grant.observationGrantId>","sessionId":"<fresh grant.sessionScope.sessionId>","targetId":"<exact WebOverlay targetId selected from the fresh scope>","dataScope":"pixels","allowValidatedFlashKeyframeFallback":false}}
```

The client must stop if the lifecycle changed, the fresh grant is empty, or the
intended WebOverlay cannot be selected exactly from its authorized scope. A
fresh WebOverlay observation may support visual reconciliation; it does not
turn the earlier broker-dispatch receipt into domain or causal proof.

Production accepts only panel names `help`, `map`, `tasks`, `team`, `jukebox`,
`settings`, `settings_camera_preview`, and `materials`. `settings` opens the
Host-owned Web settings surface; `settings_camera_preview` is an exact diagnostic
alias that maps to that same panel with `initialView:"camera_preview"` after the
authoritative settings snapshot arrives. Neither name applies or saves settings,
and neither creates Flash pixel/input authority. A runner that needs the entry
Flash image must first use a metadata-only Flash grant plus `window.list` to wait
past the startup `200×101` surface, then verify the visible result with a fresh
WebOverlay WGC grant. `materials` reuses the fixed Host-to-AS2 `openMaterialUI`
handshake with the `nativehud_materials` origin; it is not a direct Web-panel
open. Its dispatch receipt must be followed by a fresh WebOverlay observation
of the exact crafting/materials result. Every production panel-instance producer, including PanelHost, the
Loot coordinator, and Router fallback, generates an opaque ID with at least
144 bits of CSPRNG entropy. Prefixes such as `panel`, `panelloot`, or `fallback`
are diagnostic only and must never be interpreted as authority, ordering, or
client-chosen identity.

The compatibility boundary is fail closed:

- `gui_input` plus `panel.open` is invalid after F8. Do not retry it as a
  compatibility downgrade, and never add `send_input_guarded` to Launcher.
- `structured_action` is a closed-enum contract addition. An older strict
  client or Host that does not recognize it is incompatible and must stop
  rather than forward, reinterpret, or downgrade the request.
- `PlayerAssist` cannot acquire this phase-one structured lease. The ordinary
  developer example above is not a consent path, and the Node wrapper never
  becomes an unattended principal.
- The structured path binds no `NativeInputGuard` lease and emits no mouse or
  keyboard packet. It still participates in the session's single-writer,
  observation, generation, audit, human-override, and revocation fences.
- Trusted unattended shutdown authority is unchanged: the verified Core runner still
  uses the dedicated shutdown lease, requests only an exact Launcher
  observation with `allowValidatedFlashKeyframeFallback:false`, and accepts no
  Flash or fallback frame as shutdown authority.

The F8 visible acceptance used the trusted `--adapter mcp` path only. It did not
use Codex Computer Use, browser/Chrome, legacy privileged HTTP, or any `input.*`
tool; it kept captured pixels in memory only for SHA-256 verification, wrote no
PNG, and requested neither persistence nor export. Those facts are bound to
`tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.json` and `tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.jsonl`, not inferred from this example.

## F7 typed boundaries retained under F8

The adapters mirror the Host's exact parameter and result contracts:

- `observation.capture` requires the exact constant `dataScope:"pixels"` and a
  `pixels`-authorized grant; the field is not a scope selector. `window.state` has its own closed
  `window_metadata|pixels` data-scope field.
- Grant-free `app.list` and `app.launch` return only minimal standard-entry state,
  never a session, target, HWND, PID, or path inventory. Pipe `app.launch` is
  not itself a pre-launch control channel.
- `trace.export` is advertised only to an explicitly enrolled developer in a
  `DeveloperInteractive` session with `trace.export + observation.export`, exact
  `consentPurpose`, and a same-principal/session grant carrying
  `data.export + allowExport` plus a consent receipt. The Host exports at most
  8 MiB of scoped Runtime-owned JSONL using an exclusive process-incarnation
  pending marker and same-directory atomic move. Controlled failures clean only
  owned files; a blocked delete retains the marker for a dead-owner/inactive-
  transaction janitor retry. Marker removal is the publication linearization
  point, so the single-file move is not a cross-resource audit/filesystem
  "every failure leaves zero residue" guarantee. A `trace_export_completed` fact
  written before marker removal is publish-prepared, not standalone publication
  proof; a later failed fact for the same artifact compensates a failed closeout.
  The wire returns only an artifact ID/name, never an arbitrary
  filesystem path.
- Every `appearance.hair.change.v1.*` call uses one identical exact
  `WebOverlay + DomainTransaction` target and the operation-specific typed params;
  a generic, cross-target, or multi-target chain is rejected. Commit uses
  `expectedCurrentHair` CAS, a focused runner, and zero replay. An unknown receipt
  never carries a raw restore token: the token remains in the same
  `HairAppearanceModifierTransaction` instance's lifecycle-local escrow and can be
  consumed once only after exact connection/principal/session/lifecycle/target
  validation and authoritative durable reconcile. A different connection, new
  transaction, or Core restart can never receive it. The Launcher-owned consent
  prompt binds its exact Launcher HWND/owner and prompt instance; foreign input,
  a second security surface, or any binding drift fails closed.
- Web navigation start immediately advances document generation. `window.state`
  remains read-only and type-level distinct from `window.activate`; F7 defined
  exact process/HWND/owner, session/lifecycle, attempt, target, surface,
  coordinate, focus, and modal binding for that action. F8 production does not
  grant or advertise `window.activate`, and its activator map is empty.
- Player-assist consent is server-bound to the credential issuer receipt. Neither
  JSONL nor MCP accepts a caller-selected principal, approval, issuer key, or receipt
  substitution as authority.
- `LeaseDescriptor.purpose` is required and `renewAfter` is optional. A shutdown
  descriptor omits `renewAfter`. Shutdown exists only for `DeveloperInteractive` or
  `UnattendedTest`; its exact scope resolves one current `RuntimeOwned` Launcher
  target. That is exact scope cardinality, not a claim that the session globally
  contains only one Launcher target. The lease has only `session.shutdown`, TTL at
  most 30 seconds, one action, and no renewal. Only a
  syntactically valid, authenticated, fully authorized PlayerAssist acquire that
  reaches issuance policy returns `consent_required`; malformed, unauthorized, or
  direct action requests may fail earlier.
- Renew/release resolves only the exact active lease and exact client/principal
  owner; a tombstone, owner mismatch, or unrelated lease cannot clean the active
  owner. The live table contains only active or reservation-draining leases; terminal
  tombstones are a 256-item FIFO. A separate committed-shutdown latch retains 64
  exact session IDs without eviction and overflows to global fail-closed. Tombstone
  eviction never reopens a writer.
- The same action/idempotency identity and canonical payload replays the exact
  retained `ContractReceipt`, including `DeliveryUnknown` terminal `Unknown`, with
  zero redispatch, zero second generic-action audit group, and zero secondary
  receipt synthesis. Mismatched canonical
  payload or identity remains a conflict.
- The successful lease consumer alone owns the session execution reservation through
  every JSON/optional-binary response frame completing `WriteAsync` or explicit
  abort. A failed consumer never owns and cannot release another owner's reservation.
  Before the first success byte, the Gateway first claims audit response identity and
  then lease write ownership plus the human-input sequence fence. Second-claim
  failure keeps zero success bytes, compensates audit pending to
  `action_response_unknown`, and aborts SafeExit. Full-frame `WriteAsync` commits
  only the server-side delivery disposition, not peer acknowledgment; a later Flush
  failure does not roll it back. Delivery-unknown uses
  `EvidenceKind.ReconciliationRequired`. Generic audit append rejects the reserved
  `action_response_written` and `action_response_unknown` names. Post-write
  audit-append failure marks continuity lost, removes pending, and truncates the
  segment without synthesizing Unknown on later disposal.
- External/human input preempts all active, execution-pending, delivery-pending, or
  queued actions that have not claimed delivery-write ownership. Once shutdown
  claims it before byte one, ordinary revoke/human override cannot roll it back;
  response completion alone owns the terminal outcome. A dependent host abort
  callback returning false or throwing retains the session reservation and marks
  continuity lost. A post-write commit callback returning false or throwing cannot
  roll delivery back, marks continuity lost, and does not guarantee SafeExit continuation.
- An action's one absolute deadline starts when its complete CF7A request frame is
  received, before parsing, and covers parse, admission, scheduler, performer,
  response-writer lock, and every JSON/optional-binary response `WriteAsync`; no phase
  resets it.

Unknown properties, lower-scope labels for higher-data results, and locally invented
compatibility defaults are rejected before forwarding. Credential rotation or
revocation invalidates the live connection; the client must rediscover and
reauthenticate with a newly issued receipt rather than replaying the old pipe.

## Trusted unattended entry

The final unattended security boundary is the verified Core binary, not this Node
wrapper or PowerShell:

```powershell
node tools/cf7-agent/unattended.js `
  --adapter jsonl `
  --slot cf7_agent_equipment_tuning

# A5 isolated-candidate example; formal binding omits --candidate-id but is not a material acceptance runner
node tools/cf7-agent/unattended.js `
  --adapter mcp `
  --slot cf7_agent_a5_material_shop_run `
  --candidate-id a5
```

`unattended.js` accepts only `--adapter jsonl|mcp`, one frozen slot, and an optional
safe immutable candidate leaf ID. It invokes the fixed system PowerShell and
`automation/start.ps1`; it never becomes a principal. The start script applies the
v2 strict verifier to the full manifest inventory, selected payload, build identity,
and payload closure, then executes that exact
`Core.exe --agent-unattended-runner --adapter ... --slot ...`.

The slot allow-list is:

- `cf7_agent_equipment_tuning`
- `cf7_agent_arena_calibration`
- `cf7_agent_character_build`
- `cf7_agent_loot_target_full_v1`
- `cf7_agent_a5_material_shop_run` — accepts exactly two runtime bindings:
  `--candidate-id a5` resolves the materialized
  `resources/tmp/runtime-candidates/v2/a5` candidate, while no candidate
  selector binds the verified canonical `formal_runtime`. It rejects ordinary
  `c-*` candidates and every other short leaf.

The historical slots retain the existing boundary: no candidate ID selects
formal runtime, while an explicit candidate ID must match the immutable `c-*`
leaf contract. A5's formal binding only admits the verified runtime shape; there
is no material-specific formal admission/runner, so a bare/direct invocation
cannot prove or close the material 24-step journey or `PG-MAT-RELEASE-01`.

The Core runner owns the Guardian lifecycle. Normal stdin completion requests its
exact-one current `RuntimeOwned` Launcher observation (scope cardinality, not a
session-global singleton) with
`allowValidatedFlashKeyframeFallback=false` and accepts only the exact target's
`SourceLayer.Launcher` frame. It strictly validates a dedicated shutdown lease with
active `UnattendedTest`, purpose `Shutdown`, no `renewAfter`, exact
owner/principal/session/attempt/target, singleton capability/operation, one action,
and issuer receipt. It then sends `session.shutdown` and requires a complete receipt
bound to the same action/target/before-observation with `terminal=true`,
`outcome=input_dispatched`, `evidenceKind=broker_dispatch`,
`reasonCode=shutdown_requested`, `reconcileKind=none`, `retryable=false`,
`focusVerified=false`, and `leaseState=consumed`.

Only two exact structured setup transients have bounded retries. Capture is
attempted at most four times with 750/1250/2000 ms delays, and only
`capture_unavailable / retryable=true / reconcileKind=none` permits another
attempt. Shutdown lease acquire is attempted at most four times with
100/200/400 ms delays, and only `input_not_quiescent / true / none` permits
another attempt. Retries keep the same grant/session/target/parameters or the
same lease scope, changing only the RPC request ID. All other errors fail
immediately. The final `session.shutdown` action is never retried.

After that strict receipt, the same exact owned child must exit within 10 seconds
with exit code 0. A timeout, nonzero exit, or forced kill is failure and never E2E
success. Each JSONL call has a 30-second wall-clock deadline. Each MCP `tools/call`, including one active after
stdin EOF, has one absolute 30-second budget from handler start through buffered
response copy and flush; concurrent active-loop output consumes the same remaining
budget. Idle lifecycle, `tools/list`, and protocol-error output each has an
independent 30-second budget. The complete shutdown transcript has another
30-second deadline. A deadline cancels the call, closes the authenticated pipe
without fabricating a response, and enters bounded exact-child recovery; failure to
observe a killed exact child within 5 seconds is explicit failure.

Credential acquisition uses a fixed internal 30-second monotonic deadline,
independent of the bootstrap/session document's 10-minute maximum lifetime; JSONL,
MCP, and callers have no tuning option. Each periodic full Host surface refresh
(250 ms by default) retries complete unattended credential
observe/publish/enforce processing. The unattended-binding lock keeps those
attempts single-flight, while the stopping fence and teardown barrier prevent a
queued refresh from publishing through disposed dependencies.

Only adapter exit 0 plus an observed strict shutdown receipt, clean exit of the
exact owned Guardian, and no forced recovery emits success evidence. The single
stderr line uses the exact prefix `cf7-trusted-runner-evidence: `, is at most
16 KiB, and contains only schema
`cf7.agent_runtime.trusted_unattended_completion.v1`, `runtimeMode`,
`processPath`, `coreSha256`, `buildIdentity`, `payloadClosure`,
`guardianProcessId`, and strict `terminalReceipt`; it never contains
credential/ticket/nonce secrets. stdout remains protocol-only.

## Fixed formal-runtime pre-launch

`prelaunch.js` is the separate narrow authority for the one case where no
Launcher pipe exists yet:

```powershell
node tools/cf7-agent/prelaunch.js `
  --client-instance-id '<22-128 character enrolled client ID>'
```

It derives the project root from its own repository location, loads that client's
protected developer credential, and requires the credential to contain
`app.launch`. The only accepted option is the explicit client instance ID. The
caller cannot supply a project root, executable, script, runtime mode, candidate,
legacy flag, credential proof, capability set, or shell fragment.

If a protected, process-bound `formal_runtime` rendezvous is already available,
the authority authenticates directly and does not start another process.
Otherwise it starts the exact repository `automation/start.ps1` with no
`-CandidateRoot` or `-EnableLegacyHttpAutomation`, using the verified absolute
system Windows PowerShell path and a fixed argument array with shell expansion
disabled. It then waits for the protected rendezvous,
authenticates through the shared `AgentClient`, and calls only:

```json
{"method":"app.launch","params":{"launchRequestId":"<fresh opaque request ID>","entryPoint":"standard_entry","runtimeMode":"formal_runtime"}}
```

Successful stdout is exactly one JSON line containing the frozen minimal
`app.launch` receipt. Bootstrap diagnostics and credential/ticket secrets are
never forwarded. Before authenticated handoff, timeout or failure may terminate
only the PowerShell bootstrap child created by this invocation; it never scans
for or kills a Guardian process. A valid non-formal rendezvous fails closed.

This authority was present in C1
`dd84230a1d262c6478591cae2d11051b7a8aa7b1` but absent from the unchanged formal
runtime at D1. The later F8 formal release now contains the matching authority,
protected rendezvous, and enrolled trusted-runner path; the successful standard
entry evidence above proves that exact bounded composition, not arbitrary
`app.launch` authority for ordinary clients.

The CLI reads and writes one strict CF7 JSON-RPC object per line. Its own
`runtime.hello` is hidden and cannot be supplied on stdin. MCP uses the
2025-06-18 stdio boundary: the first request must be `initialize`; after its
successful response the client must send `notifications/initialized` before
`tools/list` or `tools/call`. It accepts string or JSON-safe-integer outer request
IDs and otherwise supports only `notifications/cancelled`; invalid or unsupported
notifications produce no JSON-RPC response. Every tool call receives a fresh
internal string ID; outer IDs and notifications are never forwarded. Cancellation
suppresses the local MCP response but does not invent a CF7 notification.
Cancelling an active `tools/call` also closes the entire underlying Agent
connection so the Runtime can revoke its grants, leases, and pending actions; a
caller that may have crossed the dispatch boundary must reconnect and use
`action.get` rather than retrying a write blindly. That reconnect contract applies
to the developer MCP entrypoint. In the trusted unattended Core runner,
cancellation closes the authenticated pipe and fail-closes the exact owned
Guardian; the isolated lifecycle is not preserved for reconnect, and the
cancelled run is never reported as E2E success.
`tools/list` publishes the compiled parameter contract's top-level
`properties`, `required`, basic field types, and `additionalProperties:false`
for every granted method. Nested `binding`/`arguments` and operation-specific
bounds remain identified by `x_cf7ParameterContract` and are authoritatively
checked by the same strict Host validator; this projection is not a replacement
for the canonical method-params schema.

`content.read` is specialized in the shared client. It validates the JSON
receipt and separately bound binary frame, and can assemble and SHA-256 verify a
bounded object. JSONL and MCP each return one bounded chunk as
`{result,metadata,contentBase64}` in their own outer protocol result; no base64
is inserted into the CF7 pipe JSON.

Run the standard-library test harness with:

```powershell
node --test tools/cf7-agent/tests
```

F7 historical source evidence is Launcher **2678 passed + 3 explicit opt-in skipped /
2681 total, 0 failed**, repository SDK resolver **7/7** resolving exact SDK
**10.0.300**, Node client **37/37**, and TrustedRunner-filtered **48/48**. These are
C1 source-level results only; C1 has not reached `candidate_executed`,
`e2e_verified`, or `promoted`, and the formal runtime is unchanged.

F8 fresh gates are SDK resolver **7/7** resolving exact .NET SDK
**10.0.300**, Launcher **2724 passed + 3 explicit opt-in skipped / 2727 total,
0 failed**, Node client **37/37**, TrustedRunner **57/57**, and production policy
**26/26**. First-stage evidence is bound to source `53caabc90941826ddacf626f536b0f473adbf049`, tree
`5ac63ec05fbbc9b89aa14f7f0b5ab25698f9742d`, candidate `c-0f4c92f237ab-98ebd18146-20260731t022411220z-20da007a`, build identity
`0F4C92F237ABD7785C957F3CD135ABF2EFB1EB5D9AB5671B869F39D00970675C`, payload closure `54FBCCBA7C90ACF407B09E38FFB874C13DE3CDFB80CF62D0F8D4E239A42962F0`, Core
SHA-256 `86DF1F5DC611037DB3A85FD9BA0D43490394F232D25A4F62B59AA4F2B4B6E4FD`, report `tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.json`, and transcript
`tmp/manual-agent-acceptance/agent-runtime-help-20260731T022753Z.jsonl`. It
reached `e2e_verified / NOT_DEPLOYED` at the candidate stage. The later formal
release retained the same identity/closure, added Core DLL SHA-256
`0CEA0C64C037090ADAB4E9C38294075E58F1D298615DD447677D0D6725A9271E`,
and reached the bounded `standard_entry_verified` status described above.
Physical multi-monitor, Flash pixels/input, the GUI 13/13 matrix, Hair/Wings
full product behavior, and human visual acceptance remain outside this evidence.

stdout is reserved for protocol messages. Diagnostics, configuration failures,
and malformed notification reports go to stderr.
