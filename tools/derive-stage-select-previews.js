#!/usr/bin/env node
'use strict';

// 选关界面 hover 预览派生工具（P4-b，2026-08-16）。
//
// 目的：压降 stage-select-data.js 中 previewSource='default'（通用占位帧）的覆盖率。
// 映射链（与 AS2 运行时一致，对照 scripts/类定义/org/flashNight/gesh/xml/LoadXml/StageInfoLoader.as）：
//   关卡名 → data/stages/list.xml 有序区域 → <区域>/__list__.xml 的 StageInfo（同名后者覆盖前者）
//          → data/stages/<区域>/<Name>.xml 首个 <SubStage> 的 <BasicInformation>/<Background>
//          → 背景 SWF 经 FFDec 导出 frame 1（主视觉帧）
//          → ffmpeg 按 161:69 取景窗裁剪并缩放为 161×69 JPEG
//            （取景窗非死中心：在模糊后的 64×64 灰度网格上滑窗取细节最丰富条带，
//              含近黑/近白未绘制区的窗扣分；同等平淡时回退居中）
//          → 写入 launcher/web/assets/stage-select/previews/derived/stage-derived-<fnv1a(关卡名)>.jpg
//
// 质量门（宁可留 default，不出假预览）：任一环节失败即保留 default 并记录原因——
//   stage-info-missing / stage-xml-missing / no-background / background-not-swf /
//   background-swf-missing / ffdec-export-failed / image-size-anomaly / image-anomaly。
// 环境缺 JRE 或 ffdec.jar 时明确报错并整体退出（exit 2），不静默跳过、不写任何文件。
//
// 用法：
//   node tools/derive-stage-select-previews.js [--json] [--report <file>] [--limit N] [--only 名1,名2]
//   node tools/derive-stage-select-previews.js --write   # 追加精准回写 stage-select-data.js（改前自动备份到 tmp/）
// 默认全量派生 + 写资产 + 出报告，不动 manifest；--write 才逐按钮字段替换（不整文件重排）。
// 报告同时产出 stage→background 索引（report.stageBackgroundIndex），供 P5 三维沙盘参考包复用。

const fs = require('fs');
const path = require('path');
const vm = require('vm');
const childProcess = require('child_process');

const projectRoot = path.resolve(__dirname, '..');
const dataFile = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-data.js');
const stagesRoot = path.join(projectRoot, 'data', 'stages');
const stageListPath = path.join(stagesRoot, 'list.xml');
const ffdecJar = path.join(projectRoot, 'tools', 'ffdec', 'ffdec.jar');
const derivedAssetDir = path.join(projectRoot, 'launcher', 'web', 'assets', 'stage-select', 'previews', 'derived');
const derivedAssetUrlPrefix = 'assets/stage-select/previews/derived/';
const workRoot = path.join(projectRoot, 'tmp', 'stage-select-preview-derive');

const PREVIEW_WIDTH = 161;
const PREVIEW_HEIGHT = 69;
const PREVIEW_ASPECT = PREVIEW_WIDTH / PREVIEW_HEIGHT;
const MIN_SOURCE_DIMENSION = 32;
const LUMA_STDDEV_MIN = 4;
const LUMA_MEAN_MIN = 6;
const LUMA_MEAN_MAX = 249;
const JPEG_QUALITY = 4;

function parseArgs(argv) {
    const args = {
        write: false,
        json: false,
        report: '',
        limit: 0,
        only: null
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--write') {
            args.write = true;
        } else if (arg === '--json') {
            args.json = true;
        } else if (arg === '--report') {
            args.report = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--limit') {
            args.limit = Math.max(0, Number(argv[i + 1]) || 0);
            i += 1;
        } else if (arg === '--only') {
            args.only = String(argv[i + 1] || '').split(',').map(function(s) { return s.trim(); }).filter(Boolean);
            i += 1;
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
    console.error('usage: node tools/derive-stage-select-previews.js [--write] [--json] [--report <file>] [--limit N] [--only 名1,名2]');
    process.exit(exitCode);
}

function readUtf8(filePath) {
    return fs.readFileSync(filePath, 'utf8').replace(/^﻿/, '');
}

function escapeRegExp(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function decodeXml(value) {
    return String(value || '')
        .replace(/&#x([0-9a-f]+);/gi, function(_, hex) { return String.fromCharCode(parseInt(hex, 16)); })
        .replace(/&#([0-9]+);/g, function(_, dec) { return String.fromCharCode(parseInt(dec, 10)); })
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
}

function readSimpleXmlTag(body, tagName) {
    const match = String(body || '').match(new RegExp('<' + escapeRegExp(tagName) + '\\b[^>]*>([\\s\\S]*?)<\\/' + escapeRegExp(tagName) + '>|<' + escapeRegExp(tagName) + '\\b[^>]*/>', 'u'));
    if (!match) return '';
    return decodeXml(String(match[1] || '').replace(/<[^>]+>/gu, '').trim());
}

// 与 tools/export-stage-select-manifest.js 相同的 FNV-1a 命名，保持资产命名族一致。
function hashText(text) {
    let hash = 2166136261;
    for (let i = 0; i < text.length; i++) {
        hash ^= text.charCodeAt(i);
        hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16).padStart(8, '0');
}

function loadManifest() {
    const sandbox = { console };
    vm.createContext(sandbox);
    vm.runInContext(fs.readFileSync(dataFile, 'utf8'), sandbox, { filename: dataFile });
    if (!sandbox.StageSelectData) throw new Error('StageSelectData not found in ' + dataFile);
    return sandbox.StageSelectData.exportManifest();
}

// StageInfo 索引：先按 data/stages/list.xml 有序区域加载（同名后者覆盖前者，镜像
// StageInfoLoader.mergeStageInfo 的 acc[info.Name]=info），再补扫 list.xml 未列目录。
function readStageInfoIndex() {
    const byName = {};
    const areaOrder = [];
    const seenArea = {};
    if (fs.existsSync(stageListPath)) {
        const xml = readUtf8(stageListPath);
        const re = /<stages\b[^>]*>([\s\S]*?)<\/stages>/gu;
        let match;
        while ((match = re.exec(xml))) {
            const area = decodeXml(String(match[1] || '').trim());
            if (area && !seenArea[area]) {
                seenArea[area] = true;
                areaOrder.push(area);
            }
        }
    }
    if (fs.existsSync(stagesRoot)) {
        fs.readdirSync(stagesRoot, { withFileTypes: true }).forEach(function(entry) {
            if (entry.isDirectory() && !seenArea[entry.name]) {
                seenArea[entry.name] = true;
                areaOrder.push(entry.name);
            }
        });
    }
    areaOrder.forEach(function(area) {
        const listPath = path.join(stagesRoot, area, '__list__.xml');
        if (!fs.existsSync(listPath)) return;
        const xml = readUtf8(listPath);
        const re = /<StageInfo>([\s\S]*?)<\/StageInfo>/gu;
        let match;
        while ((match = re.exec(xml))) {
            const body = match[1] || '';
            const name = readSimpleXmlTag(body, 'Name');
            if (!name) continue;
            byName[name] = {
                name: name,
                area: area,
                type: readSimpleXmlTag(body, 'Type'),
                url: path.join(stagesRoot, area, name + '.xml')
            };
        }
    });
    return byName;
}

// 单关 XML → 首个 <SubStage> 的 <BasicInformation>/<Background>。
function findFirstBackground(stageXml) {
    const subStage = String(stageXml || '').match(/<SubStage\b[^>]*>[\s\S]*?<\/SubStage>/u);
    if (!subStage) return '';
    const basic = subStage[0].match(/<BasicInformation>[\s\S]*?<\/BasicInformation>/u);
    if (!basic) return '';
    const bg = basic[0].match(/<Background>([\s\S]*?)<\/Background>/u);
    return bg ? decodeXml(String(bg[1] || '').trim()) : '';
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
    return '';
}

function readPngSize(filePath) {
    const buffer = fs.readFileSync(filePath);
    if (buffer.length < 24 || buffer.readUInt32BE(0) !== 0x89504e47) return null;
    return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
}

// FFDec 导出背景 SWF 的 frame 1 主视觉帧；同一 SWF 在一次运行内只导一次。
function exportBackgroundFrame(java, swfPath, cache) {
    const key = swfPath;
    if (Object.prototype.hasOwnProperty.call(cache, key)) return cache[key];
    const outDir = path.join(workRoot, 'frames', hashText(path.relative(projectRoot, swfPath)));
    fs.rmSync(outDir, { recursive: true, force: true });
    fs.mkdirSync(outDir, { recursive: true });
    const result = childProcess.spawnSync(java, [
        '-jar', ffdecJar,
        '-format', 'frame:png',
        '-export', 'frame',
        outDir,
        swfPath
    ], { encoding: 'utf8' });
    let entry;
    if (result.status !== 0) {
        entry = { ok: false, error: 'ffdec exit ' + result.status + ': ' + String(result.stderr || result.stdout || result.error || 'unknown').trim().slice(0, 300) };
    } else {
        const framePath = path.join(outDir, '1.png');
        if (!fs.existsSync(framePath)) {
            entry = { ok: false, error: 'ffdec produced no 1.png' };
        } else {
            entry = { ok: true, framePath: framePath };
        }
    }
    cache[key] = entry;
    return entry;
}

const PROBE_GRID = 64;
// 行/列均分带里近黑 / 近白（未绘制区）的惩罚权重：防止取景窗被「黑→白」边界的高对比吸引。
const EXTREME_ROW_PENALTY = 25;

// 像素探针：64×64 灰度网格 + 全局亮度统计，供异常检测与取景窗打分共用。
function probeImage(framePath) {
    const size = readPngSize(framePath);
    if (!size) return { ok: false, reason: 'image-size-anomaly', detail: 'not a png: ' + path.basename(framePath) };
    if (size.width < MIN_SOURCE_DIMENSION || size.height < MIN_SOURCE_DIMENSION) {
        return { ok: false, reason: 'image-size-anomaly', detail: size.width + 'x' + size.height + ' < ' + MIN_SOURCE_DIMENSION };
    }
    const probe = childProcess.spawnSync('ffmpeg', [
        '-y', '-hide_banner', '-loglevel', 'error',
        '-i', framePath,
        '-vf', 'scale=' + PROBE_GRID + ':' + PROBE_GRID,
        '-f', 'rawvideo', '-pix_fmt', 'rgba',
        'pipe:1'
    ], { encoding: 'buffer', maxBuffer: PROBE_GRID * PROBE_GRID * 4 * 2 });
    if (probe.status !== 0 || !probe.stdout || probe.stdout.length < PROBE_GRID * PROBE_GRID * 4) {
        return { ok: false, reason: 'image-anomaly', detail: 'ffmpeg pixel probe failed: ' + String(probe.stderr || probe.error || '').toString().slice(0, 200) };
    }
    const px = probe.stdout;
    const luma = new Float64Array(PROBE_GRID * PROBE_GRID);
    let sum = 0;
    let sumSq = 0;
    for (let i = 0; i < PROBE_GRID * PROBE_GRID; i += 1) {
        const o = i * 4;
        const v = 0.299 * px[o] + 0.587 * px[o + 1] + 0.114 * px[o + 2];
        luma[i] = v;
        sum += v;
        sumSq += v * v;
    }
    const mean = sum / (PROBE_GRID * PROBE_GRID);
    const stddev = Math.sqrt(Math.max(0, sumSq / (PROBE_GRID * PROBE_GRID) - mean * mean));
    return { ok: true, width: size.width, height: size.height, luma: luma, lumaMean: mean, lumaStddev: stddev };
}

// 图像异常检测：尺寸过小 / 近纯色 / 近全黑 / 近全白一律视为不可信。
function analyzeProbe(probe) {
    if (!probe.ok) return probe;
    if (probe.lumaMean <= LUMA_MEAN_MIN) return { ok: false, reason: 'image-anomaly', detail: 'near-black frame, lumaMean=' + probe.lumaMean.toFixed(2) };
    if (probe.lumaMean >= LUMA_MEAN_MAX) return { ok: false, reason: 'image-anomaly', detail: 'near-white frame, lumaMean=' + probe.lumaMean.toFixed(2) };
    if (probe.lumaStddev < LUMA_STDDEV_MIN) return { ok: false, reason: 'image-anomaly', detail: 'near-solid frame, lumaStddev=' + probe.lumaStddev.toFixed(2) };
    return probe;
}

// 取景窗选择：背景帧多为「顶部地标/天际线 + 中部建筑 + 底部光秃地面」，
// 中心条带常落在空地板上。改为在 3×3 模糊后的 64×64 灰度网格上滑动
// 161:69 比例窗，取行/列标准差之和最大（细节最丰富）的位置；
// 含近黑/近白（未绘制区）行/列的窗扣分。全部同等平淡时回退居中。
function chooseCrop(probe) {
    const width = probe.width;
    const height = probe.height;
    let cropW = width;
    let cropH = height;
    let horizontal = false; // true: 源比目标更宽，沿 x 滑动；false: 沿 y 滑动
    if (width / height > PREVIEW_ASPECT) {
        cropW = Math.round(height * PREVIEW_ASPECT);
        horizontal = true;
    } else {
        cropH = Math.round(width / PREVIEW_ASPECT);
    }

    // 3×3 盒式模糊，压地面颗粒噪，保留结构化地标对比。
    const blurred = new Float64Array(PROBE_GRID * PROBE_GRID);
    for (let y = 0; y < PROBE_GRID; y += 1) {
        for (let x = 0; x < PROBE_GRID; x += 1) {
            let acc = 0;
            let n = 0;
            for (let dy = -1; dy <= 1; dy += 1) {
                for (let dx = -1; dx <= 1; dx += 1) {
                    const yy = y + dy;
                    const xx = x + dx;
                    if (yy < 0 || yy >= PROBE_GRID || xx < 0 || xx >= PROBE_GRID) continue;
                    acc += probe.luma[yy * PROBE_GRID + xx];
                    n += 1;
                }
            }
            blurred[y * PROBE_GRID + x] = acc / n;
        }
    }

    // 标准差用模糊网格（压颗粒噪）；均值用原始网格——模糊会把白区边界行拉进 245 阈值内，
    // 使「未绘制白区」逃脱惩罚并被自身高对比边界吸引（合成探针实测复现）。
    const lineStd = new Float64Array(PROBE_GRID);
    const lineMean = new Float64Array(PROBE_GRID);
    for (let i = 0; i < PROBE_GRID; i += 1) {
        let s = 0;
        let sq = 0;
        let rawS = 0;
        for (let j = 0; j < PROBE_GRID; j += 1) {
            const blurredV = horizontal ? blurred[j * PROBE_GRID + i] : blurred[i * PROBE_GRID + j];
            const rawV = horizontal ? probe.luma[j * PROBE_GRID + i] : probe.luma[i * PROBE_GRID + j];
            s += blurredV;
            sq += blurredV * blurredV;
            rawS += rawV;
        }
        lineMean[i] = rawS / PROBE_GRID;
        lineStd[i] = Math.sqrt(Math.max(0, sq / PROBE_GRID - (s / PROBE_GRID) * (s / PROBE_GRID)));
    }

    const windowLines = horizontal
        ? Math.max(4, Math.round(PROBE_GRID * cropW / width))
        : Math.max(4, Math.round(PROBE_GRID * cropH / height));
    let bestScore = -Infinity;
    let bestLine = -1;
    for (let start = 0; start + windowLines <= PROBE_GRID; start += 1) {
        let score = 0;
        for (let i = start; i < start + windowLines; i += 1) {
            score += lineStd[i];
            if (lineMean[i] <= 8 || lineMean[i] >= 245) score -= EXTREME_ROW_PENALTY;
        }
        if (score > bestScore) {
            bestScore = score;
            bestLine = start;
        }
    }
    if (bestLine < 0) {
        return { x: Math.max(0, Math.floor((width - cropW) / 2)), y: Math.max(0, Math.floor((height - cropH) / 2)), w: cropW, h: cropH };
    }
    if (horizontal) {
        const x = Math.min(width - cropW, Math.round(bestLine / PROBE_GRID * width));
        return { x: Math.max(0, x), y: 0, w: cropW, h: cropH };
    }
    const y = Math.min(height - cropH, Math.round(bestLine / PROBE_GRID * height));
    return { x: 0, y: Math.max(0, y), w: cropW, h: cropH };
}

// 按取景窗裁剪后缩放为 161×69 JPEG。
function renderPreview(framePath, crop, targetPath) {
    const filter = 'crop=' + crop.w + ':' + crop.h + ':' + crop.x + ':' + crop.y + ',scale=' + PREVIEW_WIDTH + ':' + PREVIEW_HEIGHT;
    const result = childProcess.spawnSync('ffmpeg', [
        '-y', '-hide_banner', '-loglevel', 'error',
        '-i', framePath,
        '-vf', filter,
        '-q:v', String(JPEG_QUALITY),
        targetPath
    ], { encoding: 'utf8' });
    if (result.status !== 0) {
        throw new Error('ffmpeg preview render failed for ' + path.basename(framePath) + ': ' + (result.stderr || result.error || 'unknown error'));
    }
}

function keep(entry, reason, detail) {
    entry.status = 'kept';
    entry.reason = reason;
    entry.detail = detail || '';
    return entry;
}

function deriveAll(manifest, stageInfoIndex, java, options) {
    const defaultButtonsByStage = {};
    (manifest.frames || []).forEach(function(frame) {
        (frame.stageButtons || []).forEach(function(button) {
            if (button.previewSource !== 'default') return;
            if (!defaultButtonsByStage[button.stageName]) defaultButtonsByStage[button.stageName] = [];
            defaultButtonsByStage[button.stageName].push({ id: button.id, frameLabel: button.frameLabel });
        });
    });

    let stageNames = Object.keys(defaultButtonsByStage);
    if (options.only && options.only.length) {
        const onlySet = {};
        options.only.forEach(function(name) { onlySet[name] = true; });
        stageNames = stageNames.filter(function(name) { return onlySet[name]; });
    }
    stageNames.sort(function(a, b) { return a.localeCompare(b, 'zh-CN'); });
    if (options.limit > 0) stageNames = stageNames.slice(0, options.limit);

    const frameCache = {};
    const derived = [];
    const kept = [];
    const stageBackgroundIndex = {};

    stageNames.forEach(function(stageName) {
        const buttons = defaultButtonsByStage[stageName];
        const entry = { stageName: stageName, buttons: buttons };
        const info = stageInfoIndex[stageName];
        if (!info) {
            kept.push(keep(entry, 'stage-info-missing', 'data/stages 各 __list__.xml 无此 StageInfo'));
            return;
        }
        entry.stageArea = info.area;
        entry.stageType = info.type;
        if (!fs.existsSync(info.url)) {
            kept.push(keep(entry, 'stage-xml-missing', path.relative(projectRoot, info.url)));
            return;
        }
        const background = findFirstBackground(readUtf8(info.url));
        if (!background) {
            kept.push(keep(entry, 'no-background', '首个 SubStage 无 BasicInformation/Background'));
            return;
        }
        stageBackgroundIndex[stageName] = background;
        entry.background = background;
        if (!/\.swf$/i.test(background)) {
            kept.push(keep(entry, 'background-not-swf', background));
            return;
        }
        const swfPath = path.join(projectRoot, ...background.split('/'));
        if (!fs.existsSync(swfPath)) {
            kept.push(keep(entry, 'background-swf-missing', background));
            return;
        }
        const exported = exportBackgroundFrame(java, swfPath, frameCache);
        if (!exported.ok) {
            kept.push(keep(entry, 'ffdec-export-failed', exported.error));
            return;
        }
        const probe = analyzeProbe(probeImage(exported.framePath));
        if (!probe.ok) {
            kept.push(keep(entry, probe.reason, probe.detail + ' (' + background + ')'));
            return;
        }
        const assetName = 'stage-derived-' + hashText(stageName) + '.jpg';
        const assetPath = path.join(derivedAssetDir, assetName);
        const crop = chooseCrop(probe);
        renderPreview(exported.framePath, crop, assetPath);
        entry.status = 'derived';
        entry.assetName = assetName;
        entry.assetUrl = derivedAssetUrlPrefix + assetName;
        entry.assetBytes = fs.statSync(assetPath).size;
        entry.sourceWidth = probe.width;
        entry.sourceHeight = probe.height;
        entry.lumaMean = Math.round(probe.lumaMean * 100) / 100;
        entry.lumaStddev = Math.round(probe.lumaStddev * 100) / 100;
        entry.crop = crop;
        derived.push(entry);
    });

    return { derived: derived, kept: kept, stageBackgroundIndex: stageBackgroundIndex };
}

// ---- manifest --write：逐按钮字段替换，保持其余字节不动 ----

function escapeJsonString(value) {
    return JSON.stringify(String(value)).slice(1, -1);
}

function replaceOnce(segment, re, replacement, label, buttonId) {
    if (!re.test(segment)) {
        throw new Error('manifest write aborted: ' + label + ' not found in button ' + buttonId + ' segment');
    }
    return segment.replace(re, replacement);
}

function applyManifestWrite(manifest, derivedEntries) {
    const assetNameByStage = {};
    const urlByStage = {};
    const backgroundByStage = {};
    derivedEntries.forEach(function(entry) {
        assetNameByStage[entry.stageName] = 'derived/' + entry.assetName;
        urlByStage[entry.stageName] = entry.assetUrl;
        backgroundByStage[entry.stageName] = entry.background;
    });

    // 需更新的按钮集合（previewSource==='default' 且其关卡派生成功）。
    const targetIds = {};
    (manifest.frames || []).forEach(function(frame) {
        (frame.stageButtons || []).forEach(function(button) {
            if (button.previewSource === 'default' && urlByStage[button.stageName]) targetIds[button.id] = button.stageName;
        });
    });

    let text = fs.readFileSync(dataFile, 'utf8');
    // 源文件为 CRLF；所有块级替换必须沿用同一 EOL，否则引入混合行尾。
    const eol = text.indexOf('\r\n') >= 0 ? '\r\n' : '\n';
    const cropRe = new RegExp('"previewCrop": \\{' + eol + '(\\s*)"x": [^\\r\\n]*' + eol + '\\s*"y": [^\\r\\n]*' + eol + '\\s*"w": [^\\r\\n]*' + eol + '\\s*"h": [^\\r\\n]*' + eol + '\\s*\\}', 'u');
    let replacedButtons = 0;
    Object.keys(targetIds).forEach(function(buttonId) {
        const stageName = targetIds[buttonId];
        const idIdx = text.indexOf('"id": "' + buttonId + '"');
        if (idIdx < 0) throw new Error('manifest write aborted: button id not found: ' + buttonId);
        const endIdx = text.indexOf('"previewMissing"', idIdx);
        if (endIdx < 0) throw new Error('manifest write aborted: previewMissing not found after ' + buttonId);
        let segment = text.slice(idIdx, endIdx);
        if (segment.indexOf('"previewSource": "default"') < 0) {
            throw new Error('manifest write aborted: button ' + buttonId + ' is not previewSource=default (stale run?)');
        }
        segment = replaceOnce(segment, /"previewUrl": "[^"]*"/u, '"previewUrl": "' + escapeJsonString(urlByStage[stageName]) + '"', 'previewUrl', buttonId);
        segment = replaceOnce(segment, /"previewAssetName": "[^"]*"/u, '"previewAssetName": "' + escapeJsonString(assetNameByStage[stageName]) + '"', 'previewAssetName', buttonId);
        segment = replaceOnce(segment, /"previewSource": "default"/u, '"previewSource": "derived"', 'previewSource', buttonId);
        segment = replaceOnce(segment, /"previewSourcePath": "[^"]*"/u, '"previewSourcePath": "' + escapeJsonString(backgroundByStage[stageName]) + '"', 'previewSourcePath', buttonId);
        segment = replaceOnce(segment, /"previewSourceFrameIndex": \d+/u, '"previewSourceFrameIndex": 1', 'previewSourceFrameIndex', buttonId);
        const cropBefore = segment.match(cropRe);
        if (!cropBefore) throw new Error('manifest write aborted: previewCrop block not matched for ' + buttonId);
        segment = segment.replace(cropRe, function(whole, indent) {
            return '"previewCrop": {' + eol + indent + '"x": 0,' + eol + indent + '"y": 0,' + eol + indent + '"w": ' + PREVIEW_WIDTH + ',' + eol + indent + '"h": ' + PREVIEW_HEIGHT + eol + indent.slice(4) + '}';
        });
        // 精确验证：新块必须 x:0/y:0/w:161/h:69（旧 default 帧 crop 也含 w:161，不能只看宽度；
        // 若旧块本就已是该形状则属幂等 no-op，不视为失败）。
        const cropAfter = segment.match(cropRe);
        if (!cropAfter || cropAfter[0].indexOf('"x": 0,') < 0 || cropAfter[0].indexOf('"y": 0,') < 0) {
            throw new Error('manifest write aborted: previewCrop rewrite failed for ' + buttonId);
        }
        text = text.slice(0, idIdx) + segment + text.slice(endIdx);
        replacedButtons += 1;
    });

    // assetReport.previewSources / previewFallbacks 按唯一 stageName 重算（沿用导出器口径；
    // derived 与 external 同为关卡专属真实图，不计入 previewFallbacks 回退数）。
    const perName = {};
    (manifest.frames || []).forEach(function(frame) {
        (frame.stageButtons || []).forEach(function(button) {
            if (perName[button.stageName]) return;
            const src = (button.previewSource === 'default' && urlByStage[button.stageName]) ? 'derived' : button.previewSource;
            perName[button.stageName] = src || 'missing';
        });
    });
    const counts = { external: 0, internal: 0, default: 0, derived: 0, missing: 0 };
    Object.keys(perName).forEach(function(name) {
        const src = perName[name];
        counts[src] = (counts[src] || 0) + 1;
    });
    const fallbacks = (counts.internal || 0) + (counts.default || 0);
    const sourcesBlock = '"previewSources": {' + eol + '                "external": ' + counts.external +
        ',' + eol + '                "internal": ' + counts.internal +
        ',' + eol + '                "default": ' + counts.default +
        ',' + eol + '                "derived": ' + counts.derived +
        ',' + eol + '                "missing": ' + counts.missing +
        eol + '            }';
    if (!/"previewSources": \{[^}]*\}/u.test(text)) throw new Error('manifest write aborted: assetReport.previewSources block not found');
    text = text.replace(/"previewSources": \{[^}]*\}/u, sourcesBlock);
    if (!/"previewFallbacks": \d+/u.test(text)) throw new Error('manifest write aborted: assetReport.previewFallbacks not found');
    text = text.replace(/"previewFallbacks": \d+/u, '"previewFallbacks": ' + fallbacks);

    fs.writeFileSync(dataFile, text, 'utf8');
    return { replacedButtons: replacedButtons, previewSources: counts, previewFallbacks: fallbacks };
}

function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;

    const manifest = loadManifest();
    const stageInfoIndex = readStageInfoIndex();

    // 环境硬前置：无 JRE / ffdec.jar 时明确报错、整体保留 default，不静默跳过。
    if (!fs.existsSync(ffdecJar)) {
        console.error('[derive-stage-select-previews] FATAL: ffdec.jar 缺失: ' + path.relative(projectRoot, ffdecJar) + '；未写任何文件，全部保留 default。');
        process.exit(2);
    }
    const java = resolveJava();
    if (!java) {
        console.error('[derive-stage-select-previews] FATAL: 未找到 JRE（设 JAVA_EXE 或安装 Adobe Animate 2024 / Flash CS6 自带 JRE）；未写任何文件，全部保留 default。');
        process.exit(2);
    }
    const ffmpegProbe = childProcess.spawnSync('ffmpeg', ['-version'], { encoding: 'utf8' });
    if (ffmpegProbe.status !== 0) {
        console.error('[derive-stage-select-previews] FATAL: 未找到 ffmpeg；未写任何文件，全部保留 default。');
        process.exit(2);
    }

    fs.mkdirSync(derivedAssetDir, { recursive: true });
    fs.mkdirSync(workRoot, { recursive: true });

    const result = deriveAll(manifest, stageInfoIndex, java, args);

    // 派生成功的按钮数（含同名多按钮）。
    const derivedButtonCount = result.derived.reduce(function(sum, entry) { return sum + entry.buttons.length; }, 0);
    const keptButtonCount = result.kept.reduce(function(sum, entry) { return sum + entry.buttons.length; }, 0);

    const reasonCounts = {};
    result.kept.forEach(function(entry) {
        reasonCounts[entry.reason] = (reasonCounts[entry.reason] || 0) + 1;
    });

    let writeResult = null;
    if (args.write && result.derived.length) {
        const backupDir = path.join(workRoot, 'backup');
        fs.mkdirSync(backupDir, { recursive: true });
        const stamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupPath = path.join(backupDir, 'stage-select-data-' + stamp + '.js');
        fs.copyFileSync(dataFile, backupPath);
        writeResult = applyManifestWrite(manifest, result.derived);
        writeResult.backupPath = path.relative(projectRoot, backupPath);
    }

    const report = {
        schema: 'stage-select-preview-derive-report-v1',
        generated: new Date().toISOString(),
        totals: {
            uniqueDefaultStages: result.derived.length + result.kept.length,
            derivedStages: result.derived.length,
            keptStages: result.kept.length,
            derivedButtons: derivedButtonCount,
            keptButtons: keptButtonCount
        },
        keptReasons: reasonCounts,
        write: writeResult,
        derived: result.derived,
        kept: result.kept,
        // stage→background 索引（P5 Stage 3 参考包 §5.4 可复用）。
        stageBackgroundIndex: result.stageBackgroundIndex
    };

    const reportPath = args.report
        ? path.resolve(projectRoot, args.report)
        : path.join(workRoot, 'report-' + new Date().toISOString().replace(/[:.]/g, '-') + '.json');
    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n', 'utf8');
    fs.writeFileSync(path.join(workRoot, 'stage-background-index.json'), JSON.stringify(result.stageBackgroundIndex, null, 2) + '\n', 'utf8');

    if (args.json) {
        process.stdout.write(JSON.stringify(report, null, 2) + '\n');
    } else {
        console.log('[derive-stage-select-previews] derived stages=' + report.totals.derivedStages + ' (buttons=' + derivedButtonCount + ') kept stages=' + report.totals.keptStages + ' (buttons=' + keptButtonCount + ')');
        console.log('[derive-stage-select-previews] kept reasons=' + JSON.stringify(reasonCounts));
        if (writeResult) {
            console.log('[derive-stage-select-previews] --write: replaced buttons=' + writeResult.replacedButtons + ' previewSources=' + JSON.stringify(writeResult.previewSources) + ' previewFallbacks=' + writeResult.previewFallbacks);
            console.log('[derive-stage-select-previews] backup=' + writeResult.backupPath);
        } else {
            console.log('[derive-stage-select-previews] manifest untouched (use --write to apply)');
        }
        console.log('[derive-stage-select-previews] report=' + path.relative(projectRoot, reportPath));
    }
}

if (require.main === module) {
    main();
}

// 供 tmp 探针/单测复用内部函数（不改变 CLI 行为）。
module.exports = {
    chooseCrop: chooseCrop,
    probeImage: probeImage,
    analyzeProbe: analyzeProbe,
    findFirstBackground: findFirstBackground,
    readStageInfoIndex: readStageInfoIndex,
    hashText: hashText
};
