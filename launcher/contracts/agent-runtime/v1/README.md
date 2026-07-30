# CF7 Agent Runtime wire contract v1

This directory is the versioned source of truth for the phase-1 wire representation.
The current source tree also contains gateway, capture, input, domain, and client
implementations and production `Program` composition. Source presence does not prove
that a clean immutable candidate was built or executed. Candidate execution is an
isolated stage, not the standard entry; only promotion followed by a no-argument
standard-entry verification of the same identity can establish deployment.

F7 was frozen on 2026-07-31 at source commit C1
`dd84230a1d262c6478591cae2d11051b7a8aa7b1`. The ADR filename retains its
initial 2026-07-30 freeze date to avoid canonical-path and link churn. This
documentation-only D1 records its immutable parent C1; D1 cannot record its own
not-yet-created commit hash. At this closeout point C1 has not reached
`candidate_executed`, `e2e_verified`, or `promoted`; the formal runtime is
unchanged. Source presence therefore does not establish deployment or
standard-entry verification.

Files:

- `agent-runtime.v1.schema.json`: JSON Schema 2020-12 catalog for handshake,
  session, surface, grant, lease, observation, action, and terminal receipt payloads.
- `json-rpc.v1.schema.json`: exact single-message JSON-RPC 2.0 request,
  success, structured error, content-read, and binary-header representations.
- `method-registry.v1.json`: closed method-to-capability registry. It is a
  protocol error to route an unregistered method.
- `parameter-contracts.v1.json`: exact required/optional property table,
  closed observation data scopes, nested hair binding, and per-operation action
  argument allowlists.
- `method-params.v1.schema.json`: JSON Schema form of every non-Hello method
  parameter contract and every action argument contract.
- `capability-applicability.v1.json`: the 13-item GUI capability set and its mode,
  surface, observation, semantic, lease, and containment gates.
- `limits.v1.json`: frame, queue, TTL, rate, lease, and identifier hard caps.
- `reason-codes.v1.json`: closed reason-code registry with legal outcome,
  reconciliation, and retry semantics.
- `canonical-json-vectors.v1.json`: canonical action-payload vectors.
- `contract-vectors.v1.json`: valid and invalid cross-field examples used by the
  C# conformance tests.
- `rpc-vectors.v1.json`: valid and invalid JSON-RPC and binary-chunk examples.

The CF7A transport accepts one request or one response per JSON frame. A request is
exactly `{"jsonrpc":"2.0","id":string,"method":string,"params":object}`. A success
is exactly `{"jsonrpc":"2.0","id":string,"result":...}`. A failure is exactly
`{"jsonrpc":"2.0","id":string,"error":{"code":int32,"message":string,"data":
{"reasonCode":string,"retryable":boolean,"reconcileKind":string,
"serverSequence":positive-safe-integer}}}`. `result` and `error` are mutually
exclusive. Batch messages, notifications, numeric IDs, null IDs, duplicate
properties, unknown top-level properties, and unregistered methods are rejected.
Malformed messages without an accepted string ID may be closed without a response;
the server must not manufacture a null ID that this profile forbids.

`runtime.hello` is the only pre-authentication method and its `params` are exactly
`HelloMessage`. Every other method is authorized against the required capability
in `method-registry.v1.json`. Each of the 13 GUI capability names is itself its
wire method. There is deliberately no generic `action.execute` wire method:
action-shaped methods carry an `ActionEnvelope`, and the Gateway must set and verify
that `ActionEnvelope.operation` equals the selected method before invoking the
shared executor. `action.get` is the read-only receipt lookup route.

## First observation grant bootstrap

F4 deliberately keeps the full session and target inventory out of `Welcome`.
Phase 1 supports exactly one current logical session. `minimalSessionRef` contains
only `projectRunning`, `qualificationState`, and, when that unique current session
exists, an opaque `lifecycleRef`. Zero or multiple registry sessions do not produce
a usable lifecycle reference.

The required call order is:

1. Call granted `session.status` (or the same minimal `session.discover` contract)
   and read `lifecycleRef`.
2. Call `observation.grant.issue` with that `lifecycleRef` and exactly one target
   selector: `targetKinds` or `targetIds`.
3. Read the exact `sessionScope` and `targetScope` from the successful grant.
4. Use that grant with `window.list`, `window.get`, capture, or domain methods.

`targetKinds` is the bootstrap selector for a client that does not yet know opaque
target IDs. Its closed values are `launcher`, `flash`, `web_overlay`, `native_hud`,
`wings_shell`, and `business_modal`. `targetIds` is used to narrow a later grant
after exact IDs are already known. Supplying neither selector or both selectors is
invalid.

The Host resolves either selector only within the unique current session and only
to the intersection of registered `RuntimeOwned` surfaces and the authenticated
principal's verified `AllowedTargets`. `AllowedTargets` is a server-side
authorization decision input: it is not accepted from Hello or any method params,
and the complete list is not returned by the pre-grant protocol. An issuer-produced
copy inside a protected developer-enrollment credential is evidence bound to that
credential, not a client assertion; the adapter never forwards it as grant
authority. A successful descriptor reveals only that grant's resolved exact target
scope. The resolved scope must be non-empty and has a hard cap of 32 targets, also
advertised as `Welcome.limits.maximumTargetScopeItems`.

Where a method requires exact-one target cardinality, “one target” means its
authorized exact scope resolves to one current `RuntimeOwned` target. It does not
assert that the session registry contains only one target of that kind. In
particular, shutdown selects one current `RuntimeOwned` Launcher target from the
request's exact scope; it is not a session-global Launcher singleton rule.

Issuance is a two-sided authority check. The dispatcher validates the opaque
lifecycle reference and current generation before issuing; after the broker creates
the grant, it snapshots the registry again and revalidates lifecycle, every exact
target's `RuntimeOwned` classification, the principal target authority, and any
requested kind. A mismatch revokes the new grant before returning a stale/scope
rejection. A kind request that has no authorized intersection must not disclose
whether an unauthorized target exists.

## F5–F7 method and authority closure

F5 binds authorization to the data and target authority a method actually consumes:

- `observation.capture` requires the exact constant assertion
  `dataScope:"pixels"`; it is not a selectable lower scope. `window.state`
  separately accepts only
  `window_metadata` or `pixels` and authorizes the exact requested representation.
- `app.list` and `app.launch` are grant-free only because their results are minimal
  and contain no session, target, window, process, or path inventory. `app.launch`
  can report the already-running standard entry; it is not pre-launch authority.
- `trace.export`'s target contract requires an `observationGrantId` for the
  authenticated principal and current session with `data.export` and
  `allowExport=true`. Those checks are not sufficient on their own: production also
  requires an enrolled `DeveloperInteractive` principal, exact `consentPurpose`
  capabilities and receipt, and a complete trusted principal/session/purpose-scoped
  audit hash chain. A mixed, incomplete, global, or otherwise unscoped segment is
  never export authority and must not advertise the method. Once every scoped gate
  is complete and current, production may advertise the method and a direct call may
  succeed; the old incomplete segment is not a permanent production disable switch.
- All six `appearance.hair.change.v1.*` methods require the same single exact
  `RuntimeOwned` WebOverlay target classified `DomainTransaction`. A generic
  Runtime-owned target, a cross-target chain, or a multi-target grant is invalid.
- A `player_assist` consent receipt must exactly equal the active credential's trusted
  issuer receipt. The server derives the principal/issuer budget key; callers cannot
  select or reset that key by changing receipt text.
- Every `LeaseDescriptor` requires `purpose`; `renewAfter` is optional. A shutdown
  descriptor must omit `renewAfter` entirely—null, zero, or a synthetic value is not
  an alternative representation.
- `session.shutdown` uses a distinct shutdown lease whose exact target scope
  resolves to one current `RuntimeOwned` Launcher target; this cardinality is not
  a session-global singleton assertion. Its only capability/operation is
  `session.shutdown`, its TTL is at most 30 seconds, its action limit is one, and it
  cannot be renewed. Phase one issues it only in `DeveloperInteractive` or
  `UnattendedTest`; it never emits a `PlayerAssist + Shutdown` descriptor. Only a
  syntactically valid, authenticated, fully authorized PlayerAssist acquire that
  passes every earlier connection/principal/session/method/target gate and reaches
  issuance policy returns `consent_required`. Malformed, unauthorized, or direct
  action requests may fail earlier; enrollment and ordinary write receipts are not
  exit authority.
- A session execution reservation belongs only to the action whose lease consume
  succeeded and remains held through every response frame (JSON plus any optional
  binary frames) completing `WriteAsync`, or through explicit abort. A failed
  consume never owns the reservation and therefore cannot release, abort, or
  overwrite another owner's reservation or lease. Shutdown cannot cross a
  predecessor mutation or restore-token receipt.
- Lease renew and release resolve only the exact active lease and exact
  client/principal owner. A terminal tombstone, mismatched owner, or unrelated
  lease cannot clean up the active owner. The live table retains only active or
  reservation-draining leases; terminal lease tombstones use a 256-item FIFO. A
  separate committed-shutdown latch retains up to 64 exact session IDs without
  eviction; the next distinct session overflows to a global fail-closed latch.
  Tombstone eviction can never reopen a session for writes.
- The same action/idempotency identity and canonical payload replays the exact
  retained `ContractReceipt`, including the `DeliveryUnknown` terminal `Unknown`;
  it causes zero redispatch, zero second generic-action audit group, and zero
  secondary receipt synthesis. A
  canonical-payload or cross-index identity mismatch remains an idempotency
  conflict.
- SafeExit is only armed before response delivery. Before the first successful byte,
  the Gateway performs two claims in order: first the exact pending terminal-audit
  identity, then shutdown-lease write ownership together with the captured
  human-input sequence fence. If the second claim fails, successful bytes remain
  zero; the first audit pending is compensated to the sole
  `action_response_unknown`, the action is fixed at `unknown/manual`, and SafeExit
  abort is synchronously acknowledged before the owner releases its reservation.
- Delivery commits only after every required JSON/binary response frame completes
  `WriteAsync`. The normal path then appends one `action_response_written`, preserves
  the original `shutdown_requested` receipt, and continues SafeExit. A later
  `FlushAsync` failure cannot roll delivery back. If the post-write audit append
  fails, delivery likewise remains committed: continuity is marked lost, the pending
  entry is removed, and the segment closes as `truncated`, so later dispose must not
  synthesize Unknown. A pre-commit write failure remains `unknown/manual` and never
  authorizes a blind retry or kill.
- `WriteAsync` completion records the server-side delivery disposition only; it is
  not a peer acknowledgment. Delivery-unknown receipts always use
  `EvidenceKind.ReconciliationRequired`. The generic audit append route rejects the
  reserved `action_response_written` and `action_response_unknown` event names;
  only the response-delivery state machine may claim and append them.
- External/human input preempts every active, execution-pending, delivery-pending,
  or queued action that has not yet claimed delivery-write ownership. Once shutdown
  claims that ownership before byte one, ordinary revocation or human override
  cannot roll it back; the response completion state machine alone owns the terminal
  delivery outcome. If a dependent host abort callback returns false or throws, the
  session reservation remains held and ledger continuity is marked lost. If the
  post-write commit callback returns false or throws, completed delivery is not
  rolled back, continuity is marked lost, and SafeExit continuation is not guaranteed.

Credential rotation, credential/grant/lease revocation, and connection termination
are one authority transition. The Gateway revalidates the authoritative connection
and credential after frame read and again immediately before scheduler dispatch, so
an already-read request cannot execute after revocation.

Each action has one absolute deadline. Its monotonic start is recorded as soon as the
complete CF7A request frame is received, before UTF-8, JSON, or parameter parsing.
Parsing, capability/admission checks, scheduler wait, performer work, response-writer
lock acquisition, and every JSON/optional-binary response `WriteAsync` consume that
same budget; no phase may reset it.

Every method has exact params; “arbitrary object” is not a v1 contract.
`clientInstanceId`, `securityPrincipalId`, and `credentialId` are derived from
the authenticated connection and are never accepted in method params. Full
window descriptors/state require an observation grant with
`window_metadata`. The only observation data-scope spellings are
`window_metadata`, `pixels`, `accessibility`, `focus`, `selection`,
`player_state`, `lore_public`, `retention.persist`, and `data.export`;
legacy implementation aliases such as `frame`, `structured`, and `uia` are not
wire values. Hair inspect/preview/consent/reconcile additionally require a
`player_state`-authorized grant and the unique exact DomainTransaction WebOverlay
target described above. Hair consent binds the original
authenticated principal, exact session/lifecycle, transaction, and preview hash;
it returns a 60-second one-shot token only after the Launcher-owned neutral human
UI explicitly approves. Reject, dismiss, cancellation, stale authority, or an
unwired host presenter returns no token. Hair commit/restore are full
`ActionEnvelope` write attempts with exact arguments, idempotency, observation,
generation, and lease bindings.

`content.read` has exact params `{handle,offset,count}`. The response JSON is
followed by one CF7A `binaryChunk` frame whose payload is:

`u32le(metadataLength) || UTF-8 metadata JSON || data bytes`

The metadata JSON is exactly `{handle,offset,totalLength,final,contentHash}` and is
bound to the request/result. `metadataLength` is at most 1024 bytes. The whole
binary-frame payload, including the four-byte prefix and metadata, is at most
4 MiB; therefore actual data capacity is
`4194304 - 4 - encodedMetadataLength`, not 4 MiB. `count` is capped at 4194300,
the sender must clamp again after encoding the real header, and a complete object
is capped at 16 MiB. Reads are sequential, `final` must match the exact terminal
range, and the client verifies the same SHA-256 `contentHash` over the assembled
object.

The JSONL CLI uses the strict CF7A profile above. MCP stdio is a separate outer
protocol boundary: the first request must be `initialize`; only after its successful
response and `notifications/initialized` may the client use `tools/list` or
`tools/call`. It may receive string or JSON safe-integer request IDs and implements
only that lifecycle, `notifications/cancelled`, `tools/list`, and `tools/call`.
Invalid or unsupported notifications produce no JSON-RPC response. The adapter
creates a fresh internal string ID for every forwarded tool call. Numeric MCP IDs,
MCP notifications, arbitrary MCP methods, and cancellation are never passed through
to CF7A. Cancelling work that has not been forwarded only abandons the corresponding
local wait. In the developer MCP entrypoint, cancelling an active forwarded
`tools/call` closes the entire authenticated CF7A connection so the Host revokes its
grants, leases, and pending actions; a caller that may have crossed dispatch must
reconnect and use `action.get` before deciding whether any write can be retried. In
the trusted Core runner, cancellation or deadline instead terminates the isolated
runner lifecycle and exact-owned Guardian; that run has no reconnect path and cannot
be reported as E2E success.

For shutdown the trusted runner requests observation with
`allowValidatedFlashKeyframeFallback=false` and accepts only the exact target's
`SourceLayer.Launcher` frame. It validates every shutdown-lease field and requires a
strict terminal receipt bound to the same action, target, and before-observation:
`terminal=true`, `outcome=input_dispatched`, `evidenceKind=broker_dispatch`,
`reasonCode=shutdown_requested`, `reconcileKind=none`, `retryable=false`,
`focusVerified=false`, and `leaseState=consumed`. After that complete receipt it must
observe the same exact owned child exit within 10 seconds with exit code 0; timeout,
nonzero exit, or forced kill is failure, never successful E2E evidence.

Credential acquisition has a fixed internal 30-second monotonic deadline,
independent of the bootstrap/session document's 10-minute maximum lifetime; no CLI,
MCP, or caller option can tune it. While the Host is live, every periodic full
surface refresh (250 ms by default) retries complete unattended credential
observe/publish/enforce processing. These attempts are single-flight under the
unattended-binding lock, and the stopping fence plus teardown barrier prevents a
queued refresh from publishing through disposed dependencies.

The trusted runner gives each active `tools/call` one absolute 30-second wall-clock
budget from handler start through buffered response copy and flush; concurrent
active-loop output consumes the same remaining budget. Each idle lifecycle,
`tools/list`, or protocol-error write has its own 30-second output budget. A timeout
cancels work, closes the authenticated pipe, emits no fabricated response, and
enters bounded exact-child recovery. Both adapters keep stdout protocol-only, write
diagnostics to stderr, and emit exactly one JSON object per line. A success-evidence
line is written to stderr only when the adapter exits 0, strict shutdown receipt is
observed, the exact owned Guardian exits cleanly, and no forced recovery occurs. It
uses the exact stderr prefix `cf7-trusted-runner-evidence: `, is at most 16 KiB,
and contains only schema
`cf7.agent_runtime.trusted_unattended_completion.v1`, `runtimeMode`,
`processPath`, `coreSha256`, `buildIdentity`, `payloadClosure`,
`guardianProcessId`, and the strict `terminalReceipt`; credential, ticket, and
nonce secrets are forbidden. stdout remains protocol-only.

F7 source evidence is 2678 passed plus 3 explicit opt-in skipped out of 2681
Launcher tests (0 failed), 7/7 SDK-resolver checks resolving exact SDK 10.0.300,
37/37 Node client tests, and 48/48 TrustedRunner-filtered tests. These are C1
source-level results only; C1 has not reached `candidate_executed`,
`e2e_verified`, or `promoted`.

Canonical action JSON uses ordinal object-key ordering, preserves array order and
Unicode code points, rejects duplicate properties, and permits only signed integers
in the interoperable range `[-9007199254740991, 9007199254740991]`. `actionId`,
`idempotencyKey`, `deadlineMs`, and display-only `reason` are deliberately excluded
from the canonical idempotency payload.

All opaque IDs are server/client generated base64url-compatible strings of 22 to 128
characters, providing at least 128 bits of CSPRNG entropy. A UUID textual form also
fits the representation, but sequential or display-derived identifiers do not satisfy
the entropy contract.

An `ObservationEnvelope` binds the requested primary target. Its `frames` array may
also contain Launcher-owned business-modal or sibling-window surfaces from the same
authorized logical session. Every `FrameEnvelope` therefore carries and validates its
own `targetId`, `surfaceEpoch`, and `coordinateSpaceVersion`; only `observationId` is
required to equal the parent. The Gateway must resolve every frame target through the
host registry and must redact security, foreign, unknown, or unauthorized surfaces.
