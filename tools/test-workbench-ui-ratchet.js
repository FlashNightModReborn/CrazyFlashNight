#!/usr/bin/env node
'use strict';

var childProcess = require('child_process');
var fs = require('fs');
var os = require('os');
var path = require('path');
var ratchet = require('./lib/workbench-ui-ratchet.js');

var passed = 0;
var failed = 0;

function check(name, condition) {
    if (condition) {
        passed++;
        console.log('ok - ' + name);
    } else {
        failed++;
        console.error('not ok - ' + name);
    }
}

function rules(scan) {
    return scan.findings.map(function(item) { return item.rule; });
}

check('F0 baseline identity is the reviewed ADR commit',
    ratchet.F0_BASELINE_COMMIT === 'c96f4c3d750561022b706c72a4d53050431e627d');
check('F0 debt rule set is closed',
    ratchet.DEBT_RULES.join('|')
    === 'rawColor|fontBelow9|font9PlayerText|rawDuration|rawEasing|transitionAll');

var rawColors = ratchet.scanCss(
    '.a { color:#fff; box-shadow:0 0 2px rgb(1, 2, 3); }\n'
    + '.b { color:var(--wb-white-text); border-color:rgba(var(--dls-crystal-rgb),.2); }',
    'fixture.css'
);
check('raw color scanner covers general hex and rgb literals',
    rules(rawColors).filter(function(rule) { return rule === 'rawColor'; }).length === 2);

var namedColors = ratchet.scanCss(
    '.named { color:crimson; border-color:rebeccapurple; background:navy; }',
    'fixture.css'
);
check('raw color scanner covers the complete CSS named-color family',
    rules(namedColors).filter(function(rule) { return rule === 'rawColor'; }).length === 3);

var tokenScope = ratchet.scanCss(
    ':root { --wb-test:#fff; --wb-time:120ms; }\n'
    + '.not-a-token { color:#fff; transition:opacity 120ms ease; }',
    'launcher/web/css/workbench/tokens.css'
);
check('tokens.css exempts only custom-property definitions',
    rules(tokenScope).filter(function(rule) { return rule === 'rawColor'; }).length === 1
    && rules(tokenScope).filter(function(rule) { return rule === 'rawDuration'; }).length === 1
    && rules(tokenScope).filter(function(rule) { return rule === 'rawEasing'; }).length === 1);

var importantFixture = ratchet.scanImportantDeclarations(
    '.real { display:none ! important; content:"!important"; }\n'
    + '/* .fake { color:red !important; } */\n'
    + ".also-real { color:red!important; content:'still !important'; }",
    'fixture.css'
);
check('important scanner ignores comments and strings but records declaration priorities',
    importantFixture.length === 2
    && importantFixture[0].line === 1
    && importantFixture[1].line === 3);

var visibleImportantDisplay = ratchet.scanVisibleImportantDisplayDeclarations(
    '.spaced { display:flex ! important }\n'
    + '.hidden { display:none ! important }\n'
    + '.quoted { content:"display:grid!important"; }\n'
    + '.terminal { display:grid!important }\n'
    + '.reset[hidden] { all:unset!important }',
    'fixture.css'
);
check('hidden priority scanner covers visible display, all reset, spacing and omitted semicolons',
    visibleImportantDisplay.length === 3
    && visibleImportantDisplay[0].line === 1
    && visibleImportantDisplay[1].line === 4
    && visibleImportantDisplay[2].line === 5);

var focusOutlineFixture = [
    '@layer workbench.states { button:focus-visible { outline:2px solid var(--wb-focus); } }',
    '@media (min-width:1px) { .feature:focus-visible { outline:none; } }',
    '.field { outline:0; }',
    '.workbench-drop-rejected { outline:1px dashed var(--wb-role-reject); }',
    '.character-build-slot:focus-visible { outline:0; }',
    '.character-build-slot:focus-visible .character-build-slot-card { outline:2px solid var(--wb-focus); }'
].join('\n');
var focusOutlineFindings = ratchet.scanUnlayeredFocusOutlineOverrides(
    focusOutlineFixture, 'launcher/web/css/workbench/character-build.css');
check('G5 focus scanner ignores named-layer/state/slot contracts but catches unlayered overrides',
    focusOutlineFindings.length === 2
    && focusOutlineFindings[0].property === 'outline'
    && focusOutlineFindings[1].property === 'outline');

var type = ratchet.scanCss(
    '.help-copy { font-size:9px; }\n'
    + '.corner-badge { font-size:9px; }\n'
    + '.tiny { font:8px/1.2 sans-serif; }\n'
    + '.clamped { font-size:clamp(8px, 1vw, 10px); }',
    'fixture.css'
);
check('typography scanner rejects 9px player copy but permits an explicit badge role',
    rules(type).filter(function(rule) { return rule === 'font9PlayerText'; }).length === 1);
check('typography scanner covers font shorthand below 9px',
    rules(type).filter(function(rule) { return rule === 'fontBelow9'; }).length === 2);

var motion = ratchet.scanCss(
    '.a { transition:all .12s ease; animation:pulse 1s linear infinite; }\n'
    + '.b { transition:opacity var(--wb-motion-micro) var(--wb-ease-standard); }\n'
    + '.c { transition:none; animation:none; }',
    'fixture.css'
);
check('motion scanner covers transition all and naked durations/easing',
    rules(motion).filter(function(rule) { return rule === 'transitionAll'; }).length === 1
    && rules(motion).filter(function(rule) { return rule === 'rawDuration'; }).length === 2
    && rules(motion).filter(function(rule) { return rule === 'rawEasing'; }).length === 2);

function readRepo(relative) {
    return fs.readFileSync(path.resolve(__dirname, '..', relative), 'utf8');
}

var g3WorkbenchFiles = [
    'launcher/web/css/workbench/skills.css',
    'launcher/web/css/workbench/entities.css',
    'launcher/web/css/workbench/inventory.css',
    'launcher/web/css/workbench/core.css',
    'launcher/web/css/workbench/equipment-tuning.css',
    'launcher/web/css/workbench/equipment-inspector.css',
    'launcher/web/css/workbench/skins.css',
    'launcher/web/css/workbench/character-build.css',
    'launcher/web/css/workbench/components.css'
];
var g3WorkbenchSources = {};
var g3MotionFindings = [];
g3WorkbenchFiles.forEach(function(relative) {
    var source = readRepo(relative);
    g3WorkbenchSources[relative] = source;
    g3MotionFindings = g3MotionFindings.concat(
        ratchet.scanCss(source, relative).findings.filter(function(item) {
            return item.rule === 'rawDuration' || item.rule === 'rawEasing';
        })
    );
});
function isVisibilityDelayContract(item) {
    return /launcher\/web\/css\/workbench\/components\.css$/.test(item.file)
        && (item.property === 'transition-delay' && item.value === '0s'
            || item.property === 'transition'
                && /visibility 0s linear var\(--wb-motion-structural\)/.test(item.value));
}
var unexpectedG3Motion = g3MotionFindings.filter(function(item) {
    return !isVisibilityDelayContract(item);
});
var g3WorkbenchSource = g3WorkbenchFiles.map(function(relative) {
    return g3WorkbenchSources[relative];
}).join('\n');
check('G4 workbench fragments use semantic duration/easing contracts, preserving only the visibility-delay contract',
    unexpectedG3Motion.length === 0
    && !/\.001(?:ms|s)\b/.test(g3WorkbenchSource)
    && !/\btransition\s*:[^;}]*\bbackground(?!-color)\b/i.test(g3WorkbenchSource));

var sharedMotionSource = readRepo('launcher/web/css/workbench/motion.css');
var foundationKShopSource = readRepo('launcher/web/css/panels/foundation-rest.css');
var g3ScopedMotionSource = g3WorkbenchSource + '\n' + foundationKShopSource;
check('G3 shared motion owns neutral busy/reject keyframes and removes legacy feature names',
    (sharedMotionSource.match(/@keyframes\s+wb-pulse-busy\b/g) || []).length === 1
    && (sharedMotionSource.match(/@keyframes\s+wb-reject-pulse\b/g) || []).length === 1
    && /@keyframes\s+wb-reject-pulse[\s\S]*?var\(--wb-role-reject\)/.test(sharedMotionSource)
    && !/\b(?:kshop-pulse|skills-reject-pulse)\b/.test(g3ScopedMotionSource));
check('G3 consumers map reject, busy and ambient motion to their exact semantic tokens',
    (g3WorkbenchSources['launcher/web/css/workbench/skills.css']
        .match(/animation:wb-reject-pulse var\(--wb-motion-reject\) var\(--wb-ease-standard\) 2/g) || []).length === 2
    && /animation:wb-pulse-busy var\(--wb-motion-busy\) var\(--wb-ease-standard\) infinite/
        .test(g3WorkbenchSources['launcher/web/css/workbench/inventory.css'])
    && /animation:wb-pulse-busy var\(--wb-motion-busy\) var\(--wb-ease-standard\) infinite/
        .test(g3WorkbenchSources['launcher/web/css/workbench/core.css'])
    && (foundationKShopSource
        .match(/animation:wb-pulse-busy var\(--wb-motion-busy\) var\(--wb-ease-standard\) infinite/g) || []).length === 2
    && /animation:equipment-tuning-core-pulse var\(--wb-motion-ambient\) var\(--wb-ease-standard\) infinite/
        .test(g3WorkbenchSources['launcher/web/css/workbench/equipment-tuning.css']));
check('G3 KShop foundation transitions use allowed properties with semantic duration and standard easing',
    /\.kshop-grid\s*\{[\s\S]*?transition:opacity var\(--wb-motion-standard\) var\(--wb-ease-standard\);[\s\S]*?\}/
        .test(foundationKShopSource)
    && /\.kshop-cart-row\s*\{[^}]*transition:background-color var\(--wb-motion-micro\) var\(--wb-ease-standard\);[^}]*\}/
        .test(foundationKShopSource)
    && !/\.kshop-(?:close-btn|card|add-btn|checkout-btn|claim-btn|dlg-btn)\s*\{[^}]*transition:[^;}]*var\(--wb-motion-(?:micro|standard)\)(?!\s+var\(--wb-ease-standard\))/
        .test(foundationKShopSource));
check('G4 removes redundant feature-local reduced-motion shutdown blocks',
    !/@media\s*\(prefers-reduced-motion:\s*reduce\)/.test(
        g3WorkbenchSources['launcher/web/css/workbench/inventory.css'])
    && !/@media\s*\(prefers-reduced-motion:\s*reduce\)/.test(
        g3WorkbenchSources['launcher/web/css/workbench/equipment-inspector.css'])
    && !/@media\s*\(prefers-reduced-motion:\s*reduce\)/.test(
        g3WorkbenchSources['launcher/web/css/workbench/skins.css'])
    && !/@media\s*\(prefers-reduced-motion:\s*reduce\)/.test(
        g3WorkbenchSources['launcher/web/css/workbench/character-build.css']));
check('G4 keeps only the Tuning ambient static-state compensation locally',
    /@media\s*\(prefers-reduced-motion:reduce\)\s*\{\s*\.equipment-tuning-stone-core::after\s*\{\s*opacity:\.55;\s*\}\s*\}/
        .test(g3WorkbenchSources['launcher/web/css/workbench/equipment-tuning.css'])
    && !/@media\s*\(prefers-reduced-motion:reduce\)[\s\S]*?\.equipment-tuning-stone-core::after\s*\{[^}]*\b(?:animation|transition)\s*:/
        .test(g3WorkbenchSources['launcher/web/css/workbench/equipment-tuning.css']));
check('G4 shared reducer owns shell descendants and exact out-of-shell workbench tooltip loading pulses',
    /\.workbench-shell,\s*\.workbench-shell \*,\s*\.workbench-shell \.workbench-secondary-page,\s*\.workbench-shell \*::before,\s*\.workbench-shell \*::after,\s*\.arena-xshell,\s*\.arena-xshell \*,\s*\.arena-xshell \*::before,\s*\.arena-xshell \*::after\s*\{[^}]*animation:none !important;[^}]*transition:none !important;/
        .test(sharedMotionSource)
    && /#panel-container:is\(\[data-panel="kshop"\],\[data-panel="workbench"\],\[data-panel="npcshop"\],\[data-panel="crafting"\],\[data-panel="skills"\],\[data-panel="loot"\]\)\s*~\s*#panel-tooltip\s*:is\(\.kshop-tt-loading,\s*\.flash-tt-loading\)\s*\{\s*animation:none;\s*\}/
        .test(sharedMotionSource));
check('G4 preserves SecondaryPage delayed visibility exit instead of erasing the 0s linear contract',
    /visibility 0s linear var\(--wb-motion-structural\)/.test(
        g3WorkbenchSources['launcher/web/css/workbench/components.css'])
    && /transition-delay:0s;/.test(
        g3WorkbenchSources['launcher/web/css/workbench/components.css']));

var g5FocusFiles = fs.readdirSync(path.resolve(
    __dirname, '..', 'launcher/web/css/workbench'))
    .filter(function(name) { return /\.css$/i.test(name); })
    .map(function(name) { return 'launcher/web/css/workbench/' + name; });
var g5FocusFindings = [];
g5FocusFiles.forEach(function(relative) {
    g5FocusFindings = g5FocusFindings.concat(
        ratchet.scanUnlayeredFocusOutlineOverrides(readRepo(relative), relative));
});
var statesSource = readRepo('launcher/web/css/workbench/states.css');
var characterFocusSource = g3WorkbenchSources[
    'launcher/web/css/workbench/character-build.css'];
check('G5 layered focus baseline explicitly excludes only the Character slot and has no bridge',
    /@layer\s+workbench\.states\s*\{[\s\S]*?\.workbench-shell\s+:where\([^}]*\):not\(\.character-build-slot\):focus-visible\s*\{[\s\S]*?outline:2px solid var\(--wb-focus\);[\s\S]*?outline-offset:2px;/
        .test(statesSource)
    && !/\.workbench-shell\[data-profile\][\s\S]*?:focus-visible\s*\{/
        .test(statesSource));
check('G5 production workbench CSS has no unlayered focus outline override beyond the slot/state contracts',
    g5FocusFindings.length === 0);
check('G5 Character slot is the sole outer-ring exception with an exact inner token ring',
    /\.character-build-slot:focus-visible\s*\{\s*outline:0;\s*\}/
        .test(characterFocusSource)
    && /\.character-build-slot:focus-visible\s+\.character-build-slot-card\s*\{[^}]*outline:2px solid var\(--wb-focus\);[^}]*outline-offset:-2px;[^}]*\}/
        .test(characterFocusSource)
    && !/\.character-build-slot:hover\s+\.character-build-slot-card\s*\{[^}]*outline\s*:/
        .test(characterFocusSource));

var characterBuildSource = readRepo('launcher/web/modules/character-build.js');
var equipmentInspectorSource = readRepo('launcher/web/modules/equipment-inspector.js');
var equipmentTuningRenderSource = readRepo('launcher/web/modules/equipment-tuning-render.js');
check('G4 retains bounded instantaneous renderer motion reads without a shared registry or listener',
    /animate:!\(global\.matchMedia && global\.matchMedia\('\(prefers-reduced-motion: reduce\)'\)\.matches\)/
        .test(characterBuildSource)
    && /var animationEnabled = !\(window\.matchMedia && window\.matchMedia\('\(prefers-reduced-motion: reduce\)'\)\.matches\);/
        .test(equipmentInspectorSource)
    && /function prefersReducedMotion\(\)\s*\{[\s\S]*?window\.matchMedia\('\(prefers-reduced-motion: reduce\)'\)\.matches;[\s\S]*?\}/
        .test(equipmentTuningRenderSource)
    && !/\b(?:WorkbenchReducedMotion|ReducedMotionRegistry|MotionPreferenceRegistry)\b/.test(
        characterBuildSource + '\n' + equipmentInspectorSource + '\n' + equipmentTuningRenderSource));

var touched = ratchet.parseUnifiedZeroDiff(
    'diff --git a/a.css b/a.css\n'
    + '--- a/a.css\n'
    + '+++ b/a.css\n'
    + '@@ -2,0 +3,2 @@\n'
    + '+x\n+y\n'
);
check('zero-context diff parser records exact current-tree lines',
    !!(touched['a.css'] && touched['a.css'][3] && touched['a.css'][4] && !touched['a.css'][2]));

var baselineFinding = [{rule:'rawColor', file:'a.css', line:1}];
var currentFinding = [{rule:'rawColor', file:'a.css', line:2}];
var evaluated = ratchet.evaluateDebtRatchet(
    baselineFinding,
    currentFinding,
    {'a.css':{2:true}}
);
check('equal debt totals cannot hide a touched-line substitution',
    evaluated.violations.length === 1
    && evaluated.violations[0].delta === 0
    && evaluated.violations[0].touchedCount === 1);

var multiline = ratchet.evaluateDebtRatchet(
    [{rule:'rawColor', file:'a.css', line:1, endLine:3}],
    [{rule:'rawColor', file:'a.css', line:1, endLine:3}],
    {'a.css':{3:true}}
);
check('touched-line gate covers multiline declaration values',
    multiline.violations.length === 1 && multiline.violations[0].touchedCount === 1);

var calls = ratchet.scanDualPaneCalls(
    'new Workbench.DualPaneShell({title:"profile: fake"});\n'
    + 'new Workbench.DualPaneShell({profile:"not-real"});\n'
    + 'new Workbench.DualPaneShell({/* profile: fake */ title:"x", profile:resolveProfile(view)});\n'
    + 'new Workbench.DualPaneShell({profile});\n'
    + 'new Workbench.DualPaneShell({profile:"transfer-pair"});\n'
    + 'new Workbench.DualPaneShell({profile:isArchive ? /* closed */ "archive-reference" : ("catalog-decision")});\n'
    + 'new Workbench.DualPaneShell({profile:mode === "build" ? "character-build" : '
        + '(mode === "tuning" ? "library-decision" : "transfer-pair")});\n'
    + 'new Workbench.DualPaneShell({profile:isBuild ? "character-build" : resolveProfile(view)});\n'
    + 'new Workbench.DualPaneShell({profile:configuredProfile || "transfer-pair"});',
    'consumer.js'
);
check('profile scanner accepts only a valid literal or a closed conditional with valid literal leaves',
    calls.length === 9
    && !calls[0].hasProfile
    && calls[1].hasProfile && !calls[1].valid
    && calls[2].hasProfile && !calls[2].valid
    && calls[3].hasProfile && !calls[3].valid
    && calls[4].valid && calls[4].literalProfile === 'transfer-pair'
    && calls[5].valid && calls[5].closedProfiles.length === 2
    && calls[6].valid && calls[6].closedProfiles.length === 3
    && !calls[7].valid
    && !calls[8].valid);

var bypassCalls = ratchet.scanDualPaneCalls(
    'new Workbench.DualPaneShell(options);\n'
    + 'new Workbench.DualPaneShell({profile:"transfer-pair", profile:"catalog-decision"});\n'
    + 'new Workbench.DualPaneShell({profile:"transfer-pair", ...override});\n'
    + 'new Workbench.DualPaneShell({profile:() => ready ? "transfer-pair" : "catalog-decision"});\n'
    + 'new Workbench.DualPaneShell({profile:"transfer-pair", ["profile"]:"catalog-decision"});',
    'consumer.js'
);
check('profile scanner counts and fail-closes non-literals, duplicate/override keys, and arrow values',
    bypassCalls.length === 5
    && !bypassCalls[0].hasProfile && !bypassCalls[0].valid
    && bypassCalls.slice(1).every(function(call) { return !call.valid; }));

function checkProfileContract(name, source, expected) {
    var parses = true;
    try {
        new Function(source);
    } catch (_) {
        parses = false;
    }
    check(name, parses && ratchet.profileContractImplemented(source) === expected);
}

checkProfileContract(
    'profile structure ignores contract text inside a JavaScript string',
    'function DualPaneShell(options) {'
        + "var misleading = \"options.profile this._root.setAttribute('data-profile', profile)\";"
        + '}',
    false
);
checkProfileContract(
    'profile structure ignores contract text inside comments',
    'function DualPaneShell(options) {'
        + '/* WorkbenchShellProfile.requireProfile(options.profile); */'
        + '// this._root.setAttribute("data-profile", profile)\n'
        + '}',
    false
);
checkProfileContract(
    'profile structure accepts the production literal contract',
    'function DualPaneShell(options) {options = options || {};'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    true
);
checkProfileContract(
    'profile structure permits empty parameter defaults, ASI initialization, and unrelated if',
    'function DualPaneShell(options = {}) {'
        + 'initializeUnrelatedState()\n'
        + 'if (options.debug) this._debug = true;'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'if (options.trace) { this._trace = true; }'
        + 'this._root.setAttribute("data-profile", profile); }',
    true
);
checkProfileContract(
    'profile structure does not confuse unrelated profile, computed this, or dataset state',
    'function DualPaneShell(options) {options ||= {};'
        + 'var telemetry = {}; telemetry.profile = "boot";'
        + 'this["debug"] = true;'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'var other = {dataset:{}}; other.dataset.profile = "x";'
        + 'this._root.setAttribute("data-profile", profile); }',
    true
);
checkProfileContract(
    'profile structure permits caught throws and object-method returns in initialization',
    'function DualPaneShell(options) {options = options || {};'
        + 'var helpers = {read:function() { return options; }, method() { return options; }};'
        + 'try { throw new Error("handled"); } catch (error) { helpers.error = error; }'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    true
);
checkProfileContract(
    'profile structure rejects a parameter default that synthesizes profile',
    'function DualPaneShell(options = {profile:"transfer-pair"}) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects contract tokens outside DualPaneShell',
    'function DualPaneShell(options) { this.root = root; }'
        + 'function unrelated(options) {'
        + 'var profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects duplicate DualPaneShell declarations',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }'
        + 'function DualPaneShell(options) { this._root = makeElement("div"); }',
    false
);
checkProfileContract(
    'profile structure rejects a constructor-local validator shadow',
    'function DualPaneShell(options) {'
        + 'const WorkbenchShellProfile = {requireProfile:function(value) { return value; }};'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects a literal write that bypasses the validated binding',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", options.profile); }',
    false
);
checkProfileContract(
    'profile structure rejects validation inside a nested function',
    'function DualPaneShell(options) { function never() {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }}',
    false
);
checkProfileContract(
    'profile structure rejects validation inside a dead branch',
    'function DualPaneShell(options) { if (false) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }}',
    false
);
checkProfileContract(
    'profile structure rejects validation inside a loop-controlled branch',
    'function DualPaneShell(options) { for (; false;) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }}',
    false
);
checkProfileContract(
    'profile structure rejects direct reassignment of the validated binding',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'profile = options.profile;'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects duplicate direct validation calls',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'const other = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects a nested duplicate validation call',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'function duplicate() {'
        + 'return WorkbenchShellProfile.requireProfile(options.profile);'
        + '}'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects a computed duplicate validator access',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'WorkbenchShellProfile["requireProfile"](options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects flat destructuring reassignment',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + '({value:profile} = options);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects multiline destructuring reassignment',
    'function DualPaneShell(options) {\n'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);\n'
        + '({\nvalue:\nprofile\n} = options);\n'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects nested destructuring reassignment',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + '({value:{nested:profile}} = options);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure permits a nested helper before the literal root write',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'function helper() { return options; }'
        + 'this._root.setAttribute("data-profile", profile); }',
    true
);
checkProfileContract(
    'profile structure rejects a direct return before validation',
    'function DualPaneShell(options) {return;'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects a conditional constructor return before validation',
    'function DualPaneShell(options) {'
        + 'if (options.skip) { return; }'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects explicit root initialization before validation',
    'function DualPaneShell(options) {'
        + 'if (options.mount) this._root = makeElement("div");'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects an unbraced conditional literal root write',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'if (false) this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects a direct throw before the literal root write',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'throw new Error("stop");'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);
checkProfileContract(
    'profile structure rejects a braced conditional literal root write',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'if (options.ready) { this._root.setAttribute("data-profile", profile); }}',
    false
);
checkProfileContract(
    'profile structure rejects duplicate literal root data-profile writes',
    'function DualPaneShell(options) {'
        + 'const profile = WorkbenchShellProfile.requireProfile(options.profile);'
        + 'this._root.setAttribute("data-profile", profile);'
        + 'this._root.setAttribute("data-profile", profile); }',
    false
);

var indirectReferences = ratchet.scanUnexpectedDualPaneReferences(
    'new Workbench.DualPaneShell({profile:"transfer-pair"});\n'
    + 'var Shell = Workbench.DualPaneShell;\n'
    + 'var Other = Workbench["DualPaneShell"];\n'
    + 'var Local = DualPaneShell;',
    'consumer.js'
);
check('profile reference scanner permits only direct constructor use in production consumers',
    indirectReferences.length === 3
    && indirectReferences.every(function(item) {
        return item.file === 'consumer.js' && item.line > 1;
    }));

var phantomCalls = ratchet.scanDualPaneCalls(
    "var sample = \"new Workbench.DualPaneShell({profile:'transfer-pair'})\";\n"
    + '// new Workbench.DualPaneShell({profile:"transfer-pair"});\n'
    + '/* new Workbench.DualPaneShell({profile:"transfer-pair"}); */',
    'consumer.js'
);
check('production call scanner ignores constructor text inside strings and comments',
    phantomCalls.length === 0);

var maskedCode = ratchet.maskJavaScriptCode(
    '// PanelScale ResizeObserver detach\n'
    + 'var fake = "DualPaneShell:DualPaneShell";\n'
    + "var pattern = /['\"]PanelScale/;\n"
    + 'function PanelScale() { new ResizeObserver(detach); }'
);
check('JavaScript code masking ignores comments, strings, and regex literals',
    /function PanelScale/.test(maskedCode)
    && /ResizeObserver\(detach\)/.test(maskedCode)
    && maskedCode.indexOf('DualPaneShell:DualPaneShell') === -1);

var psWithoutComments = ratchet.maskPowerShellComments(
    "# tools/check-workbench-css-bundle.js\n"
    + "$tool = 'tools/check-workbench-css-bundle.js' # real invocation input\n"
);
check('PowerShell masking removes comments but preserves command strings',
    psWithoutComments.indexOf("$tool = 'tools/check-workbench-css-bundle.js'") >= 0
    && psWithoutComments.trim().indexOf('#') === -1);

var gateOff = ratchet.evaluateProfileGate(false, false);
var gateOn = ratchet.evaluateProfileGate(true, true);
var flagTooEarly = ratchet.evaluateProfileGate(true, false);
var structureTooEarly = ratchet.evaluateProfileGate(false, true);
check('profile gate handshake accepts only the fully disabled and fully enabled states',
    gateOff.valid && !gateOff.enabled && gateOn.valid && gateOn.enabled);
check('profile gate handshake rejects flag-first and structure-first activation',
    !flagTooEarly.valid && !structureTooEarly.valid
    && /flag is enabled/.test(flagTooEarly.reason)
    && /contract appeared/.test(structureTooEarly.reason));

var grid = ratchet.scanCss(
    '.inventory-workbench .workbench-body { grid-template-columns:1fr 1fr; }\n'
    + '.workbench-shell[data-profile="transfer-pair"] .workbench-body { grid-template-columns:1fr 1fr; }\n'
    + '.workbench-shell[data-profile=character-build] .workbench-body,'
    + '.legacy .workbench-body { grid-template-rows:1fr; }',
    'fixture.css'
);
check('shell-grid preparation rejects mixed legacy branches but permits closed profile ownership',
    grid.shellGrid.length === 2);

var fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-workbench-ratchet-'));
try {
    childProcess.execFileSync('git', ['init', '-q'], {cwd:fixtureRoot});
    childProcess.execFileSync('git', ['config', 'user.email', 'ratchet@example.invalid'], {cwd:fixtureRoot});
    childProcess.execFileSync('git', ['config', 'user.name', 'Ratchet Fixture'], {cwd:fixtureRoot});
    childProcess.execFileSync('git', ['config', 'core.autocrlf', 'false'], {cwd:fixtureRoot});
    fs.writeFileSync(path.join(fixtureRoot, 'fixture.css'), '.a { color:var(--safe); }\n');
    childProcess.execFileSync('git', ['add', 'fixture.css'], {cwd:fixtureRoot});
    childProcess.execFileSync('git', ['commit', '-q', '-m', 'baseline'], {cwd:fixtureRoot});
    var fixtureCommit = childProcess.execFileSync(
        'git', ['rev-parse', 'HEAD'], {cwd:fixtureRoot, encoding:'utf8'}).trim();
    fs.writeFileSync(path.join(fixtureRoot, 'fixture.css'), '.a { color:#fff; }\n');
    var integrated = ratchet.auditCssDebt({
        root:fixtureRoot,
        baselineCommit:fixtureCommit,
        files:['fixture.css']
    });
    check('git-backed ratchet integration reports a touched-line debt injection',
        integrated.available
        && integrated.currentCounts.rawColor === 1
        && integrated.violations.length === 1
        && integrated.violations[0].touchedCount === 1);
} finally {
    fs.rmSync(fixtureRoot, {recursive:true, force:true});
}

var auditExit = childProcess.spawnSync(
    process.execPath,
    [path.join(__dirname, 'audit-workbench-ui.js'), '--release-tree', '--text', '--strict-warnings'],
    {cwd:path.resolve(__dirname, '..'), encoding:'utf8'}
);
check('release-tree audit is wired to a strict process exit code',
    auditExit.status === 0
    && /\[workbench-ui-audit\] errors=0 warnings=0/.test(auditExit.stdout || ''));

console.log('workbench ui ratchet tests: ' + passed + '/' + (passed + failed));
if (failed) process.exit(1);
