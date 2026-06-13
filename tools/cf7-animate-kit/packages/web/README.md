# @cf7-animate-kit/web — 驾驶舱 (Cockpit)

A standalone **Electron + React** desktop app for use when **Adobe Animate is
closed**. Two tabs:

- **AN 维护 (maintenance)** — run an "AN doctor" (`collectDiagnostics`), list
  discovered Animate installs, and perform maintenance ops. Every mutating
  action is **plan-first**: it first runs with `apply:false`, shows the
  `OpResult` plan, and only an explicit **应用 / Apply** click writes anything.
  Ops: install plugin `.swf`, set JVM `-Xmx` memory, clear the `tmp` cache,
  tighten a sidebar dictionary `.dat`, and open the WindowSWF / Commands /
  Configuration / Cache folders.
- **SOL 检视/编辑 (inspector/editor)** — open a Flash SharedObject `.sol`, view
  its AMF0 tree (collapsible) plus metadata (name / amfVersion / element count),
  edit **primitive leaf values** (number / boolean / string), **preview the
  diff**, and **Save**. Saving always **backs up first** (`.bak-<timestamp>`)
  and re-reads from disk before applying. There is a prominent warning to never
  write while the game might be running (Flash overwrites the `.sol` on exit).

## Clean-room guarantees

- **No networking of any kind in the app.** No fetch / sockets / telemetry /
  license / activation / hosts edits. The *only* network access is `launch.bat`
  downloading the Electron binary at build time.
- All filesystem / `an-host` / `core` calls live in the **Electron main
  process**. The **renderer never imports** `@cf7-animate-kit/an-host` or
  `node:fs`; it reaches the machine only through the typed preload
  `contextBridge` (`window.ankit.*`).

## Architecture

```
electron main (Node)            preload (isolated)        renderer (React)
  ipc-maintenance-handlers  ──►  contextBridge.expose ──►  window.ankit.*
  ipc-sol-handlers               "ankit"                   MaintenancePanel
  sol-model (AST <-> tree)                                 SolPanel / SolTreeView
  @cf7-animate-kit/an-host + core
```

- `src/shared/ipc-types.ts` is the single typed contract both sides compile
  against.
- `src/electron/sol-model.ts` projects the lossless AMF0 AST into an editable
  tree (stable, escaped paths) and applies edits in place so `writeSol` stays
  byte-faithful for the untouched parts.

## Run

```bat
:: from packages\web\
launch.bat
```

`launch.bat` will (1) `npm install` at the monorepo root if needed (with
`ELECTRON_SKIP_BINARY_DOWNLOAD=1`), (2) build `core` + `an-host` + `web`, (3)
download + checksum-verify Electron v35.7.5 into `%TEMP%` (with curl/GitHub,
curl/npmmirror, and two PowerShell fallbacks), and (4) launch the bundled main
process (`dist/electron/main.cjs`).

## Develop / typecheck

```bash
# from the monorepo root
npm run build -w @cf7-animate-kit/core -w @cf7-animate-kit/an-host
npm run typecheck -w @cf7-animate-kit/web   # tsc --noEmit (renderer + electron)

# renderer dev server (UI only; window.ankit is absent → placeholder screen)
npm run dev:renderer -w @cf7-animate-kit/web
```

This package is intentionally **not** part of the root `tsc -b` project
references: it has its own `tsconfig.json` (renderer, DOM/JSX) and
`tsconfig.electron.json` (main + preload, Node) and its own `typecheck` script.

## Build outputs

- `dist/renderer/` — Vite-built renderer (`index.html` + assets).
- `dist/electron/main.cjs` — esbuild-bundled main process (CJS, `electron`
  external, core + an-host inlined via the `development` export condition).
- `dist/electron/preload.js` — copied verbatim (CommonJS).
