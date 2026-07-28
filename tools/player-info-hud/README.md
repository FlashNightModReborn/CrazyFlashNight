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

The committed snapshot is
`evidence/b0-05/runtime-qualification.json`. The accepted form is UTF-8
without BOM and canonical LF, with the exact 31 Gate IDs, 37-file executable
source closure, executing test assembly, Core plus the exact win-x64
11-file renderer target closure, an independently enumerated exact 15-file
renderer-family closure under the test output, and a separately enumerated
actual-loaded subset. Dependencies that the text-free canonical SVG run does not load
(currently HarfBuzz managed/native) remain bound target inputs but are not
mislabelled as executed. The runner independently hashes those files and
recomputes nearest-rank summaries and Gate values from the raw timing samples;
it does not trust the report's `passed` fields alone.

The report covers the production embedded asset/renderer identity, four
physical viewports (including 4:3 letterbox), eight-layer PArgb raster batches,
the 16 MiB active+inactive cache, 100 resize requests, 3000 current-key
requests, ownership/disposal counters, and a fixed-bounds topology probe. Its
scope is deliberately
`measurementKind=synthetic_fixed_bounds`: it does not register a production
`PlayerInfoWidget`, invoke an actual `UpdateLayeredWindow`, measure the final
split surface, establish Flash/Web/C# visual parity, or replace human review.
The accepted B0-05 topology decision is `split_required`.

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
change requires regeneration and the full B0-06 closure/visual rerun.

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
contract exposes one B0 active dynamic-text/glow effect and two explicitly
deferred B3 HP effects; a narrow composition recipe freezes the seven text
placements instead of introducing a generic effect graph.

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

The final implementation-base result is
`evidence/b0-06/runtime-qualification.json`: base commit
`0215c03b4594221f02e993bf8d58dd1bc669e815`, run
`c53cd48cd1054f6e9b988d11f5f06c85`, 647,221 B, SHA-256
`E41F8CFC...FBFAB`, 47/47. Its third warmup group first converged, and the
immediately adjacent acceptance interval had process/GDI/USER deltas `-3/0/0`
with no positive trend. NativeHud hidden/enabled commit p95 was
`7.3670/7.2699 ms`; split surface/observer-commit p95 was
`3.6748/1.1382 ms`. The report binds an exact 32-file sourceTrace Git-blob
closure plus the executed binary/renderer closure. Tool existence or a
focused test run is not a qualification result.

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
11 transparent full-stage images, 11 tight crops, 12 viewport/state images,
and one HP full-to-empty contact sheet. The manifest status is only
`structural_capture_complete`, scope `fixture_only`; it explicitly excludes
cross-renderer parity, a visual threshold, game composite, human acceptance,
real UiData, and deployment. The final implementation-base A/B snapshots are
complete 36-file closures and are byte-identical: each is 796,806 B with
closure SHA-256 `53F019EB...47000`; the identical manifest is 162,661 B with
SHA-256 `16B78FB3...66855`, and its 35-PNG output closure is
634,145 B / `0263EFF7...F3D4`.

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

The comparator validates exact case order, C#/Web canonical manifest identity,
Flash candidate/receipt provenance, and Edge/Playwright identity. It emits 66
diagnostic PNGs plus
`csharp-web-flash-comparison-report.json` for the direct C#↔Web and C#↔Flash
edges. Status remains `diagnostic_awaiting_human_review`: there is no threshold,
Web↔Flash edge, transitive inference, parity verdict, or Flash-oracle
acceptance. The final implementation-base Web A/B 12-file closures are
byte-identical at 120,280 B / SHA-256 `2608142C...D1388`; both Web reports are
5,485 B / `C6B6C8E7...BD38`. Both direct-edge runs emit the same 66-PNG
closure, 1,449,236 B / `87EA77C8...E9668`. Their reports are 183,816 B and
differ only because they retain distinct `-a/-b` input paths; report hashes
are `963A16BD...2D2F6` and `23D012E6...3097D`. The exact final index is
`evidence/b0-06/visual-evidence.json`; the pre-origin index remains historical
evidence only.

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
```

The comparison emits composites, 50/50 overlays, absolute-difference
heatmaps, and metrics without an acceptance threshold. FFDec does not execute
Adobe Flash Player and is never equivalent to the Flash runtime oracle.

`compare-flash-web-svg.js` performs the analogous diagnostic against the
actual Flash Player candidate's 1024×64 raw captures. A Flash candidate remains
unaccepted until a human reviews its source, state, layer isolation, crop, and
visual quality:

```powershell
node tools/player-info-hud/compare-flash-web-svg.js `
  --flash=tmp/player-info-hud/oracle/<run>/oracle-manifest.json `
  --web=tmp/player-info-hud-web-canonical-a/web-render-report.json `
  --output=tmp/player-info-hud-flash-web-canonical-a
```

## Acceptance boundary

Automated hashes and metrics can freeze structure and expose differences; they
cannot promote a Flash candidate to `oracle_frozen`, assert visual parity, or
accept the UI aesthetic. Only a human may sign those checks. Until then the
B0-01B/B0-04 state is `awaiting_human_review`, and the old Flash HUD remains
the active visual reference. In the 2026-07-29 agent session the computer-use
connector could not initialize its native pipe (Windows error 2). Headless
Playwright/Edge remains valid for deterministic Web and direct-edge rendering,
and the formal runner exercises real HWND/ULW calls, but neither route proves a
real hand click, desktop z-order over the running game, game-scene composite,
or aesthetic quality. Those items remain mandatory human evidence even if the
connector later becomes healthy.
