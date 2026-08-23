#!/usr/bin/env node
'use strict';

const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const { loadCatalog, validateCatalog } = require('./fontctl/lib/catalog');
const { resolveRole } = require('./fontctl/lib/resolver');

const projectRoot = path.resolve(__dirname, '..');
const playwrightModule = path.join(projectRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const browserPath = path.join(
    process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
    'Microsoft', 'Edge', 'Application', 'msedge.exe',
);
const catalogFile = path.join(projectRoot, 'fonts', 'fonts.xml');
const generatedCss = path.join(projectRoot, 'launcher', 'web', 'generated', 'font-catalog.css');
const generatedJs = path.join(projectRoot, 'launcher', 'web', 'generated', 'font-catalog.js');
const permanentJetBrains = path.join(
    projectRoot, 'fonts', 'permanent', 'runtime', 'jetbrains-mono.woff2',
);
const permanentSourceHan = path.join(
    projectRoot, 'fonts', 'permanent', 'runtime', 'source-han-serif-cn-regular.otf',
);
const sourceFiles = {
    'jetbrains-mono.woff2': permanentJetBrains,
    'source-han-serif-cn-regular.otf': permanentSourceHan,
};
const sourceDirectories = {
    'temporary/custom': ['temporary', 'custom'],
    'temporary/cache': ['temporary', 'cache'],
    'permanent/runtime': ['permanent', 'runtime'],
};

function isWithin(parent, candidate) {
    const relative = path.relative(parent, candidate);
    return relative === '' || (!relative.startsWith(`..${path.sep}`)
        && relative !== '..' && !path.isAbsolute(relative));
}

function copyTo(root, source, file) {
    const destination = path.join(root, ...sourceDirectories[source], file);
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.copyFileSync(sourceFiles[file], destination);
}

function seedScenario(root, scenario) {
    if (scenario === 'custom-woff2-rejected') {
        copyTo(root, 'temporary/custom', 'jetbrains-mono.woff2');
        copyTo(root, 'temporary/cache', 'jetbrains-mono.woff2');
        copyTo(root, 'permanent/runtime', 'jetbrains-mono.woff2');
    } else if (scenario === 'custom-otf-deferred') {
        copyTo(root, 'temporary/custom', 'source-han-serif-cn-regular.otf');
        copyTo(root, 'permanent/runtime', 'source-han-serif-cn-regular.otf');
    } else if (scenario === 'cache') {
        copyTo(root, 'temporary/cache', 'jetbrains-mono.woff2');
        copyTo(root, 'permanent/runtime', 'jetbrains-mono.woff2');
    } else if (scenario === 'permanent') {
        copyTo(root, 'permanent/runtime', 'jetbrains-mono.woff2');
    } else if (scenario === 'corrupt-cache') {
        const corrupt = path.join(root, 'temporary', 'cache', 'jetbrains-mono.woff2');
        fs.mkdirSync(path.dirname(corrupt), { recursive: true });
        fs.writeFileSync(corrupt, Buffer.from('not-a-font'));
        copyTo(root, 'permanent/runtime', 'jetbrains-mono.woff2');
    }
}

function selectedPath(fontRoot, selected) {
    const parts = selected && sourceDirectories[selected.source];
    return parts ? path.join(fontRoot, ...parts, selected.relative) : null;
}

async function runCase(browser, catalog, maps, workRoot, item) {
    const fontRoot = path.join(workRoot, item.id);
    fs.mkdirSync(fontRoot, { recursive: true });
    seedScenario(fontRoot, item.scenario);
    const roleId = item.scenario === 'custom-otf-deferred'
        ? 'web.intelligence.archive'
        : 'web.overlay.mono';
    const expectedFile = item.scenario === 'custom-otf-deferred'
        ? 'source-han-serif-cn-regular.otf'
        : 'jetbrains-mono.woff2';
    const expectedFaceAlias = item.scenario === 'custom-otf-deferred'
        ? 'CF7Face--source-han-serif-cn-regular-400'
        : 'CF7Face--jetbrains-mono-400';
    const resolution = resolveRole(catalog, maps, fontRoot, roleId);
    const assetPath = selectedPath(fontRoot, resolution.selected);
    const context = await browser.newContext({
        viewport: item.viewport,
        deviceScaleFactor: item.scale,
    });
    const page = await context.newPage();
    const requests = [];
    const pageErrors = [];
    page.on('pageerror', (error) => pageErrors.push(error && error.message ? error.message : String(error)));
    await page.route('https://cfn-fonts.local/**', async (route) => {
        const file = decodeURIComponent(new URL(route.request().url()).pathname.slice(1));
        if (file === expectedFile && assetPath && fs.existsSync(assetPath)) {
            const body = fs.readFileSync(assetPath);
            const entityTag = `"sha256-${crypto.createHash('sha256').update(body).digest('hex')}"`;
            requests.push({ file, source: resolution.selected.source, status: 200 });
            await route.fulfill({
                status: 200,
                body,
                headers: {
                    'Access-Control-Allow-Origin': '*',
                    'Cache-Control': 'private, max-age=0, must-revalidate',
                    'Content-Type': expectedFile.endsWith('.woff2') ? 'font/woff2' : 'font/otf',
                    'Cross-Origin-Resource-Policy': 'cross-origin',
                    ETag: entityTag,
                },
            });
        } else {
            requests.push({ file, source: null, status: 404 });
            await route.fulfill({ status: 404, body: '' });
        }
    });
    await page.setContent('<!doctype html><meta charset="utf-8"><div id="sample">Gate D 字体验证 龘鬱𠮷 0123456789</div><canvas id="canvas" width="800" height="80"></canvas><div id="preset"></div>');
    await page.addStyleTag({ path: generatedCss });
    await page.addScriptTag({ path: generatedJs });
    const observed = await page.evaluate(async ({ roleId, expectedFaceAlias }) => {
        const api = window.CF7FontCatalog;
        const sample = document.getElementById('sample');
        sample.style.fontFamily = 'var(' + api.cssVariable(roleId) + ')';
        sample.style.fontSize = '16px';
        await api.loadRole(roleId, { size: 16, text: 'CF7 Gate D 0123456789' });
        await document.fonts.ready;
        const face = Array.from(document.fonts).find((item) => item.family.indexOf(expectedFaceAlias) >= 0);
        const canvas = document.getElementById('canvas');
        const context = canvas.getContext('2d');
        context.font = api.canvasFont(roleId, 16, { weight: 400 });
        const latinWidth = context.measureText('CF7 Gate D 0123456789').width;
        const rareWidth = context.measureText('龘鬱𠮷').width;
        const preset = document.getElementById('preset');
        api.applyRoleContext(preset, { presets: ['intelligence.dramatic', 'intelligence.casual-title'] });
        return {
            devicePixelRatio: window.devicePixelRatio,
            roleStack: api.role(roleId),
            computedFamily: getComputedStyle(sample).fontFamily,
            fontStatus: face ? face.status : 'missing',
            latinWidth,
            rareWidth,
            canvasFont: context.font,
            legacyMsMincho: api.legacyFamily('MS Mincho'),
            orderedPreset: preset.style.getPropertyValue(api.cssVariable('web.intelligence.title')),
        };
    }, { roleId, expectedFaceAlias });
    await context.close();

    const expectedSource = {
        'custom-woff2-rejected': 'temporary/cache',
        'custom-otf-deferred': 'permanent/runtime',
        cache: 'temporary/cache',
        permanent: 'permanent/runtime',
        'corrupt-cache': 'permanent/runtime',
        offline: 'system-fallback',
    }[item.scenario];
    const actualSource = resolution.selected ? resolution.selected.source : null;
    const online = item.scenario !== 'offline';
    const checks = {
        sourcePriority: actualSource === expectedSource,
        fontOutcome: online ? observed.fontStatus === 'loaded' : observed.fontStatus !== 'loaded',
        semanticCss: observed.computedFamily.includes(expectedFaceAlias),
        canvasSemantic: observed.canvasFont.includes(expectedFaceAlias),
        canvasMetrics: Number.isFinite(observed.latinWidth) && observed.latinWidth > 0
            && Number.isFinite(observed.rareWidth) && observed.rareWidth > 0,
        dpi: Math.abs(observed.devicePixelRatio - item.scale) < 0.001,
        compatibilityMap: observed.legacyMsMincho === '"MS Mincho", serif',
        orderedPreset: observed.orderedPreset.indexOf('CF7Face--zhi-mang-xing-regular-400') >= 0,
        requestSource: online
            ? requests.some((request) => request.status === 200 && request.source === expectedSource)
            : requests.every((request) => request.status === 404),
        pageErrors: pageErrors.length === 0,
        corruptRejected: item.scenario !== 'corrupt-cache'
            || resolution.diagnostics.some((diagnostic) => diagnostic.code === 'FONT_INVALID'),
        customWoff2Rejected: item.scenario !== 'custom-woff2-rejected'
            || resolution.diagnostics.some((diagnostic) => diagnostic.code === 'CUSTOM_WOFF2_OVERRIDE_UNSUPPORTED'),
        customRuntimeProbeDeferred: item.scenario !== 'custom-otf-deferred'
            || resolution.diagnostics.some((diagnostic) => diagnostic.code === 'CUSTOM_RUNTIME_PROBE_REQUIRED'),
        nodeSelectionAuthority: item.scenario === 'custom-otf-deferred'
            ? resolution.runtimeProbePending === true
                && resolution.selectionAuthority === 'provisional-node-fallback'
                && resolution.selected && resolution.selected.provisional === true
                && resolution.selected.authoritative === false
            : item.scenario === 'offline'
                ? resolution.runtimeProbePending === false
                    && resolution.systemAvailabilityPending === true
                    && resolution.selectionAuthority === 'provisional-system-availability'
                    && resolution.selected && resolution.selected.authoritative === false
            : resolution.runtimeProbePending === false
                && (!resolution.selected || resolution.selected.authoritative === true),
    };
    return {
        ...item,
        viewport: `${item.viewport.width}x${item.viewport.height}`,
        selectedSource: actualSource,
        selectionAuthority: resolution.selectionAuthority,
        runtimeProbePending: resolution.runtimeProbePending,
        systemAvailabilityPending: resolution.systemAvailabilityPending,
        diagnosticCodes: resolution.diagnostics.map((diagnostic) => diagnostic.code),
        requests,
        observed,
        checks,
        passed: Object.values(checks).every(Boolean),
    };
}

async function main() {
    if (!fs.existsSync(playwrightModule)) throw new Error('Playwright is missing under launcher/perf/node_modules.');
    if (!fs.existsSync(browserPath)) throw new Error('Microsoft Edge executable is missing: ' + browserPath);
    const { chromium } = require(playwrightModule);
    const catalog = loadCatalog(catalogFile);
    const validated = validateCatalog(catalog);
    const errors = validated.diagnostics.filter((item) => item.severity === 'error');
    if (errors.length) throw new Error('fonts.xml is invalid: ' + errors.map((item) => item.code).join(', '));

    const viewports = [
        { width: 1024, height: 576 },
        { width: 1600, height: 900 },
        { width: 1920, height: 1080 },
    ];
    const scales = [1, 1.25, 1.5, 1.75];
    const matrix = [];
    for (const viewport of viewports) {
        for (const scale of scales) {
            matrix.push({ id: `permanent-${viewport.width}x${viewport.height}-${scale}`, scenario: 'permanent', viewport, scale });
        }
    }
    for (const scenario of ['custom-woff2-rejected', 'custom-otf-deferred', 'cache', 'corrupt-cache', 'offline']) {
        matrix.push({ id: `${scenario}-1024x576-1`, scenario, viewport: viewports[0], scale: 1 });
    }

    const workRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-font-browser-'));
    const legacyAppDataFontRoot = process.env.LOCALAPPDATA
        ? path.resolve(process.env.LOCALAPPDATA, 'CF7FlashNight', 'fonts')
        : null;
    if (legacyAppDataFontRoot && isWithin(legacyAppDataFontRoot, workRoot)) {
        throw new Error('Browser fixture must not use the retired AppData font root: ' + workRoot);
    }
    const browser = await chromium.launch({ executablePath: browserPath, headless: true });
    const results = [];
    try {
        for (const item of matrix) results.push(await runCase(browser, catalog, validated.maps, workRoot, item));
    } finally {
        await browser.close();
        fs.rmSync(workRoot, { recursive: true, force: true });
    }
    const failed = results.filter((item) => !item.passed);
    const payload = {
        schemaVersion: 1,
        gate: 'E',
        evidenceTier: 'browser-fixture-non-authoritative',
        fontRootModel: 'isolated-project-root-contract',
        candidateOrder: 'face-major',
        legacyAppDataFontRootRead: false,
        browser: browserPath,
        cases: results.length,
        passed: results.length - failed.length,
        failed: failed.length,
        viewports: viewports.map((item) => `${item.width}x${item.height}`),
        scales,
        scenarios: [...new Set(results.map((item) => item.scenario))],
        results,
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
    if (failed.length) process.exitCode = 1;
}

main().catch((error) => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
