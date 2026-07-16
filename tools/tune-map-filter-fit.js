#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const mapDataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-panel-data.js');
const avatarSourceFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'map-avatar-source-data.js');
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

// content-fit 是场景内部取景倍率，不等同于外层 stageScale。高分辨率的小场景
// （例如地下水）需要显著高于 1.75 才能获得合理占有率；最终物理像素放大仍由
// MapScalePolicy 的 stage * fit * DPR / sourceRatio <= 1.75 约束兜底。
const FILTER_MAX_SCALE_CANDIDATES = [1.36, 1.48, 1.6, 1.72, 2, 2.4, 2.8, 3.2, 3.6, 4, 4.5];
const STAGE_PRESETS = [
    { id: 'compact', width: 749, height: 441, weight: 1.4 },
    { id: 'standard', width: 980, height: 578, weight: 1.0 },
    { id: 'roomy', width: 1334, height: 787, weight: 1.0 }
];
const PAGE_GAIN_THRESHOLD = 0.12;
const EXPERIENCE_GAIN_THRESHOLD = 0.0005;
const EXPERIENCE_PROFILES = {
    focus: { minX: 0.56, maxX: 0.88, minY: 0.50, maxY: 0.84 },
    horizontal: { minX: 0.84, maxX: 0.93, minY: 0.30, maxY: 0.56 },
    vertical: { minX: 0.40, maxX: 0.66, minY: 0.72, maxY: 0.91 },
    overview: { minX: 0.72, maxX: 0.93, minY: 0.72, maxY: 0.93 },
    dense: { minX: 0.78, maxX: 0.93, minY: 0.78, maxY: 0.93 }
};
const FILTER_EXPERIENCE_PROFILES = {
    base: {
        roof: 'focus', first_floor: 'horizontal', basement1: 'focus', basement2: 'horizontal',
        water: 'focus', all: 'overview', hierarchy: 'overview'
    },
    faction: {
        warlord: 'vertical', rock: 'vertical', blackiron: 'vertical', fallen: 'horizontal', all: 'overview'
    },
    defense: { first_line: 'horizontal', restricted: 'vertical', all: 'overview' },
    school: { inside: 'dense', outside: 'focus', all: 'overview' }
};
// 产品级舞台异常兜底；运行时还会叠加素材清晰度与 Canvas backing-pixel 预算。
// 与 map-scale-policy.js PRODUCT_STAGE_SCALE_MAX 保持一致。
const STAGE_MAX_SCALE = 1.75;
// composite 在 DPR=1 下的“视觉放大倍数” = stageScale * fitScale / sourceRatio。
// 运行时真实物理像素倍率还要乘 devicePixelRatio，由 MapScalePolicy 动态裁切；
// tuner 不预设设备 DPR，只生成 sourceRatio capability 与 DPR=1 的离线覆盖率报告。
// 超过此阈值说明运行时位图被拉伸绘制到屏幕，有明显 pixelated 风险。
// 此阈值用于告警并写入生成态 capability；运行时由 MapScalePolicy 联合舞台缩放动态限幅。
//
// 1.75 是配合 map-panel.js 中 scene-node unsharp mask 后处理 (amount=0.45) 的视觉容忍阈;
// 锐化把"可接受放大"从无后处理的 ~1.5 抬到 ~1.75。改这个常量必须重跑 --write 重新生成
// map-fit-presets.js, 且需同步调整 sharpen amount 才能持续匹配 (sharpen↑ → cap↑)。
const COMPOSITE_VISUAL_SCALE_CAP = 1.75;
// fallback: 当无法读取运行时图像时，假设 sourceRatio = 1.0（一张刚好够 1× 绘制的资产）
const DEFAULT_SOURCE_RATIO = 1.0;
const webRoot = path.join(projectRoot, 'launcher', 'web');
const imageSizeCache = {};

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

function readUInt24LE(buf, offset) {
    return buf[offset] | (buf[offset + 1] << 8) | (buf[offset + 2] << 16);
}

function readWebpSize(buf) {
    if (buf.length < 30 || buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WEBP') {
        return null;
    }
    let offset = 12;
    while (offset + 8 <= buf.length) {
        const chunkType = buf.toString('ascii', offset, offset + 4);
        const chunkSize = buf.readUInt32LE(offset + 4);
        const dataOffset = offset + 8;
        if (dataOffset + chunkSize > buf.length) return null;
        if (chunkType === 'VP8X' && chunkSize >= 10) {
            return { w: readUInt24LE(buf, dataOffset + 4) + 1, h: readUInt24LE(buf, dataOffset + 7) + 1 };
        }
        if (chunkType === 'VP8L' && chunkSize >= 5 && buf[dataOffset] === 0x2f) {
            const b0 = buf[dataOffset + 1];
            const b1 = buf[dataOffset + 2];
            const b2 = buf[dataOffset + 3];
            const b3 = buf[dataOffset + 4];
            return {
                w: 1 + b0 + ((b1 & 0x3f) << 8),
                h: 1 + (b1 >> 6) + (b2 << 2) + ((b3 & 0x0f) << 10)
            };
        }
        if (chunkType === 'VP8 ' && chunkSize >= 10
            && buf[dataOffset + 3] === 0x9d && buf[dataOffset + 4] === 0x01 && buf[dataOffset + 5] === 0x2a) {
            return {
                w: buf.readUInt16LE(dataOffset + 6) & 0x3fff,
                h: buf.readUInt16LE(dataOffset + 8) & 0x3fff
            };
        }
        offset = dataOffset + chunkSize + (chunkSize % 2);
    }
    return null;
}

function readImageSize(absPath) {
    if (imageSizeCache[absPath] !== undefined) return imageSizeCache[absPath];
    try {
        const buf = fs.readFileSync(absPath);
        if (buf.readUInt32BE(0) !== 0x89504e47 || buf.toString('ascii', 12, 16) !== 'IHDR') {
            imageSizeCache[absPath] = readWebpSize(buf);
            return imageSizeCache[absPath];
        }
        const size = { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
        imageSizeCache[absPath] = size;
        return size;
    } catch (err) {
        imageSizeCache[absPath] = null;
        return null;
    }
}

function computeFilterSourceCeiling(mapData, pageId, filterId) {
    // 取 filter 下所有可见 sceneVisual 的运行时图像采样率，返回最严（最小）的 ratio；
    // 即“源图能支撑的最大逻辑放大倍数”。filter 里只要有一张低清素材，整张 fit 上限就被它锁死。
    const visuals = mapData.getVisibleSceneVisuals(pageId, filterId || '');
    let minRatio = Infinity;
    let worst = null;
    for (let i = 0; i < visuals.length; i += 1) {
        const visual = visuals[i];
        if (!visual || !visual.rect || !visual.assetUrl) continue;
        const imagePath = path.join(webRoot, visual.assetUrl.replace(/^\/+/, ''));
        const size = readImageSize(imagePath);
        if (!size) continue;
        const ratioW = size.w / Math.max(1, visual.rect.w);
        const ratioH = size.h / Math.max(1, visual.rect.h);
        const ratio = Math.min(ratioW, ratioH);
        if (ratio < minRatio) {
            minRatio = ratio;
            worst = {
                assetUrl: visual.assetUrl,
                imageW: size.w,
                imageH: size.h,
                rectW: visual.rect.w,
                rectH: visual.rect.h,
                ratio: round(ratio)
            };
        }
    }
    if (!isFinite(minRatio)) {
        return { sourceRatio: DEFAULT_SOURCE_RATIO, worstAsset: null };
    }
    return { sourceRatio: round(minRatio), worstAsset: worst };
}

function loadMapBundle() {
    const sandbox = { console };
    vm.createContext(sandbox);
    // C 阶段后 panel-data 的 exportManifest 在 IIFE 末尾访问 MapAvatarSourceData,
    // 必须先加载 source-data 才能让 staticAvatar marker rect 派生正确。
    vm.runInContext(fs.readFileSync(avatarSourceFile, 'utf8'), sandbox, { filename: avatarSourceFile });
    vm.runInContext(fs.readFileSync(mapDataFile, 'utf8'), sandbox, { filename: mapDataFile });
    if (!sandbox.MapPanelData) {
        throw new Error('MapPanelData not found in ' + mapDataFile);
    }
    if (!sandbox.MapAvatarSourceData) {
        throw new Error('MapAvatarSourceData not found in ' + avatarSourceFile);
    }
    return { mapData: sandbox.MapPanelData, avatarSource: sandbox.MapAvatarSourceData };
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

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function resolveStaticAvatarBoundsRect(mapData, avatarSource, pageId, slot) {
    if (!slot || !slot.assetUrl) return null;
    const sourceSlot = avatarSource.getByAssetUrl(slot.assetUrl);
    if (!sourceSlot || !sourceSlot.size) return null;
    const hotspotId = sourceSlot.hotspotId || slot.hotspotId;
    if (!hotspotId) return null;
    const hotspot = mapData.findHotspot(pageId, hotspotId);
    if (!hotspot || !hotspot.rect) return null;
    return {
        x: hotspot.rect.x + sourceSlot.relX,
        y: hotspot.rect.y + sourceSlot.relY,
        w: sourceSlot.size.w,
        h: sourceSlot.size.h
    };
}

function resolveDynamicAvatarBoundsRect(mapData, pageId, slot) {
    if (!slot || !slot.hotspotId) return null;
    const hotspot = mapData.findHotspot(pageId, slot.hotspotId);
    if (!hotspot || !hotspot.rect) return null;
    return {
        x: hotspot.rect.x + slot.relX,
        y: hotspot.rect.y + slot.relY,
        w: slot.w,
        h: slot.h
    };
}

function buildFilterBounds(mapData, avatarSource, pageId, filterId) {
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
            const rect = resolveStaticAvatarBoundsRect(mapData, avatarSource, pageId, staticAvatars[i]);
            if (rect) rects.push(rect);
        }
    }

    const dynamicAvatars = page.dynamicAvatars || [];
    for (let i = 0; i < dynamicAvatars.length; i += 1) {
        if (!dynamicAvatars[i].hotspotId || visibleLookup[dynamicAvatars[i].hotspotId]) {
            const rect = resolveDynamicAvatarBoundsRect(mapData, pageId, dynamicAvatars[i]);
            if (rect) rects.push(rect);
        }
    }

    // 与 runtime 的逻辑内容坐标保持同一口径；视觉留白只由 fit preset padding 负责，
    // 不再在离线侧偷偷膨胀一次包围盒。
    return unionRects(rects);
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
    const stageScale = Math.min(stagePreset.width / page.width, stagePreset.height / page.height, STAGE_MAX_SCALE);
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

function resolveExperienceProfile(pageId, filterId) {
    const pageProfiles = FILTER_EXPERIENCE_PROFILES[pageId] || {};
    const profileId = pageProfiles[filterId] || 'focus';
    return {
        id: profileId,
        target: EXPERIENCE_PROFILES[profileId]
    };
}

function rangePenalty(value, min, max) {
    if (value < min) return Math.pow(min - value, 2);
    if (value > max) return Math.pow(value - max, 2);
    return 0;
}

function scoreExperience(stageMetrics, target) {
    let penalty = 0;
    let weightTotal = 0;
    for (let i = 0; i < stageMetrics.length; i += 1) {
        const metrics = stageMetrics[i].metrics;
        const weight = STAGE_PRESETS[i].weight;
        penalty += (
            rangePenalty(metrics.coverageX, target.minX, target.maxX) +
            rangePenalty(metrics.coverageY, target.minY, target.maxY)
        ) * weight;
        weightTotal += weight;
    }
    return penalty / Math.max(1, weightTotal);
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
            Math.abs(DEFAULT_PRESET.padXRate - candidatePreset.padXRate) +
            Math.abs(DEFAULT_PRESET.padYRate - candidatePreset.padYRate);
        candidateScore -= padChangeCost;

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

function selectFilterOverride(page, filterId, bounds, basePreset, sourceRatio) {
    const baseline = evaluateFilter(page, bounds, basePreset);
    const baselineCoverage = averageCoverage(baseline.stageMetrics);
    const experience = resolveExperienceProfile(page.id, filterId);
    const baselinePenalty = scoreExperience(baseline.stageMetrics, experience.target);

    // 素材倍率写入 capability manifest；运行时 MapScalePolicy 优先放大外层舞台，
    // 再按 stageScale 动态裁切 content-fit。离线 tuner 只负责内容覆盖率，不再把最坏
    // 大视口假设固化进 preset，否则低清单块会让紧凑视口也失去本可安全使用的 fit。
    const safeRatio = Number(sourceRatio) > 0 ? Number(sourceRatio) : DEFAULT_SOURCE_RATIO;

    let best = {
        objective: baselinePenalty,
        preset: basePreset,
        metrics: baseline,
        penalty: baselinePenalty
    };

    for (let i = 0; i < FILTER_MAX_SCALE_CANDIDATES.length; i += 1) {
        const rawCandidateMax = FILTER_MAX_SCALE_CANDIDATES[i];
        const candidatePreset = mergePreset(basePreset, {
            maxScale: rawCandidateMax
        });
        const candidateMetrics = evaluateFilter(page, bounds, candidatePreset);
        const candidatePenalty = scoreExperience(candidateMetrics.stageMetrics, experience.target);
        // 目标区间内优先采用更小倍率，避免在等价覆盖下留下无意义的高 cap。
        const changeCost = Math.max(0, candidatePreset.maxScale - basePreset.maxScale) * 0.0001;
        const candidateObjective = candidatePenalty + changeCost;

        if (candidateObjective < best.objective) {
            best = {
                objective: candidateObjective,
                preset: candidatePreset,
                metrics: candidateMetrics,
                penalty: candidatePenalty
            };
        }
    }

    if ((baselinePenalty - best.penalty) < EXPERIENCE_GAIN_THRESHOLD ||
            round(best.preset.maxScale) === round(basePreset.maxScale)) {
        return null;
    }

    return {
        changed: pickChangedKeys(best.preset, basePreset),
        baselineMetrics: baseline,
        candidateMetrics: best.metrics,
        baselineCoverage: baselineCoverage,
        candidateCoverage: averageCoverage(best.metrics.stageMetrics),
        sourceRatio: safeRatio,
        experienceProfile: experience.id,
        experienceTarget: experience.target,
        baselinePenalty: baselinePenalty,
        candidatePenalty: best.penalty,
        reason: 'experience_target'
    };
}

function buildTuningReport(mapData, avatarSource) {
    const pageOrder = mapData.getPageOrder();
    const presets = {};
    const capabilities = {};
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
        experienceProfiles: EXPERIENCE_PROFILES,
        filterExperienceProfiles: FILTER_EXPERIENCE_PROFILES,
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
        capabilities[pageId] = {};

        for (let j = 0; j < filters.length; j += 1) {
            boundsByFilter[filters[j].id] = buildFilterBounds(mapData, avatarSource, pageId, filters[j].id);
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
            const experience = resolveExperienceProfile(pageId, filterId);
            const sourceCeiling = computeFilterSourceCeiling(mapData, pageId, filterId);
            capabilities[pageId][filterId] = {
                sourceRatio: sourceCeiling.sourceRatio,
                worstAsset: sourceCeiling.worstAsset ? sourceCeiling.worstAsset.assetUrl : ''
            };
            const filterOverride = selectFilterOverride(page, filterId, boundsByFilter[filterId], pagePreset, sourceCeiling.sourceRatio);
            const tunedEvaluation = filterOverride
                ? filterOverride.candidateMetrics
                : evaluateFilter(page, boundsByFilter[filterId], pagePreset);

            pageEntry.filters.push({
                filterId: filterId,
                bounds: {
                    x: round(boundsByFilter[filterId].x),
                    y: round(boundsByFilter[filterId].y),
                    w: round(boundsByFilter[filterId].w),
                    h: round(boundsByFilter[filterId].h)
                },
                sourceRatio: sourceCeiling.sourceRatio,
                worstAsset: sourceCeiling.worstAsset,
                override: filterOverride ? filterOverride.changed : {},
                baselineCompact: filterOverride
                    ? filterOverride.baselineMetrics.stageMetrics[0].metrics
                    : tunedEvaluation.stageMetrics[0].metrics,
                tunedCompact: tunedEvaluation.stageMetrics[0].metrics,
                tunedStageMetrics: tunedEvaluation.stageMetrics, // 所有 stage preset × filter 的 fit 结果, 供放大告警扫描
                averageCoverage: filterOverride ? filterOverride.candidateCoverage : averageCoverage(tunedEvaluation.stageMetrics),
                capBoundStages: countCapBoundStages(tunedEvaluation.stageMetrics),
                experienceProfile: experience.id,
                experienceTarget: experience.target,
                experiencePenalty: scoreExperience(tunedEvaluation.stageMetrics, experience.target)
            });

            if (filterOverride && Object.keys(filterOverride.changed).length) {
                presets[pageId] = presets[pageId] || {};
                presets[pageId][filterId] = filterOverride.changed;
            }
        }

        let pageWorst = null;
        const capabilityIds = Object.keys(capabilities[pageId]);
        for (let j = 0; j < capabilityIds.length; j += 1) {
            const entry = capabilities[pageId][capabilityIds[j]];
            if (!pageWorst || entry.sourceRatio < pageWorst.sourceRatio) pageWorst = entry;
        }
        capabilities[pageId]['*'] = pageWorst || { sourceRatio: DEFAULT_SOURCE_RATIO, worstAsset: '' };

        report.pages.push(pageEntry);
    }

    return {
        defaults: mergePreset(DEFAULT_PRESET),
        presets: presets,
        capabilities: capabilities,
        experienceProfiles: EXPERIENCE_PROFILES,
        filterExperienceProfiles: FILTER_EXPERIENCE_PROFILES,
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
        '    var _capabilities = ' + JSON.stringify(runtimePresets.capabilities, null, 4).replace(/\n/g, '\n    ') + ';',
        '    var _experienceProfiles = ' + JSON.stringify(runtimePresets.experienceProfiles, null, 4).replace(/\n/g, '\n    ') + ';',
        '    var _filterExperienceProfiles = ' + JSON.stringify(runtimePresets.filterExperienceProfiles, null, 4).replace(/\n/g, '\n    ') + ';',
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
        '            presets: copy(_presets),',
        '            capabilities: copy(_capabilities),',
        '            experienceProfiles: copy(_experienceProfiles),',
        '            filterExperienceProfiles: copy(_filterExperienceProfiles)',
        '        };',
        '    }',
        '',
        '    function resolveCapability(pageId, filterId) {',
        '        var pageCapabilities = _capabilities[pageId] || null;',
        '        var capability = pageCapabilities ? (pageCapabilities[filterId] || pageCapabilities["*"]) : null;',
        '        return capability ? copy(capability) : { sourceRatio: 1, worstAsset: "" };',
        '    }',
        '',
        '    function resolveExperience(pageId, filterId) {',
        '        var pageProfiles = _filterExperienceProfiles[pageId] || {};',
        '        var profileId = pageProfiles[filterId] || "focus";',
        '        return { id: profileId, target: copy(_experienceProfiles[profileId] || _experienceProfiles.focus) };',
        '    }',
        '',
        '    return {',
        '        resolve: resolve,',
        '        resolveCapability: resolveCapability,',
        '        resolveExperience: resolveExperience,',
        '        getManifest: getManifest',
        '    };',
        '})();',
        ''
    ].join('\n');
}

function collectPixelWarnings(report) {
    // 告警 DPR=1 下的 composite 视觉放大 = stageScale * fitScale / sourceRatio；
    // 设备 DPR 由运行时 MapScalePolicy 计入，不在离线 stage preset 中固化。
    // (PNG 实际被绘制到屏幕时相对自身像素的放大倍数; >1 有失真可能, > CAP 明显 pixelated)
    const warnings = [];
    const pages = (report && report.pages) ? report.pages : [];
    for (let i = 0; i < pages.length; i += 1) {
        const page = pages[i];
        const filters = page.filters || [];
        for (let j = 0; j < filters.length; j += 1) {
            const filter = filters[j];
            const stageMetrics = filter.tunedStageMetrics || [];
            const sourceRatio = Number(filter.sourceRatio) > 0 ? Number(filter.sourceRatio) : DEFAULT_SOURCE_RATIO;
            for (let k = 0; k < stageMetrics.length; k += 1) {
                const entry = stageMetrics[k];
                const m = entry.metrics;
                if (!m) continue;
                const runtimeFitCap = Math.max(1, (COMPOSITE_VISUAL_SCALE_CAP * sourceRatio) / m.stageScale);
                const effectiveFitScale = Math.min(m.fitScale, runtimeFitCap);
                const total = m.stageScale * effectiveFitScale;
                const visualScale = total / sourceRatio;
                if (visualScale > COMPOSITE_VISUAL_SCALE_CAP) {
                    warnings.push({
                        pageId: page.pageId,
                        filterId: filter.filterId,
                        stageId: entry.stageId,
                        stageScale: m.stageScale,
                        fitScale: effectiveFitScale,
                        requestedFitScale: m.fitScale,
                        totalScale: round(total),
                        sourceRatio: round(sourceRatio),
                        visualScale: round(visualScale),
                        worstAsset: filter.worstAsset
                    });
                }
            }
        }
    }
    return warnings;
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

    const pixelWarnings = collectPixelWarnings(result.report);
    if (pixelWarnings.length) {
        console.log('');
        console.log('[warn] composite 视觉放大 > ' + COMPOSITE_VISUAL_SCALE_CAP + 'x (源图相对自身像素被拉伸, 可能 pixelated):');
        for (let i = 0; i < pixelWarnings.length; i += 1) {
            const w = pixelWarnings[i];
            const asset = w.worstAsset ? ' [' + w.worstAsset.assetUrl + ' ratio=' + w.worstAsset.ratio + ']' : '';
            console.log('  ' + w.pageId + ':' + w.filterId + '@' + w.stageId +
                ' stage=' + w.stageScale + ' fit=' + w.fitScale +
                ' total=' + w.totalScale + 'x / sourceRatio=' + w.sourceRatio +
                ' -> visual=' + w.visualScale + 'x' + asset);
        }
    }
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const { mapData, avatarSource } = loadMapBundle();
    const result = buildTuningReport(mapData, avatarSource);
    printSummary(result, args.json);

    if (args.write) {
        fs.writeFileSync(args.out, buildRuntimeFile(result), 'utf8');
        console.log('wrote ' + path.relative(projectRoot, args.out));
    }
}

if (require.main === module) {
    main();
}

module.exports = {
    buildTuningReport,
    buildRuntimeFile,
    loadMapBundle,
    computeStageMetrics,
    mergePreset,
    resolveExperienceProfile,
    scoreExperience,
    constants: {
        DEFAULT_PRESET,
        STAGE_PRESETS,
        STAGE_MAX_SCALE,
        COMPOSITE_VISUAL_SCALE_CAP,
        FILTER_MAX_SCALE_CANDIDATES,
        EXPERIENCE_PROFILES,
        FILTER_EXPERIENCE_PROFILES
    }
};
