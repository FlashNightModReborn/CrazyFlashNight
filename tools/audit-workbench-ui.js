#!/usr/bin/env node
'use strict';

var fs = require('fs');
var path = require('path');
var cssBundleReader = require('./lib/read-css-bundle.js');
var uiRatchet = require('./lib/workbench-ui-ratchet.js');

var ROOT = path.resolve(__dirname, '..');
var errors = [];
var warnings = [];
var metrics = {};
var releaseTree = process.argv.indexOf('--release-tree') !== -1;

function abs(rel) { return path.join(ROOT, rel); }
function exists(rel) { return fs.existsSync(abs(rel)); }
function read(rel) {
    if (rel === 'launcher/web/css/panels.css') {
        return cssBundleReader.readCssBundle(abs(rel), {rootDir:abs('launcher/web')});
    }
    return fs.readFileSync(abs(rel), 'utf8');
}
function lineOf(text, index) { return text.slice(0, Math.max(0, index)).split(/\r?\n/).length; }
function lines(rel) { return read(rel).split(/\r?\n/).length; }
function collectFiles(rel, extension, output) {
    output = output || [];
    var target = abs(rel);
    if (!fs.existsSync(target)) return output;
    fs.readdirSync(target, {withFileTypes:true}).forEach(function(entry) {
        var child = path.join(rel, entry.name);
        if (entry.isDirectory()) {
            collectFiles(child, extension, output);
        } else if (!extension || entry.name.toLowerCase().slice(-extension.length) === extension) {
            output.push(child.replace(/\\/g, '/'));
        }
    });
    return output;
}

function isProductionModule(rel) {
    return rel.indexOf('/dev/') === -1
        && rel.indexOf('/node_modules/') === -1
        && rel.indexOf('/.test-dist/') === -1;
}

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
    'tools/lib/workbench-ui-ratchet.js',
    'tools/workbench-ui-ratchet-baseline.json',
    'tools/workbench-important-ledger.json',
    'tools/test-workbench-ui-ratchet.js',
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
    'launcher/web/css/workbench/loadout-picker.css',
    'launcher/web/css/workbench/character-build.css',
    'launcher/web/css/workbench/character-build-stats.css',
    'launcher/web/css/workbench/states.css',
    'launcher/web/css/workbench/motion.css',
    'launcher/web/css/workbench/utilities.css',
    'launcher/web/modules/panel-scale.js',
    'launcher/web/modules/panel-runtime.js',
    'launcher/web/modules/workbench-lifecycle.js',
    'launcher/web/modules/workbench-focus.js',
    'launcher/web/modules/workbench-primitives.js',
    'launcher/web/modules/workbench-profile.js',
    'launcher/web/modules/workbench-components.js',
    'launcher/web/modules/workbench-inspection-viewport.js',
    'launcher/web/modules/workbench.js',
    'launcher/web/modules/character-build/character-build-mutation.js',
    'launcher/web/modules/character-build/character-build-drug-layout.js',
    'launcher/web/modules/character-build/character-build-session-contract.js',
    'launcher/web/modules/loadout-picker/loadout-picker-action-view.js',
    'launcher/web/modules/character-build/character-build-tuning-adapter.js',
    'launcher/web/modules/character-build/character-build-tuning-ports.js',
    'launcher/web/modules/character-build/character-build-candidate-eligibility.js',
    'launcher/web/modules/character-build/character-build-candidate-tooltip.js',
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-state.js',
    'launcher/web/modules/character-build/character-build-facet-counts.js',
    'launcher/web/modules/character-build/character-build-stats-view.js',
    'launcher/web/modules/character-build/character-build-doll-preview.js',
    'launcher/web/modules/character-build/character-build-template.js',
    'launcher/web/modules/character-build/character-build-loadout-presenter.js',
    'launcher/web/modules/loadout-picker/loadout-picker-slot-grid.js',
    'launcher/web/modules/loadout-picker/loadout-picker-drop-policy.js',
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-drag.js',
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-pane.js',
    'launcher/web/modules/loadout-picker/loadout-picker.js',
    'launcher/web/modules/merc/merc-loadout-drop-policy.js',
    'launcher/web/modules/merc/merc-loadout-channel.js',
    'launcher/web/modules/merc/merc-loadout-picker.js',
    'launcher/web/modules/character-build/character-build-tuning.js',
    'launcher/web/modules/character-build/character-build-slot-transition.js',
    'launcher/web/modules/character-build/character-build-pose.js',
    'launcher/web/modules/character-build/character-build-projection.js',
    'launcher/web/modules/character-build/character-build-transport.js',
    'launcher/web/modules/character-build/character-build-item-use.js',
    'launcher/web/modules/character-build/character-build-item-use-channel.js',
    'launcher/web/modules/character-build/character-build-candidate-channel.js',
    'launcher/web/modules/character-build-session.js',
    'launcher/web/modules/character-build-view.js',
    'launcher/web/modules/character-build.js',
    'launcher/web/modules/inventory-ui.js',
    'launcher/web/modules/inventory-runtime.js',
    'launcher/web/modules/inventory-workbench-config.js',
    'launcher/web/modules/inventory-workbench-preparation-menu.js',
    'launcher/web/modules/inventory-workbench-header.js',
    'launcher/web/modules/inventory-workbench-quick-transfer.js',
    'launcher/web/modules/inventory-workbench-owned-view.js',
    'launcher/web/modules/inventory-workbench-feature-loader.js',
    'launcher/web/modules/inventory-tuning-scope.js',
    'launcher/web/modules/inventory-storage-workbench.js',
    'launcher/web/modules/crafting-inventory-organizer.js',
    'launcher/web/modules/kshop-cart-controller.js',
    'launcher/web/modules/kshop-catalog-presenter.js',
    'launcher/web/modules/kshop-owned-inventory-presenter.js',
    'launcher/web/modules/kshop-tooltip-presenter.js',
    'launcher/web/modules/kshop-procurement-navigation.js',
    'launcher/web/modules/npcshop-material-navigation.js',
    'launcher/web/modules/npcshop-secondary-pages.js',
    'launcher/web/modules/crafting-detail-presenter.js',
    'launcher/web/modules/skills-library.js',
    'launcher/web/modules/skills-loadout.js',
    'launcher/web/modules/skills-trainer.js',
    'launcher/web/modules/skills-interactions.js',
    'launcher/web/modules/skills-render.js',
    'launcher/web/modules/skills-diagnostics.js',
    'launcher/web/modules/equipment-tuning-model.js',
    'launcher/web/modules/equipment-tuning-decision-presenter.js',
    'launcher/web/modules/equipment-tuning-confirmation.js',
    'launcher/web/modules/equipment-tuning-interaction.js',
    'launcher/web/modules/equipment-tuning-write-lifecycle.js',
    'launcher/web/modules/equipment-tuning-loadout-lifecycle.js',
    'launcher/web/modules/equipment-tuning-source-marker.js',
    'launcher/web/modules/equipment-tuning-render.js',
    'tools/test-panel-runtime.js',
    'tools/test-workbench-lifecycle.js',
    'tools/test-workbench-focus.js',
    'tools/test-workbench-focus-integration.js',
    'tools/test-workbench-primitives.js',
    'tools/test-workbench-profile.js',
    'tools/test-workbench-components.js',
    'tools/test-workbench-inspection-viewport.js',
    'tools/test-inventory-workbench-lazy-closure.js',
    'tools/test-inventory-runtime.js',
    'tools/test-inventory-workbench-modules.js',
    'tools/test-inventory-workbench-preparation-menu.js',
    'tools/test-character-build-session.js',
    'tools/test-character-build-candidate-tuning.js',
    'tools/test-character-build-candidate-tooltip.js',
    'tools/test-character-build-facet-counts.js',
    'tools/test-character-build-projection.js',
    'tools/test-character-build-item-use.js',
    'tools/test-kshop-presenters.js',
    'tools/test-npcshop-secondary-pages.js',
    'tools/test-skills-ui-modules.js',
    'tools/test-equipment-tuning-model.js',
    'tools/test-equipment-tuning-confirmation.js',
    'tools/test-equipment-tuning-interaction.js',
    'tools/test-equipment-tuning-source-marker.js',
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
    var cleanCss = uiRatchet.maskComments(css);
    metrics.panelsCssLines = css.split(/\r?\n/).length - (css.endsWith('\n') ? 1 : 0);
    metrics.panelsCssAggregateLines = metrics.panelsCssLines;
    metrics.panelsCssFacadeLines = fs.readFileSync(abs(cssRel), 'utf8').split(/\r?\n/).length - 1;
    var resolvedCss = cssBundleReader.resolveCssBundle(abs(cssRel), {rootDir:abs('launcher/web')});
    metrics.panelsCssFragments = resolvedCss.files.slice(1).map(function (file) {
        var source = fs.readFileSync(file, 'utf8');
        return {
            file:path.relative(ROOT, file).replace(/\\/g, '/'),
            lines:source.split(/\r?\n/).length - (source.endsWith('\n') ? 1 : 0)
        };
    });
    var importantLedgerRel = 'tools/workbench-important-ledger.json';
    var importantLedger = exists(importantLedgerRel)
        ? JSON.parse(read(importantLedgerRel))
        : {};
    var importantEntries = Array.isArray(importantLedger.entries)
        ? importantLedger.entries
        : [];
    var resolvedCssSet = {};
    var importantActual = {};
    resolvedCss.files.slice(1).forEach(function(file) {
        var rel = path.relative(ROOT, file).replace(/\\/g, '/');
        resolvedCssSet[rel] = true;
        var findings = uiRatchet.scanImportantDeclarations(
            fs.readFileSync(file, 'utf8'),
            rel
        );
        if (findings.length) {
            importantActual[rel] =
                (importantActual[rel] || []).concat(findings);
        }
    });
    var importantEntryByFile = {};
    var invalidImportantEntries = [];
    importantEntries.forEach(function(entry) {
        var valid = entry
            && typeof entry.file === 'string'
            && resolvedCssSet[entry.file]
            && Number.isInteger(entry.ceiling)
            && entry.ceiling > 0
            && (entry.classification === 'migration-debt'
                || entry.classification === 'semantic-exception')
            && typeof entry.reason === 'string'
            && entry.reason.trim().length > 0
            && typeof entry.exitCondition === 'string'
            && entry.exitCondition.trim().length > 0
            && !importantEntryByFile[entry.file];
        if (!valid) {
            invalidImportantEntries.push(entry);
            return;
        }
        importantEntryByFile[entry.file] = entry;
    });
    expect(importantLedger.schemaVersion === 1
            && importantLedger.kind === 'cf7-workbench-important-ledger'
            && importantLedger.scope === 'resolved-launcher/web/css/panels.css'
            && invalidImportantEntries.length === 0,
        'WB133', 'workbench !important ledger has an invalid schema, target, or duplicate entry',
        importantLedgerRel, null, invalidImportantEntries.slice(0, 8));
    var unregisteredImportant = Object.keys(importantActual).filter(function(rel) {
        return !importantEntryByFile[rel];
    });
    expect(unregisteredImportant.length === 0, 'WB133',
        'resolved workbench CSS contains !important outside the checked-in ledger',
        unregisteredImportant[0], null, unregisteredImportant.map(function(rel) {
            return {file:rel, count:importantActual[rel].length};
        }));
    var importantOverCeiling = [];
    var importantBelowCeiling = [];
    importantEntries.forEach(function(entry) {
        if (!entry || !importantEntryByFile[entry.file]) return;
        var count = (importantActual[entry.file] || []).length;
        if (count > entry.ceiling) {
            importantOverCeiling.push({
                file:entry.file,
                ceiling:entry.ceiling,
                current:count,
                sample:(importantActual[entry.file] || [])[entry.ceiling]
            });
        } else if (count < entry.ceiling) {
            importantBelowCeiling.push({
                file:entry.file,
                ceiling:entry.ceiling,
                current:count
            });
        }
    });
    expect(importantOverCeiling.length === 0, 'WB133',
        'workbench !important debt exceeded its per-file ledger ceiling',
        importantOverCeiling[0] && importantOverCeiling[0].file,
        importantOverCeiling[0] && importantOverCeiling[0].sample
            && importantOverCeiling[0].sample.line,
        importantOverCeiling.slice(0, 8));
    if (importantBelowCeiling.length) {
        finding('warning', 'WB134',
            'workbench !important debt dropped; lower or remove its ledger entry in the same change',
            importantLedgerRel, null, importantBelowCeiling);
    }
    var hiddenImportantEntry = importantEntryByFile[
        'launcher/web/css/workbench/utilities.css'
    ];
    expect(hiddenImportantEntry
            && hiddenImportantEntry.classification === 'semantic-exception'
            && hiddenImportantEntry.exceptionId === 'WB-HIDDEN-001'
            && hiddenImportantEntry.ceiling === 1,
        'WB133', 'semantic hidden priority exception must remain explicitly registered',
        importantLedgerRel);
    var previousImportantLedgerSource = releaseTree ? null
        : uiRatchet.previousCommittedFile(
            ROOT,
            importantLedgerRel,
            fs.readFileSync(abs(importantLedgerRel), 'utf8')
        );
    var raisedImportantCeilings = [];
    if (previousImportantLedgerSource) {
        try {
            var previousImportantEntries =
                (JSON.parse(previousImportantLedgerSource).entries || []);
            var previousImportantByFile = {};
            previousImportantEntries.forEach(function(entry) {
                if (entry && entry.file) previousImportantByFile[entry.file] = entry;
            });
            importantEntries.forEach(function(entry) {
                var previous = entry && previousImportantByFile[entry.file];
                if (previous && Number.isInteger(previous.ceiling)
                        && entry.ceiling > previous.ceiling) {
                    raisedImportantCeilings.push({
                        file:entry.file,
                        previous:previous.ceiling,
                        current:entry.ceiling
                    });
                }
            });
        } catch (previousImportantLedgerError) {
            raisedImportantCeilings.push({
                error:'previous !important ledger is not valid JSON'
            });
        }
    }
    expect(raisedImportantCeilings.length === 0, 'WB133',
        'workbench !important ceilings are monotonic and may not rise',
        importantLedgerRel, null, raisedImportantCeilings);
    metrics.importantLedger = {
        registeredFiles:importantEntries.length,
        currentFiles:Object.keys(importantActual).length,
        currentDeclarations:Object.keys(importantActual).reduce(function(total, rel) {
            return total + importantActual[rel].length;
        }, 0)
    };
    var ratchetConfigRel = 'tools/workbench-ui-ratchet-baseline.json';
    var ratchetConfig = exists(ratchetConfigRel)
        ? JSON.parse(read(ratchetConfigRel))
        : {};
    expect(ratchetConfig.schemaVersion === 1
            && ratchetConfig.kind === 'cf7-workbench-ui-ratchet-baseline'
            && ratchetConfig.sourceCommit === uiRatchet.F0_BASELINE_COMMIT
            && ratchetConfig.cssScope === 'launcher/web/css/'
            && Array.isArray(ratchetConfig.excludedCss)
            && ratchetConfig.excludedCss.length === 0
            && ratchetConfig.profileGate
            && typeof ratchetConfig.profileGate.enabled === 'boolean'
            && ratchetConfig.profileGate.activation === 'explicit-e-batch-handshake',
        'WB121', 'workbench CSS ratchet scope or immutable baseline identity changed',
        ratchetConfigRel);
    var ratchetScope = String(ratchetConfig.cssScope || '');
    var ratchetExcluded = ratchetConfig.excludedCss || [];
    var ratchetCeilings = ratchetConfig.debtCeilings || {};
    var ceilingShapeValid = uiRatchet.DEBT_RULES.every(function(rule) {
        return Number.isInteger(ratchetCeilings[rule]) && ratchetCeilings[rule] >= 0;
    }) && Object.keys(ratchetCeilings).length === uiRatchet.DEBT_RULES.length;
    expect(ceilingShapeValid, 'WB130',
        'workbench CSS debt ceilings must cover the exact F0 rule set with non-negative integers',
        ratchetConfigRel);
    var ratchetCssFiles = resolvedCss.files.slice(1).map(function(file) {
        return path.relative(ROOT, file).replace(/\\/g, '/');
    }).filter(function(rel) {
        return rel.indexOf(ratchetScope) === 0 && ratchetExcluded.indexOf(rel) === -1;
    });
    var cssDebtRatchet;
    try {
        cssDebtRatchet = releaseTree
            ? uiRatchet.auditCurrentCssDebt({root:ROOT, files:ratchetCssFiles})
            : uiRatchet.auditCssDebt({
                root:ROOT,
                baselineCommit:ratchetConfig.sourceCommit,
                files:ratchetCssFiles
            });
    } catch (ratchetError) {
        cssDebtRatchet = {
            available:false,
            baselineCommit:ratchetConfig.sourceCommit,
            error:ratchetError && ratchetError.message
        };
    }
    metrics.cssDebtRatchet = {
        available:!!cssDebtRatchet.available,
        currentTreeOnly:!!cssDebtRatchet.currentTreeOnly,
        baselineCommit:cssDebtRatchet.baselineCommit || null,
        files:cssDebtRatchet.files || 0,
        touchedFiles:cssDebtRatchet.touchedFiles || 0,
        sourceBaselineCounts:cssDebtRatchet.baselineCounts || null,
        configuredCeilings:ceilingShapeValid ? ratchetCeilings : null,
        currentCounts:cssDebtRatchet.currentCounts || null
    };
    expect(cssDebtRatchet.available, 'WB121',
        'workbench CSS ratchet must resolve its immutable Git baseline and current-tree diff',
        ratchetConfigRel, null, cssDebtRatchet.error);
    var ratchetCodes = {
        rawColor:'WB122',
        fontBelow9:'WB123',
        font9PlayerText:'WB124',
        rawDuration:'WB125',
        rawEasing:'WB126',
        transitionAll:'WB127'
    };
    (cssDebtRatchet.violations || []).forEach(function(violation) {
        var sample = violation.samples && violation.samples[0];
        finding('error', ratchetCodes[violation.rule],
            'workbench CSS debt increased or remains on a line touched since the immutable baseline',
            sample && sample.file, sample && sample.line, violation);
    });
    if (cssDebtRatchet.available && ceilingShapeValid) {
        var ceilingMismatches = uiRatchet.DEBT_RULES.filter(function(rule) {
            return cssDebtRatchet.currentCounts[rule] > ratchetCeilings[rule]
                || !releaseTree && ratchetCeilings[rule] > cssDebtRatchet.baselineCounts[rule];
        }).map(function(rule) {
            return {
                rule:rule,
                sourceBaseline:releaseTree ? null
                    : cssDebtRatchet.baselineCounts[rule],
                ceiling:ratchetCeilings[rule],
                current:cssDebtRatchet.currentCounts[rule]
            };
        });
        expect(ceilingMismatches.length === 0, 'WB130',
            'CSS debt counts must stay at or below monotonic ceilings, which cannot exceed the immutable source baseline',
            ratchetConfigRel, null, ceilingMismatches);

        var loweredDebt = uiRatchet.DEBT_RULES.filter(function(rule) {
            return cssDebtRatchet.currentCounts[rule] < ratchetCeilings[rule];
        }).map(function(rule) {
            return {
                rule:rule,
                ceiling:ratchetCeilings[rule],
                current:cssDebtRatchet.currentCounts[rule]
            };
        });
        if (loweredDebt.length) {
            finding('warning', 'WB131',
                'CSS debt dropped below its ceiling; lower the checked-in ceiling in the same cleanup',
                ratchetConfigRel, null, loweredDebt);
        }

        var previousConfigSource = releaseTree ? null : uiRatchet.previousCommittedFile(
            ROOT,
            ratchetConfigRel,
            fs.readFileSync(abs(ratchetConfigRel), 'utf8')
        );
        var raisedCeilings = [];
        if (previousConfigSource) {
            try {
                var previousConfig = JSON.parse(previousConfigSource);
                var previousCeilings = previousConfig.debtCeilings || {};
                raisedCeilings = uiRatchet.DEBT_RULES.filter(function(rule) {
                    return Number.isInteger(previousCeilings[rule])
                        && ratchetCeilings[rule] > previousCeilings[rule];
                }).map(function(rule) {
                    return {rule:rule, previous:previousCeilings[rule], current:ratchetCeilings[rule]};
                });
            } catch (previousConfigError) {
                raisedCeilings.push({error:'previous ratchet config is not valid JSON'});
            }
        }
        expect(raisedCeilings.length === 0, 'WB130',
            'CSS debt ceilings are monotonic and must not rise above the previous committed config',
            ratchetConfigRel, null, raisedCeilings);
    }
    var cssFacade = fs.readFileSync(abs(cssRel), 'utf8');
    var hiddenUtilityRel = 'launcher/web/css/workbench/utilities.css';
    var hiddenUtility = exists(hiddenUtilityRel) ? read(hiddenUtilityRel) : '';
    expect(/@import\s+url\(["']\.\/workbench\/utilities\.css["']\)\s*;\s*$/.test(cssFacade),
        'WB038', 'semantic hidden utility must be the terminal panels.css import', cssRel);
    expect(!/@layer\b/.test(hiddenUtility)
            && /\.workbench-shell\s+\[hidden\]\s*\{\s*display\s*:\s*none\s*!important\s*;\s*\}/.test(hiddenUtility)
            && /WB-HIDDEN-001/.test(hiddenUtility),
        'WB039', 'semantic hidden compatibility rule or migration ledger is incomplete',
        hiddenUtilityRel);
    var importantDisplayOverrides = [];
    resolvedCss.files.slice(1).forEach(function(file) {
        if (path.resolve(file) === abs(hiddenUtilityRel)) return;
        var rel = path.relative(ROOT, file).replace(/\\/g, '/');
        importantDisplayOverrides = importantDisplayOverrides.concat(
            uiRatchet.scanVisibleImportantDisplayDeclarations(
                fs.readFileSync(file, 'utf8'),
                rel
            )
        );
    });
    metrics.importantVisibleDisplayOverrides = importantDisplayOverrides.length;
    expect(importantDisplayOverrides.length === 0, 'WB040',
        'feature/skin CSS must not outrank the semantic hidden invariant with visible !important display',
        importantDisplayOverrides[0] && importantDisplayOverrides[0].file,
        importantDisplayOverrides[0] && importantDisplayOverrides[0].line,
        importantDisplayOverrides.slice(0, 8));
    expect(/\.workbench-shell\s*\{[\s\S]*?width\s*:\s*1024px\s*;[\s\S]*?height\s*:\s*576px\s*;/.test(cleanCss), 'WB010', 'workbench shell must retain the 1024x576 logical canvas', cssRel);
    expect(/--workbench-compact-tile-size\s*:\s*48px/.test(cleanCss) && /--workbench-compact-icon-size\s*:\s*40px/.test(cleanCss) && /--workbench-compact-gap\s*:\s*4px/.test(cleanCss), 'WB011', 'shared compact geometry must retain 48/40/4 tokens', cssRel);
    expect(/\.workbench-shell button,[\s\S]*?min-width\s*:\s*24px\s*;[\s\S]*?min-height\s*:\s*24px/.test(cleanCss), 'WB012', 'workbench icon controls need the shared 24px hit-target floor', cssRel);
    expect(/kshop-checkout-btn[\s\S]*?min-height\s*:\s*40px/.test(cleanCss), 'WB013', 'workbench primary actions need the shared 40px height floor', cssRel);
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
        var matches = uiRatchet.maskComments(fs.readFileSync(file, 'utf8'))
            .match(/(?:#3dd5ff|rgba?\(\s*61\s*,\s*213\s*,\s*255\b)/gi) || [];
        dlsLiterals = dlsLiterals.concat(matches);
    });
    metrics.dlsAccentLiterals = dlsLiterals.length;
    if (dlsLiterals.length) finding('warning', 'WB103', 'DLS accent literals remain outside semantic role tokens', cssRel, null, {count:dlsLiterals.length});

    var reducedBlocks = cleanCss.match(/@media\s*\(prefers-reduced-motion\s*:\s*reduce\)[\s\S]{0,800}/gi) || [];
    var hasRootReducedMotion = reducedBlocks.some(function (block) { return /workbench-shell|\[data-workbench/.test(block) && /animation\s*:\s*none/.test(block); });
    warnUnless(hasRootReducedMotion, 'WB104', 'no shared workbench-root reduced-motion animation shutdown was found', cssRel);
    warnUnless(/--wb-motion-(?:micro|standard|structural)/.test(css), 'WB105', 'shared semantic motion-duration tokens are not implemented yet', cssRel);
    var largestCssFragment = metrics.panelsCssFragments.reduce(function (largest, item) {
        return !largest || item.lines > largest.lines ? item : largest;
    }, null);
    if (largestCssFragment && largestCssFragment.lines > 10000) finding('warning', 'WB106', 'a panels.css fragment remains above the split threshold', largestCssFragment.file, null, {lines:largestCssFragment.lines, threshold:10000});

    var workbenchSource = exists('launcher/web/modules/workbench.js')
        ? read('launcher/web/modules/workbench.js')
        : '';
    var profileStructureReady = uiRatchet.profileContractImplemented(workbenchSource);
    var profileHandshake = uiRatchet.evaluateProfileGate(
        (ratchetConfig.profileGate || {}).enabled,
        profileStructureReady
    );
    var productionCalls = [];
    var unexpectedDualPaneReferences = [];
    var productionModuleFiles = collectFiles('launcher/web/modules', '.js')
        .filter(isProductionModule);
    productionModuleFiles.forEach(function(rel) {
        var source = read(rel);
        productionCalls = productionCalls.concat(uiRatchet.scanDualPaneCalls(source, rel));
        if (rel !== 'launcher/web/modules/workbench.js') {
            unexpectedDualPaneReferences = unexpectedDualPaneReferences.concat(
                uiRatchet.scanUnexpectedDualPaneReferences(source, rel)
            );
        }
    });
    var missingProfiles = productionCalls.filter(function(call) { return !call.hasProfile; });
    var invalidProfiles = productionCalls.filter(function(call) { return call.hasProfile && !call.valid; });
    var configuredProductionCalls = (ratchetConfig.profileGate || {}).productionCalls || [];
    var invalidProductionCallInventory = configuredProductionCalls.filter(function(entry) {
        return !entry || typeof entry.file !== 'string' || !entry.file
            || !Number.isInteger(entry.count) || entry.count < 1;
    });
    var actualCallCounts = {};
    productionCalls.forEach(function(call) {
        actualCallCounts[call.file] = (actualCallCounts[call.file] || 0) + 1;
    });
    var actualProductionCallInventory = Object.keys(actualCallCounts).sort().map(function(file) {
        return {file:file, count:actualCallCounts[file]};
    });
    var expectedProductionCallInventory = configuredProductionCalls.map(function(entry) {
        return {
            file:String((entry || {}).file || '').replace(/\\/g, '/'),
            count:(entry || {}).count
        };
    }).sort(function(left, right) {
        return left.file.localeCompare(right.file);
    });
    var productionCallInventoryValid = invalidProductionCallInventory.length === 0
        && JSON.stringify(actualProductionCallInventory)
            === JSON.stringify(expectedProductionCallInventory);
    var shellGridExceptions = ratchetConfig.shellGridExceptions || [];
    var invalidGridExceptions = shellGridExceptions.filter(function(exception) {
        return !exception || !exception.file || !exception.selector || !exception.property
            || !exception.reason || !exception.exitCondition;
    });
    var unapprovedShellGrid = (cssDebtRatchet.shellGrid || []).filter(function(item) {
        return !shellGridExceptions.some(function(exception) {
            return exception.file === item.file
                && exception.selector === item.selector
                && exception.property === item.property;
        });
    });
    metrics.profileStaticGate = {
        enabled:profileHandshake.enabled,
        handshakeValid:profileHandshake.valid,
        configuredEnabled:profileHandshake.configuredEnabled,
        structureReady:profileHandshake.structureReady,
        activation:(ratchetConfig.profileGate || {}).activation || null,
        validProfiles:uiRatchet.VALID_PROFILES,
        productionCalls:productionCalls.length,
        missingProfiles:missingProfiles.length,
        invalidProfiles:invalidProfiles.length,
        unexpectedReferences:unexpectedDualPaneReferences.length,
        productionCallInventoryValid:productionCallInventoryValid,
        expectedProductionCalls:expectedProductionCallInventory,
        actualProductionCalls:actualProductionCallInventory,
        shellGridOverrides:unapprovedShellGrid.length,
        registeredShellGridExceptions:shellGridExceptions.length,
        disabledReason:profileHandshake.enabled ? null
            : (profileHandshake.reason || 'explicit E-batch profile gate remains disabled')
    };
    expect(profileHandshake.valid, 'WB128',
        'profile static gate requires an explicit flag and structural shell contract to change in the same E batch',
        ratchetConfigRel, null, profileHandshake);
    expect(invalidGridExceptions.length === 0, 'WB129',
        'shell-grid exception entries require an exact target, reason, and exit condition',
        ratchetConfigRel, null, invalidGridExceptions[0]);
    if (profileHandshake.enabled) {
        expect(missingProfiles.length === 0 && invalidProfiles.length === 0, 'WB128',
            'production DualPaneShell calls must declare a valid closed profile',
            (missingProfiles[0] || invalidProfiles[0] || {}).file,
            (missingProfiles[0] || invalidProfiles[0] || {}).line,
            {missing:missingProfiles.slice(0, 12), invalid:invalidProfiles.slice(0, 12)});
        expect(unexpectedDualPaneReferences.length === 0, 'WB128',
            'production consumers must not alias or indirectly reference DualPaneShell',
            unexpectedDualPaneReferences[0] && unexpectedDualPaneReferences[0].file,
            unexpectedDualPaneReferences[0] && unexpectedDualPaneReferences[0].line,
            unexpectedDualPaneReferences.slice(0, 12));
        expect(productionCallInventoryValid, 'WB128',
            'production DualPaneShell consumer/count inventory must match the reviewed profile gate',
            ratchetConfigRel, null, {
                invalid:invalidProductionCallInventory,
                expected:expectedProductionCallInventory,
                actual:actualProductionCallInventory
            });
        expect(unapprovedShellGrid.length === 0, 'WB129',
            'feature CSS must not own shell-level grid outside a declared profile or migration exception',
            unapprovedShellGrid[0] && unapprovedShellGrid[0].file,
            unapprovedShellGrid[0] && unapprovedShellGrid[0].line,
            unapprovedShellGrid.slice(0, 12));
    }
}

if (exists('launcher/web/modules/panel-scale.js')) {
    var panelScale = uiRatchet.maskJavaScriptCode(read('launcher/web/modules/panel-scale.js'));
    expect(/PanelScale/.test(panelScale) && /ResizeObserver/.test(panelScale) && /detach/.test(panelScale), 'WB014', 'PanelScale must own resize observation and deterministic detach', 'launcher/web/modules/panel-scale.js');
}

if (exists('launcher/web/modules/workbench.js')) {
    var wbRel = 'launcher/web/modules/workbench.js';
    var workbenchSourceForAudit = read(wbRel);
    var workbench = uiRatchet.maskJavaScriptCode(workbenchSourceForAudit);
    ['DualPaneShell','ViewChrome','ItemCard','ItemGrid','GridDensityController','InteractionBroker','PointerDragController'].forEach(function (name) {
        expect(new RegExp(name + '\\s*:\\s*' + name).test(workbench), 'WB015', 'shared workbench export is missing', wbRel, null, name);
    });
    var focusRel = 'launcher/web/modules/workbench-focus.js';
    var focusSource = exists(focusRel) ? read(focusRel) : '';
    var focus = uiRatchet.maskJavaScriptCode(focusSource);
    var focusNoComments = uiRatchet.maskJavaScriptComments(focusSource);
    var hasFocusTrap = /FocusScope/.test(focus)
        && /keydown/.test(focusNoComments) && /focusin/.test(focusNoComments);
    var hasInert = /\.inert\s*=|setAttribute\(['"]inert['"]/.test(focusNoComments);
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
var componentSource = exists(componentRel) ? read(componentRel) : '';
var components = uiRatchet.maskJavaScriptCode(componentSource);
var componentsNoComments = uiRatchet.maskJavaScriptComments(componentSource);
warnUnless(/SecondaryPage\s*:\s*SecondaryPage/.test(components), 'WB109', 'shared SecondaryPage primitive is not exported from the workbench layer', componentRel);
warnUnless(/ChoiceGroup\s*:\s*ChoiceGroup/.test(components), 'WB110', 'shared ChoiceGroup primitive is not exported from the workbench layer', componentRel);
warnUnless(/CommitBar\s*:\s*CommitBar/.test(components), 'WB111', 'shared CommitBar primitive is not exported from the workbench layer', componentRel);
warnUnless(/new FocusScope/.test(components)
        && /_requestClose\('escape'/.test(componentsNoComments),
    'WB116', 'SecondaryPage must share the canonical nested focus scope and Escape close path', componentRel);

var inspectionViewportRel = 'launcher/web/modules/workbench-inspection-viewport.js';
var inspectionViewport = exists(inspectionViewportRel)
    ? uiRatchet.maskJavaScriptCode(read(inspectionViewportRel)) : '';
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

var shellRel = 'launcher/web/modules/workbench.js';
var shellSource = exists(shellRel) ? read(shellRel) : '';
var shellProfileRel = 'launcher/web/modules/workbench-profile.js';
var shellProfileSource = exists(shellProfileRel) ? read(shellProfileRel) : '';
var layoutProfiles = [
    'catalog-decision',
    'archive-reference',
    'transfer-pair',
    'library-action-strip',
    'library-decision',
    'character-build'
];
expect(/WorkbenchShellProfile\.requireProfile\(options\.profile\)/.test(shellSource)
        && /setAttribute\(['"]data-profile['"],\s*profile\)/.test(shellSource)
        && /DualPaneShell\.prototype\.setProfile\s*=\s*WorkbenchShellProfile\.setProfile/.test(shellSource)
        && !/data-workbench-profile|function requireLayoutProfile/.test(shellSource),
    'WB142', 'DualPaneShell must consume the single closed profile owner and project only data-profile',
    shellRel);
layoutProfiles.forEach(function (profile) {
    expect(new RegExp("'" + profile + "'\\s*:\\s*true").test(shellProfileSource),
        'WB143', 'closed profile owner is missing a canonical profile',
        shellProfileRel, null, profile);
    expect(css.indexOf('[data-profile="' + profile + '"]') !== -1,
        'WB144', 'canonical profile has no shell-level CSS projection',
        'launcher/web/css/workbench/profiles.css', null, profile);
});
[
    'launcher/web/css/workbench/crafting.css',
    'launcher/web/css/workbench/inventory.css',
    'launcher/web/css/workbench/skills.css',
    'launcher/web/css/workbench/skins.css',
    'launcher/web/css/workbench/loadout-picker.css',
    'launcher/web/css/workbench/character-build.css',
    'launcher/web/css/workbench/equipment-tuning.css'
].forEach(function (rel) {
    if (!exists(rel)) return;
    var source = read(rel).replace(/\/\*[\s\S]*?\*\//g, '');
    var rule = /([^{}]*\.workbench-body[^{}]*)\{([^{}]*)\}/g;
    var match;
    while ((match = rule.exec(source)) !== null) {
        if (!/grid-template-(?:columns|rows)\s*:/.test(match[2])) continue;
        finding('error', 'WB042',
            'feature CSS must not own shell-level workbench grid templates',
            rel, lineOf(source, match.index), match[1].trim().slice(0, 180));
    }
});
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
    'launcher/web/modules/skills.js':1240, // 2026-08-16 Web UI 语义音效工程合法增长（data-audio-cue/cue() 迁移），1208 行基线显式上调
    'launcher/web/modules/equipment-tuning-view.js':1200,
    'launcher/web/modules/equipment-tuning-write-lifecycle.js':360,
    'launcher/web/modules/equipment-tuning-loadout-lifecycle.js':300,
    'launcher/web/modules/workbench-inspection-viewport.js':420,
    'launcher/web/modules/character-build/character-build-mutation.js':260,
    'launcher/web/modules/character-build/character-build-drug-layout.js':170,
    'launcher/web/modules/character-build/character-build-session-contract.js':220,
    'launcher/web/modules/loadout-picker/loadout-picker-action-view.js':240,
    'launcher/web/modules/character-build/character-build-tuning-adapter.js':380,
    'launcher/web/modules/character-build/character-build-tuning-ports.js':140,
    'launcher/web/modules/character-build/character-build-candidate-eligibility.js':120,
    'launcher/web/modules/character-build/character-build-candidate-tooltip.js':320,
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-state.js':340,
    'launcher/web/modules/character-build/character-build-facet-counts.js':220,
    'launcher/web/modules/character-build/character-build-stats-view.js':360,
    'launcher/web/modules/character-build/character-build-doll-preview.js':340,
    'launcher/web/modules/character-build/character-build-template.js':100,
    'launcher/web/modules/character-build/character-build-loadout-presenter.js':260,
    'launcher/web/modules/loadout-picker/loadout-picker-slot-grid.js':140,
    'launcher/web/modules/loadout-picker/loadout-picker-drop-policy.js':200,
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-drag.js':260,
    'launcher/web/modules/loadout-picker/loadout-picker-candidate-pane.js':560,
    'launcher/web/modules/loadout-picker/loadout-picker.js':240,
    'launcher/web/modules/merc/merc-loadout-drop-policy.js':80,
    'launcher/web/modules/merc/merc-loadout-channel.js':185,
    'launcher/web/modules/merc/merc-loadout-picker.js':720,
    'launcher/web/modules/character-build/character-build-tuning.js':380,
    'launcher/web/modules/character-build/character-build-slot-transition.js':100,
    'launcher/web/modules/character-build/character-build-pose.js':90,
    // 物品使用只扩展候选投影的窄闭集；transport/lifecycle 已拆到独立模块。
    'launcher/web/modules/character-build/character-build-projection.js':200,
    'launcher/web/modules/character-build/character-build-transport.js':180,
    'launcher/web/modules/character-build/character-build-item-use.js':360,
    // 2026-08-31 奖励/物品使用迁移的有限增长：保留单一通道事务与选择恢复语义，避免制造碎片化加载依赖。
    'launcher/web/modules/character-build/character-build-item-use-channel.js':260,
    'launcher/web/modules/character-build/character-build-candidate-channel.js':360,
    'launcher/web/modules/character-build-session.js':740,
    'launcher/web/modules/character-build-view.js':760,
    // 控制器仅保留 item-use 组合/锁态 seam，协议与换面编排均已拆分。
    'launcher/web/modules/character-build.js':640,
    'launcher/web/modules/inventory-tuning-scope.js':200,
    'launcher/web/modules/inventory-storage-workbench.js':960,
    'launcher/web/modules/inventory-workbench-preparation-menu.js':440,
    'launcher/web/modules/crafting-inventory-organizer.js':200,
    'launcher/web/modules/inventory-workbench-feature-loader.js':180,
    'launcher/web/modules/inventory-workbench.js':550,
    'launcher/web/modules/npcshop.js':1040, // 2026-08-16 Web UI 语义音效工程合法增长（声明式 cue 绑定迁移），1016 行基线显式上调
    'launcher/web/modules/workbench.js':1000
};
metrics.moduleLines = {};
Object.keys(moduleThresholds).forEach(function (rel) {
    if (!exists(rel)) return;
    var count = lines(rel);
    metrics.moduleLines[rel] = count;
    if (count > moduleThresholds[rel]) finding('warning', 'WB112', 'workbench module exceeds its split threshold', rel, null, {lines:count, threshold:moduleThresholds[rel]});
});

var candidateStateRel = 'launcher/web/modules/loadout-picker/loadout-picker-candidate-state.js';
if (exists(candidateStateRel)) {
    var candidateStateSource = read(candidateStateRel);
    var candidateViewSource = read('launcher/web/modules/loadout-picker/loadout-picker.js');
    var candidateCssSource = read('launcher/web/css/workbench/loadout-picker.css');
    var candidateCopies = ['unselected','loading','empty','error','ready']
        .map(function(kind) {
            var match = new RegExp(kind
                + ":\\{\\s*statement:'([^']+)',\\s*nextStep:'([^']+)'")
                .exec(candidateStateSource);
            return match ? {kind:kind, statement:match[1], nextStep:match[2]} : null;
        });
    expect(candidateCopies.every(Boolean)
            && new Set(candidateCopies.map(function(item) { return item.statement; })).size === 5
            && new Set(candidateCopies.map(function(item) { return item.nextStep; })).size === 5,
        'WB041', 'Character Build candidate states need distinct statement and next-step copy',
        candidateStateRel);
    expect(candidateViewSource.indexOf('new CandidateStateModule.CandidateState') !== -1
            && candidateViewSource.indexOf("_candidateFence = 'candidate-view-'") !== -1
            && candidateStateSource.indexOf('WorkbenchPrimitives.EntityTile.bindActivation') !== -1
            && candidateStateSource.indexOf('inspectable:true') !== -1
            && candidateStateSource.indexOf('actionable:false') !== -1
            && candidateStateSource.indexOf('onBlocked:function') !== -1
            && candidateStateSource.indexOf('data-candidate-retry') !== -1,
        'WB042', 'Character Build blocked candidates and retry must use the bounded presentation ports',
        candidateStateRel);
    var blockedCardRule = /\.character-build-candidate\[data-blocked="true"\]\s*\{([^}]*)\}/
        .exec(candidateCssSource);
    var blockedReasonRule = /\.character-build-candidate-blocked-reason\s*\{([^}]*)\}/
        .exec(candidateCssSource);
    expect(!!blockedCardRule && /opacity\s*:\s*1\b/.test(blockedCardRule[1])
            && !!blockedReasonRule && /opacity\s*:\s*1\b/.test(blockedReasonRule[1])
            && /color\s*:\s*var\(--wb-text\)/.test(blockedReasonRule[1]),
        'WB043', 'Character Build blocked reason must keep normal body contrast and card opacity',
        'launcher/web/css/workbench/loadout-picker.css');
}

var candidateFacetRel =
    'launcher/web/modules/character-build/character-build-facet-counts.js';
if (exists(candidateFacetRel)) {
    var candidateFacetSource = read(candidateFacetRel);
    var candidateFacetView = read(
        'launcher/web/modules/character-build-view.js') + '\n' + read(
        'launcher/web/modules/character-build/character-build-loadout-presenter.js');
    var candidateFacetCss = read(
        'launcher/web/css/workbench/character-build.css');
    expect(candidateFacetSource.indexOf(
            "if (kind === 'drug') return model.useCounts['药剂']") !== -1
            && candidateFacetSource.indexOf("if (id === '手枪2')") !== -1
            && candidateFacetSource.indexOf(
                "return count == null ? '—' : String(count)") !== -1
            && candidateFacetView.indexOf(
                'FacetCountsModule.normalize(this._snapshot.candidateFacets)')
                !== -1
            && candidateFacetView.indexOf(
                'FacetCountsModule.decorateSlot') !== -1,
        'WB044',
        'Character Build facet counts must preserve 11+4 mapping, zero/unknown and snapshot adoption',
        candidateFacetRel);
    expect(!/Bridge\.send|PanelRequestMux|domain\s*:|cmd\s*:/
            .test(candidateFacetSource),
        'WB045',
        'Character Build facet count presentation must not issue business requests',
        candidateFacetRel);
    expect(/\.character-build-slot-count\s*\{/.test(candidateFacetCss)
            && /\.character-build-slot-count\[data-count-state="unknown"\]/
                .test(candidateFacetCss),
        'WB046',
        'Character Build candidate count badge needs explicit known/unknown CSS',
        'launcher/web/css/workbench/character-build.css');
}

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
var tooltipRawSource = exists(tooltipRel) ? read(tooltipRel) : '';
var tooltipSource = uiRatchet.maskJavaScriptComments(tooltipRawSource);
var tooltipCode = uiRatchet.maskJavaScriptCode(tooltipRawSource);
expect(!!tooltipSource, 'WB029', 'shared PanelTooltip runtime is missing', tooltipRel);
if (tooltipSource) {
    var hasFixedOwners = /var _pointerAsyncBinding = null;/.test(tooltipSource)
        && /var _keyboardAsyncBinding = null;/.test(tooltipSource)
        && /var _inputModality = 'keyboard';/.test(tooltipSource);
    var hasInputFacts = /addEventListener\('pointerdown', notePointerInput, true\)/.test(tooltipSource)
        && /addEventListener\('keydown', noteKeyboardInput, true\)/.test(tooltipSource);
    var hasOwnerHistory = /_activeAsyncBindings|restoreActiveBinding|markActiveBinding/.test(tooltipCode);
    var hasDomainPolicyKnob =
        /\b(?:restoreOnPointerLeave|restoreOnBlur|focusMode|tooltipPolicy|ownerPolicy|keepAfterClick)\b/.test(tooltipCode);
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
var panelRuntime = exists(panelRuntimeRel)
    ? uiRatchet.maskJavaScriptCode(read(panelRuntimeRel)) : '';
warnUnless(/PanelRequestMux/.test(panelRuntime) && /PanelResponseRouter/.test(panelRuntime), 'WB113', 'shared panel request mux/router has not been extracted yet', panelRuntimeRel);
if (panelRuntime) expect(exists('tools/test-panel-runtime.js'), 'WB017', 'shared panel runtime needs a pure Node regression entry', 'tools/test-panel-runtime.js');
if (exists('launcher/web/modules/workbench-lifecycle.js')) expect(exists('tools/test-workbench-lifecycle.js'), 'WB018', 'workbench lifecycle needs a pure Node regression entry', 'tools/test-workbench-lifecycle.js');
if (exists('launcher/web/modules/workbench-focus.js')) expect(exists('tools/test-workbench-focus.js'), 'WB019', 'workbench focus scope needs a pure Node regression entry', 'tools/test-workbench-focus.js');
if (exists('launcher/web/modules/workbench-primitives.js')) expect(exists('tools/test-workbench-primitives.js'), 'WB020', 'workbench primitives need a pure Node regression entry', 'tools/test-workbench-primitives.js');
if (exists('launcher/web/modules/workbench-profile.js')) expect(exists('tools/test-workbench-profile.js'), 'WB130', 'workbench profile contract needs a pure Node regression entry', 'tools/test-workbench-profile.js');
warnUnless(/OwnedInventoryPane\s*:\s*OwnedInventoryPane/.test(components), 'WB114', 'shared OwnedInventoryPane controller has not been extracted yet', componentRel);
warnUnless(/@layer\s+workbench\.components/.test(read('launcher/web/css/workbench/components.css')),
    'WB115', 'shared workbench cascade layers have not been introduced', 'launcher/web/css/workbench/components.css');
var focusStatesRel = 'launcher/web/css/workbench/states.css';
var focusStatesSource = read(focusStatesRel);
var focusOutlineOverrides = [];
collectFiles('launcher/web/css/workbench', '.css').forEach(function(rel) {
    focusOutlineOverrides = focusOutlineOverrides.concat(
        uiRatchet.scanUnlayeredFocusOutlineOverrides(read(rel), rel));
});
expect(/@layer\s+workbench\.states\s*\{[\s\S]*?\.workbench-shell\s+:where\([^}]*\):not\(\.character-build-slot\)(:not\(\.merc-loadout-slot\))?:focus-visible\s*\{[\s\S]*?outline:2px solid var\(--wb-focus\);[\s\S]*?outline-offset:2px;/
        .test(focusStatesSource)
        && !/\.workbench-shell\[data-profile\][\s\S]*?:focus-visible\s*\{/
            .test(focusStatesSource),
    'WB135',
    'named workbench.states must own the production focus ring and exclude only the Character slot',
    focusStatesRel);
expect(focusOutlineOverrides.length === 0,
    'WB135',
    'production workbench CSS contains an unlayered focus outline override outside the slot/state contracts',
    focusOutlineOverrides[0] && focusOutlineOverrides[0].file,
    focusOutlineOverrides[0] && focusOutlineOverrides[0].line,
    focusOutlineOverrides.slice(0, 12));
metrics.focusCascade = {
    unlayeredOverrides:focusOutlineOverrides.length,
    bridgePresent:/\.workbench-shell\[data-profile\][\s\S]*?:focus-visible\s*\{/
        .test(focusStatesSource)
};

var registryRel = 'launcher/web/modules/panels-lazy-registry.js';
if (exists(registryRel)) {
    var registry = uiRatchet.maskJavaScriptComments(read(registryRel));
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
        'modules/workbench-profile.js',
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
        'modules/kshop-procurement-navigation.js',
        'modules/kshop.js'
    ], 'WB022', 'KShop presenter modules must load before the facade', registryRel);
    var workbenchBootOrder = [
        'modules/inventory-runtime.js',
        'modules/inventory-ui.js',
        'modules/inventory-workbench-config.js',
        'modules/inventory-workbench-preparation-menu.js',
        'modules/inventory-workbench-navigation.js',
        'modules/inventory-workbench-header.js',
        'modules/inventory-workbench-quick-transfer.js',
        'modules/inventory-workbench-owned-view.js',
        'modules/inventory-workbench-feature-loader.js',
        'modules/inventory-storage-workbench.js',
        'modules/inventory-workbench.js'
    ];
    expectOrdered(lazyBlock('workbench'), workbenchBootOrder,
        'WB023', 'inventory workbench storage closure must load before the facade',
        registryRel);
    var tuningFeatureOrder = [
        'modules/asset-timeline.js',
        'modules/dressup-doll-renderer.js',
        'modules/workbench-inspection-viewport.js',
        'modules/equipment-inspector.js',
        'modules/equipment-tuning-runtime.js',
        'modules/equipment-tuning-model.js',
        'modules/equipment-tuning-decision-presenter.js',
        'modules/equipment-tuning-render.js',
        'modules/equipment-tuning-confirmation.js',
        'modules/equipment-tuning-interaction.js',
        'modules/equipment-tuning-write-lifecycle.js',
        'modules/equipment-tuning-loadout-lifecycle.js',
        'modules/equipment-tuning-source-marker.js',
        'modules/equipment-tuning-view.js',
        'modules/inventory-tuning-scope.js'
    ];
    var buildFeatureOrder = [
        'modules/character-build/character-build-mutation.js',
        'modules/character-build/character-build-drug-layout.js',
        'modules/character-build/character-build-session-contract.js',
        'modules/character-build-session.js',
        'modules/loadout-picker/loadout-picker-action-view.js',
        'modules/character-build/character-build-tuning-adapter.js',
        'modules/character-build/character-build-tuning-ports.js',
        'modules/character-build/character-build-candidate-tooltip.js',
        'modules/loadout-picker/loadout-picker-candidate-state.js',
        'modules/character-build/character-build-facet-counts.js',
        'modules/character-build/character-build-stats-view.js',
        'modules/character-build/character-build-doll-preview.js',
        'modules/character-build/character-build-template.js',
        'modules/character-build/character-build-loadout-presenter.js',
        'modules/loadout-picker/loadout-picker-slot-grid.js',
        'modules/loadout-picker/loadout-picker-drop-policy.js',
        'modules/loadout-picker/loadout-picker-candidate-drag.js',
        'modules/loadout-picker/loadout-picker-candidate-pane.js',
        'modules/loadout-picker/loadout-picker.js',
        'modules/character-build-view.js',
        'modules/character-build/character-build-tuning.js',
        'modules/character-build/character-build-slot-transition.js',
        'modules/character-build/character-build-pose.js',
        'modules/character-build/character-build-candidate-eligibility.js',
        'modules/character-build/character-build-projection.js',
        'modules/character-build/character-build-transport.js',
        'modules/character-build/character-build-item-use.js',
        'modules/character-build/character-build-item-use-channel.js',
        'modules/character-build/character-build-candidate-channel.js',
        'modules/character-build.js'
    ];
    tuningFeatureOrder.concat(buildFeatureOrder).forEach(function (dependency) {
        expect(lazyBlock('workbench').indexOf(dependency) === -1,
            'WB136', 'inventory storage boot closure preloads a view-level feature dependency',
            registryRel, null, dependency);
    });
    var featureLoaderSource = read('launcher/web/modules/inventory-workbench-feature-loader.js');
    expectOrdered(featureLoaderSource, tuningFeatureOrder,
        'WB137', 'inventory workbench tuning feature closure is incomplete or out of order',
        'launcher/web/modules/inventory-workbench-feature-loader.js');
    expectOrdered(featureLoaderSource, buildFeatureOrder,
        'WB137', 'inventory workbench Character Build feature closure is incomplete or out of order',
        'launcher/web/modules/inventory-workbench-feature-loader.js');
    expect(featureLoaderSource.indexOf("Promise.reject(new Error('LazyLoader is unavailable'))") !== -1
            && featureLoaderSource.indexOf('load returned a non-thenable') !== -1
            && featureLoaderSource.indexOf('closure did not initialize') !== -1,
        'WB138', 'inventory workbench feature loader must fail closed when its lazy closure is unavailable or incomplete',
        'launcher/web/modules/inventory-workbench-feature-loader.js');
    expectOrdered(lazyBlock('crafting'), [
        'modules/dressup-doll-renderer.js',
        'modules/workbench-inspection-viewport.js',
        'modules/equipment-inspector.js',
        'modules/crafting-inspector.js',
        'modules/crafting-detail-presenter.js',
        'modules/crafting-runtime.js',
        'modules/crafting.js'
    ], 'WB035', 'crafting inspection consumers must load after the shared viewport', registryRel);
    var craftingSource = read('launcher/web/modules/crafting.js');
    expectOrdered(craftingSource, [
        'modules/inventory-runtime.js',
        'modules/inventory-ui.js',
        'modules/inventory-workbench-config.js',
        'modules/inventory-workbench-quick-transfer.js',
        'modules/inventory-workbench-owned-view.js',
        'modules/inventory-storage-workbench.js',
        'modules/crafting-inventory-organizer.js'
    ], 'WB139', 'crafting organizer child closure is out of order',
        'launcher/web/modules/crafting.js');
    expect(craftingSource.indexOf("Panels.open('workbench'") === -1,
        'WB140', 'crafting organizer must remain a local child view, not a workbench panel alias',
        'launcher/web/modules/crafting.js');
    var workbenchConfigSource = read('launcher/web/modules/inventory-workbench-config.js');
    var workbenchFacadeSource = read('launcher/web/modules/inventory-workbench.js');
    var workbenchHeaderSource = read('launcher/web/modules/inventory-workbench-header.js');
    expect(workbenchConfigSource.indexOf('resolveReturnTarget') === -1
            && workbenchConfigSource.indexOf('hostOwner') === -1
            && workbenchFacadeSource.indexOf('function returnToPanel(') === -1
            && workbenchFacadeSource.indexOf('openReturnTarget(') === -1
            && workbenchFacadeSource.indexOf('onReturnPanel') === -1
            && workbenchHeaderSource.indexOf("'return-panel'") === -1
            && workbenchHeaderSource.indexOf('options.returnTarget') === -1
            && workbenchHeaderSource.indexOf('options.onReturnPanel') === -1,
        'WB141', 'standalone inventory workbench retains a crafting-owner fallback or return-target alias',
        'launcher/web/modules/inventory-workbench.js');
    expectOrdered(lazyBlock('npcshop'), [
        'modules/npcshop-material-navigation.js',
        'modules/npcshop-secondary-pages.js',
        'modules/npcshop.js'
    ], 'WB024', 'NPC material navigation and secondary presenters must load before the facade', registryRel);
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
    var buildSource = uiRatchet.maskPowerShellComments(read(buildRel)).replace(/\\/g, '/');
    var releasePolicySource = uiRatchet.maskPowerShellComments(
        read(releasePolicyRel)).replace(/\\/g, '/');
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
    expect(releasePolicySource.indexOf('tools/test-workbench-ui-ratchet.js') !== -1
            && releasePolicySource.indexOf("'workbench-ui-ratchet-regression'") !== -1
            && releasePolicySource.indexOf('tools/audit-workbench-ui.js') !== -1
            && releasePolicySource.indexOf("'workbench-ui-release-tree-audit'") !== -1
            && releasePolicySource.indexOf("'--release-tree'") !== -1
            && releasePolicySource.indexOf("'--strict-warnings'") !== -1,
        'WB132', 'Launcher release policy must consume the ratchet regression and strict current-tree UI audit',
        releasePolicyRel);
    expect(releasePolicySource.indexOf('tools/test-workbench-inspection-viewport.js') !== -1
            && releasePolicySource.indexOf("'workbench-inspection-viewport'") !== -1,
        'WB036', 'Launcher release policy must execute the shared inspection viewport regression gate',
        releasePolicyRel);
    expect(releasePolicySource.indexOf('tools/test-inventory-workbench-preparation-menu.js') !== -1
            && releasePolicySource.indexOf("'inventory-preparation-menu'") !== -1,
        'WB133', 'Launcher release policy must execute the fixed preparation menu regression gate',
        releasePolicyRel);
}

collectFiles('launcher/web/modules', '.js').filter(isProductionModule).forEach(function (rel) {
    expect(!/addMessageListener\s*\(/.test(uiRatchet.maskJavaScriptCode(read(rel))),
        'WB026', 'domain modules must not install direct Bridge response listeners outside PanelResponseRouter', rel);
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
