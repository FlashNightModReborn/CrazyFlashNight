#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');

const projectRoot = path.resolve(__dirname, '..');
const sourceRoot = path.join(projectRoot, 'flashswf', 'UI', '选关界面');
const libraryRoot = path.join(sourceRoot, 'LIBRARY');
const domDocumentPath = path.join(sourceRoot, 'DOMDocument.xml');
const mainSymbolPath = path.join(libraryRoot, '选关界面UI', '选关界面 1024&#042576.xml');
const previewSymbolPath = path.join(libraryRoot, '选关界面UI', 'Symbol 3274.xml');
const previewRoot = path.join(projectRoot, 'flashswf', 'images', '关卡预览图');
const webAssetRoot = path.join(projectRoot, 'launcher', 'web', 'assets', 'stage-select');
const moduleOutput = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-data.js');
const sourceSwf = path.join(projectRoot, 'flashswf', 'UI', '选关界面.swf');
const ffdecJar = path.join(projectRoot, 'tools', 'ffdec', 'ffdec.jar');

const backgroundNames = {
    '背景-废城-topaz-enhance-1024w.png': 'waste-city.png',
    '背景-堕落城-topaz-enhance-1024w.png': 'fallen-city.png',
    '背景-黑铁会总部-topaz-enhance-1024w.png': 'blackiron-hq.png',
    '背景-禁区-topaz-enhance-1024w.png': 'restricted-zone.png',
    '背景-荒漠-topaz-enhance-1024w.png': 'desert.png',
    '背景-诺亚深处-topaz-enhance-1024w.png': 'noah-depth.png',
    '背景-雪山-topaz-enhance-1024w.png': 'snow-mountain.png',
    '背景-试炼场深处.png': 'trial-depth.jpg'
};

const fallbackBackgroundByFrame = {
    '沙漠虫洞': {
        assetName: 'wormhole-cave.jpg',
        exportedImage: '295.jpg',
        exportId: 295,
        sourcePath: 'image/bitmap3342.jpg',
        rect: { x: -6.5, y: -105.55, w: 1030.7, h: 677.69 },
        reason: 'FFDec image export for embedded bitmap3342'
    },
    '雪山内部': {
        assetName: 'snow-interior.jpg',
        exportedImage: '318.jpg',
        exportId: 318,
        sourcePath: 'image/bitmap3366.jpg',
        rect: { x: 0, y: 0, w: 1023.98, h: 614.39 },
        reason: 'FFDec image export for embedded bitmap3366'
    },
    '雪山内部第二层': {
        assetName: 'snow-interior.jpg',
        exportedImage: '318.jpg',
        exportId: 318,
        sourcePath: 'image/bitmap3366.jpg',
        rect: { x: 0, y: 0, w: 1023.98, h: 614.39 },
        reason: 'FFDec image export for embedded bitmap3366'
    },
    '亡灵沙漠': {
        assetName: 'wide-sky-1024x768.jpg',
        exportedImage: '19.jpg',
        exportId: 19,
        sourcePath: 'shape/Symbol 3371 -> image/bitmap3108.jpg',
        rect: { x: 0, y: -206.95, w: 1024, h: 768 },
        reason: 'FFDec image export for shape/Symbol 3371 embedded bitmap3108'
    },
    '异界战场': {
        assetName: 'wide-sky-1024x768.jpg',
        exportedImage: '19.jpg',
        exportId: 19,
        sourcePath: 'shape/Symbol 3371 -> image/bitmap3108.jpg',
        rect: { x: 0, y: -46.05, w: 1024, h: 768 },
        reason: 'FFDec image export for shape/Symbol 3371 embedded bitmap3108'
    },
    '坠毁战舰': {
        assetName: 'crashed-warship.jpg',
        exportedImage: '324.jpg',
        exportId: 324,
        sourcePath: 'shape/Symbol 3377 -> image/bitmap3376.jpg',
        rect: { x: -0.08, y: -19.76, w: 1024.18, h: 613.02 },
        reason: 'FFDec image export for shape/Symbol 3377 embedded bitmap3376'
    }
};

function parseArgs(argv) {
    const args = {
        output: '',
        summary: false,
        writeModule: false,
        copyAssets: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--output') {
            args.output = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--summary') {
            args.summary = true;
        } else if (arg === '--write-module') {
            args.writeModule = true;
        } else if (arg === '--copy-assets') {
            args.copyAssets = true;
        } else if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        } else {
            printHelp(1, 'unknown arg: ' + arg);
            return null;
        }
    }
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/export-stage-select-manifest.js [--output <file>] [--summary] [--write-module] [--copy-assets]');
    process.exit(exitCode);
}

function readUtf8(filePath) {
    return fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, '');
}

function escapeRegExp(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function decodeXml(value) {
    return String(value || '')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
}

function attrsToObject(attrText) {
    const out = {};
    const re = /([A-Za-z0-9_:.-]+)="([^"]*)"/g;
    let match;
    while ((match = re.exec(attrText || ''))) {
        out[match[1]] = decodeXml(match[2]);
    }
    return out;
}

function extractLayer(xml, name) {
    const re = new RegExp('<DOMLayer\\b(?=[^>]*name="' + escapeRegExp(name) + '")[^>]*>[\\s\\S]*?</DOMLayer>', 'u');
    const match = xml.match(re);
    return match ? match[0] : '';
}

function eachFrame(layerXml, visitor) {
    const re = /<DOMFrame\b([^>]*)>([\s\S]*?)<\/DOMFrame>/gu;
    let match;
    while ((match = re.exec(layerXml || ''))) {
        visitor(attrsToObject(match[1]), match[2], match[0]);
    }
}

function eachSymbol(frameBody, visitor) {
    const re = /<DOMSymbolInstance\b([^>]*)>([\s\S]*?)<\/DOMSymbolInstance>/gu;
    let match;
    while ((match = re.exec(frameBody || ''))) {
        visitor(attrsToObject(match[1]), match[2], match[0]);
    }
}

function firstMatrixAttrs(body) {
    const match = String(body || '').match(/<Matrix\b([^>]*)\/>/u);
    return match ? attrsToObject(match[1]) : {};
}

function numberAttr(attrs, name, fallback) {
    const value = attrs && attrs[name] !== undefined ? Number(attrs[name]) : NaN;
    return Number.isFinite(value) ? value : fallback;
}

function normalizeDuration(attrs) {
    const duration = Number(attrs.duration || 1);
    return Number.isFinite(duration) && duration > 0 ? duration : 1;
}

function parseLabels(xml) {
    const labelsLayer = extractLayer(xml, 'Labels Layer');
    const labels = [];
    eachFrame(labelsLayer, function(attrs) {
        if (!attrs.name) return;
        labels.push({
            label: attrs.name,
            index: Number(attrs.index || 0),
            duration: normalizeDuration(attrs)
        });
    });
    labels.sort(function(a, b) { return a.index - b.index; });
    for (let i = 0; i < labels.length; i += 1) {
        labels[i].rangeStart = i === 0 ? 0 : labels[i].index;
        labels[i].rangeEnd = i < labels.length - 1 ? labels[i + 1].index - 1 : labels[i].index + labels[i].duration - 1;
    }
    return labels;
}

function labelForIndex(labels, index) {
    for (let i = labels.length - 1; i >= 0; i -= 1) {
        if (index >= labels[i].rangeStart) return labels[i].label;
    }
    return labels.length ? labels[0].label : '';
}

function labelsForRange(labels, index, duration) {
    const start = index;
    const end = index + Math.max(1, duration || 1) - 1;
    return labels.filter(function(label) {
        return start <= label.rangeEnd && end >= label.rangeStart;
    }).map(function(label) { return label.label; });
}

function findStageName(script) {
    const match = String(script || '').match(/配置关卡属性\("([^"]+)"\)/u);
    return match ? match[1] : '';
}

function findStageDetail(script) {
    const match = String(script || '').match(/(?:^|\n)\s*详细\s*=\s*"([^"]*)"/u);
    return match ? match[1] : '';
}

function findNavTarget(script) {
    let match = String(script || '').match(/_parent\.gotoAndStop\("([^"]+)"\)/u);
    if (match) return { targetFrameLabel: match[1], actionKind: 'localFrame' };
    match = String(script || '').match(/_root\.关卡地图帧值\s*=\s*"([^"]+)"/u);
    if (match) return { targetFrameLabel: match[1], actionKind: 'flashJumpFrameValue' };
    if (/淡出跳转帧/u.test(script || '')) return { targetFrameLabel: '', actionKind: 'flashJumpCurrent' };
    return null;
}

function hashText(text) {
    let hash = 2166136261;
    for (let i = 0; i < text.length; i += 1) {
        hash ^= text.charCodeAt(i);
        hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
}

function dedupeByKey(items, keyFn) {
    const seen = {};
    return (items || []).filter(function(item) {
        const key = keyFn(item);
        if (seen[key]) return false;
        seen[key] = true;
        return true;
    });
}

function backgroundAssetUrl(assetName) {
    return 'assets/stage-select/backgrounds/' + assetName;
}

function previewAssetUrl(assetName) {
    return 'assets/stage-select/previews/' + assetName;
}

function readMediaIndex() {
    const mediaXml = readUtf8(domDocumentPath);
    const byName = {};
    const re = /<DOMBitmapItem\b([^>]*)\/>/gu;
    let match;
    while ((match = re.exec(mediaXml))) {
        const attrs = attrsToObject(match[1]);
        if (!attrs.name) continue;
        const hrefIndex = parseMediaHrefIndex(attrs.bitmapDataHRef || '');
        byName[attrs.name] = {
            name: attrs.name,
            href: attrs.href || attrs.name,
            bitmapDataHRef: attrs.bitmapDataHRef || '',
            binPath: attrs.bitmapDataHRef ? path.join(sourceRoot, 'bin', attrs.bitmapDataHRef) : '',
            isJPEG: attrs.isJPEG === 'true' || /\.jpe?g$/i.test(attrs.href || attrs.name),
            extension: path.extname(attrs.href || attrs.name || '.jpg').toLowerCase() || '.jpg',
            width: round(Number(attrs.frameRight || 0) / 20),
            height: round(Number(attrs.frameBottom || 0) / 20),
            ffdecExportId: hrefIndex >= 2 && hrefIndex <= 84 ? (hrefIndex * 2 + 15) : (hrefIndex === 1 ? 1 : 0)
        };
    }
    return byName;
}

function parseMediaHrefIndex(href) {
    const match = String(href || '').match(/^M\s+(\d+)\s+/u);
    return match ? Number(match[1]) : 0;
}

function parsePreviewSourceFromFrame(frameBody) {
    let match = String(frameBody || '').match(/<BitmapFill\b([^>]*)>([\s\S]*?)<\/BitmapFill>/u);
    if (match) {
        const attrs = attrsToObject(match[1] || '');
        if (attrs.bitmapPath) {
            return {
                bitmapPath: attrs.bitmapPath,
                crop: parseBitmapFillCrop(frameBody, match[2])
            };
        }
    }
    match = String(frameBody || '').match(/<DOMBitmapInstance\b([^>]*)\/>|<DOMBitmapInstance\b([^>]*)>/u);
    if (match) {
        const attrs = attrsToObject(match[1] || match[2] || '');
        if (attrs.libraryItemName) {
            return {
                bitmapPath: attrs.libraryItemName,
                crop: null
            };
        }
    }
    return null;
}

function parseBitmapFillCrop(frameBody, fillBody) {
    const matrix = firstMatrixAttrs(fillBody || '');
    const bounds = parseShapeBounds(frameBody);
    const a = numberAttr(matrix, 'a', 20);
    const d = numberAttr(matrix, 'd', 20);
    const tx = numberAttr(matrix, 'tx', 0);
    const ty = numberAttr(matrix, 'ty', 0);
    if (!bounds || !a || !d) return null;
    return {
        x: Math.max(0, Math.floor((bounds.minX - tx) / a)),
        y: Math.max(0, Math.floor((bounds.minY - ty) / d)),
        w: Math.max(1, Math.round((bounds.maxX - bounds.minX) / a)),
        h: Math.max(1, Math.round((bounds.maxY - bounds.minY) / d))
    };
}

function parseShapeBounds(frameBody) {
    const match = String(frameBody || '').match(/<Edge\b[^>]*\bedges="([^"]*)"/u);
    if (!match) return null;
    const nums = match[1].match(/-?\d+(?:\.\d+)?/g);
    if (!nums || nums.length < 4) return null;
    const xs = [];
    const ys = [];
    for (let i = 0; i + 1 < nums.length; i += 2) {
        xs.push(Number(nums[i]));
        ys.push(Number(nums[i + 1]));
    }
    return {
        minX: Math.min.apply(Math, xs),
        maxX: Math.max.apply(Math, xs),
        minY: Math.min.apply(Math, ys),
        maxY: Math.max.apply(Math, ys)
    };
}

function buildPreviewIndex() {
    const xml = readUtf8(previewSymbolPath);
    const media = readMediaIndex();
    const labels = parseLabels(xml).filter(function(label) { return label.index > 0; });
    const frames = [];
    const layerRe = /<DOMLayer\b([^>]*)>([\s\S]*?)<\/DOMLayer>/gu;
    let layerMatch;
    while ((layerMatch = layerRe.exec(xml))) {
        eachFrame(layerMatch[0], function(frameAttrs, frameBody) {
            const source = parsePreviewSourceFromFrame(frameBody);
            if (!source || !source.bitmapPath) return;
            frames.push({
                index: Number(frameAttrs.index || 0),
                duration: normalizeDuration(frameAttrs),
                bitmapPath: source.bitmapPath,
                crop: source.crop,
                media: media[source.bitmapPath] || null
            });
        });
    }

    const byStage = {};
    labels.forEach(function(label) {
        const frame = frames.find(function(item) {
            return label.index >= item.index && label.index < item.index + item.duration;
        });
        if (!frame) return;
        byStage[label.label] = makeInternalPreviewEntry(label.label, frame, false);
    });

    const defaultFrame = frames.find(function(frame) { return frame.index === 1; }) || frames[0] || null;
    return {
        byStage: byStage,
        defaultEntry: defaultFrame ? makeInternalPreviewEntry('_default', defaultFrame, true) : null
    };
}

function makeInternalPreviewEntry(stageName, frame, isDefault) {
    const media = frame.media || {};
    const ext = media.extension || path.extname(frame.bitmapPath) || '.jpg';
    return {
        source: isDefault ? 'default' : 'internal',
        assetName: (isDefault ? 'stage-default' : 'stage-internal-' + hashText(stageName)) + ext,
        sourcePath: frame.bitmapPath,
        sourceFrameIndex: frame.index,
        width: media.width || 161,
        height: media.height || 69,
        crop: frame.crop || null,
        isJPEG: !!media.isJPEG,
        binPath: media.binPath || '',
        ffdecExportId: media.ffdecExportId || 0
    };
}

function resolvePreview(stageName, previewIndex) {
    const external = path.join(previewRoot, stageName + '.png');
    if (fs.existsSync(external)) {
        return {
            previewUrl: previewAssetUrl(previewAssetName(stageName)),
            previewAssetName: previewAssetName(stageName),
            previewSource: 'external',
            previewSourcePath: 'flashswf/images/关卡预览图/' + stageName + '.png',
            previewMissing: false
        };
    }
    const entry = previewIndex.byStage[stageName] || previewIndex.defaultEntry;
    if (entry) {
        return {
            previewUrl: previewAssetUrl(entry.assetName),
            previewAssetName: entry.assetName,
            previewSource: entry.source,
            previewSourcePath: entry.sourcePath,
            previewSourceFrameIndex: entry.sourceFrameIndex,
            previewCrop: entry.crop,
            previewMissing: false
        };
    }
    return {
        previewUrl: previewAssetUrl('_missing-preview.svg'),
        previewAssetName: '_missing-preview.svg',
        previewSource: 'missing',
        previewSourcePath: '',
        previewMissing: true
    };
}

function parseBackgroundForFrame(frameBody) {
    let match = String(frameBody || '').match(/<DOMBitmapInstance\b([^>]*)>([\s\S]*?)<\/DOMBitmapInstance>|<DOMBitmapInstance\b([^>]*)\/>/u);
    if (match) {
        const attrs = attrsToObject(match[1] || match[3] || '');
        const matrix = firstMatrixAttrs(match[2] || '');
        return {
            type: 'bitmap',
            libraryItemName: attrs.libraryItemName || '',
            matrix: {
                a: numberAttr(matrix, 'a', 1),
                d: numberAttr(matrix, 'd', 1),
                tx: numberAttr(matrix, 'tx', 0),
                ty: numberAttr(matrix, 'ty', 0)
            }
        };
    }
    match = String(frameBody || '').match(/<BitmapFill\b([^>]*)>/u);
    if (match) {
        const attrs = attrsToObject(match[1] || '');
        return {
            type: 'embeddedBitmapFill',
            bitmapPath: attrs.bitmapPath || ''
        };
    }
    match = String(frameBody || '').match(/<DOMSymbolInstance\b([^>]*)>/u);
    if (match) {
        const attrs = attrsToObject(match[1] || '');
        if (attrs.libraryItemName && attrs.libraryItemName.indexOf('shape/') === 0) {
            return {
                type: 'shape',
                libraryItemName: attrs.libraryItemName
            };
        }
    }
    return null;
}

function buildManifest() {
    const xml = readUtf8(mainSymbolPath);
    const labels = parseLabels(xml);
    const previewIndex = buildPreviewIndex();
    const frameMap = {};
    labels.forEach(function(label) {
        frameMap[label.label] = {
            frameLabel: label.label,
            sourceFrameIndex: label.index,
            sourceDuration: label.duration,
            background: null,
            stageButtons: [],
            navButtons: []
        };
    });

    const layerRe = /<DOMLayer\b([^>]*)>([\s\S]*?)<\/DOMLayer>/gu;
    let layerMatch;
    let sourceStageButtonCount = 0;
    let sourceNavButtonCount = 0;
    const uniqueStages = {};
    const backgroundsByLabel = {};

    while ((layerMatch = layerRe.exec(xml))) {
        const layerAttrs = attrsToObject(layerMatch[1]);
        const layerName = layerAttrs.name || '';
        if (layerName === 'Labels Layer' || layerName === 'Script Layer') continue;
        eachFrame(layerMatch[0], function(frameAttrs, frameBody) {
            const sourceFrameIndex = Number(frameAttrs.index || 0);
            const duration = normalizeDuration(frameAttrs);
            const frameLabel = labelForIndex(labels, sourceFrameIndex);
            const background = parseBackgroundForFrame(frameBody);
            if (background) {
                labelsForRange(labels, sourceFrameIndex, duration).forEach(function(label) {
                    if (!backgroundsByLabel[label]) backgroundsByLabel[label] = background;
                });
            }

            eachSymbol(frameBody, function(instanceAttrs, instanceBody) {
                const libraryItemName = instanceAttrs.libraryItemName || '';
                const matrix = firstMatrixAttrs(instanceBody);
                const x = numberAttr(matrix, 'tx', 0);
                const y = numberAttr(matrix, 'ty', 0);
                const centerX = numberAttr(instanceAttrs, 'centerPoint3DX', x);
                const centerY = numberAttr(instanceAttrs, 'centerPoint3DY', y);
                const scriptMatch = String(instanceBody || '').match(/<script><!\[CDATA\[([\s\S]*?)\]\]><\/script>/u);
                const script = scriptMatch ? scriptMatch[1] : '';

                if (libraryItemName === '选关界面UI/选关按钮') {
                    const stageName = findStageName(script);
                    const preview = resolvePreview(stageName, previewIndex);
                    sourceStageButtonCount += 1;
                    uniqueStages[stageName] = true;
                    frameMap[frameLabel].stageButtons.push({
                        id: 'stage_' + sourceFrameIndex + '_' + frameMap[frameLabel].stageButtons.length,
                        frameLabel: frameLabel,
                        stageName: stageName,
                        detail: findStageDetail(script),
                        x: round(x),
                        y: round(y),
                        centerX: round(centerX),
                        centerY: round(centerY),
                        sourceFrameIndex: sourceFrameIndex,
                        previewUrl: preview.previewUrl,
                        previewAssetName: preview.previewAssetName,
                        previewSource: preview.previewSource,
                        previewSourcePath: preview.previewSourcePath,
                        previewSourceFrameIndex: preview.previewSourceFrameIndex,
                        previewCrop: preview.previewCrop,
                        previewMissing: preview.previewMissing
                    });
                    return;
                }

                const nav = findNavTarget(script);
                if (nav) {
                    sourceNavButtonCount += 1;
                    frameMap[frameLabel].navButtons.push({
                        id: 'nav_' + sourceFrameIndex + '_' + frameMap[frameLabel].navButtons.length,
                        frameLabel: frameLabel,
                        label: nav.targetFrameLabel || '返回',
                        x: round(x),
                        y: round(y),
                        centerX: round(centerX),
                        centerY: round(centerY),
                        sourceFrameIndex: sourceFrameIndex,
                        libraryItemName: libraryItemName,
                        targetFrameLabel: nav.targetFrameLabel,
                        actionKind: nav.actionKind
                    });
                }
            });
        });
    }

    Object.keys(frameMap).forEach(function(frameLabel) {
        frameMap[frameLabel].background = resolveBackground(frameLabel, backgroundsByLabel[frameLabel]);
        frameMap[frameLabel].stageButtons = dedupeByKey(frameMap[frameLabel].stageButtons, function(button) {
            return [button.stageName, button.x, button.y].join('|');
        });
        frameMap[frameLabel].navButtons = dedupeByKey(frameMap[frameLabel].navButtons, function(button) {
            return [button.label, button.x, button.y, button.targetFrameLabel, button.actionKind].join('|');
        });
    });

    const frames = labels.map(function(label) { return frameMap[label.label]; });
    const stageNames = Object.keys(uniqueStages).filter(Boolean).sort(function(a, b) { return a.localeCompare(b, 'zh-CN'); });
    const assetReport = buildAssetReport(frames, stageNames, sourceStageButtonCount, sourceNavButtonCount, previewIndex);
    return {
        version: 1,
        schema: 'stage-select-manifest-v1',
        designSize: { width: 1024, height: 576 },
        sourceRefs: {
            xflDir: 'flashswf/UI/选关界面',
            mainSymbol: 'flashswf/UI/选关界面/LIBRARY/选关界面UI/选关界面 1024&#042576.xml',
            buttonSymbol: 'flashswf/UI/选关界面/LIBRARY/选关界面UI/选关按钮.xml',
            previewDir: 'flashswf/images/关卡预览图',
            ffdecCli: 'tools/ffdec/ffdec-cli.exe'
        },
        frameOrder: frames.map(function(frame) { return frame.frameLabel; }),
        frames: frames,
        stageNames: stageNames,
        assetReport: assetReport,
        fixtures: buildFixtures(frames, stageNames)
    };
}

function resolveBackground(frameLabel, source) {
    if (source && source.type === 'bitmap' && backgroundNames[source.libraryItemName]) {
        const assetName = backgroundNames[source.libraryItemName];
        return {
            type: 'image',
            mode: 'direct',
            assetUrl: backgroundAssetUrl(assetName),
            assetName: assetName,
            sourcePath: 'flashswf/UI/选关界面/LIBRARY/' + source.libraryItemName,
            sourceType: source.type,
            matrix: source.matrix,
            rect: buildDirectBackgroundRect(source.libraryItemName, source.matrix)
        };
    }
    const fallback = fallbackBackgroundByFrame[frameLabel];
    if (fallback) {
        return {
            type: 'image',
            mode: 'derived',
            assetUrl: backgroundAssetUrl(fallback.assetName),
            assetName: fallback.assetName,
            sourcePath: fallback.sourcePath,
            sourceType: source ? source.type : 'missing',
            exportId: fallback.exportId,
            exportedImage: fallback.exportedImage,
            rect: fallback.rect,
            reason: fallback.reason
        };
    }
    return {
        type: 'image',
        mode: 'missing',
        assetUrl: '',
        assetName: '',
        sourcePath: '',
        sourceType: source ? source.type : 'missing',
        reason: 'no source background mapped'
    };
}

function buildDirectBackgroundRect(libraryItemName, matrix) {
    const source = path.join(libraryRoot, libraryItemName || '');
    const dim = readImageSize(source) || { width: 1024, height: 576 };
    const sx = Number.isFinite(matrix && matrix.a) ? matrix.a : 1;
    const sy = Number.isFinite(matrix && matrix.d) ? matrix.d : 1;
    const tx = Number.isFinite(matrix && matrix.tx) ? matrix.tx : 0;
    const ty = Number.isFinite(matrix && matrix.ty) ? matrix.ty : 0;
    return {
        x: round(tx),
        y: round(ty),
        w: round(dim.width * sx),
        h: round(dim.height * sy)
    };
}

function readImageSize(filePath) {
    if (!filePath || !fs.existsSync(filePath)) return null;
    const buffer = fs.readFileSync(filePath);
    if (buffer.length >= 24 && buffer.readUInt32BE(0) === 0x89504e47) {
        return {
            width: buffer.readUInt32BE(16),
            height: buffer.readUInt32BE(20)
        };
    }
    if (buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
        let offset = 2;
        while (offset < buffer.length) {
            if (buffer[offset] !== 0xff) {
                offset += 1;
                continue;
            }
            const marker = buffer[offset + 1];
            const length = buffer.readUInt16BE(offset + 2);
            if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
                return {
                    width: buffer.readUInt16BE(offset + 7),
                    height: buffer.readUInt16BE(offset + 5)
                };
            }
            offset += 2 + length;
        }
    }
    return null;
}

function buildAssetReport(frames, stageNames, sourceStageButtonCount, sourceNavButtonCount, previewIndex) {
    const backgroundMissing = [];
    const backgroundFallbacks = [];
    const derivedBackgrounds = [];
    const previewSources = {
        external: 0,
        internal: 0,
        default: 0,
        missing: 0
    };
    frames.forEach(function(frame) {
        if (!frame.background || frame.background.mode === 'missing') backgroundMissing.push(frame.frameLabel);
        if (frame.background && frame.background.mode === 'fallback') {
            backgroundFallbacks.push({ frameLabel: frame.frameLabel, reason: frame.background.reason });
        }
        if (frame.background && frame.background.mode === 'derived') {
            derivedBackgrounds.push({ frameLabel: frame.frameLabel, assetName: frame.background.assetName, reason: frame.background.reason });
        }
    });

    const previewMissing = stageNames.filter(function(stageName) {
        const preview = resolvePreview(stageName, previewIndex);
        previewSources[preview.previewSource] = (previewSources[preview.previewSource] || 0) + 1;
        return preview.previewMissing;
    });

    return {
        labels: frames.length,
        sourceStageButtonInstances: sourceStageButtonCount,
        sourceNavButtonInstances: sourceNavButtonCount,
        uniqueStageNames: stageNames.length,
        backgroundMissing: backgroundMissing,
        backgroundFallbacks: backgroundFallbacks,
        derivedBackgrounds: derivedBackgrounds,
        previewMissing: previewMissing,
        previewSources: previewSources,
        previewFallbacks: previewSources.internal + previewSources.default
    };
}

function previewAssetName(stageName) {
    const source = path.join(previewRoot, stageName + '.png');
    if (!fs.existsSync(source)) return '_missing-preview.svg';
    return 'stage-' + hashText(stageName) + '.png';
}

function round(value) {
    return Math.round(Number(value || 0) * 100) / 100;
}

function buildFixtures(frames, stageNames) {
    const allUnlocked = {};
    const mixed = {};
    const challenge = {};
    const difficulties = ['简单', '冒险', '修罗', '地狱'];
    const firstSeenOrder = [];
    const firstSeenIndex = {};
    frames.forEach(function(frame) {
        (frame.stageButtons || []).forEach(function(button) {
            const stageName = button.stageName || '';
            if (!stageName || firstSeenIndex[stageName] !== undefined) return;
            firstSeenIndex[stageName] = firstSeenOrder.length;
            firstSeenOrder.push(stageName);
        });
    });
    stageNames.forEach(function(stageName, index) {
        const stageIndex = firstSeenIndex[stageName] !== undefined ? firstSeenIndex[stageName] : index;
        allUnlocked[stageName] = {
            unlocked: true,
            task: false,
            highestDifficulty: '简单',
            detail: ''
        };
        const locked = stageIndex > 18 && stageIndex % 5 === 0;
        mixed[stageName] = {
            unlocked: !locked,
            task: !locked && stageIndex % 7 === 0,
            highestDifficulty: difficulties[stageIndex % difficulties.length],
            detail: ''
        };
        challenge[stageName] = {
            unlocked: true,
            task: stageIndex % 6 === 0,
            highestDifficulty: '地狱',
            detail: ''
        };
    });
    return {
        allUnlocked: { name: 'allUnlocked', challenge: false, stages: allUnlocked },
        mixed: { name: 'mixed', challenge: false, stages: mixed },
        challenge: { name: 'challenge', challenge: true, stages: challenge }
    };
}

function ensureDir(dir) {
    fs.mkdirSync(dir, { recursive: true });
}

function copyAssets(manifest) {
    const backgroundDir = path.join(webAssetRoot, 'backgrounds');
    const previewDir = path.join(webAssetRoot, 'previews');
    ensureDir(backgroundDir);
    ensureDir(previewDir);

    Object.keys(backgroundNames).forEach(function(sourceName) {
        const targetName = backgroundNames[sourceName];
        const source = path.join(libraryRoot, sourceName);
        const target = path.join(backgroundDir, targetName);
        if (!fs.existsSync(source)) return;
        if (/\.jpg$/i.test(targetName)) {
            convertToJpeg(source, target);
        } else {
            fs.copyFileSync(source, target);
        }
    });

    copyEmbeddedBackgroundAssets(backgroundDir);

    fs.writeFileSync(path.join(previewDir, '_missing-preview.svg'), missingPreviewSvg(), 'utf8');
    manifest.stageNames.forEach(function(stageName) {
        const source = path.join(previewRoot, stageName + '.png');
        if (!fs.existsSync(source)) return;
        fs.copyFileSync(source, path.join(previewDir, previewAssetName(stageName)));
    });
    copyInternalPreviewAssets(manifest, previewDir);
}

function copyInternalPreviewAssets(manifest, previewDir) {
    const media = readMediaIndex();
    const needed = {};
    (manifest.frames || []).forEach(function(frame) {
        (frame.stageButtons || []).forEach(function(button) {
            if (button.previewSource !== 'internal' && button.previewSource !== 'default') return;
            if (!button.previewAssetName || !button.previewSourcePath) return;
            needed[button.previewAssetName] = {
                assetName: button.previewAssetName,
                sourcePath: button.previewSourcePath,
                crop: button.previewCrop || null
            };
        });
    });

    const losslessByExportId = {};
    Object.keys(needed).forEach(function(assetName) {
        const item = needed[assetName];
        const bitmap = media[item.sourcePath];
        if (!bitmap || !bitmap.binPath || !fs.existsSync(bitmap.binPath)) return;
        const target = path.join(previewDir, assetName);
        if (bitmap.isJPEG && hasMagic(bitmap.binPath, [0xff, 0xd8, 0xff])) {
            if (item.crop) {
                cropImage(bitmap.binPath, target, item.crop);
                return;
            }
            fs.copyFileSync(bitmap.binPath, target);
            return;
        }
        if (hasMagic(bitmap.binPath, [0x89, 0x50, 0x4e, 0x47])) {
            fs.copyFileSync(bitmap.binPath, target);
            return;
        }
        if (bitmap.ffdecExportId) {
            losslessByExportId[String(bitmap.ffdecExportId)] = {
                assetName: assetName,
                extension: bitmap.extension || '.png'
            };
            return;
        }
        fs.writeFileSync(target, missingPreviewSvg(), 'utf8');
    });

    const ids = Object.keys(losslessByExportId).sort(function(a, b) { return Number(a) - Number(b); });
    if (!ids.length) return;
    const java = resolveJava();
    const tempDir = path.join(projectRoot, 'tmp_ffdec_stage_select_preview_export');
    if (fs.existsSync(tempDir)) {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
    const result = childProcess.spawnSync(java, [
        '-jar', ffdecJar,
        '-format', 'image:png_gif_jpeg',
        '-selectid', ids.join(','),
        '-export', 'image',
        tempDir,
        sourceSwf
    ], { encoding: 'utf8' });
    if (result.status !== 0) {
        throw new Error('FFDec internal preview export failed: ' + (result.stderr || result.stdout || result.error || 'unknown error'));
    }
    ids.forEach(function(id) {
        const entry = losslessByExportId[id];
        const exported = firstExisting(path.join(tempDir, id + '.png'), path.join(tempDir, id + '.jpg'), path.join(tempDir, id + '.gif'));
        if (!exported) {
            throw new Error('Missing FFDec exported internal preview image for character id ' + id);
        }
        fs.copyFileSync(exported, path.join(previewDir, entry.assetName));
    });
}

function firstExisting() {
    for (let i = 0; i < arguments.length; i += 1) {
        if (fs.existsSync(arguments[i])) return arguments[i];
    }
    return '';
}

function hasMagic(filePath, bytes) {
    if (!filePath || !fs.existsSync(filePath)) return false;
    const buffer = fs.readFileSync(filePath);
    if (buffer.length < bytes.length) return false;
    for (let i = 0; i < bytes.length; i += 1) {
        if (buffer[i] !== bytes[i]) return false;
    }
    return true;
}

function copyEmbeddedBackgroundAssets(backgroundDir) {
    const exportEntries = {};
    Object.keys(fallbackBackgroundByFrame).forEach(function(frameLabel) {
        const entry = fallbackBackgroundByFrame[frameLabel];
        exportEntries[String(entry.exportId)] = entry;
    });
    const ids = Object.keys(exportEntries).sort(function(a, b) { return Number(a) - Number(b); });
    if (!ids.length) return;

    const java = resolveJava();
    const tempDir = path.join(projectRoot, 'tmp_ffdec_stage_select_image_export');
    if (fs.existsSync(tempDir)) {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
    const result = childProcess.spawnSync(java, [
        '-jar', ffdecJar,
        '-format', 'image:png_gif_jpeg',
        '-selectid', ids.join(','),
        '-export', 'image',
        tempDir,
        sourceSwf
    ], { encoding: 'utf8' });
    if (result.status !== 0) {
        throw new Error('FFDec embedded background export failed: ' + (result.stderr || result.stdout || result.error || 'unknown error'));
    }
    ids.forEach(function(id) {
        const entry = exportEntries[id];
        const source = path.join(tempDir, entry.exportedImage);
        if (!fs.existsSync(source)) {
            throw new Error('Missing FFDec exported image: ' + path.relative(projectRoot, source));
        }
        fs.copyFileSync(source, path.join(backgroundDir, entry.assetName));
    });
}

function resolveJava() {
    if (process.env.JAVA_EXE && fs.existsSync(process.env.JAVA_EXE)) return process.env.JAVA_EXE;
    const candidates = [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Adobe', 'Adobe Animate 2024', 'jre', 'bin', 'java.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Common Files', 'Adobe', 'Adobe Flash CS6', 'jre', 'bin', 'java.exe')
    ];
    for (let i = 0; i < candidates.length; i += 1) {
        if (fs.existsSync(candidates[i])) return candidates[i];
    }
    const probe = childProcess.spawnSync('java', ['-version'], { encoding: 'utf8' });
    if (probe.status === 0 || probe.stderr || probe.stdout) return 'java';
    throw new Error('No Java runtime found. Set JAVA_EXE or install a JRE for FFDec export.');
}

function convertToJpeg(source, target) {
    const ffmpeg = childProcess.spawnSync('ffmpeg', [
        '-y',
        '-hide_banner',
        '-loglevel', 'error',
        '-i', source,
        '-vf', 'scale=1024:-2',
        '-q:v', '4',
        target
    ], { encoding: 'utf8' });
    if (ffmpeg.status !== 0) {
        throw new Error('ffmpeg failed for ' + path.relative(projectRoot, source) + ': ' + (ffmpeg.stderr || ffmpeg.error || 'unknown error'));
    }
}

function cropImage(source, target, crop) {
    const filter = 'crop=' + [
        Math.max(1, Math.round(crop.w || 1)),
        Math.max(1, Math.round(crop.h || 1)),
        Math.max(0, Math.round(crop.x || 0)),
        Math.max(0, Math.round(crop.y || 0))
    ].join(':');
    const args = [
        '-y',
        '-hide_banner',
        '-loglevel', 'error',
        '-i', source,
        '-vf', filter
    ];
    if (/\.jpe?g$/i.test(target)) {
        args.push('-q:v', '4');
    }
    args.push(target);
    const ffmpeg = childProcess.spawnSync('ffmpeg', args, { encoding: 'utf8' });
    if (ffmpeg.status !== 0) {
        throw new Error('ffmpeg crop failed for ' + path.relative(projectRoot, source) + ': ' + (ffmpeg.stderr || ffmpeg.error || 'unknown error'));
    }
}

function missingPreviewSvg() {
    return '<svg xmlns="http://www.w3.org/2000/svg" width="180" height="108" viewBox="0 0 180 108">' +
        '<defs><linearGradient id="g" x1="0" x2="1" y1="0" y2="1"><stop stop-color="#1f2937"/><stop offset="1" stop-color="#0f172a"/></linearGradient></defs>' +
        '<rect width="180" height="108" fill="url(#g)"/><rect x="8" y="8" width="164" height="92" fill="none" stroke="#64748b" stroke-width="2"/>' +
        '<text x="90" y="50" fill="#e5e7eb" font-family="Arial,sans-serif" font-size="14" text-anchor="middle">NO PREVIEW</text>' +
        '<text x="90" y="70" fill="#94a3b8" font-family="Arial,sans-serif" font-size="11" text-anchor="middle">stage-select fixture</text></svg>\n';
}

function writeModule(manifest) {
    const source = 'var StageSelectData = (function() {\n' +
        '    \'use strict\';\n\n' +
        '    var manifest = ' + JSON.stringify(manifest, null, 4).replace(/\n/g, '\n    ') + ';\n\n' +
        '    function clone(value) { return JSON.parse(JSON.stringify(value)); }\n' +
        '    function getManifest() { return manifest; }\n' +
        '    function getFrame(label) {\n' +
        '        var frames = manifest.frames || [];\n' +
        '        var i;\n' +
        '        for (i = 0; i < frames.length; i += 1) if (frames[i].frameLabel === label) return frames[i];\n' +
        '        return frames.length ? frames[0] : null;\n' +
        '    }\n' +
        '    function getFixture(name) {\n' +
        '        var fixtures = manifest.fixtures || {};\n' +
        '        return clone(fixtures[name] || fixtures.mixed || fixtures.allUnlocked || { name: name || \'\', challenge: false, stages: {} });\n' +
        '    }\n' +
        '    function exportManifest() { return clone(manifest); }\n\n' +
        '    return {\n' +
        '        getManifest: getManifest,\n' +
        '        getFrame: getFrame,\n' +
        '        getFixture: getFixture,\n' +
        '        exportManifest: exportManifest\n' +
        '    };\n' +
        '})();\n';
    fs.writeFileSync(moduleOutput, source, 'utf8');
}

function buildSummary(manifest) {
    return {
        schema: manifest.schema,
        labels: manifest.assetReport.labels,
        sourceStageButtonInstances: manifest.assetReport.sourceStageButtonInstances,
        uniqueStageNames: manifest.assetReport.uniqueStageNames,
        backgroundMissing: manifest.assetReport.backgroundMissing.length,
        backgroundFallbacks: manifest.assetReport.backgroundFallbacks.length,
        derivedBackgrounds: manifest.assetReport.derivedBackgrounds.length,
        previewMissing: manifest.assetReport.previewMissing.length,
        previewSources: manifest.assetReport.previewSources
    };
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;
    const manifest = buildManifest();
    if (args.copyAssets) copyAssets(manifest);
    if (args.writeModule) writeModule(manifest);
    const json = JSON.stringify(manifest, null, 2) + '\n';
    if (args.output) {
        const output = path.resolve(projectRoot, args.output);
        ensureDir(path.dirname(output));
        fs.writeFileSync(output, json, 'utf8');
    } else if (!args.writeModule) {
        process.stdout.write(json);
    }
    if (args.summary) {
        console.error('[stage-select-manifest] summary ' + JSON.stringify(buildSummary(manifest)));
    }
}

main();
