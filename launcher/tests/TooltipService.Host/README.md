# TooltipService cross-platform host

This `net10.0` console host links the production `TooltipService`, `TooltipV8Engine`,
`TooltipResponseEnricher`, `MessageRouter`, `NativeInteractionTask`,
`TooltipDocumentSanitizer`, `InventoryTask`, `EquipmentTuningTask`, all three
`ItemUseTask` partials, and their actual pending tracker, request bridge,
`CharacterBuildProtocol` and authority-log dependencies. The ClearScript packages are the same
centrally pinned **7.4.5** packages used by Launcher. Both native package identities
are locked so the same restore works on Windows and Linux; ClearScript loads the
binary matching the actual host OS. It does not reference WinForms, WebView2 or the full Launcher
executable.

`FakeHostSurfaces.cs` replaces only platform presentation/socket interfaces. The
fake content engine controls scheduling races. Actual-bundle checks instantiate
`TooltipV8Engine`, validate the real catalog manifest and execute the real TS
bundle through ClearScript. No AS2 equipment calculator or content builder is
reimplemented in this host.

## Commands

Run from the repository root with the SDK selected by `global.json` (10.0.300):

```sh
npm ci --ignore-scripts --prefix launcher/scripts
node launcher/tooltip-engine/build.cjs
python3 tools/build-tooltip-catalog.py --check
dotnet restore launcher/tests/TooltipService.Host/TooltipService.Host.csproj --locked-mode
dotnet run --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --test .
```

Protocol checks cover bounded queue/subscribers/cache, single worker ownership,
coalescing, latest request and completed sequence frontiers, exact cancellation,
revision/scene/lease distinctions, exception recovery, disconnect, closed pending
owners, deferred Socket callbacks, nested details-only response enrichment,
business acknowledgement preservation, Native hide-before-result, scene roll,
owner suppression, revision regression, and separate pinned Inspector behavior.
`ManagedTaskIntegration.cs` sends requests through the real Inventory/ItemUse
pending stores, simulates only the Flash response transport, and routes the
reply through the real MessageRouter/enricher/domain schema validator. It checks
same-item caching and lease changes, hover supersession, independent choice/hover
lanes, closed bindings and late absent-pending responses, unchanged committed
write acknowledgement while a tooltip read fails, and real-V8 details failure
against the exact six-field ChoiceReward item schema. These are protocol fixtures,
not captures of Flash behavior. The pure `LootPanelCoordinator.IsOpaque` predicate
is shared from its production identity partial, with no duplicate business rule.
`EquipmentTuningIntegration.cs` first establishes a real snapshot/candidate/lease
binding, then checks real-V8 content success and explicit unavailable fallback
through the actual tuning response validator. It also checks optional-document
sanitization, invalid-document stripping, HTML compatibility and rejection of
unrelated outer keys. Its snapshot and Flash responses are fixture data; it does
not reproduce the tuning validator.
The real item Inspector check runs production V8 content through the real Native
completion path with a fake presentation surface.

## Same-input parity and performance

```sh
node launcher/tooltip-engine/fixtures.cjs /tmp/tooltip-inputs.jsonl
node launcher/tooltip-engine/benchmark.cjs --evaluate /tmp/tooltip-inputs.jsonl > /tmp/node-tooltip.jsonl
dotnet run --no-build --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --evaluate . /tmp/tooltip-inputs.jsonl > /tmp/v8-tooltip.jsonl
cmp /tmp/node-tooltip.jsonl /tmp/v8-tooltip.jsonl
dotnet run --no-build --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --validate-service . /tmp/tooltip-inputs.jsonl
dotnet run --no-build --project launcher/tests/TooltipService.Host/TooltipService.Host.csproj -- --bench . /tmp/tooltip-inputs.jsonl
```

`--evaluate` emits exactly one raw `buildProjectionJson` result per input line.
`--validate-service` runs every input through production input validation, V8,
output sanitization and the bounded cache; it fails on the first rejected line.
`--bench` reports initialization, the first distinct batch, six passes of direct
engine calls, process working set, 1,000 cached service calls, and a 1,000-request
rapid-hover run including cancellation, maximum queue depth and latest-request
tail latency. `cacheEstimatedBytes` counts UTF-16 result storage plus bounded
entry bookkeeping; it is separate from process/V8 RSS. Initialization includes
first-process ClearScript/.NET/JIT work and catalog source hash reads. All file I/O
is in initialization, not item-hover computation.

The receipt reports the actual OS, framework, process architecture and PID. It
sets `gameInputMeasured: false`: this standalone process observes no GameInput
frames, input-lock waits or incremental memory inside an existing Launcher.

The generated inputs are current-catalog baselines and explicitly synthetic
projections. Node/ClearScript equality is **same-rule, cross-host evidence**, not
an AVM1 oracle. Fake surfaces do not establish real Flash transport, Windows
message-loop behavior, layout/scroll/wheel hit testing or CS6 compilation. The
Windows Launcher candidate build remains a separate gate; this host neither
builds nor deploys a formal Windows runtime.

## Runtime asset closure

`Program.Run` supplies the existing project root (`--project-root`, then the
`crossdomain.xml` ancestor fallback). The worker reads
`launcher/scripts/dist/tooltip-bundle.js`, `data/tooltip/tooltip-catalog.json` and
its manifest under that root. The manifest's `data/**` inputs are checked by
SHA-256 at startup. Development-only generator/AS2 source files are not required
in a player package.

The existing packer `launcher-scripts` and `data` layers ship these resources;
`output.minify.exclude` preserves their integrity-governed bytes. The targeted
packer test performs real copy/hash verification without deploying a game:

```sh
npm ci --ignore-scripts --prefix tools/cf7-packer
npm test --prefix tools/cf7-packer -- --run packages/core/tests/tooltip-runtime-config.test.ts
```

Release prepare regenerates the TS bundle/catalog, and release policy requires
all three files and checks both generated products for freshness. They are
external game assets, not files copied into the FDD `runtime/` executable folder.
