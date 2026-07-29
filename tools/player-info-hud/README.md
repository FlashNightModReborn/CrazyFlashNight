# PlayerInfo HUD B0 tools

This directory owns the B0 evidence and diagnostic tools for the HP/MP
NativeHud asset migration. The runtime contract and the audit trail are
deliberately separate:

- `launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json` and
  its eight SVG files are the runtime inputs. The manifest contains no source
  commit, timestamp, oracle hash, machine name, or absolute path.
- `evidence/b0-04/conversion-provenance.json` is repository-only provenance.
  It records the XFL/SWF ancestry, one-time conversion seed, manual curation,
  and local review candidates. It must not be embedded in the Launcher.
- The one-time converter is not a build step and is not retained. The
  canonical SVGs are maintained directly after B0.

## B0-01 placement and Flash-oracle boundary

Evidence revision `b0-01a-r4` separates two placement profiles that must never
be treated as interchangeable:

- `standalone_child_document_wrapper`: directly loading
  `flashswf/UI/玩家信息界面.swf` executes its document timeline. That timeline
  places the linkage-exported `玩家信息界面` symbol at `ty=3`, so HP/MP compose
  to `ty=5.65/-1.3`.
- `main_rsl_exported_symbol`: the main SWF imports linkage identifier
  `玩家信息界面` from that child RSL and places the exported symbol directly.
  Relative to the main instance its root is identity (`ty=0`), so HP/MP use
  their symbol-local `ty=2.65/-4.3`. The main-stage instance itself is
  separately placed at `ty=512`.

The seventh-round TestLoader candidate used `MovieClipLoader` on the whole
child SWF. Its images and hashes remain valid historical diagnostics for the
first profile, but they are not a main-runtime placement oracle and cannot be
promoted to `oracle_frozen` by human review alone.

The v2 runner instead loads the exact child SWF, extracts the
linkage-exported-symbol instance below the child document wrapper, and draws
that instance into a 1024×576 main-stage canvas at `ty=512`. Its contract binds
`capturedPlacementProfile=main_rsl_exported_symbol_equivalent`,
`extractionMode=loaded_child_exported_symbol_instance`,
`childDocumentWrapperApplied=false`, and
`mainRslPlacementEquivalent=true`. The main SWF is an identity-chain reference;
it is not executed by the oracle. Validate the protocol without starting Flash,
then run the real capture only after the runner and protocol are source-frozen:

```powershell
chcp.com 65001 | Out-Null
& tools/player-info-hud/capture-flash-oracle.ps1 -ValidateOnly
& tools/player-info-hud/capture-flash-oracle.ps1
```

The real command publishes only the dedicated TestLoader through the guarded
Flash CS6 transaction, restores its temporary source/SWF state, and writes an
ignored candidate beneath `tmp/player-info-hud/oracle/`. It does not publish or
modify the production main or child SWF.

The current main-stage candidate
`20260729T143326Z-32f8ec2142ec47e29c5b191cf2ee339c` contains all 11 cases and
records `strictToolIdentity=head_index_clean_filter_equal` for the two tracked
capture-tool files; this does not assert a clean whole worktree. Its four
manifest human-review fields and the independent source-identity onsite review
remain unsigned, so its status is only
`candidate_captured; awaiting_human_review`, never `oracle_frozen`.

## Exact structural validation

Run from the repository root with the exact SDK:

```powershell
chcp.com 65001 | Out-Null
. .\launcher\resolve-dotnet.ps1
$dotnetHost = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
if ((& $dotnetHost --version) -ne '10.0.300') {
    throw 'Expected SDK 10.0.300'
}

& $dotnetHost restore `
  tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --locked-mode -r win-x64

& $dotnetHost build `
  tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --no-restore -c Release -r win-x64

& $dotnetHost run `
  --project tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --no-build -c Release -r win-x64 -- `
  --asset-manifest launcher\src\Guardian\Hud\PlayerInfo\Assets\player-info.manifest.json `
  --report tmp\player-info-hud-b004-validation.json
```

The validator checks the exact eight-file closure, hashes, asset-set revision,
manifest grammar, semantic IDs, frame/morph contracts, and the strict SVG
element, attribute, value, path, transform, reference, and cycle grammar.
The committed B0-04 snapshot is
`evidence/b0-04/canonical-validation-report.json`; ordinary reruns stay under
ignored `tmp/`. The historical B0-02 report is immutable and must not be
overwritten. Passing this command does not set `rendererQualified`.

## B0-05 runtime raster qualification

The dedicated runner resolves exact SDK `10.0.300`, performs a locked restore,
selects only the opt-in qualification test, rejects a stale run ID or BOM, and
writes a machine-readable report:

```powershell
chcp.com 65001 | Out-Null
& tools/player-info-hud/run-b0-05-runtime-qualification.ps1 `
  -ReportPath tmp/player-info-hud-b0-05-runtime-qualification.json
```

The currently committed snapshot
`evidence/b0-05/runtime-qualification.json` is historical v1 evidence and does
not approve the corrected main-space v2 source. The accepted report form is UTF-8
without BOM and canonical LF, with the exact 32 Gate IDs, 37-file executable
source closure, executing test assembly, Core plus the exact win-x64
11-file renderer target closure, an independently enumerated exact 15-file
renderer-family closure under the test output, and a separately enumerated
actual-loaded subset. Dependencies that the text-free canonical SVG run does not load
(currently HarfBuzz managed/native) remain bound target inputs but are not
mislabelled as executed. The runner independently hashes those files and
recomputes nearest-rank summaries and Gate values from the raw timing samples;
it does not trust the report's `passed` fields alone.

The report covers the production embedded asset/renderer identity, four
physical viewports (including 4:3 letterbox), eight logical raster layers that
own ten PArgb payloads (`mp.fill` owns its canonical payload plus two clip
fragments), the full eight-field raster key including
`sourceToBitmapIdentity`, the 16 MiB active+inactive cache, 100 resize requests,
3000 current-key
requests, ownership/disposal counters, and a fixed-bounds topology probe. Its
scope is deliberately
`measurementKind=synthetic_fixed_bounds`: it does not register a production
`PlayerInfoWidget`, invoke an actual `UpdateLayeredWindow`, measure the final
split surface, establish Flash/Web/C# visual parity, or replace human review.
The accepted B0-05 topology decision is `split_required`.

The corrected v2 timing contract runs 16 fixed excluded round-robin rounds over
all four viewports (64 recorded samples) through the same background
`Task.Run`/fresh parse+raster/PArgb `Bake` path as acceptance. It has no
adaptive early stop or priority mutation. Before any dotnet host is launched,
the runner rejects the frozen performance-affecting `DOTNET_*` / `COMPlus_*`
JIT/GC overrides; the report and verifier also bind Normal priority, inherited
processor affinity and server-GC state. Parse/raster counters are aggregate
completed StrictSvg/Skia payload-slot operations, not PArgb-copy completion or
independently observed per-logical-layer attribution. The separate PArgb-copy
diagnostic copies one representative payload per logical layer and excludes
the two `mp.fill` fragments. Only after that excluded phase does
it collect 20 independent acceptance samples per viewport; each nearest-rank
p95 must remain at or below 100 ms. A dirty-tree diagnostic cannot replace the
fresh clean source-frozen qualification.

## Source-bound path glyph atlas

The fixture compositor never loads a system font or distributes a font
program. The checked-in outline/metric atlas is generated from two FFDec
21.1.1 font exports of the source-bound
`flashswf/UI/玩家信息界面.swf`: `245_LCD Std.ttf` (28,864 B,
SHA-256 `8E275872...9AE6B`) and `2_Aero.ttf` (19,400 B,
SHA-256 `A2EF5132...68CC3`). The exported TTF files remain under ignored
`tmp/`; the source SWF, exported byte hashes, fontTools version, minimum
character set, output hash, and distribution boundary are recorded in
`evidence/b0-06/glyph-atlas-provenance.json`.

From the repository root, the exact regeneration command is:

```powershell
chcp.com 65001 | Out-Null
python tools/player-info-hud/generate-player-info-glyph-atlas.py `
  --font-root tmp/player-info-font-export-current-20260728 `
  --source-swf flashswf/UI/玩家信息界面.swf `
  --output launcher/src/Guardian/Hud/PlayerInfo/PlayerInfoPathGlyphAtlas.Generated.cs `
  --provenance tools/player-info-hud/evidence/b0-06/glyph-atlas-provenance.json
```

The accepted generated C# file is 10,331 B with SHA-256
`B15CA80E...5D66`; the provenance file is 2,670 B with SHA-256
`9486BEEB...DC3D`. A source SWF, font-export byte, generator, or fontTools
change requires regeneration and the full B0-06 closure/visual rerun. A
fail-closed xUnit synchronization Gate independently checks the generated
source's tracked path, UTF-8-without-BOM/canonical-LF encoding, byte length,
and SHA-256 against that provenance; a green renderer test alone cannot mask
stale generated glyph data.

## B0-06 fixture surface qualification and visual evidence

B0-06 implements an opt-in fixture surface without creating a second runtime
state authority. `CF7_PLAYER_INFO_FIXTURE_CASE` must be one exact allowlist
member and is ignored/rejected in bus-only mode or when `useNativeHud=false`.
The resulting `PlayerInfoSplitSurface` is a separate click-through layered
window; it is never registered in the existing `NativeHudOverlay` union.
Program does not hide or mutate the old Flash HUD, and the fixture has no
UiData consumer or `pi_*` fields. The surface is the sole owner and driver of
`PlayerInfoAnimationModel`; `PlayerInfoWidget` receives only the getter-only
`IPlayerInfoVisualStateSource`. Resume remains pending until a valid placement
and raster request are established, so a transient invalid layout cannot leave
the companion logically resumed but permanently hidden. The runtime effect
contract exposes two active B0 effects—dynamic text/HP Glow and the HP
horizontal-line highlight—and one deferred B3 light-overlay effect. A narrow
composition recipe freezes nine text placements instead of introducing a
generic effect graph. The three HP text placements use the source-resolved red
Glow; MP has no Glow. MP's two low-alpha decorative fields reproduce the
authored `00000` text at their distinct anchors. MP current keeps its
source-derived right anchor at `74.55`; the XFL-authored maximum left anchor is
`80.65`, while the C# path rasterizer applies a `+0.30` local phase correction
for Flash standard-text coverage, producing an effective runtime anchor of
`80.95`. Each decorative field is relationship-tested against its foreground
anchor. The HP Glow uses `sigma=1`
with two alpha passes (`255` and `128`) to model authored Flash strength `1.5`;
this remains an explicit Skia approximation, not a pixel-parity claim.

The formal runtime runner resolves exact SDK `10.0.300`, performs a locked
restore, selects the single STA HWND/ULW qualification, then verifies its
canonical report and identities:

```powershell
chcp.com 65001 | Out-Null
& tools/player-info-hud/run-b0-06-runtime-qualification.ps1 `
  -ReportPath tmp/player-info-hud-b0-06-runtime-qualification.json
```

Its contract is 3000 visible visual steps, 3000 idle ticks, and an independent
100-cycle real surface/HWND acceptance interval. Before acceptance, the same
STA thread and owner run one to five complete excluded 100-cycle warmup groups.
A group converges only if every GDI, USER, and process-handle checkpoint is at
or below its start, all endpoint deltas are non-positive, and none of the three
series has positive monotonic growth. The first converged group is followed
immediately by a new acceptance group. If five groups do not converge, any
following group is diagnostic-only, `acceptanceMeasurementEligible=false`, and
the 47th warmup-convergence Gate fails. The runner binds source, binary,
renderer, and runner closures and independently recomputes every Gate.

`evidence/b0-06/runtime-qualification-attempts.json` preserves two rejected
pre-merge attempts without relaxing the original thresholds: v1 was 43/46
(USER +2, process handles +35); v2 was still 43/46 after one fixed warmup
(USER +1, process handles +3 and both positive trends). The accepted
pre-origin-sync v3 snapshot remains historical evidence in
`evidence/b0-06/runtime-qualification-premerge-v3.json`.

The historical v1 implementation-base result is
`evidence/b0-06/runtime-qualification.json`: base commit
`bf8dd2c410267855c8ea12f25a594042b3158479`, run
`a6aadeb6e3264577bb9da8fe90857a7b`, 647,234 B, SHA-256
`656286825CE9717D0DC31BDF9DFE00F3ECB57AB515C5C130601BDF23D319CD74`,
47/47. Its third warmup group first converged, and the
immediately adjacent acceptance interval had process/GDI/USER deltas `-3/0/0`
with no positive trend. NativeHud hidden/enabled commit p95 was
`7.3485/7.2711 ms`; split surface/observer-commit p95 was
`3.5610/1.0918 ms`. The report binds an exact 32-file sourceTrace Git-blob
closure plus the executed binary/renderer closure. Tool existence or a
focused test run is not a qualification result.

On that historical clean base, the focused PlayerInfo plus
`PanelHostHudCompanionTests` run is 136 passed + 3 opt-in skipped / 139 total;
the complete Launcher run is 1,737 passed + 3 opt-in skipped / 1,740 total.
The later historical v1 clean source-freeze commit
`cb38600aae51f5019d09f87c33bd9e67d2b1f511` was verified separately:
Runtime Lane C is 11/11, exit 0, with 566 scalar assertions. Its guardrails
remain a distinct `scripts=3 / unsafeCandidateCases=3` count and are not
relabelled as additional homogeneous scalar assertions. This source-freeze
verification does not rebind the implementation-base qualification or visual
reports described above.

## Historical v1 F source freeze and non-deploying builder quorum

The historical v1 source input is commit
`cb38600aae51f5019d09f87c33bd9e67d2b1f511`, tree
`c74cc66f445921f5fcda1da04a2de0f013fef8ef`, frozen by
`runtime-build-v2/20260729-player-info-nativehud-b0-v1`. Request
`839C74FD1DF61ACC1DA580041F6FA71CA13A84DF1F43A55237BF9BEEF8648FB2`
binds that source and tree to build identity
`7687B56106F0C19EFD4463DCA2B69B3892BD3EE39503A3FD5521ED6DB0257A9F`.
The local X509 builder in `physical-host-b` and the GitHub OIDC builder in
`github-hosted-windows` independently produced the same 33-file payload
closure
`AF2E9E5727E9B6ADE056EBE4CA52BE93AD518116F10FF3307DA4409059CC724B`.

The canonical quorum result is
`evidence/b0-06/runtime-promotion-preflight.v2.json`: 15,128 B, SHA-256
`5B13C629833165452A6229913AB8449632B0E2E949145CE7274D3DD746CEEC14`,
schema `cf7-runtime-promotion-preflight.v2`, status `preflight-passed`, and
`proofCount=2`. It was created by the production promotion verifier in
`-VerifyOnly` mode. The report explicitly records
`runtimeMutationPerformed=false`, `releaseStateMutationPerformed=false`,
`promotionPerformed=false`, `deploymentPerformed=false`, and
`reusableAsPromotionInput=false`. Therefore the strict result is
`candidate_built / NOT_DEPLOYED`: it is not `candidate_executed`,
`e2e_verified`, `promoted`, or `standard_entry_verified`.

The report is acceptance evidence only. It must never be supplied, copied, or
treated as cached approval for a later promotion. A formal promotion must omit
`-VerifyOnly` and `-ReportPath`, rerun the complete validation and transaction
checks, and produce the normal deployment consensus. The later documentation
commit that carries this report is likewise not the source commit built by the
two builders.

The C# capture is deliberately opt-in. Run it twice against two empty absolute
output directories after exact-SDK locked restore:

```powershell
chcp.com 65001 | Out-Null
. .\launcher\resolve-dotnet.ps1
$dotnetHost = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
& $dotnetHost restore launcher\tests\Launcher.Tests.csproj --locked-mode
& $dotnetHost build launcher\tests\Launcher.Tests.csproj `
  -c Release --no-restore --no-incremental

$captureRoots = @(
  [IO.Path]::GetFullPath('tmp\player-info-hud-b006-csharp-a'),
  [IO.Path]::GetFullPath('tmp\player-info-hud-b006-csharp-b')
)
$priorCaptureRoot = $env:CF7_PLAYER_INFO_B006_VISUAL_OUTPUT_DIR
try {
  foreach ($captureRoot in $captureRoots) {
    $env:CF7_PLAYER_INFO_B006_VISUAL_OUTPUT_DIR = $captureRoot
    & $dotnetHost test launcher\tests\Launcher.Tests.csproj `
      -c Release --no-restore --no-build `
      --filter 'FullyQualifiedName=CF7Launcher.Tests.Guardian.Hud.PlayerInfo.PlayerInfoB006VisualCaptureTests.CaptureFixtureMatrixAndHpTransition'
    if ($LASTEXITCODE -ne 0) { throw "C# visual capture failed: $captureRoot" }
  }
} finally {
  $env:CF7_PLAYER_INFO_B006_VISUAL_OUTPUT_DIR = $priorCaptureRoot
}
```

Each invocation is structurally required to emit 35 PNGs plus `manifest.json`:
11 transparent 1024×576 main-viewport images, 11 tight crops, 12
viewport/state images, and one HP full-to-empty contact sheet. The child
document's authored 1024×64 frame metadata is not a runtime clip. At the
baseline viewport, the raw main-space layer union is
`(-3,474,285,81)` and its visible tight rectangle is `(0,474,282,81)`.
The manifest status is only
`structural_capture_complete`, scope `fixture_only`; it explicitly excludes
cross-renderer parity, a visual threshold, game composite, human acceptance,
real UiData, and deployment. The historical v1 implementation-base A/B
snapshots are 1024×64 captures only. They were complete 36-file closures and
byte-identical: each is 834,893 B with
closure SHA-256
`44C22A045B4CA0AC19C4ECB7664024E5C318E39B2290F1E8856C19F1F6BEE06F`;
the identical manifest is 162,661 B with SHA-256
`ADE926A6385BDB47D573061F2F0AF574DA6D93022F94C3E815137AB4C5EB4E08`,
and its 35-PNG output closure is 672,232 B /
`3C3901A64DFD4D3658D4BBC929B4D0DD54AE938DFD0C3289C4E4660C589A907E`.

After producing the two Web reports below, run the direct-edge diagnostic once
for each independent C#/Web pair. All paths must be repository-relative, each
output directory must not exist, and its parent must already exist:

```powershell
node tools/player-info-hud/compare-b0-06-csharp-web-flash.js `
  --csharp=tmp/player-info-hud-b006-csharp-a/manifest.json `
  --web=tmp/player-info-hud-web-canonical-a/web-render-report.json `
  --flash=tmp/player-info-hud/oracle/<run>/oracle-manifest.json `
  --output=tmp/player-info-hud-b006-direct-a

node tools/player-info-hud/compare-b0-06-csharp-web-flash.js `
  --csharp=tmp/player-info-hud-b006-csharp-b/manifest.json `
  --web=tmp/player-info-hud-web-canonical-b/web-render-report.json `
  --flash=tmp/player-info-hud/oracle/<run>/oracle-manifest.json `
  --output=tmp/player-info-hud-b006-direct-b
```

The v2 comparator validates exact case order; C#/Web canonical manifest
identity; the Flash candidate, receipt, compile, tooling, source-binary,
placement-closure, and 40-file Flash-directory provenance; Edge/Playwright
identity; and exact geometry for all four physical viewport profiles. It
rejects historical v1 inputs and performs no standalone-to-main coordinate
normalization. The `p50` case also measures the MP label, current value,
maximum value, and percentage independently over fixed ROIs; all four must
have both a unique best horizontal registration at `dx=0` and an exact
anchor-edge delta of zero for manual Exit-Gate review. Left-aligned label,
maximum, and percentage fields use their leading edge; the right-aligned
current field uses its trailing edge. The edge check prevents repeated digits
from hiding a one-pixel field-origin error behind a stronger whole-glyph
overlap score. A cyan-weighted centroid delta is retained as a diagnostic but
is not an acceptance threshold. It emits 66 diagnostic PNGs plus
`csharp-web-flash-comparison-report.json` for the direct C#↔Web and C#↔Flash
edges. This three-input report itself does not emit a Web↔Flash edge;
`compare-flash-web-svg.js` below emits an independent supplemental diagnostic.
Neither report provides a threshold, transitive inference, parity verdict, or
Flash-oracle acceptance. The seventh-round direct-child manifest is therefore
retained only as a historical standalone diagnostic and cannot be fed to the
v2 comparator.
Web scope is exactly `canonical_static_svg_layers_only`; the Web
captures do not include C# programmatic dynamic text or Glow. Consequently the
C#↔Web metrics compare a full C# fixture composite with only those Web static
layers and intentionally include that layer-scope difference.

The historical v1 implementation-base Web A/B 12-file closures are
byte-identical at
120,439 B / SHA-256
`2F18FAAB0D3490FF2F3DDEE632EE228ED709F924806D6577805418B1F579E6F6`;
both 5,644 B Web reports have SHA-256
`7826B89DAF49BFFF409B2CEC066B4D8853BF593EF1EA3675C88D3FCA9C8BF97F`.
Both direct-edge runs emit the same 66-PNG closure, 1,470,180 B /
`5207F27B2ACEE5E7A3F04D89EE627DEE6E4C58CBCD93F4AF975E778C5803C234`.
Their historical v1 184,472 B reports differ only because they retain distinct
`-a/-b` input paths; report hashes are
`519CF97BC632F5F921C30ED64B81B80864F4C626D86885E8D9CB98CA319783C1`
and
`081B05E2E729A2C7E6C7987530C4D2D361B02E4DBD6C7CAC2E0F0F3F2E78B356`.
These hashes and the corresponding entries in
`evidence/b0-06/visual-evidence.json` are historical evidence only; the final
v2 main-space index must be regenerated from the frozen source.

Build the local review viewer from either direct-edge report:

```powershell
node tools/player-info-hud/build-visual-diagnostic-viewer.js `
  --report=tmp/player-info-hud-b006-direct-a/csharp-web-flash-comparison-report.json `
  --output=tmp/player-info-hud-b006-viewer.html
```

The viewer provides A/B blink, hard wipe, signed residual, Difference, and
Invert diagnostics at native main-stage coordinates. Difference and Invert are
inspection aids only. Every B0-rendered effect uses ordinary source-over. The
HP light-overlay preserves authored `overlay` metadata but is deferred and is
not rendered in B0. The builder independently validates the exact
field/order/anchor and canvas/search/mask/threshold/ROI contract. From each
exact 17-score vector it re-derives the Jaccard ratios, best/runner-up summaries,
bounds-derived edge deltas, centroid delta, per-field status and the 4/4
aggregate, and binds the diagnostic SHA values to the actual p50 C#/Flash PNGs.
A legitimate `insufficient_pixels` result remains buildable and displays
missing edge/centroid values as `n/a`; it can never render as aligned.

## Headless Web, FFDec, and Flash diagnostics

The Web harness uses the repository Playwright installation and the local
Microsoft Edge executable. It does not require the Codex Browser or Computer
Use plugins:

```powershell
node tools/player-info-hud/run-web-svg-harness.js `
  --manifest=launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json `
  --output=tmp/player-info-hud-web-canonical-a

node tools/player-info-hud/run-web-svg-harness.js `
  --manifest=launcher/src/Guardian/Hud/PlayerInfo/Assets/player-info.manifest.json `
  --output=tmp/player-info-hud-web-canonical-b
```

FFDec is a binary-SWF cross-reference. Reuse a frozen reference while the SWF
and FFDec identities are unchanged; otherwise recapture it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File tools/player-info-hud/capture-ffdec-reference.ps1 `
  -OutputDirectory tmp/player-info-hud-ffdec-reference-fresh

node tools/player-info-hud/compare-ffdec-web-svg.js `
  --ffdec=tmp/player-info-hud-ffdec-reference-fresh/ffdec-reference-report.json `
  --web=tmp/player-info-hud-web-canonical-a/web-render-report.json `
  --output=tmp/player-info-hud-ffdec-web-canonical-a

node tools/player-info-hud/compare-ffdec-web-svg.js `
  --ffdec=tmp/player-info-hud-ffdec-reference-fresh/ffdec-reference-report.json `
  --web=tmp/player-info-hud-web-canonical-b/web-render-report.json `
  --output=tmp/player-info-hud-ffdec-web-canonical-b
```

The comparison emits composites, 50/50 overlays, absolute-difference
heatmaps, and metrics without an acceptance threshold. FFDec does not execute
Adobe Flash Player and is never equivalent to the Flash runtime oracle. The
frozen final reference is a 23-file/22-PNG closure, 276,020 B, SHA-256
`AEC84002B2D9C030BA8528B075D522486449290245122F28CE61D298EE287E59`;
its 30,433 B report has SHA-256
`069BFD2B12EF284F11B7F9937BCFC4B1D419D0772AF6DF5D1C733FF475784167`.
The two FFDec↔Web runs each emit 33 byte-identical PNGs, 698,799 B, SHA-256
`BC2A83D15AB6D918C0DEBE5DF22A5FE61B8D54E7B6040E1F0C6D50684629E08A`;
their distinct-path reports are indexed in
`evidence/b0-06/visual-evidence.json`.

`compare-flash-web-svg.js` is the historical standalone-v1 diagnostic against
a Flash Player candidate's 1024×64 raw captures. For the seventh-round
candidate this means the standalone child-document profile described above,
not the actual main RSL placement. It is not the v2 formal comparator. A
placement-correct v2 candidate remains unaccepted until a human reviews its
source, state, layer isolation, crop, and visual quality:

```powershell
node tools/player-info-hud/compare-flash-web-svg.js `
  --flash=tmp/player-info-hud/oracle/<run>/oracle-manifest.json `
  --web=tmp/player-info-hud-web-canonical-a/web-render-report.json `
  --output=tmp/player-info-hud-flash-web-canonical-a

node tools/player-info-hud/compare-flash-web-svg.js `
  --flash=tmp/player-info-hud/oracle/<run>/oracle-manifest.json `
  --web=tmp/player-info-hud-web-canonical-b/web-render-report.json `
  --output=tmp/player-info-hud-flash-web-canonical-b
```

The two historical standalone-candidate↔Web runs likewise emit 33
byte-identical PNGs,
661,944 B, SHA-256
`6141D3870BC5ED6B40AD3C1FD19A11945D47C5973C6B1711F323220E778CC185`;
their reports and hashes are frozen in the same final evidence index. This
repeatability says nothing about main-runtime placement or acceptance of the
still-unsigned Flash candidate.

## Acceptance boundary

Automated hashes and metrics can freeze structure and expose differences; they
cannot promote a Flash candidate to `oracle_frozen`, assert visual parity, or
accept the UI aesthetic. Human review is necessary but cannot repair a wrong
placement profile. A source-bound v2 run has been captured as
`20260729T143326Z-32f8ec2142ec47e29c5b191cf2ee339c`, with 1024×576
main-stage/exported-symbol/wrapper-excluded semantics and strict tooling
identity. Its four manifest human-review checks and independent source-identity
onsite review remain unsigned, so B0-01B remains
`standalone_child_diagnostic_captured; main_rsl_equivalent_candidate_captured; awaiting_human_review`,
B0-04 remains without accepted visual parity, and the old Flash HUD remains
the active visual reference.

The repository-owned Playwright/local-Edge harness remains valid for
deterministic Web/direct-edge rendering without an interactive App backend;
FFDec
remains a binary-SWF diagnostic, and the formal runner exercises real HWND/ULW
calls with an offscreen owner. None of these routes proves visible desktop DWM
composition, z-order/occlusion over the running game, a real hand click,
game-scene composite, temporal smoothness, or aesthetic quality. Those items
remain mandatory human evidence. Independently, the Launcher result remains
`NOT_DEPLOYED`; human acceptance is still pending and does not itself imply a
deployment.
