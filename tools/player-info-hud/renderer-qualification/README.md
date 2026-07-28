# PlayerInfo Svg.Skia renderer qualification

This began as the isolated B0-02 qualification harness. The production
B0-03b integration now pins `Svg.Skia 5.1.1` beside the repository's
`SkiaSharp 3.119.4`; this project compile-links the production strict facade
and asset catalog so the two paths cannot drift into separate validators.

The passing result is deliberately named `isolated_qualification_passed`
while `rendererQualified` remains false. The harness has two small
qualification corpora: the program embeds one tiny synthetic core-subset
document, while the tracked SVG is an HP/MP feature-derived corpus. The latter
preserves exact gradient kind, reflect mode and endpoint colors from the named
HP/MP XFL layers while deliberately using small synthetic geometry. It is not
a canonical HUD asset or visual oracle.

When `--asset-manifest` is supplied, the same run additionally validates the
eight canonical B0-04 SVGs and their runtime manifest. This extends the
isolated qualification; it still does not claim visual acceptance or production
integration.

`--production-contract-only` is a separate early-return policy mode. It loads
the selected candidate Core assembly, first runs the full canonical source
manifest contract (including exact units/stage/gauges/effect policy), requires
the exact nine-resource PlayerInfo closure, cross-checks manifest/hash/revision,
applies the strict facade, performs one minimal raster per asset, and compares
every embedded byte with the production source under `--project-root`.
Candidate mode also requires the source-exact third-party notice, 11 managed
and native renderer payload DLLs as an exact recursively enumerated
renderer-family closure, and exact renderer-family package identities in both
the `libraries` and single runtime-target closure of Core `deps.json`, with
zero Jint or `Svg.Skia.JavaScript`. Unexpected `Svg*`, `Skia*`,
`HarfBuzz*`, `ExCSS*` or `ShimSkia*` DLL/`.so`/`.dylib` payloads fail closed.
The report records the actual candidate file sizes/hashes and actual deps
identities rather than echoing the expected list. This mode reads no
qualification fixture or repo-only provenance/oracle evidence.

## Exact run

Run from the repository root:

```powershell
chcp.com 65001 | Out-Null
. .\launcher\resolve-dotnet.ps1
$dotnetHost = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path
if ((& $dotnetHost --version) -ne '10.0.300') { throw 'Expected SDK 10.0.300' }

& $dotnetHost restore tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --locked-mode -r win-x64
& $dotnetHost build tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --no-restore -c Release -r win-x64
& $dotnetHost run --project tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --no-build -c Release -r win-x64 -- `
  --report tmp\player-info-hud-isolated-qualification-fresh.json
```

Use `restore --force-evaluate -r win-x64` only when intentionally refreshing
the committed lockfile, then immediately rerun `restore --locked-mode`.
`evidence/b0-02/qualification-report.json` is the immutable historical
B0-02 snapshot (10/10 behaviors and 16 fail-closed cases). The expanded
harness must never overwrite it.

For the canonical B0-04 closure, use a fresh report path:

```powershell
& $dotnetHost run --project tools\player-info-hud\renderer-qualification\RendererQualification.csproj `
  --no-build -c Release -r win-x64 -- `
  --asset-manifest launcher\src\Guardian\Hud\PlayerInfo\Assets\player-info.manifest.json `
  --report tmp\player-info-hud-b004-validation.json
```

For a built runtime candidate:

```powershell
$candidateRoot = (Resolve-Path tmp\runtime-candidates\v2\<candidate>).Path
$qualificationExe = (Resolve-Path `
  tmp\player-info-hud-renderer-qualification\bin\Release\net10.0-windows\win-x64\RendererQualification.exe).Path

& $qualificationExe --production-contract-only `
  --project-root (Get-Location).Path `
  --candidate-root $candidateRoot `
  --report tmp\player-info-hud-production-contract.json
```

`--core <absolute Core.dll>` may replace `--candidate-root` only as a focused
diagnostic/negative-test seam; the two options are mutually exclusive.
Core-only reports explicitly set `policyEligible=false` and leave
payload/notice/deps unevaluated, so release policy must require candidate mode.
Success prints `PLAYER_INFO_PRODUCTION_CONTRACT_OK` and exits 0. Contract
failures use the stable `PLAYER_INFO_PRODUCTION_CONTRACT_ERROR:` prefix and
exit 1; argument/path failures use
`PLAYER_INFO_PRODUCTION_CONTRACT_USAGE_ERROR:` and exit 2.

After building a valid candidate and the qualification executable, run the
focused closure negatives:

```powershell
.\tools\test-runtime-player-info-svg-production-contract.ps1 `
  -CandidateRoot $candidateRoot `
  -QualificationExe $qualificationExe
```

The test first proves its minimal candidate fixture is valid, then requires
fail-closed rejection of an unexpected `Svg.Foo.dll`, a recursively nested
`libHarfBuzzSharp.so`, a runtime junction/reparse point, and an unexpected
`Svg.Foo/1.0.0` identity in both `deps.json` libraries and its
renderer-bearing runtime target. It also fixes the family-prefix boundary
with `SvgUnexpected/1.0.0` and rejects duplicate renderer identities instead
of silently treating a JSON object as a set.

## Qualification boundary

The harness fixes a strict pre-render contract:

- the same immutable bytes first pass DTD-prohibited, resolver-free XML
  parsing, fixed byte/node/depth/dimension limits, exact element/attribute
  allowlists, bounded aggregate path complexity, and same-document-only
  references;
- the facade explicitly chooses `SecureStatic`, disables external resources,
  scripting, external scripting, broken-image placeholders, SVG fonts, text
  references and filter background inputs;
- raster output is `Bgra8888/Premul`;
- malformed XML, DTD/entity, script/event, image, text, animation,
  `foreignObject`, style, external/data href, unknown grammar, excessive depth
  and oversized dimensions fail before renderer entry;
- root attributes and processing instructions at any document depth are
  checked; transform/path/paint/opacity/gradient/points/viewBox values must
  consume their complete bounded grammar; path data accepts only the bounded
  absolute-command subset, transforms accept one finite `matrix(...)`, nested
  `svg` is rejected, and reference cycles fail closed;
- the actual render-root semantic graph expands `use`, `clip-path`, `use`
  placement and target transforms with a depth-32 reference boundary and a
  32,768-step cap, while semantic composite matrices remain finite and
  bounded;
- reflect gradient, clip, same-document `use`, alpha bytes and bounded
  parse/raster/dispose are exercised;
- empty/non-finite picture bounds, invalid BGRA/Premul allocation or stride
  fail before the result is returned;
- independent parse+raster and shared read-only raster each run 8-way for 200
  iterations; mutable parse/load state is never shared.

The unsafe-default test is intentional. In 5.1.1, DTD processing and external
resources are not safely disabled by default, the alpha default is unpremul,
and blocking an external image at renderer level can silently produce an empty
picture. Production code must not bypass the strict facade.

The current expanded corpus passes 12/12 behaviors and rejects 78/78
fail-closed cases, including 58 directed value-grammar mutations and one
complete controlled-value positive document. The canonical mode validates
8/8 SVGs; these counts belong to the current B0-04 report and do not rewrite
the historical B0-02 report.

## Dependency and payload evidence

The exact added restore graph relative to the current Launcher package set is
11 nodes:

| Package | Version | License | Acceptance |
|---|---:|---|---|
| Svg.Skia | 5.1.1 | MIT | no |
| ExCSS | 4.3.1 | MIT | no |
| HarfBuzzSharp | 8.3.1.3 | MIT | yes |
| HarfBuzzSharp.NativeAssets.Linux | 8.3.1.3 | MIT | yes |
| HarfBuzzSharp.NativeAssets.macOS | 8.3.1.3 | MIT | yes |
| HarfBuzzSharp.NativeAssets.Win32 | 8.3.1.3 | MIT | yes |
| ShimSkiaSharp | 5.1.1 | MIT | no |
| Svg.Animation | 5.1.1 | MIT | no |
| Svg.Custom | 5.1.1 | MS-PL | no |
| Svg.Model | 5.1.1 | MIT | no |
| Svg.SceneGraph | 5.1.1 | MIT | no |

`SkiaSharp` remains `3.119.4`. NuGet vulnerability/deprecation queries for the
isolated graph returned zero findings on the qualification date. A
producer-shaped `win-x64` comparison (top-level runtime files, excluding
`.xml` and `.pdb` like the current producer) added 9 files totaling
`5,289,528` bytes (`5.044 MiB`). No Linux/macOS native file entered the
payload. Raw publish also emitted a `20,918,272` byte HarfBuzz PDB, which the
producer excludes. No `Svg.Skia.JavaScript` or Jint dependency was present.

These dependency facts require maintenance review and third-party notice
handling; this harness does not make a legal conclusion.

The generated qualification report repeats the 11-package license/nupkg
inventory and the 9-file producer-shaped payload diff as structured evidence;
the committed lockfile remains the restore authority.

## Boundary after B0-03b production integration

This slice now supplies the production strict facade/catalog, central package
and lock integration, exact embedded closure, focused xUnit coverage, complete
offline notice, and candidate Core/payload/deps contract. The surrounding
artifact-source/build-identity and release-policy scripts must invoke
candidate mode and reject `policyEligible=false`; maintainer review of
distribution obligations remains a human decision rather than an automated
legal conclusion.

These production-integration gates are independent of visual acceptance.
The following remain required for B0 visual/runtime acceptance, but do not
block the narrower `renderer_qualified` state:

- accepted Flash-oracle comparison and human visual review for the current
  eight-asset HP/MP closure;
- runtime raster/cache cancellation, dispose, DPI, performance and long-run
  evidence;
- fixture widget parity without hiding the old Flash HUD.
