#!/usr/bin/env node
'use strict';

var fs = require('fs');
var path = require('path');
var cssBundleReader = require('./lib/read-css-bundle.js');

var ROOT = path.resolve(__dirname, '..');
var errors = [];
var warnings = [];
var metrics = {};

function abs(rel) { return path.join(ROOT, rel); }
function exists(rel) { return fs.existsSync(abs(rel)); }
function read(rel) {
    if (rel === 'launcher/web/css/panels.css') {
        return cssBundleReader.readCssBundle(abs(rel), {rootDir:abs('launcher/web/css')});
    }
    return fs.readFileSync(abs(rel), 'utf8');
}
function lineOf(text, index) { return text.slice(0, Math.max(0, index)).split(/\r?\n/).length; }
function lines(rel) { return read(rel).split(/\r?\n/).length; }

function finding(level, code, message, rel, line, detail) {
    var item = {level:level, code:code, message:message};
    if (rel) item.file = rel;
    if (line) item.line = line;
    if (detail !== undefined && detail !== '') item.detail = detail;
    (level === 'error' ? errors : warnings).push(item);
}

function expect(condition, code, message, rel, line, detail) {
    if (!condition) finding('error', code, message, rel, line, detail);
}

function warnUnless(condition, code, message, rel, line, detail) {
    if (!condition) finding('warning', code, message, rel, line, detail);
}

function expectOrdered(source, entries, code, message, rel) {
    var cursor = -1;
    var missing = '';
    for (var i = 0; i < entries.length; i++) {
        var next = source.indexOf(entries[i], cursor + 1);
        if (next < 0) { missing = entries[i]; break; }
        cursor = next;
    }
    expect(!missing, code, message, rel, null, missing || entries);
}

var REQUIRED_FILES = [
    'agentsDoc/workbench-ui-system.md',
    'tools/visual/workbench-atlas.html',
    'tools/run-workbench-visual-atlas.js',
    'tools/audit-workbench-ui.js',
    'tools/check-workbench-css-bundle.js',
    'tools/lib/read-css-bundle.js',
    'tools/visual/item-grid-matrix.html',
    'tools/run-item-grid-visual-matrix.js',
    'launcher/web/css/panels.css',
    'launcher/web/css/workbench/tokens.css',
    'launcher/web/css/workbench/core.css',
    'launcher/web/css/workbench/inventory.css',
    'launcher/web/css/workbench/skins.css',
    'launcher/web/css/workbench/entities.css',
    'launcher/web/css/workbench/crafting.css',
    'launcher/web/css/workbench/skills.css',
    'launcher/web/css/workbench/equipment-tuning.css',
    'launcher/web/css/workbench/components.css',
    'launcher/web/css/workbench/character-build.css',
    'launcher/web/css/workbench/character-build-stats.css',
    'launcher/web/css/workbench/states.css',
    'launcher/web/css/workbench/motion.css',
    'launcher/web/modules/panel-scale.js',
    'launcher/web/modules/panel-runtime.js',
    'launcher/web/modules/workbench-lifecycle.js',
    'launcher/web/modules/workbench-focus.js',
    'launcher/web/modules/workbench-primitives.js',
    'launcher/web/modules/workbench-components.js',
    'launcher/web/modules/workbench-inspection-viewport.js',
    'launcher/web/modules/workbench.js',
    'launcher/web/modules/character-build/character-build-mutation.js',
    'launcher/web/modules/character-build/character-build-action-view.js',
    'launcher/web/modules/character-build/character-build-stats-view.js',
    'launcher/web/modules/character-build/character-build-doll-preview.js',
    'launcher/web/modules/character-build/character-build-tuning.js',
    'launcher/web/modules/character-build/character-build-pose.js',
    'launcher/web/modules/character-build-session.js',
    'launcher/web/modules/character-build-view.js',
    'launcher/web/modules/character-build.js',
    'launcher/web/modules/inventory-ui.js',
    'launcher/web/modules/inventory-runtime.js',
    'launcher/web/modules/inventory-workbench-config.js',
    'launcher/web/modules/inventory-workbench-header.js',
    'launcher/web/modules/inventory-workbench-quick-transfer.js',
    'launcher/web/modules/inventory-workbench-owned-view.js',
    'launcher/web/modules/inventory-tuning-scope.js',
    'launcher/web/modules/inventory-storage-workbench.js',
    'launcher/web/modules/kshop-cart-controller.js',
    'launcher/web/modules/kshop-catalog-presenter.js',
    'launcher/web/modules/kshop-owned-inventory-presenter.js',
    'launcher/web/modules/kshop-tooltip-presenter.js',
    'launcher/web/modules/npcshop-secondary-pages.js',
    'launcher/web/modules/skills-library.js',
    'launcher/web/modules/skills-loadout.js',
    'launcher/web/modules/skills-trainer.js',
    'launcher/web/modules/skills-interactions.js',
    'launcher/web/modules/skills-render.js',
    'launcher/web/modules/skills-diagnostics.js',
    'launcher/web/modules/equipment-tuning-model.js',
    'launcher/web/modules/equipment-tuning-render.js',
    'tools/test-panel-runtime.js',
    'tools/test-workbench-lifecycle.js',
    'tools/test-workbench-focus.js',
    'tools/test-workbench-focus-integration.js',
    'tools/test-workbench-primitives.js',
    'tools/test-workbench-components.js',
    'tools/test-workbench-inspection-viewport.js',
    'tools/test-inventory-runtime.js',
    'tools/test-inventory-workbench-modules.js',
    'tools/test-character-build-session.js',
    'tools/test-kshop-presenters.js',
    'tools/test-npcshop-secondary-pages.js',
    'tools/test-skills-ui-modules.js',
    'tools/test-equipment-tuning-model.js',
    'tools/run-character-build-harness.js',
    'tools/run-character-build-dressup-harness.js',
    'tools/run-character-build-workbench-harness.js'
];

REQUIRED_FILES.forEach(function (rel) {
    expect(exists(rel), 'WB001', 'required workbench governance asset is missing', rel);
});

if (exists('agentsDoc/workbench-ui-system.md')) {
    var spec = read('agentsDoc/workbench-ui-system.md');
    [
        '布局系统', '密度与实体格', '排版、颜色与层级', '状态语言与权威阶段',
        '命中区、键盘与焦点', '动效语言', '生命周期与资源所有权', '组件边界',
        'CSS 级联与文件治理', 'Visual atlas 与验证矩阵'
    ].forEach(function (heading) {
        expect(spec.indexOf(heading) !== -1, 'WB002', 'canonical workbench spec is missing a required topic', 'agentsDoc/workbench-ui-system.md', null, heading);
    });
    expect(/最后核对代码基线.*commit `[\da-f]{7,40}`/.test(spec), 'WB003', 'canonical workbench spec lacks a valid code baseline', 'agentsDoc/workbench-ui-system.md');
}

[
    'agentsDoc/as2-web-panel-migration.md',
    'agentsDoc/testing-guide.md',
    'launcher/README.md'
].forEach(function (rel) {
    expect(exists(rel) && /workbench-ui-system\.md/.test(read(rel)), 'WB004', 'canonical entry does not reference workbench-ui-system.md', rel);
});

if (exists('tools/run-workbench-visual-atlas.js')) {
    var runner = read('tools/run-workbench-visual-atlas.js');
    ['1024x576','1366x768','1920x1080'].forEach(function (viewport) {
        expect(runner.indexOf(viewport) !== -1, 'WB005', 'visual atlas runner is missing a required viewport', 'tools/run-workbench-visual-atlas.js', null, viewport);
    });
    expect(/densities\s*=\s*\[['"]full['"],\s*['"]compact['"]\]/.test(runner), 'WB006', 'visual atlas runner must cross full and compact density', 'tools/run-workbench-visual-atlas.js');
    expect(/focus:[\s\S]*reducedMotion:[\s\S]*secondaryPage:/.test(runner), 'WB007', 'visual atlas report must expose focus, reduced-motion and secondary-page dimensions', 'tools/run-workbench-visual-atlas.js');
}

if (exists('launcher/web/css/panels.css')) {
    var cssRel = 'launcher/web/css/panels.css';
    var css = read(cssRel);
    metrics.panelsCssLines = css.split(/\r?\n/).length - (css.endsWith('\n') ? 1 : 0);
    metrics.panelsCssAggregateLines = metrics.panelsCssLines;
    metrics.panelsCssFacadeLines = fs.readFileSync(abs(cssRel), 'utf8').split(/\r?\n/).length - 1;
    var resolvedCss = cssBundleReader.resolveCssBundle(abs(cssRel), {rootDir:abs('launcher/web/css')});
    metrics.panelsCssFragments = resolvedCss.files.slice(1).map(function (file) {
        var source = fs.readFileSync(file, 'utf8');
        return {
            file:path.relative(ROOT, file).replace(/\\/g, '/'),
            lines:source.split(/\r?\n/).length - (source.endsWith('\n') ? 1 : 0)
        };
    });
    expect(/\.workbench-shell\s*\{[\s\S]*?width\s*:\s*1024px\s*;[\s\S]*?height\s*:\s*576px\s*;/.test(css), 'WB010', 'workbench shell must retain the 1024x576 logical canvas', cssRel);
    expect(/--workbench-compact-tile-size\s*:\s*48px/.test(css) && /--workbench-compact-icon-size\s*:\s*40px/.test(css) && /--workbench-compact-gap\s*:\s*4px/.test(css), 'WB011', 'shared compact geometry must retain 48/40/4 tokens', cssRel);
    expect(/\.workbench-shell button,[\s\S]*?min-width\s*:\s*24px\s*;[\s\S]*?min-height\s*:\s*24px/.test(css), 'WB012', 'workbench icon controls need the shared 24px hit-target floor', cssRel);
    expect(/kshop-checkout-btn[\s\S]*?min-height\s*:\s*40px/.test(css), 'WB013', 'workbench primary actions need the shared 40px height floor', cssRel);

    var cleanCss = css.replace(/\/\*[\s\S]*?\*\//g, function (comment) {
        return comment.replace(/[^\r\n]/g, ' ');
    });
    var relevant = /(?:workbench|item-card|item-grid|inventory-|kshop-|npcshop-|crafting-|skills-|equipment-tuning-|character-build-)/;
    var ruleRe = /([^{}]+)\{([^{}]*)\}/g;
    var match;
    var transitionAll = [];
    var undersizedType = [];
    while ((match = ruleRe.exec(cleanCss)) !== null) {
        var selector = match[1].trim();
        var body = match[2];
        if (!relevant.test(selector)) continue;
        if (/transition\s*:\s*all\b/i.test(body)) transitionAll.push({selector:selector.slice(0, 160), line:lineOf(cleanCss, match.index)});
        var sizeRe = /font-size\s*:\s*([0-9.]+)px/gi;
        var sizeMatch;
        while ((sizeMatch = sizeRe.exec(body)) !== null) {
            if (Number(sizeMatch[1]) < 9) undersizedType.push({selector:selector.slice(0, 160), size:Number(sizeMatch[1]), line:lineOf(cleanCss, match.index)});
        }
        var shorthandRe = /font\s*:[^;{}]*?([0-9.]+)px(?:\s*\/|\/)/gi;
        while ((sizeMatch = shorthandRe.exec(body)) !== null) {
            if (Number(sizeMatch[1]) < 9) undersizedType.push({selector:selector.slice(0, 160), size:Number(sizeMatch[1]), line:lineOf(cleanCss, match.index)});
        }
    }
    metrics.transitionAllRules = transitionAll.length;
    metrics.fontBelow9Rules = undersizedType.length;
    if (transitionAll.length) finding('warning', 'WB101', 'workbench-related rules still use transition:all', cssRel, transitionAll[0].line, {count:transitionAll.length, samples:transitionAll.slice(0, 8)});
    if (undersizedType.length) finding('warning', 'WB102', 'workbench-related rules still contain typography below 9px', cssRel, undersizedType[0].line, {count:undersizedType.length, samples:undersizedType.slice(0, 10)});

    var statsCssRel = 'launcher/web/css/workbench/character-build-stats.css';
    if (exists(statsCssRel)) {
        var statsCss = read(statsCssRel);
        var statsCleanCss = statsCss.replace(/\/\*[\s\S]*?\*\//g, function (comment) {
            return comment.replace(/[^\r\n]/g, ' ');
        });
        var statsRuleRe = /([^{}]+)\{([^{}]*)\}/g;
        var statsMatch;
        var statsUndersizedType = [];
        while ((statsMatch = statsRuleRe.exec(statsCleanCss)) !== null) {
            var statsSelector = statsMatch[1].trim();
            var statsBody = statsMatch[2];
            var statsSizeRe = /font-size\s*:\s*([0-9.]+)px/gi;
            var statsSizeMatch;
            while ((statsSizeMatch = statsSizeRe.exec(statsBody)) !== null) {
                if (Number(statsSizeMatch[1]) < 11) statsUndersizedType.push({
                    selector:statsSelector.slice(0, 160),
                    size:Number(statsSizeMatch[1]),
                    line:lineOf(statsCleanCss, statsMatch.index)
                });
            }
            var statsShorthandRe = /font\s*:[^;{}]*?([0-9.]+)px(?:\s*\/|\/|\s)/gi;
            while ((statsSizeMatch = statsShorthandRe.exec(statsBody)) !== null) {
                if (Number(statsSizeMatch[1]) < 11) statsUndersizedType.push({
                    selector:statsSelector.slice(0, 160),
                    size:Number(statsSizeMatch[1]),
                    line:lineOf(statsCleanCss, statsMatch.index)
                });
            }
        }
        var statsRawColors = statsCleanCss.match(
            /(?:#[0-9a-f]{3,8}\b|rgba?\(\s*(?:[0-9]|\.[0-9]))/gi) || [];
        metrics.characterStatsFontBelow11Rules = statsUndersizedType.length;
        metrics.characterStatsRawColorLiterals = statsRawColors.length;
        if (statsUndersizedType.length) finding('warning', 'WB119',
            'character stats contains player-facing typography below 11px',
            statsCssRel, statsUndersizedType[0].line,
            {count:statsUndersizedType.length, samples:statsUndersizedType.slice(0, 10)});
        if (statsRawColors.length) finding('warning', 'WB120',
            'character stats bypasses semantic or legacy-spectrum color tokens',
            statsCssRel, null, {count:statsRawColors.length});
    }

    var dlsLiterals = [];
    resolvedCss.files.slice(1).forEach(function (file) {
        if (/[/\\]workbench[/\\]tokens\.css$/i.test(file)) return;
        var matches = fs.readFileSync(file, 'utf8').match(/(?:#3dd5ff|rgba?\(\s*61\s*,\s*213\s*,\s*255\b)/gi) || [];
        dlsLiterals = dlsLiterals.concat(matches);
    });
    metrics.dlsAccentLiterals = dlsLiterals.length;
    if (dlsLiterals.length) finding('warning', 'WB103', 'DLS accent literals remain outside semantic role tokens', cssRel, null, {count:dlsLiterals.length});

    var reducedBlocks = css.match(/@media\s*\(prefers-reduced-motion\s*:\s*reduce\)[\s\S]{0,800}/gi) || [];
    var hasRootReducedMotion = reducedBlocks.some(function (block) { return /workbench-shell|\[data-workbench/.test(block) && /animation\s*:\s*none/.test(block); });
    warnUnless(hasRootReducedMotion, 'WB104', 'no shared workbench-root reduced-motion animation shutdown was found', cssRel);
    warnUnless(/--wb-motion-(?:micro|standard|structural)/.test(css), 'WB105', 'shared semantic motion-duration tokens are not implemented yet', cssRel);
    var largestCssFragment = metrics.panelsCssFragments.reduce(function (largest, item) {
        return !largest || item.lines > largest.lines ? item : largest;
    }, null);
    if (largestCssFragment && largestCssFragment.lines > 10000) finding('warning', 'WB106', 'a panels.css fragment remains above the split threshold', largestCssFragment.file, null, {lines:largestCssFragment.lines, threshold:10000});
}

if (exists('launcher/web/modules/panel-scale.js')) {
    var panelScale = read('launcher/web/modules/panel-scale.js');
    expect(/PanelScale/.test(panelScale) && /ResizeObserver/.test(panelScale) && /detach/.test(panelScale), 'WB014', 'PanelScale must own resize observation and deterministic detach', 'launcher/web/modules/panel-scale.js');
}

if (exists('launcher/web/modules/workbench.js')) {
    var wbRel = 'launcher/web/modules/workbench.js';
    var workbench = read(wbRel);
    ['DualPaneShell','ViewChrome','ItemCard','ItemGrid','GridDensityController','InteractionBroker','PointerDragController'].forEach(function (name) {
        expect(new RegExp(name + '\\s*:\\s*' + name).test(workbench), 'WB015', 'shared workbench export is missing', wbRel, null, name);
    });
    var focusRel = 'launcher/web/modules/workbench-focus.js';
    var focus = exists(focusRel) ? read(focusRel) : '';
    var hasFocusTrap = /FocusScope/.test(focus) && /keydown/.test(focus) && /focusin/.test(focus);
    var hasInert = /\.inert\s*=|setAttribute\(['"]inert['"]/.test(focus);
    warnUnless(hasFocusTrap && hasInert && /new FocusScope/.test(workbench), 'WB107', 'shared WorkbenchDialog focus trap and background inert contract is not fully implemented', focusRel);
    warnUnless(/function RovingGridFocus\(/.test(focus)
            && /RovingGridFocus:RovingGridFocus/.test(focus)
            && /getNeighbor/.test(focus),
        'WB117', 'shared roving-grid focus must preserve stable keys and explicit adjacency', focusRel);
    var lifecycleRel = 'launcher/web/modules/workbench-lifecycle.js';
    var lifecycle = exists(lifecycleRel) ? read(lifecycleRel) : '';
    warnUnless(/DisposableStack/.test(workbench) || /DisposableStack/.test(lifecycle), 'WB108', 'shared DisposableStack lifecycle primitive is not implemented', lifecycleRel);
}

var componentRel = 'launcher/web/modules/workbench-components.js';
var components = exists(componentRel) ? read(componentRel) : '';
warnUnless(/SecondaryPage\s*:\s*SecondaryPage/.test(components), 'WB109', 'shared SecondaryPage primitive is not exported from the workbench layer', componentRel);
warnUnless(/ChoiceGroup\s*:\s*ChoiceGroup/.test(components), 'WB110', 'shared ChoiceGroup primitive is not exported from the workbench layer', componentRel);
warnUnless(/CommitBar\s*:\s*CommitBar/.test(components), 'WB111', 'shared CommitBar primitive is not exported from the workbench layer', componentRel);
warnUnless(/new FocusScope/.test(components) && /_requestClose\('escape'/.test(components), 'WB116', 'SecondaryPage must share the canonical nested focus scope and Escape close path', componentRel);

var inspectionViewportRel = 'launcher/web/modules/workbench-inspection-viewport.js';
var inspectionViewport = exists(inspectionViewportRel) ? read(inspectionViewportRel) : '';
expect(/function Camera\(/.test(inspectionViewport)
        && /Camera:Camera/.test(inspectionViewport)
        && /create:function\(options\)/.test(inspectionViewport),
    'WB032', 'shared inspection viewport must export the camera factory',
    inspectionViewportRel);
expect(/Camera\.prototype\.activate/.test(inspectionViewport)
        && /Camera\.prototype\.deactivate/.test(inspectionViewport)
        && /Camera\.prototype\.destroy/.test(inspectionViewport)
        && /target\.style\.transform/.test(inspectionViewport)
        && !/viewport\.style\.transform/.test(inspectionViewport),
    'WB033', 'inspection viewport must own a target-only, deterministic lifecycle',
    inspectionViewportRel);
if (inspectionViewport) {
    expect(exists('tools/test-workbench-inspection-viewport.js'),
        'WB034', 'inspection viewport needs a pure Node regression entry',
        'tools/test-workbench-inspection-viewport.js');
}
[
    'launcher/web/modules/crafting/dev/harness.html',
    'launcher/web/modules/kshop/dev/harness.html',
    'launcher/web/modules/equipment-inspector-review/dev/review.html',
    'launcher/web/modules/crafting-product-review/dev/render-harness.html'
].forEach(function (rel) {
    var source = exists(rel) ? read(rel) : '';
    var cameraAt = source.indexOf('workbench-inspection-viewport.js');
    var inspectorAt = source.indexOf('equipment-inspector.js');
    expect(cameraAt >= 0 && inspectorAt > cameraAt,
        'WB037', 'EquipmentInspector browser harnesses must load the shared viewport first',
        rel);
});

var moduleThresholds = {
    'launcher/web/modules/kshop.js':1200,
    'launcher/web/modules/skills.js':1200,
    'launcher/web/modules/equipment-tuning-view.js':1200,
    'launcher/web/modules/workbench-inspection-viewport.js':420,
    'launcher/web/modules/character-build/character-build-mutation.js':260,
    'launcher/web/modules/character-build/character-build-action-view.js':180,
    'launcher/web/modules/character-build/character-build-stats-view.js':360,
    'launcher/web/modules/character-build/character-build-doll-preview.js':340,
    'launcher/web/modules/character-build/character-build-tuning.js':380,
    'launcher/web/modules/character-build/character-build-pose.js':90,
    'launcher/web/modules/character-build-session.js':700,
    'launcher/web/modules/character-build-view.js':760,
    'launcher/web/modules/character-build.js':550,
    'launcher/web/modules/inventory-tuning-scope.js':200,
    'launcher/web/modules/inventory-storage-workbench.js':900,
    'launcher/web/modules/inventory-workbench.js':550,
    'launcher/web/modules/npcshop.js':1000,
    'launcher/web/modules/workbench.js':1000
};
metrics.moduleLines = {};
Object.keys(moduleThresholds).forEach(function (rel) {
    if (!exists(rel)) return;
    var count = lines(rel);
    metrics.moduleLines[rel] = count;
    if (count > moduleThresholds[rel]) finding('warning', 'WB112', 'workbench module exceeds its split threshold', rel, null, {lines:count, threshold:moduleThresholds[rel]});
});

[
    'launcher/web/modules/kshop/dev/harness.html',
    'launcher/web/modules/npcshop/dev/harness.html',
    'launcher/web/modules/crafting/dev/harness.html',
    'launcher/web/modules/skills/dev/harness.html',
    'launcher/web/modules/equipment-tuning/dev/harness.html',
    'launcher/web/modules/character-build/dev/harness.html',
    'launcher/web/modules/character-build/dev/workbench-harness.html',
    'launcher/web/modules/dressup/dev/character-build-combination-harness.html'
].forEach(function (rel) {
    expect(exists(rel), 'WB016', 'workbench feature has no browser harness entry', rel);
});

var tooltipRel = 'launcher/web/modules/tooltip.js';
var tooltipSource = exists(tooltipRel) ? read(tooltipRel) : '';
expect(!!tooltipSource, 'WB029', 'shared PanelTooltip runtime is missing', tooltipRel);
if (tooltipSource) {
    var hasFixedOwners = /var _pointerAsyncBinding = null;/.test(tooltipSource)
        && /var _keyboardAsyncBinding = null;/.test(tooltipSource)
        && /var _inputModality = 'keyboard';/.test(tooltipSource);
    var hasInputFacts = /addEventListener\('pointerdown', notePointerInput, true\)/.test(tooltipSource)
        && /addEventListener\('keydown', noteKeyboardInput, true\)/.test(tooltipSource);
    var hasOwnerHistory = /_activeAsyncBindings|restoreActiveBinding|markActiveBinding/.test(tooltipSource);
    var hasDomainPolicyKnob =
        /\b(?:restoreOnPointerLeave|restoreOnBlur|focusMode|tooltipPolicy|ownerPolicy|keepAfterClick)\b/.test(tooltipSource);
    expect(hasFixedOwners && hasInputFacts, 'WB030',
        'PanelTooltip must derive restoration from one pointer owner, one keyboard owner, and shared input modality facts',
        tooltipRel);
    expect(!hasOwnerHistory && !hasDomainPolicyKnob, 'WB031',
        'PanelTooltip must not reintroduce owner history or per-domain restoration policy knobs',
        tooltipRel);
    metrics.tooltipOwnership = {
        pointerOwners:hasFixedOwners ? 1 : 0,
        keyboardOwners:hasFixedOwners ? 1 : 0,
        ownerHistory:hasOwnerHistory,
        domainPolicyKnob:hasDomainPolicyKnob
    };
}

var panelRuntimeRel = 'launcher/web/modules/panel-runtime.js';
var panelRuntime = exists(panelRuntimeRel) ? read(panelRuntimeRel) : '';
warnUnless(/PanelRequestMux/.test(panelRuntime) && /PanelResponseRouter/.test(panelRuntime), 'WB113', 'shared panel request mux/router has not been extracted yet', panelRuntimeRel);
if (panelRuntime) expect(exists('tools/test-panel-runtime.js'), 'WB017', 'shared panel runtime needs a pure Node regression entry', 'tools/test-panel-runtime.js');
if (exists('launcher/web/modules/workbench-lifecycle.js')) expect(exists('tools/test-workbench-lifecycle.js'), 'WB018', 'workbench lifecycle needs a pure Node regression entry', 'tools/test-workbench-lifecycle.js');
if (exists('launcher/web/modules/workbench-focus.js')) expect(exists('tools/test-workbench-focus.js'), 'WB019', 'workbench focus scope needs a pure Node regression entry', 'tools/test-workbench-focus.js');
if (exists('launcher/web/modules/workbench-primitives.js')) expect(exists('tools/test-workbench-primitives.js'), 'WB020', 'workbench primitives need a pure Node regression entry', 'tools/test-workbench-primitives.js');
warnUnless(/OwnedInventoryPane\s*:\s*OwnedInventoryPane/.test(components), 'WB114', 'shared OwnedInventoryPane controller has not been extracted yet', componentRel);
warnUnless(/@layer\s+workbench\.components/.test(read('launcher/web/css/workbench/components.css')),
    'WB115', 'shared workbench cascade layers have not been introduced', 'launcher/web/css/workbench/components.css');

var registryRel = 'launcher/web/modules/panels-lazy-registry.js';
if (exists(registryRel)) {
    var registry = read(registryRel);
    function lazyBlock(panel) {
        var start = registry.indexOf("Panels.registerLazy('" + panel + "'");
        var end = start < 0 ? -1 : registry.indexOf('noop);', start);
        return start < 0 || end < 0 ? '' : registry.slice(start, end);
    }
    var sharedOrder = [
        'modules/panel-runtime.js',
        'modules/workbench-lifecycle.js',
        'modules/workbench-focus.js',
        'modules/workbench-primitives.js',
        'modules/workbench.js',
        'modules/workbench-components.js'
    ];
    ['kshop','workbench','npcshop','crafting','skills'].forEach(function (panel) {
        expectOrdered(lazyBlock(panel), sharedOrder, 'WB021', 'lazy panel must preserve the shared workbench dependency order', registryRel);
    });
    expectOrdered(lazyBlock('kshop'), [
        'modules/kshop-views.js',
        'modules/kshop-cart-controller.js',
        'modules/kshop-catalog-presenter.js',
        'modules/kshop-owned-inventory-presenter.js',
        'modules/kshop-tooltip-presenter.js',
        'modules/kshop.js'
    ], 'WB022', 'KShop presenter modules must load before the facade', registryRel);
    expectOrdered(lazyBlock('workbench'), [
        'modules/dressup-doll-renderer.js',
        'modules/workbench-inspection-viewport.js',
        'modules/equipment-inspector.js',
        'modules/inventory-workbench-config.js',
        'modules/inventory-workbench-header.js',
        'modules/inventory-workbench-quick-transfer.js',
        'modules/inventory-workbench-owned-view.js',
        'modules/inventory-tuning-scope.js',
        'modules/inventory-storage-workbench.js',
        'modules/character-build/character-build-mutation.js',
        'modules/character-build-session.js',
        'modules/character-build/character-build-action-view.js',
        'modules/character-build/character-build-stats-view.js',
        'modules/character-build/character-build-doll-preview.js',
        'modules/character-build-view.js',
        'modules/character-build/character-build-tuning.js',
        'modules/character-build/character-build-pose.js',
        'modules/character-build.js',
        'modules/inventory-workbench.js'
    ], 'WB023', 'inventory workbench feature modules must load before the facade', registryRel);
    expectOrdered(lazyBlock('crafting'), [
        'modules/dressup-doll-renderer.js',
        'modules/workbench-inspection-viewport.js',
        'modules/equipment-inspector.js',
        'modules/crafting-inspector.js'
    ], 'WB035', 'crafting inspection consumers must load after the shared viewport', registryRel);
    expectOrdered(lazyBlock('npcshop'), [
        'modules/npcshop-secondary-pages.js',
        'modules/npcshop.js'
    ], 'WB024', 'NPC secondary-page presenters must load before the facade', registryRel);
    expectOrdered(lazyBlock('skills'), [
        'modules/item-filter.js',
        'modules/skills-runtime.js',
        'modules/skills-library.js',
        'modules/skills-trainer.js',
        'modules/skills-loadout.js',
        'modules/skills-interactions.js',
        'modules/skills-render.js',
        'modules/skills-diagnostics.js',
        'modules/skills.js'
    ], 'WB027', 'Skills feature modules must preserve dependency order before the facade', registryRel);
}

var buildRel = 'launcher/build.ps1';
var releasePolicyRel = 'tools/validate-launcher-release-policy.ps1';
if (exists(buildRel) && exists(releasePolicyRel)) {
    var buildSource = read(buildRel).replace(/\\/g, '/');
    var releasePolicySource = read(releasePolicyRel).replace(/\\/g, '/');
    expect(buildSource.indexOf('tools/validate-launcher-release-policy.ps1') !== -1,
        'WB025', 'Launcher build no longer delegates required-assets checks to release policy', buildRel);
    REQUIRED_FILES.filter(function (rel) { return rel.indexOf('launcher/web/modules/') === 0; })
        .forEach(function (rel) {
            var asset = rel.slice('launcher/web/'.length);
            expect(releasePolicySource.indexOf(asset) !== -1, 'WB025', 'Launcher release-policy required-assets gate is missing a workbench runtime module', releasePolicyRel, null, asset);
        });
    expect(releasePolicySource.indexOf('tools/check-workbench-css-bundle.js') !== -1
            && releasePolicySource.indexOf("'workbench-css-closure'") !== -1,
        'WB028', 'Launcher release policy must execute the workbench CSS import/asset closure gate', releasePolicyRel);
    expect(releasePolicySource.indexOf('tools/test-workbench-inspection-viewport.js') !== -1
            && releasePolicySource.indexOf("'workbench-inspection-viewport'") !== -1,
        'WB036', 'Launcher release policy must execute the shared inspection viewport regression gate',
        releasePolicyRel);
}

[
    'launcher/web/modules/kshop-runtime.js', 'launcher/web/modules/kshop.js',
    'launcher/web/modules/npcshop-runtime.js', 'launcher/web/modules/npcshop.js',
    'launcher/web/modules/crafting-runtime.js', 'launcher/web/modules/crafting.js',
    'launcher/web/modules/skills-runtime.js', 'launcher/web/modules/skills.js',
    'launcher/web/modules/equipment-tuning-runtime.js', 'launcher/web/modules/equipment-tuning-view.js',
    'launcher/web/modules/character-build-session.js',
    'launcher/web/modules/character-build-view.js',
    'launcher/web/modules/character-build/character-build-stats-view.js',
    'launcher/web/modules/character-build/character-build-doll-preview.js',
    'launcher/web/modules/character-build/character-build-tuning.js',
    'launcher/web/modules/character-build/character-build-pose.js',
    'launcher/web/modules/character-build.js',
    'launcher/web/modules/inventory-runtime.js', 'launcher/web/modules/inventory-tuning-scope.js',
    'launcher/web/modules/inventory-storage-workbench.js',
    'launcher/web/modules/inventory-workbench.js'
].forEach(function (rel) {
    if (!exists(rel)) return;
    expect(!/addMessageListener\s*\(/.test(read(rel)), 'WB026', 'domain modules must not install direct Bridge response listeners outside PanelResponseRouter', rel);
});

var strictWarnings = process.argv.indexOf('--strict-warnings') !== -1;
var report = {
    schemaVersion:1,
    kind:'cf7-workbench-ui-audit',
    baseline:'3343c1ef2244e0c6253fc95f5b6334095f049f57',
    summary:{errors:errors.length, warnings:warnings.length, strictWarnings:strictWarnings},
    metrics:metrics,
    errors:errors,
    warnings:warnings
};

if (process.argv.indexOf('--text') !== -1) {
    console.log('[workbench-ui-audit] errors=' + errors.length + ' warnings=' + warnings.length);
    errors.concat(warnings).forEach(function (item) {
        console.log(' - ' + item.level.toUpperCase() + ' ' + item.code + ' ' + item.message
            + (item.file ? ' [' + item.file + (item.line ? ':' + item.line : '') + ']' : ''));
    });
} else {
    console.log(JSON.stringify(report, null, 2));
}

if (errors.length || (strictWarnings && warnings.length)) process.exit(1);
