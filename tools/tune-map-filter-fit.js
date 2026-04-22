#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const outputFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-fit-presets.js');

const DEFAULT_PRESET = {
    padXRate: 0.055,
    padXMin: 22,
    padXMax: 54,
    padYRate: 0.07,
    padYMin: 20,
    padYMax: 48,
    maxScale: 1.36,
    biasX: 0,
    biasY: 0
};

const PAGE_PADDING_CANDIDATES = [
    { padXRate: 0.055, padYRate: 0.07 },
    { padXRate: 0.05, padYRate: 0.06 },
    { padXRate: 0.045, padYRate: 0.05 },
    { padXRate: 0.04, padYRate: 0.045 }
];

const FILTER_MAX_SCALE_CANDIDATES = [1.36, 1.48, 1.6, 1.72];
const STAGE_PRESETS = [
    { id: 'compact', width: 749, height: 441, weight: 1.4 },
    { id: 'standard', width: 980, height: 578, weight: 1.0 },
    { id: 'roomy', width: 1207, height: 711, weight: 1.0 }
];
const BOUNDS_MARGIN_X = 12;
const BOUNDS_MARGIN_Y = 16;
const PAGE_GAIN_THRESHOLD = 0.12;
const FILTER_GAIN_THRESHOLD = 0.1;

function parseArgs(argv) {
    const args = {
        write: false,
        json: false,
        out: outputFile
    };

    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--write') {
            args.write = true;
            continue;
        }
        if (arg === '--json') {
            args.json = true;
            continue;
        }
        if (arg === '--out') {
            args.out = path.resolve(projectRoot, argv[i + 1] || '');
            i += 1;
            continue;
        }
        if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        }
        printHelp(1, 'unknown arg: ' + arg);
        return null;
    }

    return args;
}

function printHelp(exitCode, error) {
    if (error) {
        console.error(error);
    }
    console.error('usage: node tools/tune-map-filter-fit.js [--write] [--out <file>] [--json]');
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
    return Math.round(Number(value) * 1000) / 1000;
}

function cloneRect(rect) {
    if (!rect) return null;
    return {
        x: Number(rect.x),
        y: Number(rect.y),
        w: Number(rect.w),
        h: Number(rect.h)
    };
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
        x: minX,
        y: minY,
        w: maxX - minX,
        h: maxY - minY
    };
}

function inflateRect(rect, padX, padY) {
    if (!rect) return null;
    return {
        x: rect.x - padX,
        y: rect.y - padY,
        w: rect.w + (padX * 2),
        h: rect.h + (padY * 2)
    };
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function buildFilterBounds(mapData, pageId, filterId) {
    const page = mapData.getPage(pageId);
    const visibleHotspots = mapData.getVisibleHotspots(pageId, filterId || '');
    const visibleLookup = {};
    const rects = [];

    for (let i = 0; i < visibleHotspots.length; i += 1) {
        visibleLookup[visibleHotspots[i].id] = true;
        rects.push(cloneRect(visibleHotspots[i].rect));
    }

    const visuals = mapData.getVisibleSceneVisuals(pageId, filterId || '');
    for (let i = 0; i < visuals.length; i += 1) {
        rects.push(cloneRect(visuals[i].rect));
    }

    const staticAvatars = page.staticAvatars || [];
    for (let i = 0; i < staticAvatars.length; i += 1) {
        if (!staticAvatars[i].hotspotId || visibleLookup[staticAvatars[i].hotspotId]) {
            rects.push({
                x: staticAvatars[i].x,
                y: staticAvatars[i].y,
                w: staticAvatars[i].w,
                h: staticAvatars[i].h
            });
        }
    }

    const dynamicAvatars = page.dynamicAvatars || [];
    for (let i = 0; i < dynamicAvatars.length; i += 1) {
        if (!dynamicAvatars[i].hotspotId || visibleLookup[dynamicAvatars[i].hotspotId]) {
            rects.push({
                x: dynamicAvatars[i].x,
                y: dynamicAvatars[i].y,
                w: dynamicAvatars[i].w,
                h: dynamicAvatars[i].h
            });
        }
    }

    return inflateRect(unionRects(rects), BOUNDS_MARGIN_X, BOUNDS_MARGIN_Y);
}

function mergePreset(basePreset, override) {
    const merged = {};
    const keyOrder = Object.keys(DEFAULT_PRESET);
    let i;

    for (i = 0; i < keyOrder.length; i += 1) {
        merged[keyOrder[i]] = basePreset[keyOrder[i]];
    }

    if (override) {
        for (i = 0; i < keyOrder.length; i += 1) {
            if (Object.prototype.hasOwnProperty.call(override, keyOrder[i])) {
                merged[keyOrder[i]] = override[keyOrder[i]];
            }
        }
    }

    return merged;
}

function pickChangedKeys(preset, basePreset) {
    const out = {};
    const keys = Object.keys(DEFAULT_PRESET);
    for (let i = 0; i < keys.length; i += 1) {
        const key = keys[i];
        if (round(preset[key]) !== round(basePreset[key])) {
            out[key] = round(preset[key]);
        }
    }
    return out;
}

function computeStageMetrics(page, bounds, fitPreset, stagePreset) {
    const stageScale = Math.min(stagePreset.width / page.width, stagePreset.height / page.height, 1.3);
    const stageWidth = Math.round(page.width * stageScale);
    const stageHeight = Math.round(page.height * stageScale);
    const scaledBounds = {
        x: bounds.x * stageScale,
        y: bounds.y * stageScale,
        w: bounds.w * stageScale,
        h: bounds.h * stageScale
    };
    const padX = clamp(stageWidth * fitPreset.padXRate, fitPreset.padXMin, fitPreset.padXMax);
    const padY = clamp(stageHeight * fitPreset.padYRate, fitPreset.padYMin, fitPreset.padYMax);
    const widthLimit = (stageWidth - (padX * 2)) / Math.max(1, scaledBounds.w);
    const heightLimit = (stageHeight - (padY * 2)) / Math.max(1, scaledBounds.h);
    const unclampedScale = Math.min(widthLimit, heightLimit, fitPreset.maxScale);
    let fitScale = Math.max(1, unclampedScale);
    let limiter = 'min_scale';

    if (!isFinite(fitScale) || fitScale <= 0) {
        fitScale = 1;
    } else if (Math.abs(fitScale - fitPreset.maxScale) < 0.0001 && fitPreset.maxScale <= widthLimit && fitPreset.maxScale <= heightLimit) {
        limiter = 'cap';
    } else if (widthLimit <= heightLimit) {
        limiter = 'width';
    } else {
        limiter = 'height';
    }

    return {
        stageScale: round(stageScale),
        stageWidth: stageWidth,
        stageHeight: stageHeight,
        fitScale: round(fitScale),
        coverageX: round((scaledBounds.w * fitScale) / stageWidth),
        coverageY: round((scaledBounds.h * fitScale) / stageHeight),
        padX: round(padX),
        padY: round(padY),
        limiter: limiter
    };
}

function scoreStage(metrics) {
    const occupancy = (metrics.coverageX * 0.58) + (metrics.coverageY * 0.42);
    const area = Math.sqrt(metrics.coverageX * metrics.coverageY);
    return occupancy + (area * 0.35);
}

function evaluateFilter(page, bounds, fitPreset) {
    let total = 0;
    const compactMetrics = [];

    for (let i = 0; i < STAGE_PRESETS.length; i += 1) {
        const metrics = computeStageMetrics(page, bounds, fitPreset, STAGE_PRESETS[i]);
        total += scoreStage(metrics) * STAGE_PRESETS[i].weight;
        compactMetrics.push({
            stageId: STAGE_PRESETS[i].id,
            metrics: metrics
        });
    }

    return {
        score: round(total),
        stageMetrics: compactMetrics
    };
}

function countCapBoundStages(stageMetrics) {
    let total = 0;
    for (let i = 0; i < stageMetrics.length; i += 1) {
        if (stageMetrics[i].metrics.limiter === 'cap') {
            total += 1;
        }
    }
    return total;
}

function averageCoverage(stageMetrics) {
    let totalX = 0;
    let totalY = 0;
    for (let i = 0; i < stageMetrics.length; i += 1) {
        totalX += stageMetrics[i].metrics.coverageX * STAGE_PRESETS[i].weight;
        totalY += stageMetrics[i].metrics.coverageY * STAGE_PRESETS[i].weight;
    }
    const weightTotal = STAGE_PRESETS.reduce((sum, stage) => sum + stage.weight, 0);
    return {
        x: round(totalX / weightTotal),
        y: round(totalY / weightTotal)
    };
}

function selectPageDefaults(page, filters, boundsByFilter) {
    const basePreset = mergePreset(DEFAULT_PRESET);
    const baseScores = [];
    let i;

    for (i = 0; i < filters.length; i += 1) {
        baseScores.push(evaluateFilter(page, boundsByFilter[filters[i].id], basePreset));
    }

    let best = {
        score: baseScores.reduce((sum, item) => sum + item.score, 0),
        preset: basePreset
    };

    for (i = 0; i < PAGE_PADDING_CANDIDATES.length; i += 1) {
        const candidatePreset = mergePreset(DEFAULT_PRESET, PAGE_PADDING_CANDIDATES[i]);
        let candidateScore = 0;
        for (let j = 0; j < filters.length; j += 1) {
            candidateScore += evaluateFilter(page, boundsByFilter[filters[j].id], candidatePreset).score;
        }

        const padChangeCost =
            ((DEFAULT_PRESET.padXRate - candidatePreset.padXRate) * 10) +
            ((DEFAULT_PRESET.padYRate - candidatePreset.padYRate) * 10);
        candidateScore += padChangeCost;

        if (candidateScore > best.score) {
            best = {
                score: candidateScore,
                preset: candidatePreset
            };
        }
    }

    if ((best.score - baseScores.reduce((sum, item) => sum + item.score, 0)) < PAGE_GAIN_THRESHOLD) {
        return {
            preset: basePreset,
            changed: {}
        };
    }

    return {
        preset: best.preset,
        changed: pickChangedKeys(best.preset, DEFAULT_PRESET)
    };
}

function selectFilterOverride(page, filterId, bounds, basePreset) {
    const baseline = evaluateFilter(page, bounds, basePreset);
    const baselineCoverage = averageCoverage(baseline.stageMetrics);
    const capBoundCount = countCapBoundStages(baseline.stageMetrics);

    if (!capBoundCount) {
        return null;
    }

    let best = {
        score: baseline.score,
        preset: basePreset,
        metrics: baseline
    };

    for (let i = 0; i < FILTER_MAX_SCALE_CANDIDATES.length; i += 1) {
        const candidatePreset = mergePreset(basePreset, {
            maxScale: FILTER_MAX_SCALE_CANDIDATES[i]
        });
        const candidateMetrics = evaluateFilter(page, bounds, candidatePreset);
        const changeCost = Math.max(0, candidatePreset.maxScale - basePreset.maxScale) * 0.35;
        const candidateScore = candidateMetrics.score - changeCost;

        if (candidateScore > best.score) {
            best = {
                score: candidateScore,
                preset: candidatePreset,
                metrics: candidateMetrics
            };
        }
    }

    if ((best.score - baseline.score) < FILTER_GAIN_THRESHOLD) {
        return null;
    }

    return {
        changed: pickChangedKeys(best.preset, basePreset),
        baselineMetrics: baseline,
        candidateMetrics: best.metrics,
        baselineCoverage: baselineCoverage,
        candidateCoverage: averageCoverage(best.metrics.stageMetrics)
    };
}

function buildTuningReport(mapData) {
    const pageOrder = mapData.getPageOrder();
    const presets = {};
    const report = {
        stagePresets: STAGE_PRESETS.map(function(stage) {
            return {
                id: stage.id,
                width: stage.width,
                height: stage.height,
                weight: stage.weight
            };
        }),
        defaultPreset: mergePreset(DEFAULT_PRESET),
        pages: []
    };

    for (let i = 0; i < pageOrder.length; i += 1) {
        const pageId = pageOrder[i];
        const page = mapData.getPage(pageId);
        const filters = (page.filters || []).slice();
        const boundsByFilter = {};
        const pageEntry = {
            pageId: pageId,
            pageDefault: {},
            filters: []
        };

        for (let j = 0; j < filters.length; j += 1) {
            boundsByFilter[filters[j].id] = buildFilterBounds(mapData, pageId, filters[j].id);
        }

        const pageDefault = selectPageDefaults(page, filters, boundsByFilter);
        const pagePreset = mergePreset(DEFAULT_PRESET, pageDefault.changed);
        if (Object.keys(pageDefault.changed).length) {
            presets[pageId] = presets[pageId] || {};
            presets[pageId]['*'] = pageDefault.changed;
            pageEntry.pageDefault = pageDefault.changed;
        }

        for (let j = 0; j < filters.length; j += 1) {
            const filterId = filters[j].id;
            const filterOverride = selectFilterOverride(page, filterId, boundsByFilter[filterId], pagePreset);

            pageEntry.filters.push({
                filterId: filterId,
                bounds: {
                    x: round(boundsByFilter[filterId].x),
                    y: round(boundsByFilter[filterId].y),
                    w: round(boundsByFilter[filterId].w),
                    h: round(boundsByFilter[filterId].h)
                },
                override: filterOverride ? filterOverride.changed : {},
                baselineCompact: filterOverride
                    ? filterOverride.baselineMetrics.stageMetrics[0].metrics
                    : evaluateFilter(page, boundsByFilter[filterId], pagePreset).stageMetrics[0].metrics,
                tunedCompact: filterOverride
                    ? filterOverride.candidateMetrics.stageMetrics[0].metrics
                    : evaluateFilter(page, boundsByFilter[filterId], pagePreset).stageMetrics[0].metrics,
                averageCoverage: filterOverride ? filterOverride.candidateCoverage : averageCoverage(evaluateFilter(page, boundsByFilter[filterId], pagePreset).stageMetrics),
                capBoundStages: countCapBoundStages(evaluateFilter(page, boundsByFilter[filterId], pagePreset).stageMetrics)
            });

            if (filterOverride && Object.keys(filterOverride.changed).length) {
                presets[pageId] = presets[pageId] || {};
                presets[pageId][filterId] = filterOverride.changed;
            }
        }

        report.pages.push(pageEntry);
    }

    return {
        defaults: mergePreset(DEFAULT_PRESET),
        presets: presets,
        report: report
    };
}

function buildRuntimeFile(runtimePresets) {
    return [
        '// Auto-generated by tools/tune-map-filter-fit.js. Do not edit by hand.',
        'var MapFitPresets = (function() {',
        "    'use strict';",
        '',
        '    var _defaults = ' + JSON.stringify(runtimePresets.defaults, null, 4).replace(/\n/g, '\n    ') + ';',
        '    var _presets = ' + JSON.stringify(runtimePresets.presets, null, 4).replace(/\n/g, '\n    ') + ';',
        '',
        '    function copy(src) {',
        '        return JSON.parse(JSON.stringify(src));',
        '    }',
        '',
        '    function applyPreset(target, source) {',
        '        if (!source) return target;',
        '        var keys = Object.keys(source);',
        '        for (var i = 0; i < keys.length; i += 1) {',
        '            target[keys[i]] = source[keys[i]];',
        '        }',
        '        return target;',
        '    }',
        '',
        '    function resolve(pageId, filterId) {',
        '        var preset = copy(_defaults);',
        '        var pagePresets = _presets[pageId] || null;',
        '        if (pagePresets && pagePresets["*"]) {',
        '            applyPreset(preset, pagePresets["*"]);',
        '            preset.id = pageId + ":*";',
        '        } else {',
        '            preset.id = (pageId || "") + ":" + (filterId || "*");',
        '        }',
        '        if (pagePresets && filterId && pagePresets[filterId]) {',
        '            applyPreset(preset, pagePresets[filterId]);',
        '            preset.id = pageId + ":" + filterId;',
        '        }',
        '        preset.pageId = pageId || "";',
        '        preset.filterId = filterId || "";',
        '        return preset;',
        '    }',
        '',
        '    function getManifest() {',
        '        return {',
        '            defaults: copy(_defaults),',
        '            presets: copy(_presets)',
        '        };',
        '    }',
        '',
        '    return {',
        '        resolve: resolve,',
        '        getManifest: getManifest',
        '    };',
        '})();',
        ''
    ].join('\n');
}

function printSummary(result, asJson) {
    if (asJson) {
        console.log(JSON.stringify(result.report, null, 2));
        return;
    }

    console.log('map-fit tuning summary');
    console.log('stage presets: ' + STAGE_PRESETS.map(stage => stage.id + '=' + stage.width + 'x' + stage.height).join(', '));
    console.log('page defaults / filter overrides:');

    for (let i = 0; i < result.report.pages.length; i += 1) {
        const page = result.report.pages[i];
        const changedFilters = page.filters.filter(function(filter) {
            return Object.keys(filter.override || {}).length > 0;
        });
        console.log('- ' + page.pageId +
            ' pageDefault=' + JSON.stringify(page.pageDefault || {}) +
            ' filterOverrides=' + changedFilters.length);
        for (let j = 0; j < changedFilters.length; j += 1) {
            console.log('  - ' + changedFilters[j].filterId +
                ' override=' + JSON.stringify(changedFilters[j].override) +
                ' compact=' + changedFilters[j].baselineCompact.coverageX + '/' + changedFilters[j].baselineCompact.coverageY +
                ' -> ' + changedFilters[j].tunedCompact.coverageX + '/' + changedFilters[j].tunedCompact.coverageY);
        }
    }
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const mapData = evaluateScript(mapDataFile, 'MapPanelData');
    const result = buildTuningReport(mapData);
    printSummary(result, args.json);

    if (args.write) {
        fs.writeFileSync(args.out, buildRuntimeFile(result), 'utf8');
        console.log('wrote ' + path.relative(projectRoot, args.out));
    }
}

main();
