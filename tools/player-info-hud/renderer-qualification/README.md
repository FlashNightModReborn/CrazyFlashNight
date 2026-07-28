# PlayerInfo Svg.Skia renderer qualification

This is an isolated B0-02 qualification harness. It pins `Svg.Skia 5.1.1`
and the repository's current `SkiaSharp 3.119.4`, but it does not add either
reference to the Launcher production project.

The passing result is deliberately named `isolated_qualification_passed`
while `rendererQualified` remains false. The harness has two small
qualification corpora: the program embeds one tiny synthetic core-subset
document, while the tracked SVG is an HP/MP feature-derived corpus. The latter
preserves exact gradient kind, reflect mode and endpoint colors from the named
HP/MP XFL layers while deliberately using small synthetic geometry. It is not
a canonical HUD asset or visual oracle.

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
  --report tools\player-info-hud\evidence\b0-02\qualification-report.json
```

Use `restore --force-evaluate -r win-x64` only when intentionally refreshing
the committed lockfile, then immediately rerun `restore --locked-mode`.

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

## Still required before `renderer_qualified`

- real HP/MP canonical SVGs and oracle comparison;
- the production validator/facade and repository xUnit regression corpus;
- real Launcher central version, PackageReference and lockfile integration;
- artifact-source/build-identity/Core-payload and production-policy gates;
- full cancellation/dispose, DPI, performance and long-run evidence;
- maintainer acceptance of dependency distribution obligations.
