# @cf7-animate-kit/cep-panel

The **in-Animate authoring accelerator UI** — an Adobe Animate CEP HTML5 panel
(React + Vite + TypeScript). It drives the *live* FLA document through the JSFL
host at [`../jsfl-host/host/index.jsfl`](../jsfl-host/host/index.jsfl) via
`CSInterface.evalScript`.

> Clean-room: **no networking of any kind** lives in this panel — no fetch, no
> sockets, no telemetry/license/activation. The only "network" in the whole repo
> is `launch.bat` downloading Electron for an *unrelated* package. All of this
> panel's value is local document automation inside Animate.

## What it does

A panel ("CF7 AnimateKit", under Window → Extensions) with a **Doctor strip**
(host `probe`: `flVersion` + `hasDocument`/`hasSpriteSheetExporter`/`hasFLfile`)
and **6 tabs**:

| Tab | Functions |
|---|---|
| Linkage | `scanLinkage` → table; batch `applyLinkage` from a `{dir}_{base}` convention |
| Export | `exportSelected` (selected Library symbols → PNG + atlas) |
| Frame labels | `listFrameLabels` |
| Advanced | `exportStagePNG` / `exportFrameSequence` / `batchExportSymbols` / `exportLibraryBitmaps` / `exportLibrarySounds` / `safeSave` / `openDocument` |
| 库/帧/滤镜 | `libBatchRename`/`libNewFolder`/`libMoveToFolder`/`libDeleteItems` · `framesInsert`/`Remove`/`Reverse`/`ConvertToKeyframes`/`ClearKeyframes` · `applyFilter`/`clearFilters` |
| 预设/位图/诊断 | `presetSave`/`List`/`Apply`/`Delete` · `bitmapTrace`/`bitmapSetCompression` · `crashDiagnostics` |

> **Status:** verified working inside real Animate 2024 (waves 1–3 live-tested via
> the CDP method below; read-only fns on a live doc, mutating fns on a scratch doc).
> Full args/returns/confidence per function: [`../jsfl-host/README.md`](../jsfl-host/README.md).
> The whole development path + CEP playbook: [`../../docs/DEVELOPMENT.md`](../../docs/DEVELOPMENT.md) §5.

The bridge contract lives in [`../jsfl-host/README.md`](../jsfl-host/README.md);
the typed wrapper is [`src/bridge.ts`](./src/bridge.ts).

## Build — why it's a single inlined HTML (DON'T regress this)

`npm run build` = `vite build` (with **`vite-plugin-singlefile`**) + `copy-assets.mjs`
(drops `host/` + `CSXS/` + `.debug` into `dist/`). Two load-bearing config choices:

1. **`viteSingleFile()`** inlines JS+CSS into `index.html`. CEF enforces strict MIME
   on external `type="module"` scripts loaded from `file://`, and `file://` has no
   MIME → `Failed to load module script` → **blank panel**. Inlining removes the
   external fetch. Do not switch back to external chunks.
2. **`node:path` alias → `src/lib/node-path-stub.ts`** — core's `export * as anEnv`
   drags `node:path` into the bundle (can't be tree-shaken); the panel never calls
   anEnv, but a bare `node:path` import crashes CEF. The stub makes it resolve.

## Architecture notes

- **Renderer-only.** Everything under `src/` runs in the CEP renderer (CEF). A
  CEP panel has no Electron *main* process, so this package never imports
  `@cf7-animate-kit/an-host` (Node-only). The host is reached **exclusively**
  through `src/bridge.ts` → `CSInterface.evalScript`.
- **Minimal CSInterface.** Instead of vendoring Adobe's ~2000-line
  `CSInterface.js` over the network, [`src/lib/CSInterface.js`](./src/lib/CSInterface.js)
  reimplements just the surface we use (`evalScript`, `getHostEnvironment`,
  `getOSInformation`) against the `window.__adobe_cep__` global that the CEP
  runtime injects. If you ever need the full API, drop Adobe's official file in
  that folder and update `src/lib/cep.d.ts`.
- **Double-encoded args.** Per the contract, `callHost(fn, argObj)`
  `JSON.stringify`s the arg object, then `JSON.stringify`s *that* string to
  embed it safely inside the `cf7ak('fn', '<here>')` JSFL literal. It guards the
  literal `"EvalScript error."` sentinel and `JSON.parse`s the result into a
  `{ ok, data } | { ok, error }` discriminated union — `callHost` never rejects
  for host/parse errors, only resolves `ok:false`.

## Dev: unsigned install + hot reload + remote DevTools

### 0. Build the workspace deps once
This package depends on `@cf7-animate-kit/core`. From the **repo root**:
```
npm install
npm run build   # builds core (and the other ts packages)
```

### 1. Enable unsigned extensions + debugging (once)
Run [`install/enable-debug.bat`](./install/enable-debug.bat) **or** double-click
[`install/enable-debug.reg`](./install/enable-debug.reg). This sets
`HKCU\Software\Adobe\CSXS.9..12\PlayerDebugMode = 1` (Animate builds span those
CSXS versions). **Fully restart Animate afterward.**

### 2. Build + install the panel
From this package dir:
```
npm run build            # vite build -> dist/, then copies host/ + CSXS/ + .debug into dist/
install\install-dev.bat  # mklink /D %APPDATA%\Adobe\CEP\extensions\com.cf7.animatekit.panel -> dist
```
`install-dev.bat` may need **Administrator** (or Windows Developer Mode) for
`mklink`. Restart Animate → **Window → CF7 AnimateKit**.

### 3. Iterating

**UI (React) hot-reload** — opt-in via localStorage (the old `.cf7ak-dev` file
probe was removed; it 404'd under `file://` and added console noise):
```
npm run dev   # Vite serves http://localhost:5173 (base:'./', host:true)
```
From remote DevTools (§4): `localStorage.setItem('cf7ak-dev','1')` then reload the
panel → `index.html` redirects the CEF webview to the Vite dev server, HMR live.
Set it back to `'0'` / remove it to load the built bundle.

**JSFL host changes need a reload of the host VM, NOT just the webview.** The
manifest `<ScriptPath>host/index.jsfl` loads into Animate's JSFL tool VM **at
panel init**. After you edit/redeploy `host/index.jsfl`, `Page.reload` is not
enough. Either close+reopen the panel (or restart Animate), OR hot-load it into
the live shared VM (no restart):
```js
// run in the JSFL tool VM (e.g. via remote DevTools evalScript or CDP):
eval(FLfile.read('file:///<...>/extensions/com.cf7.animatekit.panel/host/index.jsfl'))
// re-defines cf7ak + all functions; the panel's evalScript shares this VM, so it
// immediately sees the new functions.
```

> `server.host = true` is deliberate (the CEF webview is a separate process and
> reaches the dev server by host). `base:'./'` keeps asset URLs relative for `file://`.

### 4. Remote DevTools
With debug mode on, the panel exposes a CEF remote-debugging server on the port
in [`.debug`](./.debug) (**8088**). Open **http://localhost:8088** in
Chrome/Edge while Animate has the panel open, click the panel's entry, and you
get full DevTools (console, network, React DevTools, breakpoints) against the
live panel.

## Verifying inside Animate (the method used here)

This panel **has been verified** in real Animate 2024 — but only because each
function was exercised against the live JSFL VM. To re-verify after changes
(headless, no clicking), use the **remote DevTools (port 8088) + CDP** approach
documented in [`../../docs/DEVELOPMENT.md`](../../docs/DEVELOPMENT.md) §5.3–5.4:

- Connect a CDP client (PowerShell `System.Net.WebSockets.ClientWebSocket`, since
  Node 20 has no global `WebSocket`) to `ws://localhost:8088/devtools/page/<id>`
  (`GET /json` for the id).
- `Runtime.evaluate` to call `window.__adobe_cep__.evalScript("cf7ak('fn','args')", cb)`
  and read the result; `Page.captureScreenshot` for visual confirmation;
  `Log.entryAdded`/`Runtime.exceptionThrown` to catch load errors (how the blank
  panel was diagnosed).

**Safe testing (never touch the user's open FLA):**
- *Read-only* fns (`scanLinkage`, `listLibrary`, `crashDiagnostics`): fine to call on the live doc.
- *Mutating* fns (rename/delete/frames/filters/trace/compression): run on a **scratch doc** —
  `var d=fl.createDocument(); /* build test content */ cf7ak('...'); fl.closeDocument(d,false);` (no save).

Build-time caveat that survives: `SpriteSheetExporter` / `exportSpriteSheet` option
names and a few `BitmapItem`/timeline property semantics vary by Animate build —
confirm against the *installed* version before relying on a batch.
