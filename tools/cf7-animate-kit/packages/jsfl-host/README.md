# @cf7-animate-kit/jsfl-host

JSFL scripts that run **inside Adobe Animate's tool VM**. The CEP panel (P4)
loads `host/index.jsfl` via its CSXS `manifest.xml` `<ScriptPath>`, then calls
the named functions through `CSInterface.evalScript`.

> ⚠️ This is the only code that touches the live FLA document DOM, and it can
> only be verified inside Animate. The functions are written per the Adobe
> AnimateSDK JSFL reference, but `SpriteSheetExporter` / `exportSpriteSheet`
> option names and a few signatures vary by Animate build — **smoke-test against
> the installed Animate version before relying on a batch** (see below).

## Bridge contract

The panel calls one dispatcher; every function returns a JSON **string**:

```js
// panel side (cep-panel/src/bridge.ts)
cs.evalScript("cf7ak('scanLinkage', " + JSON.stringify(argJson) + ")", (raw) => {
  if (raw === "EvalScript error.") { /* host threw */ }
  const res = JSON.parse(raw); // { ok: true, data } | { ok: false, error }
});
```

`argJson` is a JSON string; the host `JSON.parse`s it. Results are
`{ ok:true, data }` or `{ ok:false, error }`.

## Functions

| `cf7ak(fn, argJson)` | args | returns `data` |
|---|---|---|
| `ping` | — | `{ pong, flVersion }` |
| `probe` | — | `{ flVersion, hasDocument, hasSpriteSheetExporter, hasFLfile, hasJSON }` |
| `scanLinkage` | — | `{ count, items:[{name,itemType,linkageExportForAS,linkageIdentifier,linkageClassName}] }` |
| `applyLinkage` | `{ assignments:[{name,linkageIdentifier,exportForAS?,className?}] }` | `{ count, applied:[{name,ok,linkageIdentifier}] }` |
| `listFrameLabels` | `{ symbolName? }` | `{ timeline, count, labels:[{layer,index,name,labelType,duration}] }` |
| `exportSelected` | `{ outDir, layoutFormat?, algorithm?, trim?, borderPadding?, shapePadding? }` | `{ outDir, count, results:[{name,ok,png?,error?}] }` |
| `publish` | `{ profile? }` | `{ published, doc, profile }` |

### Wave 1 — 醉尘仙 high-阶 (export / batch / document ops)

| `cf7ak(fn, argJson)` | args | returns `data` | confidence |
|---|---|---|---|
| `listLibrary` | — | `{ count, items:[{name,itemType,symbolType?,exportForAS,linkageIdentifier}] }` | **high** — `library.items` + linkage props are stable across builds |
| `exportStagePNG` | `{ outFile, currentFrameOnly?, exactBounds? }` | `{ file }` | **high** — `document.exportPNG(uri,bCurrentFrame,bExactBounds)` is long-standing; defaults are `true`/`true` |
| `exportFrameSequence` | `{ outDir, prefix?, from?, to? }` | `{ outDir, count, files:[…] }` | **medium** — loops `tl.currentFrame=f` + `exportPNG(...,true,true)`; per-frame PNG works, but `currentFrame` repaint timing varies by build (restores the original frame after) |
| `batchExportSymbols` | `{ outDir, names?, layoutFormat?, algorithm? }` | `{ outDir, count, results:[{name,ok,png?,error?}] }` | **medium** — one `SpriteSheetExporter` per symbol; `exportSpriteSheet` option names vary by build (smoke-test). Falls back to current library selection when `names` omitted |
| `exportLibraryBitmaps` | `{ outDir, names? }` | `{ outDir, count, results:[{name,ok,file?,error?,skipped?}] }` | **medium** — `BitmapItem.exportToFile(uri)` is documented but return-value/format support varies; non-bitmaps are `skipped`. Selection/all fallback when `names` omitted |
| `exportLibrarySounds` | `{ outDir, names? }` | `{ outDir, count, results:[…] }` | **experimental** — `SoundItem.exportToFile` is unsupported on MANY builds; each item is wrapped in try/catch and reports `{ ok:false, error }` or `{ skipped, reason }`. Never throws |
| `safeSave` | `{ backupDir? }` | `{ saved, backupFile? }` | **medium** — backup-before-save via `FLfile.copy` then `document.save()`; uses `dom.pathURI`. Errors (no `ok:true`) if the doc was never saved. Backup name auto-increments `<stem>.<n>.fla` |
| `openDocument` | `{ file }` | `{ opened, name }` | **high** — `fl.openDocument(uri)`; errors if the open fails |

> Wave-1 export functions accept a `names` array to target specific library
> items; when omitted they use the **current Library selection**, and the
> bitmap/sound exporters fall back to **all** matching items if nothing is
> selected. `exportLibrarySounds` is best-effort: treat a per-item
> `ok:false`/`skipped` as "this build can't re-export that sound", not a failure.

### Wave 2 — library / frame / filter ops

| `cf7ak(fn, argJson)` | args | returns `data` | confidence |
|---|---|---|---|
| `libBatchRename` | `{ find, replace, useRegex?, names? }` | `{ count, renamed:[{from,to,ok,error?,skipped?,reason?}] }` | **high** — `selectItem(name,true,true)` + `renameItem(newLeaf)`. Renames the **leaf** only (computes `newLeaf` from the item's leaf, preserves the folder path in the reported `to`). `names?` targets those items; else all items whose **leaf** contains `find` (or matches the `new RegExp(find)` when `useRegex`). No-op renames are reported `ok:true, skipped:true`; collisions surface as `renameItem returned false` |
| `libNewFolder` | `{ path }` | `{ created, path, reason? }` | **high** — `library.newFolder(path)` (supports nested paths). Returns `created:false` if the folder path already exists |
| `libMoveToFolder` | `{ folder, names? }` | `{ count, moved:[{name,ok,error?}] }` | **high** — per item `selectItem(name,true,true)` then `library.moveToFolder(folder)`. `names?` else current **Library selection** (errors if neither) |
| `libDeleteItems` | `{ names }` | `{ count, deleted:[{name,ok,error?}] }` | **high** — `library.deleteItem(name)` guarded by `itemExists`. `names` is required (non-empty) — no selection fallback, to avoid accidental mass-delete |
| `framesInsert` | `{ count?, atEnd? }` | `{ ok, frameCount }` | **high** — `getTimeline().insertFrames(count||1, atEnd===true)`; operates on the current frame selection (or end when `atEnd`) |
| `framesRemove` | `{ count? }` | `{ ok, frameCount }` | **medium** — `getTimeline().removeFrames(count||1)`. Method presence is guarded (`typeof … !== "function"`) and reported, since the exact signature can differ by build |
| `framesReverse` | — | `{ ok }` | **medium** — `getTimeline().reverseFrames()`; acts on the **selected frames** (no-op/odd results if <2 keyframes are selected). Guarded for method presence |
| `framesConvertToKeyframes` | — | `{ ok }` | **medium** — `getTimeline().convertToKeyframes()` on the current frame selection. Guarded for method presence |
| `framesClearKeyframes` | — | `{ ok }` | **medium** — `getTimeline().clearKeyframes()` on the current frame selection. Guarded for method presence |
| `applyFilter` | `{ type, params? }` | `{ count, applied:[{name?,ok,error?,skipped?,reason?}] }` | **medium** — `type` ∈ `glow`\|`dropShadow`\|`blur`\|`bevel`\|`gradientGlow`. For each **filterable** stage selection (movie-clip/button/graphic instance or text), reads `el.filters`, appends a default filter object (`{name:'glowFilter',…}` etc.) merged with `params?`, and reassigns `el.filters = arr` (filters is copy-on-read). `glow`/`dropShadow`/`blur` field names are well-documented; `bevel`/`gradientGlow` defaults are best-effort. Non-filterable elements are `skipped`; an unknown `type` errors with `unsupported filter type` |
| `clearFilters` | — | `{ count }` | **medium** — sets `el.filters = []` on each filterable selected element; returns how many were cleared. Non-filterable elements are silently skipped |

> Wave-2 frame ops act on the **current timeline + frame selection** — the panel
> (or runner job) is responsible for selecting the target frames first; likewise
> the filter ops act on the **current stage selection** (`dom.selection`). Library
> ops resolve `names?` against full library paths; `libBatchRename` matches on the
> **leaf** name and renames the leaf in place. Every op is per-item try/catch and
> never throws out of the function. `applyFilter` filter-object field names are
> confirmed for glow/dropShadow/blur; verify bevel/gradientGlow shapes against the
> installed Animate's JSFL Filter reference before relying on them.

### Wave 3 — presets / bitmap / diagnostics

| `cf7ak(fn, argJson)` | args | returns `data` | confidence |
|---|---|---|---|
| `presetSave` | `{ name, fn, args }` | `{ ok, count, upserted, replaced }` | **high** — file-backed at `<fl.configURI>Commands/cf7ak/presets.json`. Loads (tolerating absent/empty/malformed → `[]`), **upserts by `name`**, writes back via `FLfile.write` (creates the dir if missing). No open document required |
| `presetList` | — | `{ count, presets:[{name,fn,args}] }` | **high** — reads `presets.json`; returns an empty array when the file is absent. Pure read, no document needed |
| `presetApply` | `{ name }` | `{ applied, fn, result }` | **high** — finds the preset and **re-dispatches** via `cf7ak(preset.fn, JSON.stringify(preset.args))`, then `JSON.parse`s that JSON-string into `result` (`{ ok, data }`\|`{ ok:false, error }`). Errors if the name is not found. Needs an open document only when the **applied** `fn` does |
| `presetDelete` | `{ name }` | `{ deleted, count }` | **high** — removes the named preset and writes back; `deleted:false` (no write) when the name was absent. No document needed |
| `bitmapTrace` | `{ threshold?, minArea?, curveFit?, cornerThreshold? }` | `{ ok, threshold, minArea, curveFit, cornerThreshold }` | **medium** — `document.traceBitmap(threshold||100, minArea||8, curveFit||"normal", cornerThreshold||"normal")` on the **current stage selection**. Guards that a bitmap is selected (errors otherwise) and that `traceBitmap` exists. `curveFit`/`cornerThreshold` are strings (`pixels`\|`very tight`\|`tight`\|`normal`\|`smooth`\|`very smooth`); exact param tolerance varies by build |
| `bitmapSetCompression` | `{ names?, compressionType?, quality?, allowSmoothing? }` | `{ count, applied:[{name,ok,error?,skipped?,compressionType?}] }` | **medium** — per `BitmapItem` (resolved from `names?`, else current Library selection, else **all**): sets `.compressionType` (`photo`\|`lossless`); when `photo` + `quality` given, sets `useImportedJPEGQuality=false` (guarded) then `.quality` (0–100); sets `.allowSmoothing` when provided. Non-bitmaps are `skipped`. `compressionType`/`quality` property names are documented but exact accepted values vary by build |
| `crashDiagnostics` | — | `{ report:{ flVersion, platform, openDocCount, activeDoc:{name,pathURI?,sceneCount,libraryItemCount,timelineFrameCount}\|null, configURI, hasSpriteSheetExporter, hasFLfile } }` | **high** — pure read-only environment dump: `fl.version`, `fl.getPlatform()`/`fl.platform`, `fl.documents.length`, active-doc stats (`null` if none; each sub-read individually guarded), `fl.configURI`, capability flags. Never mutates |

> **Presets** persist any cf7ak operation + its args so the panel/runner can
> re-apply later. Storage path is shared by both sides: `cf7akPresetsURI()` =
> `fl.configURI + "Commands/cf7ak/presets.json"`. CRUD (`presetSave`/`presetList`/
> `presetDelete`) never needs an open document and tolerates a missing/empty/
> malformed file (treated as `[]`); only `presetApply` may need one — and only if
> the **applied** function does. `presetApply` re-enters the **same dispatcher**,
> so a saved preset can chain any wave-1/2/3 op. `bitmapTrace`/`bitmapSetCompression`
> need a bitmap on stage / bitmap items in the library respectively — verify
> `compressionType`/`quality`/`traceBitmap` param behavior against the installed
> Animate build before relying on a batch. `crashDiagnostics` is the safe
> "what's my environment" dump for troubleshooting.

## Smoke-test in Animate (no panel needed)

1. Copy `host/index.jsfl` somewhere, open Animate, open a FLA with a few library symbols.
2. Window → Other Panels → **Actions**? No — use the **JSFL** approach: drop `index.jsfl`
   into the Animate `Commands` folder (or run via `Commands → Run Command…`) with a
   trailing test call, e.g. append `fl.trace(cf7ak('probe',''));` and run it.
3. Verify the Output panel prints `{ "ok": true, "data": { ... } }`. Then test
   `cf7ak('scanLinkage','')` and `cf7ak('listFrameLabels','')`.
4. For `exportSelected`, select 1–2 symbols in the Library, then run
   `fl.trace(cf7ak('exportSelected', '{"outDir":"C:/temp/out"}'));` and confirm PNGs appear.

Report any API mismatch (e.g. an `exportSpriteSheet` option) so the function can be
adjusted; the clean P3 CLI (`art …`) already covers the headless XFL-text slices.

## Headless runner (agent / CI driven, the CS6-native path)

`runner-main.jsfl` + `npm run build` (→ `host/cf7ak-runner.jsfl`, a concat of
`index.jsfl` + the runner) turn this host into a terminal-drivable job runner,
mirroring the repo's proven CS6 chain (`scripts/compile_action.jsfl`): a job
file (`{fn,args}`) goes into `<Configuration>/Commands/cf7ak/`, Animate runs
`cf7ak-runner.jsfl`, and the result lands in `cf7ak-result.json` + a
`cf7ak-done.marker`. The CLI drives it:

```bash
npm run build -w @cf7-animate-kit/jsfl-host
npm run art -- run scanLinkage --exe "<Animate.exe>" --timeout 60
# or, to dodge UAC, via a scheduled task (RunLevel=Highest):
npm run art -- setup-task --exe "<Animate.exe>"   # then run the .ps1 as admin
npm run art -- run probe --task AnimateKitJsflTask
```

Because **CS6 cannot host a CEP panel**, this runner is the native authoring-accel
path for CS6 users (the CEP panel serves Animate 2024+). The orchestration
(job write → trigger → marker + fresh-result check → JSON read) is unit-tested
in `an-host` with a stub trigger; the JSFL side still needs a real Animate.

## Clean-room

No networking, no license logic. Pure document automation. Consolidates the
spirit of the repo's existing `tools/jsfl/publish.jsfl` into one versioned host.
