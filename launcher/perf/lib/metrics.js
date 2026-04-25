// 度量收集：CDP Performance.getMetrics 差量 + 页面内 rAF 帧间隔统计 + LayerTree 层数 + 截图。
// 度量窗口：默认 5 秒，分两阶段（warmup + sample）以排除启动期抖动。

'use strict';

async function attachInPageProbe(page) {
    await page.addInitScript(() => {
        if (window.__cf7Perf) return;
        const probe = {
            frames: [],
            longTasks: 0,
            paints: [],
            running: false,
        };
        window.__cf7Perf = probe;

        let last = performance.now();
        function tick(now) {
            if (!probe.running) { last = now; requestAnimationFrame(tick); return; }
            probe.frames.push(now - last);
            last = now;
            requestAnimationFrame(tick);
        }
        requestAnimationFrame(tick);

        try {
            const obs = new PerformanceObserver((list) => {
                if (!probe.running) return;
                for (const e of list.getEntries()) {
                    if (e.entryType === 'longtask') probe.longTasks++;
                    else if (e.entryType === 'paint') probe.paints.push({ name: e.name, t: e.startTime });
                }
            });
            obs.observe({ entryTypes: ['longtask', 'paint'] });
        } catch (e) { /* 不支持就跳过 */ }

        window.__cf7PerfStart = function(label) {
            probe.frames.length = 0;
            probe.paints.length = 0;
            probe.longTasks = 0;
            probe.running = true;
            probe.label = label || '';
            probe.startedAt = performance.now();
        };
        window.__cf7PerfStop = function() {
            probe.running = false;
            probe.endedAt = performance.now();
            return {
                label: probe.label,
                durationMs: probe.endedAt - probe.startedAt,
                frames: probe.frames.slice(),
                longTasks: probe.longTasks,
                paints: probe.paints.slice(),
            };
        };
    });
}

function summarizeFrames(frames) {
    if (!frames || frames.length === 0) return { count: 0 };
    const sorted = frames.slice().sort((a, b) => a - b);
    const sum = sorted.reduce((a, b) => a + b, 0);
    const mean = sum / sorted.length;
    const p50 = sorted[Math.floor(sorted.length * 0.5)];
    const p95 = sorted[Math.floor(sorted.length * 0.95)];
    const p99 = sorted[Math.floor(sorted.length * 0.99)];
    const jank = sorted.filter(f => f > 16.67).length;
    const fps = 1000 / mean;
    return {
        count: sorted.length,
        meanMs: Number(mean.toFixed(3)),
        p50Ms: Number(p50.toFixed(3)),
        p95Ms: Number(p95.toFixed(3)),
        p99Ms: Number(p99.toFixed(3)),
        jankFrames: jank,
        jankRatio: Number((jank / sorted.length).toFixed(3)),
        fps: Number(fps.toFixed(1)),
    };
}

function diffMetrics(before, after) {
    const out = {};
    const map = (arr) => Object.fromEntries(arr.map(m => [m.name, m.value]));
    const a = map(before.metrics || before);
    const b = map(after.metrics || after);
    for (const k of Object.keys(b)) {
        if (typeof b[k] === 'number' && typeof a[k] === 'number') {
            out[k] = Number((b[k] - a[k]).toFixed(4));
        }
    }
    return out;
}

async function collectLayerStats(client) {
    try {
        await client.send('LayerTree.enable');
        const { layers } = await client.send('LayerTree.compositingReasons')
            .catch(() => ({ layers: null }));
        // compositingReasons 需要单个 layerId；我们从 layerTreeDidChange 收集更直接：
        // 简化：用 DOM.getDocument + DOM.queryAll 统计 promoted layer 估计太复杂。
        // 这里只暴露通过 Performance metric 的 LayoutCount/RecalcStyleCount 辅助判断。
        return { layerCount: null };
    } catch (e) {
        return { layerCount: null, error: String(e) };
    }
}

// 启动 CDP tracing。返回收集器，stop 时返回事件数组。
async function startTracing(client) {
    const events = [];
    const onData = (msg) => { for (const e of msg.value) events.push(e); };
    client.on('Tracing.dataCollected', onData);
    await client.send('Tracing.start', {
        categories: 'devtools.timeline,disabled-by-default-devtools.timeline.frame,blink.user_timing,gpu',
        options: 'sampling-frequency=10000',
        transferMode: 'ReportEvents',
    }).catch(() => {});
    return {
        stop: async () => {
            const done = new Promise(r => client.once('Tracing.tracingComplete', r));
            await client.send('Tracing.end').catch(() => {});
            await done;
            client.off('Tracing.dataCollected', onData);
            return events;
        },
    };
}

// 从 tracing 事件里提取关键合成指标。
function extractTracingMetrics(events, sampleStartUs, sampleEndUs) {
    let drawFrames = 0;
    let needsBeginFrame = 0;
    let composite = 0;
    let compositeTotalUs = 0;
    let paint = 0;
    let paintTotalUs = 0;
    let raster = 0;
    let rasterTotalUs = 0;
    for (const e of events) {
        if (typeof e.ts !== 'number') continue;
        if (sampleStartUs && e.ts < sampleStartUs) continue;
        if (sampleEndUs && e.ts > sampleEndUs) continue;
        const name = e.name;
        if (name === 'DrawFrame') drawFrames++;
        else if (name === 'NeedsBeginFrameChanged') needsBeginFrame++;
        else if (name === 'CompositeLayers' || name === 'Compositor::Display::DrawAndSwap') {
            composite++;
            if (typeof e.dur === 'number') compositeTotalUs += e.dur;
        } else if (name === 'Paint') {
            paint++;
            if (typeof e.dur === 'number') paintTotalUs += e.dur;
        } else if (name === 'RasterTask') {
            raster++;
            if (typeof e.dur === 'number') rasterTotalUs += e.dur;
        }
    }
    return {
        drawFrames,
        composite,
        compositeMs: Number((compositeTotalUs / 1000).toFixed(3)),
        paint,
        paintMs: Number((paintTotalUs / 1000).toFixed(3)),
        raster,
        rasterMs: Number((rasterTotalUs / 1000).toFixed(3)),
    };
}

async function runMeasurement(page, client, options = {}) {
    const warmupMs = options.warmupMs ?? 1000;
    const sampleMs = options.sampleMs ?? 5000;

    await page.evaluate(() => { /* warm idle */ });
    await new Promise(r => setTimeout(r, warmupMs));

    await client.send('Performance.enable').catch(() => {});
    const m0 = await client.send('Performance.getMetrics').catch(() => ({ metrics: [] }));

    const tracer = await startTracing(client);
    const sampleStart = Date.now();

    await page.evaluate((label) => window.__cf7PerfStart(label), options.label || 'sample');
    await new Promise(r => setTimeout(r, sampleMs));
    const inPage = await page.evaluate(() => window.__cf7PerfStop());

    const events = await tracer.stop();
    const m1 = await client.send('Performance.getMetrics').catch(() => ({ metrics: [] }));

    const cdpDelta = diffMetrics(m0, m1);
    const frameStats = summarizeFrames(inPage.frames);
    const trace = extractTracingMetrics(events);

    return {
        sampleMs: inPage.durationMs,
        frames: frameStats,
        longTasks: inPage.longTasks,
        paintEvents: inPage.paints.length,
        trace,
        // 组合：每"真实合成帧"的 CPU 工作量。比 rAF 间隔更可靠。
        perCompositeFrame: trace.composite > 0 ? {
            paintUs: Number((trace.paintMs * 1000 / trace.composite).toFixed(2)),
            rasterUs: Number((trace.rasterMs * 1000 / trace.composite).toFixed(2)),
            compositeUs: Number((trace.compositeMs * 1000 / trace.composite).toFixed(2)),
        } : null,
        cdp: {
            LayoutCount: cdpDelta.LayoutCount || 0,
            RecalcStyleCount: cdpDelta.RecalcStyleCount || 0,
            LayoutDuration: cdpDelta.LayoutDuration || 0,
            RecalcStyleDuration: cdpDelta.RecalcStyleDuration || 0,
            ScriptDuration: cdpDelta.ScriptDuration || 0,
            TaskDuration: cdpDelta.TaskDuration || 0,
            JSHeapUsedSize: cdpDelta.JSHeapUsedSize || 0,
        },
    };
}

module.exports = { attachInPageProbe, runMeasurement, summarizeFrames };
