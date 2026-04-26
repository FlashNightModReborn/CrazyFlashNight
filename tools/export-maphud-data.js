#!/usr/bin/env node
'use strict';

// Build-time export: map-panel-data.js → launcher/data/map_hud_data.json
//
// MapHudWidget (C# native HUD, see launcher/src/Guardian/Hud/MapHudWidget.cs)
// loads this JSON at startup and serves outlines by hotspotId. Runtime keeps
// zero dependency on the JS file; this script is the sync seam.
//
// Run after edits to map-panel-data.js or before launcher build:
//   node tools/export-maphud-data.js
//
// Output schema (protocolVersion=1):
// {
//   "protocolVersion": 1,
//   "generatedAt": "<ISO timestamp>",
//   "sourceFile": "launcher/web/modules/map-panel-data.js",
//   "hotspots": {
//     "<hotspotId>": {
//       "meta": { pageId, pageLabel, hotspotId, label, sceneName, group },
//       "outline": { viewportRect, blocks[], visuals[], currentRect, focusFilterId }
//     }
//   }
// }

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const outputFile = path.join(projectRoot, 'launcher', 'data', 'map_hud_data.json');

function loadMapData() {
    const source = fs.readFileSync(dataFile, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: dataFile });
    if (!sandbox.MapPanelData) {
        throw new Error('MapPanelData not found in ' + dataFile);
    }
    return sandbox.MapPanelData;
}

function buildHotspotEntry(D, hotspotId) {
    const meta = D.resolveHotspotMeta(hotspotId);
    if (!meta) return null;
    const outline = D.getHudOutline(meta.pageId, meta.hotspotId);
    if (!outline) return null;

    const group = D.getHotspotUnlockGroup(meta.pageId, meta.hotspotId) || '';

    return {
        meta: {
            pageId: meta.pageId,
            pageLabel: meta.pageLabel || '',
            hotspotId: meta.hotspotId,
            label: meta.label || '',
            sceneName: meta.sceneName || '',
            group: group
        },
        outline: {
            focusFilterId: outline.focusFilterId || '',
            focusFilterLabel: outline.focusFilterLabel || '',
            viewportRect: outline.viewportRect || null,
            currentRect: outline.currentRect || null,
            blocks: (outline.blocks || []).map(function (b) {
                return {
                    hotspotId: b.hotspotId,
                    label: b.label || '',
                    sourceRect: b.sourceRect || null
                };
            }),
            visuals: (outline.visuals || []).map(function (v) {
                return {
                    id: v.id,
                    label: v.label || '',
                    assetUrl: v.assetUrl || '',
                    hotspotIds: v.hotspotIds || [],
                    sourceRect: v.sourceRect || null,
                    isCurrent: !!v.isCurrent
                };
            })
        }
    };
}

function main() {
    const D = loadMapData();
    const ids = D.getAllHotspotIds();

    const hotspots = {};
    let exported = 0;
    let skipped = 0;
    for (let i = 0; i < ids.length; i += 1) {
        const id = ids[i];
        const entry = buildHotspotEntry(D, id);
        if (!entry) {
            skipped += 1;
            continue;
        }
        hotspots[id] = entry;
        exported += 1;
    }

    const payload = {
        protocolVersion: 1,
        generatedAt: new Date().toISOString(),
        sourceFile: 'launcher/web/modules/map-panel-data.js',
        hotspots: hotspots
    };

    const outputDir = path.dirname(outputFile);
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    const json = JSON.stringify(payload, null, 2);
    fs.writeFileSync(outputFile, json, 'utf8');

    console.log('[export-maphud] wrote ' + path.relative(projectRoot, outputFile));
    console.log('[export-maphud] hotspots exported: ' + exported + ' (skipped: ' + skipped + ')');
}

main();
