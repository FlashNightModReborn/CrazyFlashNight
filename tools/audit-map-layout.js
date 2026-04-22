#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const avatarSourceFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-avatar-source-data.js');

function parseArgs(argv) {
    const args = {
        page: '',
        json: false,
        failOnReview: false,
        kind: 'all'
    };

    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--page') {
            args.page = argv[i + 1] || '';
            i += 1;
            continue;
        }
        if (arg === '--kind') {
            args.kind = String(argv[i + 1] || 'all').trim().toLowerCase();
            i += 1;
            continue;
        }
        if (arg === '--json') {
            args.json = true;
            continue;
        }
        if (arg === '--fail-on-review') {
            args.failOnReview = true;
            continue;
        }
        if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        }
        printHelp(1, 'unknown arg: ' + arg);
        return null;
    }

    if (!['all', 'hotspot', 'avatar'].includes(args.kind)) {
        printHelp(1, 'unknown kind: ' + args.kind);
        return null;
    }

    return args;
}

function printHelp(exitCode, error) {
    if (error) {
        console.error(error);
    }
    console.error('usage: node tools/audit-map-layout.js [--page <id>] [--kind all|hotspot|avatar] [--json] [--fail-on-review]');
    process.exit(exitCode);
}

function evaluateScript(filePath, globalName) {
    const source = fs.readFileSync(filePath, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: filePath });
    if (!sandbox[globalName]) {
        throw new Error(globalName + ' not found in ' + filePath);
    }
    return sandbox[globalName];
}

function round(value) {
    return Math.round(Number(value) * 100) / 100;
}

function cloneRect(rect) {
    if (!rect) return null;
    return {
        x: round(rect.x),
        y: round(rect.y),
        w: round(rect.w),
        h: round(rect.h)
    };
}

function rectCenter(rect) {
    if (!rect) return null;
    return {
        x: round(rect.x + (rect.w / 2)),
        y: round(rect.y + (rect.h / 2))
    };
}

function rectDelta(currentRect, sourceRect) {
    if (!currentRect || !sourceRect) {
        return null;
    }

    const currentCenter = rectCenter(currentRect);
    const sourceCenter = rectCenter(sourceRect);
    return {
        dx: round(currentRect.x - sourceRect.x),
        dy: round(currentRect.y - sourceRect.y),
        dw: round(currentRect.w - sourceRect.w),
        dh: round(currentRect.h - sourceRect.h),
        centerDx: round(currentCenter.x - sourceCenter.x),
        centerDy: round(currentCenter.y - sourceCenter.y)
    };
}

function maxAbsDelta(delta) {
    if (!delta) return null;
    return Math.max(
        Math.abs(delta.dx),
        Math.abs(delta.dy),
        Math.abs(delta.dw),
        Math.abs(delta.dh),
        Math.abs(delta.centerDx),
        Math.abs(delta.centerDy)
    );
}

function classifyHotspot(delta, componentDelta, handTuned) {
    const maxComponentDelta = maxAbsDelta(componentDelta);
    const maxDelta = maxAbsDelta(delta);

    if (maxComponentDelta !== null) {
        if (maxComponentDelta <= 0.5) {
            if (handTuned) return { status: 'hand_tuned', note: 'hand_tuned_composite_rect' };
            if (maxDelta !== null && maxDelta <= 0.5) return { status: 'exact', note: 'xfl_aligned' };
            return { status: 'exact', note: 'component_aligned' };
        }
        if (maxComponentDelta <= 8) {
            if (handTuned) return { status: 'hand_tuned', note: 'hand_tuned_composite_rect' };
            return { status: 'near', note: 'minor_component_delta' };
        }
    }

    if (!delta) return { status: 'missing', note: 'missing_source_rect' };
    if (handTuned) return { status: 'hand_tuned', note: 'hand_tuned_composite_rect' };
    if (maxDelta <= 0.5) return { status: 'exact', note: 'xfl_aligned' };
    if (maxDelta <= 8) return { status: 'near', note: 'minor_delta' };
    return { status: 'review', note: 'large_delta' };
}

function classifyAvatar(delta) {
    if (!delta) return { status: 'missing', note: 'missing_avatar_source' };

    const maxDelta = maxAbsDelta(delta);
    if (maxDelta <= 0.5) return { status: 'exact', note: 'xfl_aligned' };
    if (maxDelta <= 4) return { status: 'near', note: 'minor_delta' };
    return { status: 'review', note: 'large_delta' };
}

function unionRects(rects) {
    const filtered = (rects || []).filter(Boolean);
    if (!filtered.length) return null;

    let minX = filtered[0].x;
    let minY = filtered[0].y;
    let maxX = filtered[0].x + filtered[0].w;
    let maxY = filtered[0].y + filtered[0].h;

    for (let i = 1; i < filtered.length; i += 1) {
        minX = Math.min(minX, filtered[i].x);
        minY = Math.min(minY, filtered[i].y);
        maxX = Math.max(maxX, filtered[i].x + filtered[i].w);
        maxY = Math.max(maxY, filtered[i].y + filtered[i].h);
    }

    return {
        x: round(minX),
        y: round(minY),
        w: round(maxX - minX),
        h: round(maxY - minY)
    };
}

function iou(rectA, rectB) {
    if (!rectA || !rectB) return null;

    const left = Math.max(rectA.x, rectB.x);
    const top = Math.max(rectA.y, rectB.y);
    const right = Math.min(rectA.x + rectA.w, rectB.x + rectB.w);
    const bottom = Math.min(rectA.y + rectA.h, rectB.y + rectB.h);
    const width = Math.max(0, right - left);
    const height = Math.max(0, bottom - top);
    const intersection = width * height;
    const areaA = rectA.w * rectA.h;
    const areaB = rectB.w * rectB.h;
    const union = areaA + areaB - intersection;
    if (!union) return 0;
    return round(intersection / union);
}

function assetStem(assetUrl) {
    return String(assetUrl || '')
        .replace(/^.*[\\/]/, '')
        .replace(/\.png$/i, '')
        .trim();
}

function buildHotspotRows(mapData, manifest, pageIds) {
    const rows = [];

    for (let i = 0; i < pageIds.length; i += 1) {
        const pageId = pageIds[i];
        const page = mapData.getPage(pageId);
        const exportedPage = manifest.pages[pageId];
        const sceneNodes = exportedPage && exportedPage.sceneNodes ? exportedPage.sceneNodes : [];
        const hotspots = exportedPage && exportedPage.hotspots ? exportedPage.hotspots : [];

        for (let j = 0; j < hotspots.length; j += 1) {
            const hotspot = hotspots[j];
            const sourceRect = cloneRect(hotspot.sourceRect || mapData.getSourceRect(pageId, hotspot.id));
            const currentRect = cloneRect(hotspot.rect);
            const sceneRects = sceneNodes
                .filter(function(node) {
                    return Array.isArray(node.hotspotIds) && node.hotspotIds.indexOf(hotspot.id) >= 0;
                })
                .map(function(node) {
                    return cloneRect(node.rect);
                });
            const componentRect = unionRects(sceneRects);
            const delta = rectDelta(currentRect, sourceRect);
            const componentDelta = rectDelta(componentRect, sourceRect);
            const boxVsComponent = rectDelta(currentRect, componentRect);
            const state = classifyHotspot(delta, boxVsComponent, mapData.isHandTunedLayout(hotspot.id));
            const drift = boxVsComponent ? maxAbsDelta(boxVsComponent) : null;
            const driftNote = componentRect
                ? (drift !== null && drift > 12 ? 'hotspot_component_drift' : 'hotspot_component_aligned')
                : 'missing_scene_visual';

            rows.push({
                kind: 'hotspot',
                pageId: pageId,
                hotspotId: hotspot.id,
                label: hotspot.label,
                sceneName: hotspot.target ? hotspot.target.sceneName : '',
                status: state.status,
                note: state.note,
                sourceRect: sourceRect,
                currentRect: currentRect,
                componentRect: componentRect,
                delta: delta,
                componentDelta: componentDelta,
                boxVsComponent: boxVsComponent,
                boxVsComponentIou: iou(currentRect, componentRect),
                driftNote: driftNote
            });
        }
    }

    return rows;
}

function buildAvatarRows(mapData, pageIds, avatarSourceData) {
    const rows = [];

    for (let i = 0; i < pageIds.length; i += 1) {
        const pageId = pageIds[i];
        const page = mapData.getPage(pageId);
        const staticAvatars = page && page.staticAvatars ? page.staticAvatars : [];

        for (let j = 0; j < staticAvatars.length; j += 1) {
            const slot = staticAvatars[j];
            const sourceSlot = avatarSourceData && avatarSourceData.getByAssetUrl
                ? avatarSourceData.getByAssetUrl(slot.assetUrl)
                : null;
            const authoredRect = cloneRect({ x: slot.x, y: slot.y, w: slot.w, h: slot.h });
            const sourceRect = sourceSlot ? cloneRect(sourceSlot.rect) : null;
            const runtimeRect = sourceRect || authoredRect;
            const runtimeDelta = rectDelta(runtimeRect, sourceRect);
            const authoredDelta = rectDelta(authoredRect, sourceRect);
            const state = classifyAvatar(runtimeDelta);
            const authoringState = classifyAvatar(authoredDelta);

            rows.push({
                kind: 'avatar',
                pageId: pageId,
                avatarId: slot.id,
                label: slot.label,
                hotspotId: slot.hotspotId || '',
                assetUrl: slot.assetUrl || '',
                symbolName: sourceSlot ? sourceSlot.symbolName : assetStem(slot.assetUrl),
                status: state.status,
                note: state.note,
                sourceRect: sourceRect,
                currentRect: runtimeRect,
                runtimeRect: runtimeRect,
                authoredRect: authoredRect,
                delta: runtimeDelta,
                runtimeDelta: runtimeDelta,
                authoredDelta: authoredDelta,
                authoredStatus: authoringState.status,
                authoredNote: authoringState.note,
                crop: sourceSlot ? sourceSlot.crop || null : null,
                assetSize: sourceSlot ? sourceSlot.assetSize || null : null
            });
        }
    }

    return rows;
}

function initCounter() {
    return { exact: 0, near: 0, hand_tuned: 0, review: 0, missing: 0 };
}

function bumpCounter(counter, status) {
    if (!(status in counter)) {
        counter[status] = 0;
    }
    counter[status] += 1;
}

function buildSummary(rows) {
    const summary = {
        total: rows.length,
        byKind: {},
        byPage: {}
    };

    for (let i = 0; i < rows.length; i += 1) {
        const row = rows[i];
        if (!summary.byKind[row.kind]) {
            summary.byKind[row.kind] = initCounter();
        }
        if (!summary.byPage[row.pageId]) {
            summary.byPage[row.pageId] = {};
        }
        if (!summary.byPage[row.pageId][row.kind]) {
            summary.byPage[row.pageId][row.kind] = initCounter();
        }

        bumpCounter(summary.byKind[row.kind], row.status);
        bumpCounter(summary.byPage[row.pageId][row.kind], row.status);
    }

    return summary;
}

function printSummary(summary) {
    console.error('[map-layout-audit] byKind ' + JSON.stringify(summary.byKind));
    console.error('[map-layout-audit] byPage ' + JSON.stringify(summary.byPage));
}

function printHotspotTable(rows) {
    const table = rows.map(function(row) {
        return {
            page: row.pageId,
            hotspot: row.hotspotId,
            status: row.status,
            dx: row.delta ? row.delta.dx : null,
            dy: row.delta ? row.delta.dy : null,
            dw: row.delta ? row.delta.dw : null,
            dh: row.delta ? row.delta.dh : null,
            sceneDx: row.boxVsComponent ? row.boxVsComponent.centerDx : null,
            sceneDy: row.boxVsComponent ? row.boxVsComponent.centerDy : null,
            iou: row.boxVsComponentIou,
            drift: row.driftNote
        };
    });
    console.table(table);
}

function printAvatarTable(rows) {
    const table = rows.map(function(row) {
        return {
            page: row.pageId,
            avatar: row.avatarId,
            symbol: row.symbolName,
            runtimeStatus: row.status,
            runtimeDx: row.runtimeDelta ? row.runtimeDelta.dx : null,
            runtimeDy: row.runtimeDelta ? row.runtimeDelta.dy : null,
            authoredStatus: row.authoredStatus,
            authoredDx: row.authoredDelta ? row.authoredDelta.dx : null,
            authoredDy: row.authoredDelta ? row.authoredDelta.dy : null,
            hotspot: row.hotspotId
        };
    });
    console.table(table);
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const mapData = evaluateScript(mapDataFile, 'MapPanelData');
    const manifest = mapData.exportManifest();
    const avatarSourceData = fs.existsSync(avatarSourceFile)
        ? evaluateScript(avatarSourceFile, 'MapAvatarSourceData')
        : null;
    const pageIds = args.page
        ? [mapData.resolvePageId(args.page)]
        : manifest.pageOrder.slice();

    let rows = [];
    if (args.kind === 'all' || args.kind === 'hotspot') {
        rows = rows.concat(buildHotspotRows(mapData, manifest, pageIds));
    }
    if (args.kind === 'all' || args.kind === 'avatar') {
        rows = rows.concat(buildAvatarRows(mapData, pageIds, avatarSourceData));
    }

    const summary = buildSummary(rows);
    if (args.json) {
        process.stdout.write(JSON.stringify({ summary: summary, rows: rows }, null, 2) + '\n');
    } else {
        printSummary(summary);
        const hotspotRows = rows.filter(function(row) { return row.kind === 'hotspot'; });
        const avatarRows = rows.filter(function(row) { return row.kind === 'avatar'; });
        if (hotspotRows.length) {
            printHotspotTable(hotspotRows);
        }
        if (avatarRows.length) {
            printAvatarTable(avatarRows);
        }
    }

    if (args.failOnReview) {
        const hasReview = rows.some(function(row) {
            return row.status === 'review' || row.status === 'missing';
        });
        if (hasReview) {
            process.exit(1);
        }
    }
}

main();
