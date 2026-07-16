#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const tuner = require('./tune-map-filter-fit.js');

const DPR_VALUES = [1, 1.5, 2];
const LOW_EFFECTS_VALUES = [false, true];
const EPSILON = 0.015;
// 与 MapCanvasStageRenderer 对齐：可见 bg canvas + backdrop 离屏缓存各占一张全 DPR 静态画布。
const STATIC_SURFACE_COUNT = 2;
const PIXEL_BUDGET = 10000000;
const PIXEL_BUDGET_LOW = 6000000;
// These filters are limited by the only two composites without a frozen Flash
// export source. A newly introduced debt must fail the build instead of being
// silently accepted as another low-resolution exception.
const KNOWN_SOURCE_DEBTS = new Set([
    'defense:all',
    'defense:first_line',
    'faction:fallen'
]);

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function round(value) {
    return Math.round(Number(value) * 1000) / 1000;
}

function resolvePreset(result, pageId, filterId) {
    const pagePresets = result.presets[pageId] || {};
    return tuner.mergePreset(
        tuner.mergePreset(result.defaults, pagePresets['*']),
        pagePresets[filterId]
    );
}

function evaluateRuntime(page, filter, preset, stagePreset, dpr, lowEffects) {
    const visualCap = tuner.constants.COMPOSITE_VISUAL_SCALE_CAP;
    const productCap = tuner.constants.STAGE_MAX_SCALE;
    const pixelBudget = lowEffects ? PIXEL_BUDGET_LOW : PIXEL_BUDGET;
    const viewportScale = Math.min(stagePreset.width / page.width, stagePreset.height / page.height);
    const assetSafeScale = (visualCap * filter.sourceRatio) / dpr;
    const canvasSafeScale = Math.sqrt(pixelBudget /
        (page.width * page.height * dpr * dpr * STATIC_SURFACE_COUNT));
    const stageScale = Math.min(viewportScale, productCap, assetSafeScale, canvasSafeScale);
    const stageWidth = Math.round(page.width * stageScale);
    const stageHeight = Math.round(page.height * stageScale);
    const scaledW = filter.bounds.w * stageScale;
    const scaledH = filter.bounds.h * stageScale;
    const padX = clamp(stageWidth * preset.padXRate, preset.padXMin, preset.padXMax);
    const padY = clamp(stageHeight * preset.padYRate, preset.padYMin, preset.padYMax);
    const widthLimit = (stageWidth - (padX * 2)) / Math.max(1, scaledW);
    const heightLimit = (stageHeight - (padY * 2)) / Math.max(1, scaledH);
    const clarityFitCap = Math.max(1, (visualCap * filter.sourceRatio) / (stageScale * dpr));
    const effectiveFitCap = Math.min(preset.maxScale, clarityFitCap);
    const fitScale = Math.max(1, Math.min(widthLimit, heightLimit, effectiveFitCap));
    const coverageX = (scaledW * fitScale) / stageWidth;
    const coverageY = (scaledH * fitScale) / stageHeight;
    const physicalScale = (stageScale * fitScale * dpr) / filter.sourceRatio;
    let limiter = 'preset';
    if (clarityFitCap < preset.maxScale - 0.0001) limiter = 'asset';
    if (canvasSafeScale <= stageScale + 0.0001 && canvasSafeScale < viewportScale) limiter = 'canvas';
    if (widthLimit <= Math.min(heightLimit, effectiveFitCap) + 0.0001) limiter = 'width';
    else if (heightLimit <= Math.min(widthLimit, effectiveFitCap) + 0.0001) limiter = 'height';

    return {
        coverageX,
        coverageY,
        physicalScale,
        stageScale,
        fitScale,
        limiter
    };
}

function outsideTarget(value, min, max) {
    return value < min - EPSILON || value > max + EPSILON;
}

function main() {
    const bundle = tuner.loadMapBundle();
    const result = tuner.buildTuningReport(bundle.mapData, bundle.avatarSource);
    const errors = [];
    const debts = {};
    let cases = 0;
    let filters = 0;
    const generatedPath = path.resolve(__dirname, '..', 'launcher', 'web', 'modules', 'map-fit-presets.js');
    const expectedGenerated = tuner.buildRuntimeFile(result);
    const actualGenerated = fs.readFileSync(generatedPath, 'utf8');
    if (actualGenerated !== expectedGenerated) {
        errors.push('generated map-fit-presets.js is stale; run node tools/tune-map-filter-fit.js --write');
    }

    for (const pageReport of result.report.pages) {
        const page = bundle.mapData.getPage(pageReport.pageId);
        for (const filter of pageReport.filters) {
            filters += 1;
            const preset = resolvePreset(result, pageReport.pageId, filter.filterId);
            const experience = tuner.resolveExperienceProfile(pageReport.pageId, filter.filterId);
            for (const stagePreset of tuner.constants.STAGE_PRESETS) {
                for (const dpr of DPR_VALUES) {
                    for (const lowEffects of LOW_EFFECTS_VALUES) {
                        cases += 1;
                        const metrics = evaluateRuntime(page, filter, preset, stagePreset, dpr, lowEffects);
                        const id = pageReport.pageId + ':' + filter.filterId + '@' + stagePreset.id +
                            '/dpr' + dpr + (lowEffects ? '/low' : '/normal');
                        if (metrics.physicalScale > tuner.constants.COMPOSITE_VISUAL_SCALE_CAP + 0.002) {
                            errors.push(id + ' physicalScale=' + round(metrics.physicalScale) + ' exceeds clarity cap');
                        }
                        const targetMiss =
                            outsideTarget(metrics.coverageX, experience.target.minX, experience.target.maxX) ||
                            outsideTarget(metrics.coverageY, experience.target.minY, experience.target.maxY);
                        if (!targetMiss) continue;
                        const detail = id + ' profile=' + experience.id +
                            ' coverage=' + round(metrics.coverageX) + '/' + round(metrics.coverageY) +
                            ' target=' + experience.target.minX + '-' + experience.target.maxX + '/' +
                            experience.target.minY + '-' + experience.target.maxY +
                            ' limiter=' + metrics.limiter;
                        if (metrics.limiter === 'asset' || metrics.limiter === 'canvas') {
                            const debtKey = pageReport.pageId + ':' + filter.filterId;
                            const miss =
                                Math.max(0, experience.target.minX - metrics.coverageX) +
                                Math.max(0, metrics.coverageX - experience.target.maxX) +
                                Math.max(0, experience.target.minY - metrics.coverageY) +
                                Math.max(0, metrics.coverageY - experience.target.maxY);
                            if (!debts[debtKey] || miss > debts[debtKey].miss) {
                                debts[debtKey] = { miss, detail };
                            }
                        }
                        else errors.push(detail);
                    }
                }
            }
        }
    }

    const debtKeys = Object.keys(debts).sort();
    for (const debtKey of debtKeys) {
        if (!KNOWN_SOURCE_DEBTS.has(debtKey)) {
            errors.push(debtKey + ' is an unexpected capability debt');
        }
    }
    console.log('[map-scale] filters=' + filters + ' cases=' + cases +
        ' errors=' + errors.length + ' capabilityDebts=' + debtKeys.length);
    for (const debtKey of debtKeys) console.log('[map-scale][debt] ' + debts[debtKey].detail);
    for (const error of errors) console.error('[map-scale][error] ' + error);
    if (filters !== 18) {
        console.error('[map-scale][error] expected 18 page/filter contracts, got ' + filters);
        process.exitCode = 1;
    } else if (errors.length) {
        process.exitCode = 1;
    }
}

main();
