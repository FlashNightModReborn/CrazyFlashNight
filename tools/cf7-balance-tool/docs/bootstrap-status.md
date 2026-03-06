# Bootstrap Status

Current workspace status for `tools/cf7-balance-tool`.

## Verified on 2026-03-06

- `npm install`
- `npm run typecheck`
- `npm test`
- `npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json`

## Current runtime surface

- `packages/core`: shared contracts and field classification helpers
- `packages/xml-io`: project loader and first-pass XML field scanner
- `packages/cli`: `project scan` / `project fields` / `xml get` / `xml set` commands
- `packages/web`: Electron shell + React renderer shell, Chinese-first by default

## First scan baseline

- XML files scanned: 89
- Field names discovered: 528
- Field occurrences: 36854
- Unknown fields: 394

The current scanner is intentionally lexical. It is good enough for Phase 0 field inventory, but it is not the round-trip parser yet.

## Commands

```bash
npm install
npm run typecheck
npm test
npm run field-scan -- --project ./project.json --output ./reports/field-usage-report.json
npm run project-scan -- --project ./project.json
.\\node_modules\\.bin\\tsx.cmd packages/cli/src/index.ts xml get --file ../../data/items/武器_手枪_压制机枪.xml --path root.item[1].data.power
.\\node_modules\\.bin\\tsx.cmd packages/cli/src/index.ts xml set --file ../../data/items/武器_手枪_压制机枪.xml --path root.item[1].data.power --value 55 --output ./reports/weapon-power-sample.xml
npm run dev:web
npm run dev:electron
```

## Known gaps

- XML round-trip read/write is not implemented yet.
- Formula modules are still placeholders.
- Unknown field count is still high because list.xml, hairstyle.xml, missileConfigs.xml and part of consumable metadata are not classified yet.
- The Electron shell is now data-driven for the field scan summary, but diff and validation panels are not wired yet.