#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const childProcess = require('child_process');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const stagesRoot = path.join(projectRoot, 'data', 'stages');
const levelsRoot = path.join(projectRoot, 'flashswf', 'levels');
const ffdecCli = path.join(projectRoot, 'tools', 'ffdec', 'ffdec-cli.exe');
const ffdecJar = path.join(projectRoot, 'tools', 'ffdec', 'ffdec.jar');
const exportRoot = path.join(projectRoot, 'tmp', 'diplomacy-stage-select-link-audit');
const sceneTransitionScript = path.join(projectRoot, 'scripts', '逻辑', '关卡系统', '关卡系统_lsy_场景转换.as');
const stageSelectServiceScript = path.join(projectRoot, 'scripts', '类定义', 'org', 'flashNight', 'arki', 'stageSelect', 'StageSelectPanelService.as');
const stageSelectPanelScript = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-panel.js');
const stageSelectModulesDir = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select');
const stageSelectDataScript = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select-data.js');

const args = process.argv.slice(2);
const jsonMode = args.indexOf('--json') >= 0;
const keepExport = args.indexOf('--keep-export') >= 0;
const skipFfdec = args.indexOf('--skip-ffdec') >= 0;

function readText(file) {
    return fs.readFileSync(file, 'utf8');
}

function tag(block, name) {
    const re = new RegExp('<' + name + '>([\\s\\S]*?)<\\/' + name + '>', 'u');
    const match = re.exec(block);
    return match ? match[1].trim() : '';
}

function safeName(name) {
    return name.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_');
}

function escapeRegExp(text) {
    return String(text).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function walkFiles(dir, out) {
    if (!fs.existsSync(dir)) return out;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            walkFiles(full, out);
        } else {
            out.push(full);
        }
    }
    return out;
}

function matchPatterns(text, patterns) {
    const hits = [];
    for (const pattern of patterns) {
        if (text.indexOf(pattern) >= 0) {
            hits.push(pattern);
        }
    }
    return hits;
}

function findJavaRuntime() {
    const candidates = [];
    if (process.env.JAVA_HOME) {
        candidates.push(path.join(process.env.JAVA_HOME, 'bin', 'java.exe'));
        candidates.push(path.join(process.env.JAVA_HOME, 'bin', 'java'));
    }
    candidates.push(
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Adobe', 'Adobe Animate 2024', 'jre', 'bin', 'java.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Common Files', 'Adobe', 'Adobe Flash CS6', 'jre', 'bin', 'java.exe'),
        'java'
    );

    for (const candidate of candidates) {
        if (!candidate) continue;
        if (candidate === 'java') {
            const probe = childProcess.spawnSync(candidate, ['-version'], { encoding: 'utf8' });
            if (!probe.error && probe.status === 0) return candidate;
            continue;
        }
        if (fs.existsSync(candidate)) return candidate;
    }
    return '';
}

function resolveFfdecRunner() {
    const java = findJavaRuntime();
    if (java && fs.existsSync(ffdecJar)) {
        return {
            command: java,
            prefixArgs: ['-jar', ffdecJar],
            description: path.relative(projectRoot, ffdecJar).replace(/\\/g, '/')
        };
    }
    if (fs.existsSync(ffdecCli)) {
        return {
            command: ffdecCli,
            prefixArgs: [],
            description: path.relative(projectRoot, ffdecCli).replace(/\\/g, '/')
        };
    }
    return null;
}

function collectDiplomacyMaps() {
    const entries = [];
    for (const folder of fs.readdirSync(stagesRoot, { withFileTypes: true })) {
        if (!folder.isDirectory()) continue;
        const listPath = path.join(stagesRoot, folder.name, '__list__.xml');
        if (!fs.existsSync(listPath)) continue;
        const xml = readText(listPath);
        const blocks = xml.match(/<StageInfo>[\s\S]*?<\/StageInfo>/gu) || [];
        for (const block of blocks) {
            if (tag(block, 'Type') !== '外交地图') continue;
            const frame = tag(block, 'RootFadeTransitionFrame');
            entries.push({
                stageSelectFrame: folder.name,
                stageName: tag(block, 'Name'),
                mapFrame: frame,
                address: tag(block, 'Address') || '出生地',
                swf: frame ? path.join(levelsRoot, frame + '.swf') : ''
            });
        }
    }
    entries.sort((a, b) => {
        if (a.stageSelectFrame !== b.stageSelectFrame) return a.stageSelectFrame < b.stageSelectFrame ? -1 : 1;
        return a.stageName < b.stageName ? -1 : 1;
    });
    return entries;
}

// P4-a（2026-08-16）工程拆分后，面板实现分布于薄 facade（stage-select-panel.js）+
// modules/stage-select/ 领域模块（core / view-model / renderer / inspector / bridge）。
// 文本探针对二者的并集生效；目录内按文件名排序拼接，保证可复现。
function collectStageSelectPanelText() {
    const files = [];
    if (fs.existsSync(stageSelectPanelScript)) files.push(stageSelectPanelScript);
    if (fs.existsSync(stageSelectModulesDir)) {
        for (const entry of fs.readdirSync(stageSelectModulesDir).sort()) {
            if (/^stage-select-.*\.js$/u.test(entry)) files.push(path.join(stageSelectModulesDir, entry));
        }
    }
    return files.map(readText).join('\n');
}

function collectStageSelectMapButtons() {
    if (!fs.existsSync(stageSelectDataScript)) return [];
    const context = {};
    vm.createContext(context);
    vm.runInContext(readText(stageSelectDataScript), context, { filename: stageSelectDataScript });
    const data = context.StageSelectData;
    const manifest = data && data.getManifest ? data.getManifest() : null;
    const buttons = [];
    for (const frame of manifest && manifest.frames || []) {
        for (const button of frame.stageButtons || []) {
            if (button.entryKind !== 'map') continue;
            buttons.push({
                stageSelectFrame: frame.frameLabel,
                stageName: button.stageName,
                stageType: button.stageType || '',
                libraryItemName: button.libraryItemName || '',
                sourceFrameIndex: button.sourceFrameIndex
            });
        }
    }
    buttons.sort((a, b) => {
        if (a.stageSelectFrame !== b.stageSelectFrame) return a.stageSelectFrame < b.stageSelectFrame ? -1 : 1;
        return a.stageName < b.stageName ? -1 : 1;
    });
    return buttons;
}

function exportScripts(entry) {
    const outDir = path.join(exportRoot, safeName(entry.mapFrame));
    const runner = resolveFfdecRunner();
    fs.mkdirSync(outDir, { recursive: true });
    const args = runner.prefixArgs.concat([
        '-onerror',
        'ignore',
        '-export',
        'script',
        outDir,
        entry.swf
    ]);
    const result = childProcess.spawnSync(runner.command, args, {
        cwd: projectRoot,
        encoding: 'utf8',
        maxBuffer: 1024 * 1024 * 16
    });
    return {
        outDir,
        status: result.status,
        stderr: result.stderr || '',
        stdout: result.stdout || ''
    };
}

function scanExportedScripts(outDir) {
    const files = walkFiles(outDir, []).filter(file => /\.as$/i.test(file));
    let legacyGateCount = 0;
    let explicitWebGateCount = 0;
    const legacyFiles = [];
    const webFiles = [];
    for (const file of files) {
        const text = readText(file);
        const mapHits = matchPatterns(text, ['关卡地图', '鍏冲崱鍦板浘']);
        const switchHits = matchPatterns(text, ['切换场景', '鍒囨崲鍦烘櫙']);
        const webHits = matchPatterns(text, ['打开Web选关', '鎵撳紑Web', 'openWebStageSelect']);
        if (mapHits.length > 0 && switchHits.length > 0) {
            legacyGateCount += 1;
            legacyFiles.push(path.relative(projectRoot, file).replace(/\\/g, '/'));
        }
        if (mapHits.length > 0 && webHits.length > 0) {
            explicitWebGateCount += 1;
            webFiles.push(path.relative(projectRoot, file).replace(/\\/g, '/'));
        }
    }
    return {
        scriptFiles: files.length,
        legacyGateCount,
        explicitWebGateCount,
        legacyFiles,
        webFiles
    };
}

function audit() {
    const errors = [];
    const warnings = [];
    const entries = collectDiplomacyMaps();
    const stageSelectMapButtons = collectStageSelectMapButtons();
    const missingSwfs = entries.filter(entry => !entry.swf || !fs.existsSync(entry.swf));
    const diplomacyNames = new Set(entries.map(entry => entry.stageName));
    const stageSelectMapNames = new Set(stageSelectMapButtons.map(button => button.stageName));
    const stageInfoOnlyMaps = entries.filter(entry => !stageSelectMapNames.has(entry.stageName));
    const stageSelectMapButtonsMissingStageInfo = stageSelectMapButtons.filter(button => !diplomacyNames.has(button.stageName));

    if (missingSwfs.length > 0) {
        for (const entry of missingSwfs) {
            errors.push('missing diplomacy map swf: ' + entry.mapFrame + ' (' + entry.stageName + ')');
        }
    }
    if (stageSelectMapButtonsMissingStageInfo.length > 0) {
        for (const button of stageSelectMapButtonsMissingStageInfo) {
            errors.push('stage-select map button has no Type=外交地图 StageInfo: ' + button.stageName + ' (' + button.stageSelectFrame + ')');
        }
    }

    const sceneText = fs.existsSync(sceneTransitionScript) ? readText(sceneTransitionScript) : '';
    const serviceText = fs.existsSync(stageSelectServiceScript) ? readText(stageSelectServiceScript) : '';
    const panelText = collectStageSelectPanelText();
    const hasLegacyTrap = sceneText.indexOf('请求打开Web选关') >= 0
        && sceneText.indexOf('目标场景帧 == "关卡地图"') >= 0
        && sceneText.indexOf('openWebStageSelect') >= 0;
    const hasFrameNormalizer = serviceText.indexOf('resolveStageSelectFrameLabel') >= 0
        && serviceText.indexOf('RootFadeTransitionFrame') >= 0
        && serviceText.indexOf('extractStageFolder') >= 0;
    const hasReturnFrameBridge = serviceText.indexOf('stageSelectReturnFrame') >= 0
        && serviceText.indexOf('handleReturnFrame') >= 0
        && panelText.indexOf("cmd: 'return_frame'") >= 0
        && panelText.indexOf('requestReturnFrame') >= 0;
    // P4-a 拆分后状态字段经共享容器 S 访问（stage-select/stage-select-view-model.js 的
    // resolveReturnFrameLabel）；探针随拆分同步改写，语义不变。
    const hasReturnFrameIsolation = serviceText.indexOf('Web选关返回帧值') >= 0
        && serviceText.indexOf('_root.Web选关当前帧值 = frameLabel') >= 0
        && panelText.indexOf('return S._returnFrameLabel || S._currentFrameLabel') >= 0;
    const hasSameSceneReturnFilter = serviceText.indexOf('isAlreadyAtReturnFrame') >= 0
        && serviceText.indexOf('skippedTransition') >= 0
        && serviceText.indexOf('if (!skipTransition)') >= 0;
    const hasDirectDestinationDrivenStageReturn =
        sceneText.indexOf('_root.淡出动画.淡出跳转帧(_root.关卡地图帧值);') >= 0;
    // 返回基地硬化允许先同步快照 destination，再在死亡/缺失主角时唯一覆写为医务室。
    // 探针同时接受旧直传形态与这一受限快照形态，但拒绝在淡出前对快照做任意二次改写。
    const destinationSnapshot = /var\s+([^\s=;]+)\s*=\s*_root\.关卡地图帧值\s*;([\s\S]*?)_root\.淡出动画\.淡出跳转帧\(\1\)\s*;/u.exec(sceneText);
    let hasGuardedDestinationSnapshot = false;
    if (destinationSnapshot) {
        const snapshotName = escapeRegExp(destinationSnapshot[1]);
        const beforeFade = destinationSnapshot[2];
        const assignments = beforeFade.match(new RegExp('(?:^|[;\\r\\n])\\s*' + snapshotName + '\\s*=', 'gu')) || [];
        const hasMedicalFallback = new RegExp('(?:^|[;\\r\\n])\\s*' + snapshotName + '\\s*=\\s*"医务室"\\s*;', 'u').test(beforeFade);
        hasGuardedDestinationSnapshot = assignments.length === 1 && hasMedicalFallback;
    }
    const hasDestinationDrivenStageReturn =
        hasDirectDestinationDrivenStageReturn || hasGuardedDestinationSnapshot;
    const completedStageAutoReturnMarkers = [
        '_root.Web选关战斗回流',
        'Web选关回流待打开',
        'as2_stage_complete_return'
    ];
    const completedStageAutoReturnResidue = completedStageAutoReturnMarkers.filter(marker =>
        serviceText.indexOf(marker) >= 0 || sceneText.indexOf(marker) >= 0
    );

    if (!hasLegacyTrap) {
        errors.push('AS2 legacy gate trap is missing in 场景转换函数.切换场景');
    }
    if (!hasFrameNormalizer) {
        errors.push('StageSelectPanelService frame normalizer is missing');
    }
    if (!hasReturnFrameBridge) {
        errors.push('stage-select return-frame bridge is missing');
    }
    if (!hasReturnFrameIsolation) {
        errors.push('stage-select return frame is not isolated from localFrame page navigation');
    }
    if (!hasSameSceneReturnFilter) {
        errors.push('stage-select same-scene return filter is missing');
    }
    if (!hasDestinationDrivenStageReturn) {
        errors.push('completed-stage return no longer follows _root.关卡地图帧值');
    }
    if (completedStageAutoReturnResidue.length > 0) {
        errors.push('completed-stage Web auto-return residue remains: ' + completedStageAutoReturnResidue.join(', '));
    }

    const scriptScans = [];
    if (!skipFfdec) {
        const ffdecRunner = resolveFfdecRunner();
        if (!ffdecRunner) {
            errors.push('missing FFDec runner: ' + path.relative(projectRoot, ffdecCli) + ' or Java + ' + path.relative(projectRoot, ffdecJar));
        } else {
            if (fs.existsSync(exportRoot)) fs.rmSync(exportRoot, { recursive: true, force: true });
            fs.mkdirSync(exportRoot, { recursive: true });

            for (const entry of entries) {
                if (!entry.swf || !fs.existsSync(entry.swf)) continue;
                const exported = exportScripts(entry);
                if (exported.status !== 0) {
                    errors.push('FFDec script export failed for ' + entry.mapFrame);
                    continue;
                }
                const scan = scanExportedScripts(exported.outDir);
                scriptScans.push(Object.assign({}, entry, {
                    swf: path.relative(projectRoot, entry.swf).replace(/\\/g, '/'),
                    scriptFiles: scan.scriptFiles,
                    legacyGateCount: scan.legacyGateCount,
                    explicitWebGateCount: scan.explicitWebGateCount,
                    legacyFiles: scan.legacyFiles,
                    webFiles: scan.webFiles
                }));
            }
            if (!keepExport) fs.rmSync(exportRoot, { recursive: true, force: true });
        }
    } else {
        warnings.push('FFDec scan skipped by --skip-ffdec');
    }

    const totalLegacyGates = scriptScans.reduce((sum, item) => sum + item.legacyGateCount, 0);
    if (totalLegacyGates > 0 && !hasLegacyTrap) {
        errors.push('legacy diplomacy map gates exist but no generic Web stage-select trap covers them');
    }

    return {
        ok: errors.length === 0,
        diplomacyMapCount: entries.length,
        stageSelectMapButtonCount: stageSelectMapButtons.length,
        diplomacyMaps: entries.map(entry => ({
            stageSelectFrame: entry.stageSelectFrame,
            stageName: entry.stageName,
            mapFrame: entry.mapFrame,
            swf: entry.swf ? path.relative(projectRoot, entry.swf).replace(/\\/g, '/') : ''
        })),
        stageSelectMapButtons,
        stageInfoOnlyMapCount: stageInfoOnlyMaps.length,
        stageInfoOnlyMaps: stageInfoOnlyMaps.map(entry => ({
            stageSelectFrame: entry.stageSelectFrame,
            stageName: entry.stageName,
            mapFrame: entry.mapFrame,
            swf: entry.swf ? path.relative(projectRoot, entry.swf).replace(/\\/g, '/') : ''
        })),
        stageSelectMapButtonsMissingStageInfo,
        missingSwfCount: missingSwfs.length,
        hasLegacyTrap,
        hasFrameNormalizer,
        hasReturnFrameBridge,
        hasReturnFrameIsolation,
        hasSameSceneReturnFilter,
        hasDestinationDrivenStageReturn,
        completedStageAutoReturnResidue,
        ffdecScanned: !skipFfdec,
        totalLegacyGateCount: totalLegacyGates,
        totalExplicitWebGateCount: scriptScans.reduce((sum, item) => sum + item.explicitWebGateCount, 0),
        scriptScans,
        warnings,
        errors
    };
}

const result = audit();
if (jsonMode) {
    process.stdout.write(JSON.stringify(result, null, 2) + '\n');
} else {
    console.log('[diplomacy-stage-select-links] diplomacy maps: ' + result.diplomacyMapCount);
    console.log('[diplomacy-stage-select-links] stage-select map buttons: ' + result.stageSelectMapButtonCount);
    console.log('[diplomacy-stage-select-links] StageInfo-only maps: ' + result.stageInfoOnlyMapCount);
    console.log('[diplomacy-stage-select-links] FFDec scanned: ' + result.ffdecScanned);
    console.log('[diplomacy-stage-select-links] legacy gate instances: ' + result.totalLegacyGateCount);
    console.log('[diplomacy-stage-select-links] explicit Web gate instances: ' + result.totalExplicitWebGateCount);
    console.log('[diplomacy-stage-select-links] AS2 legacy trap: ' + (result.hasLegacyTrap ? 'yes' : 'no'));
    console.log('[diplomacy-stage-select-links] frame normalizer: ' + (result.hasFrameNormalizer ? 'yes' : 'no'));
    console.log('[diplomacy-stage-select-links] return-frame bridge: ' + (result.hasReturnFrameBridge ? 'yes' : 'no'));
    console.log('[diplomacy-stage-select-links] return-frame isolation: ' + (result.hasReturnFrameIsolation ? 'yes' : 'no'));
    console.log('[diplomacy-stage-select-links] same-scene return filter: ' + (result.hasSameSceneReturnFilter ? 'yes' : 'no'));
    console.log('[diplomacy-stage-select-links] destination-driven completed-stage return: ' + (result.hasDestinationDrivenStageReturn ? 'yes' : 'no'));
    console.log('[diplomacy-stage-select-links] completed-stage Web auto-return residue: '
        + (result.completedStageAutoReturnResidue.length > 0 ? result.completedStageAutoReturnResidue.join(', ') : 'none'));
    for (const warning of result.warnings) console.warn('[warn] ' + warning);
    for (const error of result.errors) console.error('[error] ' + error);
}

if (!result.ok) process.exit(1);
