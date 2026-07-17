var MapScalePolicy = (function() {
    'use strict';

    // 产品层只保留异常兜底；清晰度与性能上限由 sourceRatio / fit / DPR 动态裁决。
    var PRODUCT_STAGE_SCALE_MAX = 1.75;
    var COMPOSITE_VISUAL_SCALE_CAP = 1.75;
    // Renderer 常驻两张全 DPR 静态 backing store：可见 bg canvas + backdrop 离屏缓存。
    // 预算按两张画布的总像素计；沿用原来的 10M / 6M 总上限，避免缓存让真实占用翻倍。
    var STATIC_SURFACE_COUNT = 2;
    var STATIC_PIXEL_BUDGET = 10000000;
    var STATIC_PIXEL_BUDGET_LOW = 6000000;
    var STATIC_PIXEL_BUDGET_PER_SURFACE = STATIC_PIXEL_BUDGET / STATIC_SURFACE_COUNT;
    var STATIC_PIXEL_BUDGET_PER_SURFACE_LOW = STATIC_PIXEL_BUDGET_LOW / STATIC_SURFACE_COUNT;

    function finitePositive(value, fallback) {
        var n = Number(value);
        return isFinite(n) && n > 0 ? n : fallback;
    }

    function round(value) {
        return Math.round(Number(value || 0) * 1000) / 1000;
    }

    function resolve(input) {
        input = input || {};
        var pageWidth = finitePositive(input.pageWidth, 1031);
        var pageHeight = finitePositive(input.pageHeight, 608);
        var availableWidth = finitePositive(input.availableWidth, pageWidth);
        var availableHeight = finitePositive(input.availableHeight, pageHeight);
        var dpr = finitePositive(input.dpr, 1);
        var sourceRatio = finitePositive(input.sourceRatio, 1);
        var requestedFitMaxScale = finitePositive(input.fitMaxScale, 1);
        var productMax = finitePositive(input.productMaxScale, PRODUCT_STAGE_SCALE_MAX);
        var visualCap = finitePositive(input.visualScaleCap, COMPOSITE_VISUAL_SCALE_CAP);
        var pixelBudget = finitePositive(input.staticPixelBudget,
            input.lowEffects ? STATIC_PIXEL_BUDGET_LOW : STATIC_PIXEL_BUDGET);

        var widthScale = availableWidth / pageWidth;
        var heightScale = availableHeight / pageHeight;
        var viewportScale = Math.min(widthScale, heightScale);
        // sourceRatio 表示源位图像素 / 逻辑坐标；清晰度预算必须按物理像素计算，
        // 因此 stage × fit × DPR / sourceRatio 才是真实的位图放大倍数。
        // 优先让外层舞台占满空间，再把剩余清晰度预算分给 content-fit。
        var assetSafeScale = (visualCap * sourceRatio) / dpr;
        var pixelsPerStaticSurface = pageWidth * pageHeight * dpr * dpr;
        var canvasSafeScale = Math.sqrt(pixelBudget / (pixelsPerStaticSurface * STATIC_SURFACE_COUNT));
        var maxScale = Math.min(productMax, assetSafeScale, canvasSafeScale);
        var stageScale = Math.min(viewportScale, maxScale);
        if (!isFinite(stageScale) || stageScale <= 0) stageScale = 1;

        var limiter = 'viewport';
        if (maxScale < viewportScale) {
            if (maxScale === assetSafeScale) limiter = 'asset';
            else if (maxScale === canvasSafeScale) limiter = 'canvas';
            else limiter = 'product';
        }

        return {
            stageScale: stageScale,
            limiter: limiter,
            viewportScale: round(viewportScale),
            widthScale: round(widthScale),
            heightScale: round(heightScale),
            maxScale: round(maxScale),
            productMaxScale: round(productMax),
            assetSafeScale: round(assetSafeScale),
            canvasSafeScale: round(canvasSafeScale),
            sourceRatio: round(sourceRatio),
            requestedFitMaxScale: round(requestedFitMaxScale),
            contentFitMaxScale: round(Math.max(1, (visualCap * sourceRatio) / (stageScale * dpr))),
            visualScaleCap: round(visualCap),
            staticSurfaceCount: STATIC_SURFACE_COUNT,
            staticPixelBudget: Math.round(pixelBudget),
            staticPixelBudgetPerSurface: Math.round(pixelBudget / STATIC_SURFACE_COUNT),
            estimatedStaticPixelsPerSurface: Math.round(pixelsPerStaticSurface * stageScale * stageScale),
            estimatedStaticPixels: Math.round(pixelsPerStaticSurface * stageScale * stageScale * STATIC_SURFACE_COUNT),
            dpr: round(dpr)
        };
    }

    return {
        resolve: resolve,
        getDefaults: function() {
            return {
                productStageScaleMax: PRODUCT_STAGE_SCALE_MAX,
                compositeVisualScaleCap: COMPOSITE_VISUAL_SCALE_CAP,
                staticSurfaceCount: STATIC_SURFACE_COUNT,
                staticPixelBudget: STATIC_PIXEL_BUDGET,
                staticPixelBudgetLow: STATIC_PIXEL_BUDGET_LOW,
                staticPixelBudgetPerSurface: STATIC_PIXEL_BUDGET_PER_SURFACE,
                staticPixelBudgetPerSurfaceLow: STATIC_PIXEL_BUDGET_PER_SURFACE_LOW
            };
        }
    };
})();
