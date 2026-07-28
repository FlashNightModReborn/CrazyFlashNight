#!/usr/bin/env node
'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const { startServer, stopServer } = require(path.join(ROOT, 'launcher', 'perf', 'lib', 'server'));
const OUTPUT_ROOT = path.join(ROOT, 'tmp', 'equipment-inspector-review');
const GENERATED_ROOT = path.join(OUTPUT_ROOT, 'generated');
const REVIEW_DATA = path.join(OUTPUT_ROOT, 'review-data.json');
const BUILD_REPORT = path.join(OUTPUT_ROOT, 'build-report.json');
const PLACEHOLDER_FILE = path.join(GENERATED_ROOT, 'missing-preview.svg');

const DEFAULT_ZOOM = 1.85;
const MIN_SPECIALIZATION_GAIN = 1.08;
const ARMOR_USES = new Set(['头部装备', '上装装备', '下装装备', '手部装备', '脚部装备', '颈部装备']);

function slash(value) {
    return String(value).replace(/\\/g, '/');
}

function repoUrl(filePath) {
    return '/' + slash(path.relative(ROOT, filePath));
}

function readJson(filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function recursiveFiles(root) {
    const result = [];
    function visit(directory) {
        fs.readdirSync(directory, { withFileTypes:true }).sort((left, right) =>
            left.name < right.name ? -1 : (left.name > right.name ? 1 : 0)).forEach(entry => {
            const fullPath = path.join(directory, entry.name);
            if (entry.isDirectory()) visit(fullPath);
            else if (entry.isFile()) result.push(fullPath);
        });
    }
    visit(root);
    return result;
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

function stableDomKey(value) {
    return crypto.createHash('sha1').update(String(value), 'utf8').digest('hex').slice(0, 14);
}

function loadEquipmentDefinitions() {
    const itemRoot = path.join(ROOT, 'data', 'items');
    const definitions = [];
    const sourceFiles = fs.readdirSync(itemRoot)
        .filter(name => name.toLowerCase().endsWith('.xml'))
        .sort();
    sourceFiles.forEach(fileName => {
        const content = fs.readFileSync(path.join(itemRoot, fileName), 'utf8');
        const blocks = content.match(/<item(?:\s[^>]*)?>[\s\S]*?<\/item>/gi) || [];
        const sameNameOccurrences = new Map();
        blocks.forEach((block, blockIndex) => {
            const name = tagValue(block, 'name');
            const occurrence = (sameNameOccurrences.get(name) || 0) + 1;
            sameNameOccurrences.set(name, occurrence);
            const type = tagValue(block, 'type');
            if (type !== '武器' && type !== '防具') return;
            const ordinal = blockIndex + 1;
            // 插入/删除同文件内的其他物品不会让后续 ID 漂移；只有同文件同名定义
            // 之间以 occurrence 区分。
            const id = fileName + '::' + (name || '(empty-name)') + '::' + occurrence;
            definitions.push({
                id,
                domKey: stableDomKey(id),
                sourceFile: fileName,
                sourceOrdinal: ordinal,
                sourceNameOccurrence: occurrence,
                sourceRef: 'data/items/' + fileName + '#' + (name || '(empty-name)') + '[' + occurrence + ']',
                name,
                displayName: tagValue(block, 'displayname') || name,
                iconName: tagValue(block, 'icon') || name,
                majorType: type,
                type,
                use: tagValue(block, 'use'),
                actionType: tagValue(block, 'actiontype'),
                kind: type === '武器' ? 'weapon' : 'armor',
                kindLabel: type === '武器' ? '完整武器商品图' : '男女装备聚焦'
            });
        });
    });

    const byName = new Map();
    definitions.forEach(item => {
        if (!byName.has(item.name)) byName.set(item.name, []);
        byName.get(item.name).push(item);
    });
    byName.forEach(group => {
        if (group.length < 2) return;
        const ids = group.map(item => item.id);
        group.forEach((item, index) => {
            item.duplicateName = {
                name: item.name,
                occurrence: index + 1,
                total: group.length,
                definitionIds: ids.slice(0)
            };
        });
    });
    return { definitions, sourceFiles };
}

function sourceDigest(sourceFiles) {
    const hash = crypto.createHash('sha256');
    const files = sourceFiles.map(name => path.join(ROOT, 'data', 'items', name)).concat([
        path.join(ROOT, 'launcher', 'web', 'icons', 'manifest.json'),
        path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'asset-timeline.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'dressup-doll-renderer.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'workbench-inspection-viewport.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector.js'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'crafting-product-review', 'dev', 'render-harness.html'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector-review', 'dev', 'review.html'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector-review', 'dev', 'review.css'),
        path.join(ROOT, 'launcher', 'web', 'modules', 'equipment-inspector-review', 'dev', 'review.js'),
        __filename
    ]);
    // localStorage 与导出的 pass 必须随实际图片字节失效；只哈希 manifest
    // 无法覆盖“文件原地替换、URI 不变”。这里保守哈希两个运行时资产目录的
    // 全部文件，未来 resolver 改选其它 manifest entry 时也不会复用旧结论。
    files.push.apply(files, recursiveFiles(path.join(ROOT, 'launcher', 'web', 'icons')));
    files.push.apply(files, recursiveFiles(path.join(ROOT, 'launcher', 'web', 'assets', 'dressup')));
    files.forEach(filePath => {
        hash.update(slash(path.relative(ROOT, filePath)));
        hash.update('\0');
        hash.update(fs.readFileSync(filePath));
        hash.update('\0');
    });
    return hash.digest('hex').slice(0, 20);
}

function parseArgs(argv) {
    const result = { browser: 'edge', limit: 0 };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === '--browser') {
            result.browser = String(argv[index + 1] || 'edge');
            index += 1;
        } else if (arg === '--limit') {
            result.limit = Number(argv[index + 1] || 0);
            index += 1;
        } else if (arg === '--help' || arg === '-h') {
            console.log('usage: node tools/build-equipment-inspector-review.js [--browser edge|chrome] [--limit N]');
            process.exit(0);
        } else {
            throw new Error('unknown argument: ' + arg);
        }
    }
    if (!Number.isInteger(result.limit) || result.limit < 0) throw new Error('--limit must be a non-negative integer');
    return result;
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
    const found = (name === 'chrome' ? chrome : edge).find(candidate => candidate && fs.existsSync(candidate));
    if (!found) throw new Error('cannot find browser executable: ' + name);
    return found;
}

function placeholderSvg() {
    return [
        '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">',
        '<rect width="256" height="256" fill="#141b24"/>',
        '<path d="M32 32L224 224M224 32L32 224" stroke="#704b52" stroke-width="8"/>',
        '<rect x="24" y="24" width="208" height="208" fill="none" stroke="#9c626c" stroke-width="3"/>',
        '<text x="128" y="137" text-anchor="middle" fill="#f1a0aa" font-size="20" font-family="Microsoft YaHei, sans-serif">缺少预览素材</text>',
        '</svg>\n'
    ].join('');
}

function ensurePlaceholder() {
    fs.mkdirSync(GENERATED_ROOT, { recursive: true });
    fs.writeFileSync(PLACEHOLDER_FILE, placeholderSvg(), 'utf8');
}

function verifyReviewArtifacts(items, repositoryRoot) {
    repositoryRoot = repositoryRoot || ROOT;
    const expectedPlaceholderUri = '/tmp/equipment-inspector-review/generated/missing-preview.svg';
    const expectedPlaceholder = Buffer.from(placeholderSvg(), 'utf8');
    const references = [];
    (items || []).forEach(item => {
        if (item.baseline) references.push({itemId:item.id, branchId:'baseline', value:item.baseline});
        (item.requiredBranches || []).forEach(branch => references.push({
            itemId:item.id, branchId:branch.id, value:branch
        }));
    });
    references.forEach(reference => {
        const uri = String(reference.value.uri || '');
        if (!uri.startsWith('/') || /[?#]/.test(uri)) {
            throw new Error('review artifact URI must be a clean repo-root path: ' + reference.itemId + ' ' + reference.branchId);
        }
        const filePath = path.resolve(repositoryRoot, uri.replace(/^\/+/, ''));
        const relative = path.relative(repositoryRoot, filePath);
        if (relative.startsWith('..') || path.isAbsolute(relative)) {
            throw new Error('review artifact escaped repository: ' + uri);
        }
        if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
            throw new Error('review artifact missing: ' + uri);
        }
        const bytes = fs.readFileSync(filePath);
        const declared = String(reference.value.contentDigest || '');
        if (!declared) {
            if (uri !== expectedPlaceholderUri || !bytes.equals(expectedPlaceholder)) {
                throw new Error('empty contentDigest is only valid for the exact missing placeholder: ' +
                    reference.itemId + ' ' + reference.branchId);
            }
            return;
        }
        if (!/^[0-9a-f]{12}$/.test(declared)) {
            throw new Error('invalid review artifact contentDigest: ' + declared);
        }
        const actual = crypto.createHash('sha1').update(bytes).digest('hex').slice(0, 12);
        if (actual !== declared) {
            throw new Error('review artifact digest mismatch: ' + uri + ' declared=' + declared + ' actual=' + actual);
        }
    });
    return references.length;
}

function iconFrameUri(entry) {
    if (!entry) return '';
    if (typeof entry.f1 === 'string' && entry.f1) return entry.f1;
    const frames = entry.timelineFrames && entry.timelineFrames.length ? entry.timelineFrames : entry.frames;
    if (frames && frames.length) return frames[0].uri || frames[0].file || frames[0].filename || '';
    return typeof entry.uri === 'string' ? entry.uri : '';
}

function distinctFrameUris(frames) {
    const seen = new Set();
    (frames || []).forEach(frame => {
        const uri = frame && (frame.uri || frame.file || frame.filename);
        if (uri) seen.add(uri);
    });
    return seen.size;
}

function frameVisualIdentity(frame) {
    if (!frame) return '';
    return JSON.stringify([
        frame.uri || frame.file || frame.filename || '',
        frame.cropX || 0, frame.cropY || 0, frame.cropWidth || 0, frame.cropHeight || 0,
        frame.originX || 0, frame.originY || 0,
        frame.matrix || null, frame.transform || null
    ]);
}

function distinctFrameStates(frames) {
    const seen = new Set();
    (frames || []).forEach(frame => {
        const identity = frameVisualIdentity(frame);
        if (identity) seen.add(identity);
    });
    return seen.size;
}

function nestedMotionLayers(nested, depth, parentPath, output) {
    output = output || [];
    (nested && nested.layers || []).forEach(layer => {
        const layerFrames = layer.timelineFrames && layer.timelineFrames.length ? layer.timelineFrames :
            (layer.frames && layer.frames.length ? layer.frames : layer.export &&
                (layer.export.timelineFrames || layer.export.frames) || []);
        const characterId = layer.characterId || 0;
        const pathParts = parentPath.concat([characterId]);
        const record = {
            characterId,
            depth,
            path: pathParts,
            distinctStates: distinctFrameStates(layerFrames),
            distinctUris: distinctFrameUris(layerFrames)
        };
        if (record.distinctStates > 1) output.push(record);
        // production DressupDollRenderer 会递归绘制 export.nestedAnimation；
        // 不能因第一层自身静态而漏掉更深层的动效。
        const childNested = layer.nestedAnimation || layer.export && layer.export.nestedAnimation;
        if (childNested) nestedMotionLayers(childNested, depth + 1, pathParts, output);
    });
    return output;
}

function motionEvidenceForEntry(entry) {
    if (!entry) return { animated:false, reasons:[], distinctStates:0, nestedLayers:[] };
    const reasons = [];
    const frames = entry.timelineFrames && entry.timelineFrames.length ? entry.timelineFrames : entry.frames;
    const distinctStates = distinctFrameStates(frames);
    const playback = String(entry.playback || entry.export && entry.export.playback || '');
    if ((entry.animated === true || entry.loop === true || entry.format === 'webp-animated') &&
        (distinctStates > 1 || entry.format === 'webp-animated')) reasons.push('top-level-animation');
    if ((playback.indexOf('animation') >= 0 || playback === 'loop') && distinctStates > 1) {
        reasons.push('top-level-' + playback);
    }
    const nested = entry.nestedAnimation || entry.export && entry.export.nestedAnimation || {};
    const nestedLayers = nestedMotionLayers(nested, 1, [], []);
    if (nestedLayers.length) reasons.push('nested-layer-animation');
    return {
        animated: reasons.length > 0,
        reasons: Array.from(new Set(reasons)),
        distinctStates,
        nestedLayers
    };
}

function iconEntryHasMotion(entry) {
    if (!entry) return false;
    return motionEvidenceForEntry(entry).animated;
}

function sourceMotionAudit(item, source, gender, manifest) {
    const selected = [];
    if (source && source.components && source.components.length) {
        source.components.forEach(component => selected.push({field:component.field, skinKey:component.skinKey}));
    } else if (source && source.skinKey) {
        selected.push({field:source.field || '', skinKey:source.skinKey});
    } else if (source && source.kind === 'armor') {
        const manifestItem = manifest.items && manifest.items[item.name];
        const fields = manifestItem && manifestItem.fieldsByGender && manifestItem.fieldsByGender[gender] || {};
        (source.fitFields || []).forEach(field => {
            if (fields[field]) selected.push({field, skinKey:fields[field]});
        });
    }
    const fields = selected.map(component => {
        const evidence = motionEvidenceForEntry(manifest.skinKeys && manifest.skinKeys[component.skinKey]);
        return {
            field: component.field,
            skinKey: component.skinKey,
            animated: evidence.animated,
            reasons: evidence.reasons,
            distinctStates: evidence.distinctStates,
            nestedLayers: evidence.nestedLayers
        };
    });
    return {
        selectedEquipmentFieldsOnly: true,
        animated: fields.some(field => field.animated),
        fields
    };
}

function writeDataUrl(filePath, dataUrl) {
    const comma = String(dataUrl || '').indexOf(',');
    if (comma < 0) return '';
    const buffer = Buffer.from(dataUrl.slice(comma + 1), 'base64');
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, buffer);
    return crypto.createHash('sha1').update(buffer).digest('hex').slice(0, 12);
}

async function renderHarness(page, options) {
    try {
        const result = await page.evaluate(renderOptions => {
            return window.CraftingProductRenderHarness.render(renderOptions);
        }, options);
        return { result: result || {}, error: '' };
    } catch (error) {
        return { result: {}, error: String(error && error.message || error) };
    }
}

async function resolveProductionSource(page, item, gender) {
    return page.evaluate(payload => {
        return EquipmentInspector.resolveItemSource(payload.item, payload.gender,
            window.__equipmentInspectorReviewManifest);
    }, {
        gender,
        item: {
            name: item.name,
            displayName: item.displayName,
            icon: item.iconName,
            majorType: item.majorType,
            type: item.type,
            use: item.use,
            actionType: item.actionType
        }
    });
}

function longestContentEdge(metrics) {
    const bbox = metrics && metrics.bbox || {};
    return Math.max(0, Number(bbox.width) || 0, Number(bbox.height) || 0);
}

function criticalMetrics(metrics) {
    const bbox = metrics && metrics.bbox || {};
    return {
        width: Number(metrics && metrics.width) || 0,
        height: Number(metrics && metrics.height) || 0,
        alphaPixels: Number(metrics && metrics.alphaPixels) || 0,
        bbox: {
            x: Number(bbox.x) || 0,
            y: Number(bbox.y) || 0,
            width: Number(bbox.width) || 0,
            height: Number(bbox.height) || 0
        },
        touchesEdge: !!(metrics && metrics.touchesEdge)
    };
}

function computeReviewDigest(sourceDigestValue, items) {
    const reviewEvidence = items.map(item => ({
        id: item.id,
        baseline: {
            contentDigest: item.baseline && item.baseline.contentDigest || '',
            metrics: criticalMetrics(item.baseline && item.baseline.metrics)
        },
        requiredBranches: item.requiredBranches.map(branch => ({
            id: branch.id,
            candidateId: branch.candidateId,
            contentDigest: branch.contentDigest || '',
            metrics: criticalMetrics(branch.metrics),
            specialization: branch.specialization,
            approval: branch.approval,
            animationEvidence: branch.animation && branch.animation.evidence || null,
            renderEvidence: branch.render ? {
                holders: Number(branch.render.holders) || 0,
                missing: Number(branch.render.missing) || 0,
                failedImages: Number(branch.render.failedImages) || 0,
                animated: !!branch.render.animated
            } : null
        }))
    }));
    return crypto.createHash('sha256')
        .update(String(sourceDigestValue), 'utf8')
        .update('\0')
        .update(JSON.stringify(reviewEvidence), 'utf8')
        .digest('hex').slice(0, 24);
}

function renderWarnings(result) {
    const warnings = [];
    const metrics = result.metrics || {};
    if (!metrics.alphaPixels) warnings.push('预览为空');
    if (metrics.touchesEdge) warnings.push('内容触边');
    if (result.error) warnings.push(result.error);
    return warnings;
}

async function buildBaseline(page, serverUrl, item, iconEntry) {
    const frame = iconFrameUri(iconEntry);
    const outputFile = path.join(GENERATED_ROOT, item.domKey + '-icon-current.png');
    const payload = frame ? await renderHarness(page, {
        mode: 'icon',
        uri: new URL('launcher/web/icons/' + frame, serverUrl).href,
        fitAlpha: false,
        returnImage: true
    }) : { result: {}, error: 'icon_missing' };
    const contentDigest = writeDataUrl(outputFile, payload.result.dataUrl);
    return {
        result: payload.result,
        error: payload.error || payload.result.error || '',
        candidate: {
            id: 'icon-current',
            label: '当前图标基线',
            uri: contentDigest ? repoUrl(outputFile) : repoUrl(PLACEHOLDER_FILE),
            contentDigest,
            metrics: payload.result.metrics || {},
            sourceWidth: payload.result.source && payload.result.source.width || 0,
            animation: {
                sourceAnimated: iconEntryHasMotion(iconEntry),
                previewMode: 'static-first-frame'
            },
            warnings: renderWarnings({
                metrics: payload.result.metrics || {},
                error: payload.error || payload.result.error || ''
            })
        }
    };
}

async function buildBranch(page, serverUrl, item, config, source, iconEntry, baseline, dressupManifest) {
    const outputFile = path.join(GENERATED_ROOT, item.domKey + '-' + config.id + '.png');
    const iconFrame = iconFrameUri(iconEntry);
    const payload = await renderHarness(page, {
        mode: 'dressup',
        itemName: item.name,
        iconName: item.iconName,
        kind: config.expectedKind,
        use: item.use,
        actionType: item.actionType,
        gender: config.gender,
        composition: config.expectedKind === 'armor' ? 'focus' : ''
    });

    const contentDigest = writeDataUrl(outputFile, payload.result.dataUrl);
    const previewUri = contentDigest ? repoUrl(outputFile) : repoUrl(PLACEHOLDER_FILE);
    const render = payload.result.render || null;
    const metrics = payload.result.metrics || {};
    const expectedHolders = config.expectedKind === 'weapon' &&
        (item.actionType === '双刀' || item.actionType === '疾影') ? 2 : 1;
    const actualHolders = Number(render && render.holders) || 0;
    const actualMissing = Number(render && render.missing) || 0;
    const failedImages = Number(render && render.failedImages) || 0;
    const motionAudit = sourceMotionAudit(item, source, config.gender, dressupManifest);
    const animated = motionAudit.animated;
    const baselineEdge = longestContentEdge(baseline.candidate.metrics);
    const candidateEdge = longestContentEdge(metrics);
    const gain = baselineEdge > 0 && candidateEdge > 0
        ? Math.round(candidateEdge * DEFAULT_ZOOM / baselineEdge * 1000) / 1000
        : null;
    const specialization = {
        baselineId: 'current-icon',
        metric: 'max-bbox-at-default-zoom',
        displayZoom: DEFAULT_ZOOM,
        minGain: MIN_SPECIALIZATION_GAIN,
        gain,
        largerThanBaseline: gain === null ? null : gain > 1,
        contractPass: gain === null ? false : gain >= MIN_SPECIALIZATION_GAIN
    };

    const gates = [];
    if (!iconFrame) gates.push('icon_missing');
    if (payload.error || payload.result.error) gates.push('render_error');
    if (!contentDigest || !metrics.alphaPixels) gates.push('preview_missing');
    if (actualMissing > 0) gates.push('holder_missing');
    if (failedImages > 0) gates.push('image_load_failed');
    if (actualHolders < expectedHolders ||
        (expectedHolders === 2 && actualHolders !== 2)) gates.push('holder_contract_failed');
    if (!specialization.contractPass) gates.push('specialization_gain_failed');
    if (animated) gates.push('live_animation');
    const blockingGates = Array.from(new Set(gates));
    const nonLiveGates = blockingGates.filter(gate => gate !== 'live_animation');
    const warnings = renderWarnings({ metrics, error: payload.error || payload.result.error || '' });
    if (source && source.missingFields && source.missingFields.length) {
        warnings.push('缺少 holder：' + source.missingFields.join('、'));
    }
    if (animated) warnings.push('静态首帧不可签，需 live 动效验收');
    if (!specialization.contractPass) warnings.push('默认 185% 特写增益未达合同');

    return {
        id: config.id,
        candidateId: config.id,
        label: source && source.label || config.label,
        required: true,
        gender: config.gender,
        expectedKind: config.expectedKind,
        actualKind: source && source.kind || 'missing',
        route: config.expectedKind === 'weapon' ? 'weapon-product' : 'armor-focus',
        source: source || null,
        uri: previewUri,
        contentDigest,
        metrics,
        render,
        state: payload.result.state || null,
        pipeline: payload.result.pipeline || null,
        expectedHolders,
        specialization,
        animation: {
            sourceAnimated: animated,
            renderReportedAnimated: !!(render && render.animated),
            previewMode: 'static-first-frame',
            evidence: motionAudit,
            staticSignable: !animated && nonLiveGates.length === 0,
            requiresLiveReview: animated,
            liveSignable: animated && nonLiveGates.length === 0
        },
        approval: {
            staticSignable: !animated && nonLiveGates.length === 0,
            requiresLiveReview: animated,
            liveSignable: animated && nonLiveGates.length === 0,
            blockingGates
        },
        warnings
    };
}

function buildFallbackBranch(item, sourceEntries, iconEntry, baseline, branchId) {
    const iconMotion = motionEvidenceForEntry(iconEntry);
    const animated = iconMotion.animated;
    const metrics = baseline.candidate.metrics || {};
    const edge = longestContentEdge(metrics);
    const gain = edge > 0 ? DEFAULT_ZOOM : null;
    const specialization = {
        baselineId: 'current-icon',
        metric: 'max-bbox-at-default-zoom',
        displayZoom: DEFAULT_ZOOM,
        minGain: MIN_SPECIALIZATION_GAIN,
        gain,
        largerThanBaseline: gain === null ? null : gain > 1,
        contractPass: gain === null ? false : gain >= MIN_SPECIALIZATION_GAIN
    };
    const gates = [];
    if (!iconFrameUri(iconEntry)) gates.push('icon_missing');
    if (baseline.error) gates.push('render_error');
    if (!baseline.candidate.contentDigest || !metrics.alphaPixels) gates.push('preview_missing');
    if (!specialization.contractPass) gates.push('specialization_gain_failed');
    if (animated) gates.push('live_animation');
    const blockingGates = Array.from(new Set(gates));
    const nonLiveGates = blockingGates.filter(gate => gate !== 'live_animation');
    const reasons = Array.from(new Set(sourceEntries.map(entry => entry.source && entry.source.reason || 'unknown')));
    const warnings = ['生产路线使用当前图标：' + reasons.join('、')];
    if (animated) warnings.push('静态首帧不可签，需 live 动效验收');
    if (!specialization.contractPass) warnings.push('默认 185% 特写增益未达合同');
    return {
        id: branchId || 'icon-fallback',
        candidateId: 'icon-current',
        label: '当前图标（无性别分支）',
        required: true,
        gender: '',
        liveGender: '男',
        expectedKind: 'icon',
        actualKind: 'icon',
        route: 'icon-fallback',
        source: sourceEntries.length === 1 ? sourceEntries[0].source : null,
        sourcesByGender: sourceEntries.reduce((result, entry) => {
            result[entry.gender] = entry.source;
            return result;
        }, {}),
        uri: baseline.candidate.uri,
        contentDigest: baseline.candidate.contentDigest,
        metrics,
        render: null,
        state: null,
        pipeline: null,
        expectedHolders: 0,
        specialization,
        animation: {
            sourceAnimated: animated,
            previewMode: 'static-first-frame',
            evidence: {selectedCurrentIconOnly:true, icon:iconMotion},
            staticSignable: !animated && nonLiveGates.length === 0,
            requiresLiveReview: animated,
            liveSignable: animated && nonLiveGates.length === 0
        },
        approval: {
            staticSignable: !animated && nonLiveGates.length === 0,
            requiresLiveReview: animated,
            liveSignable: animated && nonLiveGates.length === 0,
            blockingGates
        },
        fallback: {
            intentionalProductionRoute: true,
            genders: sourceEntries.map(entry => entry.gender),
            reasons
        },
        warnings
    };
}

function countsFor(items, fullDefinitionCount, duplicateGroups) {
    const branches = items.flatMap(item => item.requiredBranches);
    const branchPairs = items.flatMap(item => item.requiredBranches.map(branch => ({item, branch})));
    const specializedBranches = branches.filter(branch => branch.candidateId !== 'icon-current');
    return {
        fullDefinitionCount,
        definitionCount: items.length,
        weaponDefinitionCount: items.filter(item => item.majorType === '武器').length,
        armorDefinitionCount: items.filter(item => item.majorType === '防具').length,
        requiredBranchCount: branches.length,
        baselineCandidateCount: items.length,
        specializedCandidateCount: specializedBranches.length,
        candidateCount: items.length + specializedBranches.length,
        duplicateNameGroupCount: duplicateGroups.length,
        duplicateDefinitionCount: duplicateGroups.reduce((sum, group) => sum + group.definitionIds.length, 0),
        weaponProductBranchCount: branches.filter(branch => branch.route === 'weapon-product').length,
        armorFocusBranchCount: branches.filter(branch => branch.route === 'armor-focus').length,
        armorFocusMaleBranchCount: branches.filter(branch => branch.id === 'armor-focus-male').length,
        armorFocusFemaleBranchCount: branches.filter(branch => branch.id === 'armor-focus-female').length,
        fallbackBranchCount: branches.filter(branch => branch.route === 'icon-fallback').length,
        weaponFallbackBranchCount: branchPairs.filter(pair => pair.item.majorType === '武器' && pair.branch.route === 'icon-fallback').length,
        armorFallbackBranchCount: branchPairs.filter(pair => pair.item.majorType === '防具' && pair.branch.route === 'icon-fallback').length,
        fallbackMissingIconCount: branches.filter(branch => branch.route === 'icon-fallback' &&
            branch.approval.blockingGates.includes('icon_missing')).length,
        dualBladeDefinitionCount: items.filter(item => item.actionType === '双刀').length,
        bladeSheathDefinitionCount: items.filter(item => item.actionType === '疾影').length,
        missingImageBranchCount: branches.filter(branch => branch.approval.blockingGates.some(gate =>
            gate === 'icon_missing' || gate === 'preview_missing' || gate === 'image_load_failed')).length,
        missingHolderBranchCount: branches.filter(branch => branch.approval.blockingGates.some(gate =>
            gate === 'holder_missing' || gate === 'holder_contract_failed')).length,
        specializationFailureCount: branches.filter(branch => !branch.specialization.contractPass).length,
        animatedBranchCount: branches.filter(branch => branch.animation.sourceAnimated).length,
        liveReviewGateCount: branches.filter(branch => branch.approval.requiresLiveReview).length,
        staticSignableBranchCount: branches.filter(branch => branch.approval.staticSignable).length,
        warningDefinitionCount: items.filter(item => item.warnings.length ||
            item.requiredBranches.some(branch => branch.warnings.length)).length
    };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    const loaded = loadEquipmentDefinitions();
    const fullDefinitionCount = loaded.definitions.length;
    const items = args.limit ? loaded.definitions.slice(0, args.limit) : loaded.definitions;
    const iconManifest = readJson(path.join(ROOT, 'launcher', 'web', 'icons', 'manifest.json'));
    const dressupManifest = readJson(path.join(ROOT, 'launcher', 'web', 'assets', 'dressup', 'manifest.json'));

    fs.mkdirSync(OUTPUT_ROOT, { recursive: true });
    if (fs.existsSync(GENERATED_ROOT)) fs.rmSync(GENERATED_ROOT, { recursive: true, force: true });
    ensurePlaceholder();

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
        await page.waitForFunction(() => window.CraftingProductRenderHarness && window.CraftingProductRenderHarness.ready &&
            window.EquipmentInspector, null, { timeout: 20000 });
        await page.evaluate(async () => {
            await window.CraftingProductRenderHarness.ready;
            const response = await fetch('/launcher/web/assets/dressup/manifest.json');
            if (!response.ok) throw new Error('dressup manifest HTTP ' + response.status);
            window.__equipmentInspectorReviewManifest = await response.json();
        });

        for (let index = 0; index < items.length; index += 1) {
            const item = items[index];
            const iconEntry = iconManifest[item.iconName] || null;
            const baseline = await buildBaseline(page, server.url, item, iconEntry);
            item.baseline = baseline.candidate;
            item.requiredBranches = [];
            if (item.majorType === '武器') {
                const source = await resolveProductionSource(page, item, '男');
                if (source.kind === 'weapon') {
                    item.requiredBranches.push(await buildBranch(page, server.url, item, {
                        id: 'weapon-product', label: '完整武器商品图', gender: '男', expectedKind: 'weapon'
                    }, source, iconEntry, baseline, dressupManifest));
                } else {
                    item.requiredBranches.push(buildFallbackBranch(item, [{gender:'男', source}], iconEntry, baseline));
                }
            } else {
                const maleSource = await resolveProductionSource(page, item, '男');
                const femaleSource = await resolveProductionSource(page, item, '女');
                if (maleSource.kind === 'icon' && femaleSource.kind === 'icon') {
                    // 无纸娃娃分支的防具（当前为颈部）男女看到完全相同的图标；
                    // required 决定只保留一次，避免人类重复验同一张图。
                    item.requiredBranches.push(buildFallbackBranch(item, [
                        {gender:'男', source:maleSource}, {gender:'女', source:femaleSource}
                    ], iconEntry, baseline));
                } else {
                    item.requiredBranches.push(maleSource.kind === 'armor'
                        ? await buildBranch(page, server.url, item, {
                            id: 'armor-focus-male', label: '装备聚焦 · 男', gender: '男', expectedKind: 'armor'
                        }, maleSource, iconEntry, baseline, dressupManifest)
                        : buildFallbackBranch(item, [{gender:'男', source:maleSource}], iconEntry, baseline, 'icon-fallback-male'));
                    item.requiredBranches.push(femaleSource.kind === 'armor'
                        ? await buildBranch(page, server.url, item, {
                            id: 'armor-focus-female', label: '装备聚焦 · 女', gender: '女', expectedKind: 'armor'
                        }, femaleSource, iconEntry, baseline, dressupManifest)
                        : buildFallbackBranch(item, [{gender:'女', source:femaleSource}], iconEntry, baseline, 'icon-fallback-female'));
                }
            }
            item.warnings = [];
            if (item.duplicateName) {
                item.warnings.push('重名定义 ' + item.duplicateName.occurrence + '/' + item.duplicateName.total +
                    '；验收状态按 ' + item.id + ' 独立保存');
            }
            if (!iconEntry) item.warnings.push('当前图标缺失：' + item.iconName);
            if (!item.name) item.warnings.push('物品 name 为空');
            if ((index + 1) % 25 === 0 || index + 1 === items.length) {
                console.log('[equipment-inspector-review] rendered ' + (index + 1) + '/' + items.length);
            }
        }
    } finally {
        await browser.close();
        await stopServer(server);
    }

    const duplicateGroups = [];
    const duplicateSeen = new Set();
    items.forEach(item => {
        if (!item.duplicateName || duplicateSeen.has(item.name)) return;
        const visibleIds = item.duplicateName.definitionIds.filter(id => items.some(candidate => candidate.id === id));
        if (visibleIds.length < 2) return;
        duplicateSeen.add(item.name);
        duplicateGroups.push({ name: item.name, definitionIds: visibleIds });
    });
    const verifiedArtifactReferenceCount = verifyReviewArtifacts(items, ROOT);
    const digest = sourceDigest(loaded.sourceFiles);
    const renderedReviewDigest = computeReviewDigest(digest, items);
    const counts = countsFor(items, fullDefinitionCount, duplicateGroups);
    counts.verifiedArtifactReferenceCount = verifiedArtifactReferenceCount;
    const data = {
        schema: 'cf7-equipment-inspector-review-v1',
        generatedAt: new Date().toISOString(),
        sourceDigest: digest,
        reviewDigest: renderedReviewDigest,
        partial: items.length !== fullDefinitionCount,
        productionContract: {
            weapon: ['weapon-product'],
            armor: ['armor-focus-male', 'armor-focus-female'],
            fallback: 'current-icon',
            fallbackDecision: 'single-genderless-required-branch',
            defaultZoom: DEFAULT_ZOOM,
            minSpecializationGain: MIN_SPECIALIZATION_GAIN,
            animation: 'static-first-frame-non-signable-requires-live-review',
            motionAcceptance: 'open-live-then-explicit-motionReviewed-confirmation'
        },
        sources: {
            definitions: 'data/items/*.xml (raw item definitions, no name deduplication)',
            icons: 'launcher/web/icons/manifest.json',
            dressup: 'launcher/web/assets/dressup/manifest.json',
            digestAssets: 'recursive bytes of launcher/web/icons and launcher/web/assets/dressup',
            camera: 'launcher/web/modules/workbench-inspection-viewport.js',
            resolver: 'launcher/web/modules/equipment-inspector.js',
            renderer: 'launcher/web/modules/crafting-product-review/dev/render-harness.html'
        },
        counts,
        duplicateNameGroups: duplicateGroups,
        items
    };
    fs.writeFileSync(REVIEW_DATA, JSON.stringify(data, null, 2) + '\n');
    const report = {
        schema: 'cf7-equipment-inspector-review-build-v1',
        generatedAt: data.generatedAt,
        sourceDigest: digest,
        reviewDigest: renderedReviewDigest,
        partial: data.partial,
        elapsedSeconds: Math.round((Date.now() - startedAt) / 100) / 10,
        counts,
        pageErrors,
        failedRequests: Array.from(new Set(failedRequests)),
        reviewData: slash(path.relative(ROOT, REVIEW_DATA))
    };
    fs.writeFileSync(BUILD_REPORT, JSON.stringify(report, null, 2) + '\n');
    if (pageErrors.length || failedRequests.length) {
        throw new Error('browser render failures: ' + JSON.stringify({pageErrors, failedRequests:Array.from(new Set(failedRequests))}));
    }
    console.log('[equipment-inspector-review] complete: ' + slash(path.relative(ROOT, REVIEW_DATA)));
    console.log(JSON.stringify(counts));
}

module.exports = {
    ARMOR_USES,
    DEFAULT_ZOOM,
    MIN_SPECIALIZATION_GAIN,
    computeReviewDigest,
    loadEquipmentDefinitions,
    sourceDigest,
    verifyReviewArtifacts
};

if (require.main === module) {
    main().catch(error => {
        console.error(error && error.stack ? error.stack : String(error));
        process.exit(1);
    });
}
