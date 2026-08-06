#!/usr/bin/env node
'use strict';

const childProcess = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const { startServer, stopServer } = require(path.join(ROOT, 'launcher', 'perf', 'lib', 'server'));
const DEFAULT_OUTPUT_ROOT = path.join(ROOT, 'tmp', 'crafting-product-review');
let OUTPUT_ROOT = DEFAULT_OUTPUT_ROOT;
let CANDIDATE_ROOT = path.join(OUTPUT_ROOT, 'candidates');
let ICON_256_ROOT = path.join(OUTPUT_ROOT, 'icons-256');
let ICON_WORK_ROOT = path.join(OUTPUT_ROOT, 'icon-work');
let ICON_REPORT = path.join(OUTPUT_ROOT, 'icon-bake-report.json');
let REVIEW_DATA = path.join(OUTPUT_ROOT, 'review-data.json');
let BUILD_REPORT = path.join(OUTPUT_ROOT, 'build-report.json');

const WEAPON_USES = new Set(['刀', '长枪', '手枪']);
const ARMOR_USES = new Set(['头部装备', '上装装备', '下装装备', '手部装备', '脚部装备', '颈部装备']);
const SPECIALIZATION_MIN_GAIN = 1.08;
const DEFAULT_INSPECTOR_ZOOM = 1.85;
const SAMPLE_PREFERRED = [
    'Kel-Tec-P50', 'NEGEV', '异形女王毒刺', 'A兵团精致战术背心', 'LEE战靴',
    '黄金骑士牙狼头盔', '黑铁游侠围巾', 'A兵团精致项链',
    '炎寒对剑', '血刀配鞘版', '烬灭裁决'
];

function parseArgs(argv) {
    const result = {
        sample: false,
        limit: 0,
        skipIconBake: false,
        browser: 'edge',
        outputRoot: '',
        cleanupOutputRoot: '',
        buildOptionSeen: false
    };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === '--sample') {
            result.sample = true;
            result.buildOptionSeen = true;
        } else if (arg === '--skip-icon-bake') {
            result.skipIconBake = true;
            result.buildOptionSeen = true;
        }
        else if (arg === '--limit') {
            result.limit = Number(argv[index + 1] || 0);
            result.buildOptionSeen = true;
            index += 1;
        } else if (arg === '--browser') {
            result.browser = argv[index + 1] || 'edge';
            result.buildOptionSeen = true;
            index += 1;
        } else if (arg === '--output-root') {
            result.outputRoot = argv[index + 1] || '';
            result.buildOptionSeen = true;
            index += 1;
        } else if (arg === '--cleanup-output-root') {
            if (result.cleanupOutputRoot) throw new Error('--cleanup-output-root may appear only once');
            result.cleanupOutputRoot = argv[index + 1] || '';
            index += 1;
        } else if (arg === '--help' || arg === '-h') {
            console.log('usage: node tools/build-crafting-product-review.js [--sample] [--limit N] [--skip-icon-bake] [--browser edge|chrome] [--output-root tmp/<unique-dir>]');
            console.log('       node tools/build-crafting-product-review.js --cleanup-output-root tmp/identity-triple-gate/crafting-product-review-<unique>');
            process.exit(0);
        } else {
            throw new Error('unknown argument: ' + arg);
        }
    }
    if (!Number.isFinite(result.limit) || result.limit < 0) throw new Error('--limit must be a non-negative integer');
    if (process.argv.includes('--output-root') && !result.outputRoot) throw new Error('--output-root requires a path');
    if (process.argv.includes('--cleanup-output-root') && !result.cleanupOutputRoot) {
        throw new Error('--cleanup-output-root requires a path');
    }
    if (result.cleanupOutputRoot && result.buildOptionSeen) {
        throw new Error('--cleanup-output-root is an isolated mode and cannot be combined with build options');
    }
    delete result.buildOptionSeen;
    return result;
}

function configureOutputRoot(requestedRoot) {
    const resolved = requestedRoot ? path.resolve(ROOT, requestedRoot) : DEFAULT_OUTPUT_ROOT;
    const tmpRoot = path.join(ROOT, 'tmp');
    const relative = path.relative(tmpRoot, resolved);
    if (!relative || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)) {
        throw new Error('--output-root must name a child directory under tmp/');
    }
    OUTPUT_ROOT = resolved;
    CANDIDATE_ROOT = path.join(OUTPUT_ROOT, 'candidates');
    ICON_256_ROOT = path.join(OUTPUT_ROOT, 'icons-256');
    ICON_WORK_ROOT = path.join(OUTPUT_ROOT, 'icon-work');
    ICON_REPORT = path.join(OUTPUT_ROOT, 'icon-bake-report.json');
    REVIEW_DATA = path.join(OUTPUT_ROOT, 'review-data.json');
    BUILD_REPORT = path.join(OUTPUT_ROOT, 'build-report.json');
}

function cleanupIsolatedOutputRoot(requestedRoot) {
    const resolved = path.resolve(ROOT, requestedRoot);
    const gateRoot = path.join(ROOT, 'tmp', 'identity-triple-gate');
    const relative = path.relative(gateRoot, resolved);
    if (!relative || relative.startsWith('..' + path.sep) || path.isAbsolute(relative)
            || !path.basename(resolved).startsWith('crafting-product-review-')) {
        throw new Error('--cleanup-output-root must name a unique Crafting review child under tmp/identity-triple-gate/');
    }
    if (!fs.existsSync(resolved)) {
        throw new Error('--cleanup-output-root target does not exist: ' + slash(path.relative(ROOT, resolved)));
    }
    const stat = fs.lstatSync(resolved);
    if (stat.isSymbolicLink() || !stat.isDirectory()) {
        throw new Error('--cleanup-output-root refuses symlinks and non-directories');
    }
    fs.rmSync(path.toNamespacedPath(resolved), {
        recursive: true,
        force: false,
        maxRetries: 3,
        retryDelay: 100
    });
    if (fs.existsSync(resolved)) throw new Error('--cleanup-output-root failed to remove the exact target');
    console.log('[product-review] removed isolated output: ' + slash(path.relative(ROOT, resolved)));
}

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function slash(value) {
    return String(value).replace(/\\/g, '/');
}

function repoUrl(filePath) {
    return '/' + slash(path.relative(ROOT, filePath));
}

function safeItemId(name) {
    return crypto.createHash('sha1').update(name, 'utf8').digest('hex').slice(0, 12);
}

function decodeXml(value) {
    return String(value || '')
        .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'").replace(/&amp;/g, '&');
}

function tagValue(block, tag) {
    const match = block.match(new RegExp('<' + tag + '(?:\\s[^>]*)?>([\\s\\S]*?)</' + tag + '>', 'i'));
    return match ? decodeXml(match[1].trim()) : '';
}

function loadItemMetadata() {
    const result = {};
    const itemRoot = path.join(ROOT, 'data', 'items');
    fs.readdirSync(itemRoot).filter(name => name.toLowerCase().endsWith('.xml')).forEach(fileName => {
        const content = fs.readFileSync(path.join(itemRoot, fileName), 'utf8');
        const blocks = content.match(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/gi) || [];
        blocks.forEach(block => {
            const name = tagValue(block, 'name');
            if (!name || result[name]) return;
            result[name] = {
                type: tagValue(block, 'type'),
                use: tagValue(block, 'use'),
                actionType: tagValue(block, 'actiontype'),
                displayName: tagValue(block, 'displayname'),
                iconName: tagValue(block, 'icon'),
                sourceFile: fileName
            };
        });
    });
    return result;
}

function loadRecipes() {
    const craftingRoot = path.join(ROOT, 'data', 'crafting');
    const files = fs.readdirSync(craftingRoot).filter(name => name.toLowerCase().endsWith('.json')).sort();
    const recipes = [];
    files.forEach(fileName => {
        const category = path.basename(fileName, '.json');
        readJson(path.join(craftingRoot, fileName)).forEach((recipe, recipeIndex) => {
            recipes.push({
                category,
                recipeIndex,
                name: String(recipe.name || ''),
                title: String(recipe.title || '')
            });
        });
    });
    return { files, recipes };
}

function uniqueItems(recipeData, dressupManifest, itemMetadata) {
    const byName = new Map();
    recipeData.recipes.forEach(recipe => {
        if (!recipe.name) return;
        if (!byName.has(recipe.name)) byName.set(recipe.name, []);
        byName.get(recipe.name).push(recipe);
    });
    return Array.from(byName.entries()).map(([name, recipeRefs]) => {
        const dressupItem = dressupManifest.items[name] || null;
        const metadata = itemMetadata[name] || {};
        const use = (dressupItem && dressupItem.use) || metadata.use || '';
        const iconName = (dressupItem && dressupItem.icon) || metadata.iconName || name;
        const kind = WEAPON_USES.has(use) ? 'weapon' : (ARMOR_USES.has(use) ? 'armor' : 'fallback');
        const kindLabel = kind === 'weapon' ? '武器商品图' : (kind === 'armor' ? '防具纸娃娃' : '图标回退');
        return {
            id: safeItemId(name),
            name,
            displayName: metadata.displayName || name,
            iconName,
            use,
            actionType: metadata.actionType || '',
            kind,
            kindLabel,
            categories: Array.from(new Set(recipeRefs.map(recipe => recipe.category))).sort(),
            recipeRefs,
            dressupItem
        };
    }).sort((left, right) => {
        const order = { weapon: 0, armor: 1, fallback: 2 };
        return order[left.kind] - order[right.kind] || left.use.localeCompare(right.use, 'zh-CN') || left.name.localeCompare(right.name, 'zh-CN');
    });
}

function sampleItems(items) {
    const chosen = [];
    const add = item => {
        if (item && !chosen.some(entry => entry.name === item.name)) chosen.push(item);
    };
    SAMPLE_PREFERRED.forEach(name => add(items.find(item => item.name === name)));
    ['刀', '头部装备', '上装装备', '下装装备', '手部装备', '脚部装备', '颈部装备'].forEach(use => add(items.find(item => item.use === use)));
    add(items.find(item => item.kind === 'fallback'));
    return chosen;
}

function hasDressupFields(item, gender) {
    const fields = item && item.dressupItem && item.dressupItem.fieldsByGender;
    return !!(fields && fields[gender] && Object.keys(fields[gender]).length);
}

function sourceDigest(recipeFiles) {
    const hash = crypto.createHash('sha256');
    const files = recipeFiles.map(name => path.join(ROOT, 'data', 'crafting', name)).concat([
        path.join(ROOT, 'launcher', 'web', 'icons', 'manifest.json'),
        path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'workbench-inspection-viewport.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'crafting-inspector.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'crafting-product-review', 'dev', 'render-harness.html'),
        __filename
    ]);
    fs.readdirSync(path.join(ROOT, 'data', 'items'))
        .filter(name => name.toLowerCase().endsWith('.xml'))
        .sort()
        .forEach(name => files.push(path.join(ROOT, 'data', 'items', name)));
    files.forEach(filePath => {
        hash.update(slash(path.relative(ROOT, filePath)));
        hash.update(fs.readFileSync(filePath));
    });
    return hash.digest('hex').slice(0, 20);
}

function findBrowser(name) {
    const edge = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : ''
    ];
    const chrome = [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ];
    const candidates = name === 'chrome' ? chrome : edge;
    const found = candidates.find(candidate => candidate && fs.existsSync(candidate));
    if (!found) throw new Error('cannot find browser executable: ' + name);
    return found;
}

function runIconBake(items) {
    fs.mkdirSync(ICON_256_ROOT, { recursive: true });
    fs.mkdirSync(ICON_WORK_ROOT, { recursive: true });
    const args = [
        path.join(ROOT, 'tools', 'bake-icons-offline.py'),
        '--scope', 'items',
        '--icon-size', '256',
        '--animated-icon-size', '256',
        '--output-dir', ICON_256_ROOT,
        '--tmp-dir', ICON_WORK_ROOT,
        '--report', ICON_REPORT
    ];
    const iconNames = Array.from(new Set(items.map(item => item.iconName || item.name)));
    iconNames.forEach(name => args.push('--name', name));
    console.log('[product-review] baking 256px icon candidates: ' + iconNames.length);
    const result = childProcess.spawnSync('python', args, {
        cwd: ROOT,
        stdio: 'inherit',
        windowsHide: true
    });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error('256px icon bake failed with exit code ' + result.status);
}

function warningsFor(candidate) {
    const warnings = [];
    const metrics = candidate.metrics || {};
    if (!metrics.alphaPixels) warnings.push('空白');
    if (metrics.touchesEdge && !candidate.allowContextClip) warnings.push('触边');
    if (metrics.bboxRatio !== undefined && metrics.bboxRatio < 0.08) warnings.push('占框过小');
    if (candidate.sourceMetrics && candidate.sourceMetrics.bbox) {
        const bbox = candidate.sourceMetrics.bbox;
        if (Math.max(bbox.width || 0, bbox.height || 0) < 64) warnings.push('有效源像素低');
    }
    if (candidate.render && candidate.render.failedImages) warnings.push('素材加载失败');
    if (candidate.render && candidate.render.missing) warnings.push('holder缺失×' + candidate.render.missing);
    if (candidate.error) warnings.push(candidate.error);
    return warnings;
}

function writeDataUrl(filePath, dataUrl) {
    const comma = String(dataUrl || '').indexOf(',');
    if (comma < 0) throw new Error('invalid image data URL for ' + filePath);
    const buffer = Buffer.from(dataUrl.slice(comma + 1), 'base64');
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, buffer);
    return crypto.createHash('sha1').update(buffer).digest('hex').slice(0, 12);
}

async function renderCandidate(page, options, outputFile) {
    const result = await page.evaluate(async renderOptions => {
        return window.CraftingProductRenderHarness.render(renderOptions);
    }, options);
    const digest = outputFile && result.dataUrl ? writeDataUrl(outputFile, result.dataUrl) : '';
    return { result, digest };
}

function candidateFromResult(id, label, uri, payload, extra) {
    const result = payload.result || {};
    const candidate = Object.assign({
        id,
        label,
        uri,
        metrics: result.metrics || {},
        render: result.render || null,
        state: result.state || null,
        pipeline: result.pipeline || null,
        fitMetrics: result.fitMetrics || null,
        animation: result.render && result.render.animated ? {
            sourceAnimated: true,
            previewMode: 'static-first-frame',
            contractPass: false
        } : null,
        contentDigest: payload.digest || '',
        error: result.error || ''
    }, extra || {});
    candidate.warnings = warningsFor(candidate);
    if (candidate.animation) {
        candidate.warnings.push('动画仅首帧');
        // 静态 PNG 只能审构图，不能代表动效已验收。保留候选作参考，
        // 但禁止其成为最终通过决定。
        candidate.reviewRole = 'nonqualifying';
    }
    return candidate;
}

function visualScale(metrics) {
    return Math.sqrt(Math.max(0, Number(metrics && metrics.alphaPixels) || 0));
}

function longestContentEdge(metrics) {
    const bbox = metrics && metrics.bbox || {};
    return Math.max(0, Number(bbox.width) || 0, Number(bbox.height) || 0);
}

function applySpecializationContracts(candidates) {
    const baseline = candidates.find(candidate => candidate.id === 'icon-current');
    candidates.filter(candidate => candidate.id === 'dressup-weapon' ||
        candidate.id.indexOf('dressup-armor-focus-') === 0).forEach(candidate => {
        const isInteractiveWeapon = candidate.id === 'dressup-weapon';
        const baselineScale = isInteractiveWeapon
            ? longestContentEdge(baseline && baseline.metrics) : visualScale(baseline && baseline.metrics);
        const rawCandidateScale = isInteractiveWeapon
            ? longestContentEdge(candidate.metrics) : visualScale(candidate.metrics);
        // 武器检视器默认以 185% 打开，全貌只是玩家可选的重置状态。
        // 因此武器的放大契约比较“默认特写的最长内容边”，避免用 alpha
        // 面积误惩罚细长刀身。防具仍用现有面积契约。
        const candidateScale = rawCandidateScale * (isInteractiveWeapon ? DEFAULT_INSPECTOR_ZOOM : 1);
        if (!baseline || baselineScale <= 0) {
            candidate.specialization = {
                baselineId: '',
                metric: isInteractiveWeapon ? 'max-bbox-at-default-zoom' : 'sqrt-alpha-pixels',
                gain: null,
                largerThanBaseline: null,
                contractPass: null,
                minGain: SPECIALIZATION_MIN_GAIN,
                displayZoom: isInteractiveWeapon ? DEFAULT_INSPECTOR_ZOOM : 1
            };
            return;
        }
        const gain = candidateScale / baselineScale;
        const larger = gain > 1;
        const passes = gain >= SPECIALIZATION_MIN_GAIN;
        candidate.specialization = {
            baselineId: baseline.id,
            metric: isInteractiveWeapon ? 'max-bbox-at-default-zoom' : 'sqrt-alpha-pixels',
            gain: Math.round(gain * 1000) / 1000,
            largerThanBaseline: larger,
            contractPass: passes,
            minGain: SPECIALIZATION_MIN_GAIN,
            displayZoom: isInteractiveWeapon ? DEFAULT_INSPECTOR_ZOOM : 1
        };
        if (!larger) candidate.warnings.push('未大于原图标');
        else if (!passes) candidate.warnings.push('特写增益不足');
        if (!passes) candidate.reviewRole = 'nonqualifying';
    });
}

async function buildItemCandidates(page, serverUrl, item, iconManifest, icon256Manifest) {
    const candidates = [];
    const itemDir = path.join(CANDIDATE_ROOT, item.id);
    const icon = iconManifest[item.iconName] || null;
    const icon256 = icon256Manifest[item.iconName] || null;
    const absolute = uri => new URL(uri.replace(/^\//, ''), serverUrl).href;

    if (icon && icon.f1) {
        const uri = '/launcher/web/icons/' + icon.f1;
        const payload = await renderCandidate(page, { mode: 'icon', uri: absolute(uri), fitAlpha: false, returnImage: false });
        candidates.push(candidateFromResult('icon-current', '当前 128 图标', uri, payload, {
            sourceWidth: payload.result.source && payload.result.source.width,
            sourceMetrics: payload.result.source && payload.result.source.metrics
        }));
    }
    if (icon256 && icon256.f1) {
        const uri = repoUrl(path.join(ICON_256_ROOT, icon256.f1));
        const payload = await renderCandidate(page, { mode: 'icon', uri: absolute(uri), fitAlpha: false, returnImage: false });
        candidates.push(candidateFromResult('icon-256', '矢量重烘 256', uri, payload, {
            sourceWidth: payload.result.source && payload.result.source.width,
            sourceMetrics: payload.result.source && payload.result.source.metrics
        }));
    }
    if (icon && icon.f2) {
        const outputFile = path.join(itemDir, 'icon-f2-fit.png');
        const sourceUri = '/launcher/web/icons/' + icon.f2;
        const payload = await renderCandidate(page, { mode: 'icon', uri: absolute(sourceUri), fitAlpha: true, margin: 18 }, outputFile);
        candidates.push(candidateFromResult('icon-f2-fit', '第二帧自动取景', repoUrl(outputFile), payload, {
            sourceWidth: payload.result.source && payload.result.source.width,
            sourceMetrics: payload.result.source && payload.result.source.metrics
        }));
    }

    if (item.kind === 'weapon' && hasDressupFields(item, '男')) {
        const outputFile = path.join(itemDir, 'dressup-weapon.png');
        const payload = await renderCandidate(page, {
            mode: 'dressup', itemName: item.name, iconName: item.iconName,
            kind: item.kind, use: item.use, actionType: item.actionType, gender: '男'
        }, outputFile);
        const weaponLabel = item.actionType === '双刀' ? '完整双刀商品图' :
            (item.actionType === '疾影' ? '刀身+刀鞘商品图' : '纸娃娃完整商品图');
        candidates.push(candidateFromResult('dressup-weapon', weaponLabel, repoUrl(outputFile), payload, {
            reviewRole: 'recommended'
        }));
    }
    if (item.kind === 'armor' && hasDressupFields(item, '男')) {
        const focusFile = path.join(itemDir, 'dressup-armor-focus-male.png');
        const focusPayload = await renderCandidate(page, {
            mode: 'dressup', itemName: item.name, kind: item.kind, use: item.use, gender: '男', composition: 'focus'
        }, focusFile);
        candidates.push(candidateFromResult(
            'dressup-armor-focus-male', '装备聚焦·男', repoUrl(focusFile), focusPayload,
            { allowContextClip: true, reviewRole: 'recommended' }
        ));

        const referenceFile = path.join(itemDir, 'dressup-armor-male.png');
        const referencePayload = await renderCandidate(page, {
            mode: 'dressup', itemName: item.name, kind: item.kind, use: item.use, gender: '男', composition: 'reference'
        }, referenceFile);
        candidates.push(candidateFromResult(
            'dressup-armor-male', '全人台参考·男', repoUrl(referenceFile), referencePayload,
            { reviewRole: 'reference' }
        ));
    }
    if (item.kind === 'armor' && hasDressupFields(item, '女')) {
        const focusFile = path.join(itemDir, 'dressup-armor-focus-female.png');
        const focusPayload = await renderCandidate(page, {
            mode: 'dressup', itemName: item.name, kind: item.kind, use: item.use, gender: '女', composition: 'focus'
        }, focusFile);
        const focusFemale = candidateFromResult(
            'dressup-armor-focus-female', '装备聚焦·女', repoUrl(focusFile), focusPayload,
            { allowContextClip: true, reviewRole: 'recommended' }
        );
        const focusMale = candidates.find(candidate => candidate.id === 'dressup-armor-focus-male');
        if (focusMale && focusMale.contentDigest && focusMale.contentDigest === focusFemale.contentDigest) {
            focusFemale.warnings.push('与男版相同');
        }
        candidates.push(focusFemale);

        const referenceFile = path.join(itemDir, 'dressup-armor-female.png');
        const referencePayload = await renderCandidate(page, {
            mode: 'dressup', itemName: item.name, kind: item.kind, use: item.use, gender: '女', composition: 'reference'
        }, referenceFile);
        const referenceFemale = candidateFromResult(
            'dressup-armor-female', '全人台参考·女', repoUrl(referenceFile), referencePayload,
            { reviewRole: 'reference' }
        );
        const referenceMale = candidates.find(candidate => candidate.id === 'dressup-armor-male');
        if (referenceMale && referenceMale.contentDigest && referenceMale.contentDigest === referenceFemale.contentDigest) {
            referenceFemale.warnings.push('与男版相同');
        }
        candidates.push(referenceFemale);
    }
    applySpecializationContracts(candidates);
    return candidates;
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (args.cleanupOutputRoot) {
        cleanupIsolatedOutputRoot(args.cleanupOutputRoot);
        return;
    }
    configureOutputRoot(args.outputRoot);
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    fs.mkdirSync(OUTPUT_ROOT, { recursive: true });
    fs.mkdirSync(CANDIDATE_ROOT, { recursive: true });

    const recipeData = loadRecipes();
    const itemMetadata = loadItemMetadata();
    const iconManifest = readJson(path.join(ROOT, 'launcher', 'web', 'icons', 'manifest.json'));
    const dressupManifest = readJson(path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json'));
    let items = uniqueItems(recipeData, dressupManifest, itemMetadata);
    if (args.sample) items = sampleItems(items);
    if (args.limit) items = items.slice(0, args.limit);

    if (!args.skipIconBake) runIconBake(items);
    const icon256ManifestPath = path.join(ICON_256_ROOT, 'manifest.json');
    const icon256Manifest = fs.existsSync(icon256ManifestPath) ? readJson(icon256ManifestPath) : {};

    const { chromium } = require(PLAYWRIGHT);
    const server = await startServer(ROOT, 0);
    const browser = await chromium.launch({ executablePath: findBrowser(args.browser), headless: true });
    const pageErrors = [];
    const failedRequests = [];
    const startedAt = Date.now();
    try {
        const page = await browser.newPage({ viewport: { width: 640, height: 420 }, deviceScaleFactor: 1 });
        page.on('pageerror', error => pageErrors.push(error.message || String(error)));
        page.on('requestfailed', request => failedRequests.push(request.url()));
        await page.addInitScript(() => {
            Object.defineProperty(window.performance, 'now', {
                configurable: true,
                value: function() { return 0; }
            });
        });
        await page.goto(server.url + 'launcher/web/modules/crafting-product-review/dev/render-harness.html', { waitUntil: 'load' });
        await page.waitForFunction(() => window.CraftingProductRenderHarness && window.CraftingProductRenderHarness.ready, null, { timeout: 20000 });
        await page.evaluate(() => window.CraftingProductRenderHarness.ready);

        for (let index = 0; index < items.length; index += 1) {
            const item = items[index];
            item.candidates = await buildItemCandidates(page, server.url, item, iconManifest, icon256Manifest);
            item.warnings = [];
            if (!iconManifest[item.iconName]) item.warnings.push('当前图标缺失');
            if ((item.kind === 'weapon' || item.kind === 'armor') && !hasDressupFields(item, '男') && !hasDressupFields(item, '女')) {
                item.warnings.push('无纸娃娃映射');
            }
            if (!item.candidates.length) item.warnings.push('无可用候选');
            delete item.dressupItem;
            if ((index + 1) % 20 === 0 || index + 1 === items.length) {
                console.log('[product-review] rendered ' + (index + 1) + '/' + items.length);
            }
        }
    } finally {
        await browser.close();
        await stopServer(server);
    }

    const digest = sourceDigest(recipeData.files);
    const candidateCount = items.reduce((sum, item) => sum + item.candidates.length, 0);
    const data = {
        schema: 'cf7-crafting-product-review-v1',
        generatedAt: new Date().toISOString(),
        sourceDigest: digest,
        sources: {
            crafting: 'data/crafting/*.json',
            icons: 'launcher/web/icons/manifest.json',
            dressup: 'launcher/web/assets/dressup/manifest.json',
            camera: 'launcher/web/modules/workbench-inspection-viewport.js'
        },
        counts: {
            recipeCount: recipeData.recipes.length,
            uniqueItemCount: items.length,
            candidateCount,
            weaponCount: items.filter(item => item.kind === 'weapon').length,
            armorCount: items.filter(item => item.kind === 'armor').length,
            fallbackCount: items.filter(item => item.kind === 'fallback').length,
            warningItemCount: items.filter(item => item.warnings.length || item.candidates.some(candidate => candidate.warnings.length)).length
        },
        items
    };
    fs.writeFileSync(REVIEW_DATA, JSON.stringify(data, null, 2) + '\n');
    const report = {
        schema: 'cf7-crafting-product-review-build-v1',
        generatedAt: data.generatedAt,
        sourceDigest: digest,
        elapsedSeconds: Math.round((Date.now() - startedAt) / 100) / 10,
        counts: data.counts,
        pageErrors,
        failedRequests,
        reviewData: slash(path.relative(ROOT, REVIEW_DATA))
    };
    fs.writeFileSync(BUILD_REPORT, JSON.stringify(report, null, 2) + '\n');
    if (pageErrors.length || failedRequests.length) {
        throw new Error('browser render errors: ' + JSON.stringify({ pageErrors, failedRequests }));
    }
    console.log('[product-review] complete: ' + slash(path.relative(ROOT, REVIEW_DATA)));
    console.log(JSON.stringify(data.counts));
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
