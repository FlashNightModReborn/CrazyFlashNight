#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const { pathToFileURL } = require('url');

const projectRoot = path.resolve(__dirname, '..');
const perfRoot = path.join(projectRoot, 'launcher', 'perf');
const playwrightModule = path.join(perfRoot, 'node_modules', 'playwright');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-data.js');
const harnessPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select', 'dev', 'harness.html');

const CAPTURE_CSS = `
body {
    margin: 0 !important;
    overflow: hidden !important;
    background: #000 !important;
}
#harness-toolbar,
#harness-status,
#debug-log,
#qa-panel {
    display: none !important;
}
#viewport-shell {
    width: 1024px !important;
    height: 576px !important;
    margin: 0 !important;
    border: 0 !important;
    overflow: hidden !important;
    background: transparent !important;
}
#panel-container,
#panel-content {
    display: block !important;
    position: absolute !important;
    inset: 0 !important;
}
#panel-backdrop,
.stage-select-header,
.stage-select-side {
    display: none !important;
}
.stage-select-panel {
    position: absolute !important;
    left: 0 !important;
    top: 0 !important;
    width: 1024px !important;
    height: 576px !important;
    min-width: 0 !important;
    min-height: 0 !important;
    border: 0 !important;
    box-shadow: none !important;
    background: transparent !important;
    animation: none !important;
}
.stage-select-body {
    display: block !important;
    height: 576px !important;
    padding: 0 !important;
}
.stage-select-stage-shell {
    width: 1024px !important;
    height: 576px !important;
    border: 0 !important;
    background: transparent !important;
}
#stage-select-stage {
    left: 0 !important;
    top: 0 !important;
    width: 1024px !important;
    height: 576px !important;
    transform: none !important;
    transform-origin: 0 0 !important;
}
* {
    transition-duration: 0s !important;
    animation-duration: 0s !important;
    animation-delay: 0s !important;
}
`;

function parseArgs(argv) {
    const args = {
        browser: 'edge',
        outDir: path.join('tmp', 'stage-select-visual-audit', 'web'),
        frames: [],
        fixture: 'allUnlocked',
        hoverStage: '',
        headed: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--browser') {
            args.browser = argv[i + 1] || 'edge';
            i += 1;
        } else if (arg === '--out-dir') {
            args.outDir = argv[i + 1] || args.outDir;
            i += 1;
        } else if (arg === '--frame') {
            args.frames.push(argv[i + 1] || '');
            i += 1;
        } else if (arg === '--fixture') {
            args.fixture = argv[i + 1] || 'allUnlocked';
            i += 1;
        } else if (arg === '--hover-stage') {
            args.hoverStage = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--headed') {
            args.headed = true;
        } else if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        } else {
            printHelp(1, 'unknown arg: ' + arg);
            return null;
        }
    }
    args.frames = args.frames.filter(Boolean);
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/capture-stage-select-web-frames.js [--browser edge|chrome] [--out-dir tmp/stage-select-visual-audit/web] [--frame <label>] [--fixture allUnlocked|mixed|challenge] [--hover-stage <stageName>] [--headed]');
    process.exit(exitCode);
}

function loadManifest() {
    const source = fs.readFileSync(dataFile, 'utf8');
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(source, sandbox, { filename: dataFile });
    if (!sandbox.StageSelectData) {
        throw new Error('StageSelectData not found in ' + dataFile);
    }
    return sandbox.StageSelectData.exportManifest();
}

function findBrowser(name) {
    const candidates = name === 'chrome' ? [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ] : [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    for (let i = 0; i < candidates.length; i += 1) {
        if (candidates[i] && fs.existsSync(candidates[i])) return candidates[i];
    }
    throw new Error('Cannot find ' + name + ' executable.');
}

function safeName(label, index) {
    const normalized = String(label || 'frame').replace(/[<>:"/\\|?*\u0000-\u001f]/g, '_').replace(/\s+/g, '_');
    return String(index).padStart(3, '0') + '-' + normalized;
}

function resolveFrames(manifest, requested) {
    const frames = manifest.frames || [];
    if (!requested.length) return frames;
    const byLabel = {};
    frames.forEach(frame => { byLabel[frame.frameLabel] = frame; });
    return requested.map(label => {
        if (!byLabel[label]) throw new Error('Unknown frame label: ' + label);
        return byLabel[label];
    });
}

async function waitForImages(page) {
    await page.waitForFunction(() => Array.from(document.images).every(img => !img.currentSrc || (img.complete && img.naturalWidth > 0)), null, { timeout: 20000 });
}

async function captureFrame(page, frame, args, outDir) {
    const url = new URL(pathToFileURL(harnessPath).toString());
    url.searchParams.set('viewport', '1024x576');
    url.searchParams.set('fixture', args.fixture);
    url.searchParams.set('frame', frame.frameLabel);
    await page.goto(url.toString(), { waitUntil: 'load' });
    await page.waitForFunction(label => {
        if (!window.StageSelectPanel || !window.StageSelectPanel._debugGetState) return false;
        const state = window.StageSelectPanel._debugGetState();
        return state && state.isOpen && state.frameLabel === label;
    }, frame.frameLabel, { timeout: 20000 });
    await page.addStyleTag({ content: CAPTURE_CSS });
    await page.evaluate(async options => {
        window.StageSelectPanel._debugSetFixture(options.fixture);
        window.StageSelectPanel._debugSetFrame(options.label, 'visual-capture');
        await new Promise(resolve => requestAnimationFrame(resolve));
        await new Promise(resolve => requestAnimationFrame(resolve));
    }, { label: frame.frameLabel, fixture: args.fixture });
    await waitForImages(page);
    if (args.hoverStage) {
        const point = await page.evaluate(stageName => {
            const node = Array.from(document.querySelectorAll('.stage-select-stage-button')).find(item => item.getAttribute('data-stage-name') === stageName);
            if (!node) throw new Error('Hover stage not found: ' + stageName);
            const rect = node.getBoundingClientRect();
            return { x: rect.left + rect.width / 2, y: rect.top + Math.min(12, rect.height / 2) };
        }, args.hoverStage);
        await page.mouse.move(point.x, point.y);
        await page.evaluate(async () => {
            await new Promise(resolve => requestAnimationFrame(resolve));
            await new Promise(resolve => requestAnimationFrame(resolve));
        });
        await waitForImages(page);
    }

    const basename = safeName(frame.frameLabel + (args.hoverStage ? '-hover-' + args.hoverStage : ''), frame.sourceFrameIndex);
    const screenshotPath = path.join(outDir, basename + '.png');
    await page.locator('#stage-select-stage').screenshot({ path: screenshotPath, animations: 'disabled' });

    const metrics = await page.evaluate(() => {
        const stage = document.getElementById('stage-select-stage');
        const stageRect = stage.getBoundingClientRect();
        function relRect(el) {
            const rect = el.getBoundingClientRect();
            return {
                x: Math.round((rect.left - stageRect.left) * 100) / 100,
                y: Math.round((rect.top - stageRect.top) * 100) / 100,
                w: Math.round(rect.width * 100) / 100,
                h: Math.round(rect.height * 100) / 100
            };
        }
        return {
            stageRect: relRect(stage),
            backgroundRect: relRect(document.getElementById('stage-select-bg')),
            stageButtons: Array.from(document.querySelectorAll('.stage-select-stage-button')).map(node => ({
                id: node.getAttribute('data-stage-id') || '',
                stageName: node.getAttribute('data-stage-name') || '',
                rect: relRect(node),
                styleLeft: parseFloat(node.style.left || '0'),
                styleTop: parseFloat(node.style.top || '0')
            })),
            navButtons: Array.from(document.querySelectorAll('.stage-select-nav-button')).map(node => ({
                id: node.getAttribute('data-nav-id') || '',
                label: node.textContent || '',
                rect: relRect(node),
                styleLeft: parseFloat(node.style.left || '0'),
                styleTop: parseFloat(node.style.top || '0')
            })),
            hoverCard: (() => {
                const hovered = document.querySelector('.stage-select-stage-button:hover');
                const card = hovered && hovered.querySelector('.stage-select-card');
                if (!card) return null;
                return {
                    stageName: hovered.getAttribute('data-stage-name') || '',
                    rect: relRect(card),
                    previewSource: hovered.querySelector('.stage-select-preview') && hovered.querySelector('.stage-select-preview').getAttribute('data-preview-source') || ''
                };
            })()
        };
    });

    return {
        frameLabel: frame.frameLabel,
        sourceFrameIndex: frame.sourceFrameIndex,
        screenshot: path.relative(projectRoot, screenshotPath).replace(/\\/g, '/'),
        capture: metrics
    };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const manifest = loadManifest();
    const frames = resolveFrames(manifest, args.frames);
    const outDir = path.resolve(projectRoot, args.outDir);
    fs.mkdirSync(outDir, { recursive: true });

    const { chromium } = require(playwrightModule);
    const executablePath = findBrowser(args.browser);
    const browser = await chromium.launch({ executablePath, headless: !args.headed });
    const page = await browser.newPage({ viewport: { width: 1024, height: 576 }, deviceScaleFactor: 1 });
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
    page.on('requestfailed', request => {
        const failure = request.failure();
        failedRequests.push(request.url() + ' :: ' + (failure && failure.errorText || 'failed'));
    });

    const captures = [];
    try {
        for (let i = 0; i < frames.length; i += 1) {
            captures.push(await captureFrame(page, frames[i], args, outDir));
        }
    } finally {
        await browser.close();
    }

    const payload = {
        browser: args.browser,
        executablePath,
        fixture: args.fixture,
        frames: captures,
        failedRequests,
        pageErrors
    };
    const indexPath = path.join(outDir, 'web-capture-index.json');
    fs.writeFileSync(indexPath, JSON.stringify(payload, null, 2) + '\n', 'utf8');
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
    if (failedRequests.length || pageErrors.length) process.exit(1);
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
