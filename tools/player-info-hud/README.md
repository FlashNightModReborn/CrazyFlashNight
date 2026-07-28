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
the active visual reference.
