/**
 * LoadoutPicker composition root: explicit assembly of the browse-select-drag
 * five-state-rollback interaction layer.
 *
 * install(prototype, ports) formalizes the former implicit prototype contract
 * of the character-build candidate pane:
 * - ports.slotGrid — slot-grid hooks {releaseGrid, projectSlot, bindSlotTooltip,
 *   decorateSlot}; badges, tuning flags and slot tooltips stay host-injected.
 * - ports.drag — candidate drag overrides {policy, subjectKind, classPrefix,
 *   texts}; defaults keep the character-build vocabulary.
 * - ports.pane — candidate pane ports {syncFocusSummary(host, key), texts,
 *   classPrefix, candidateTitleSelector}; syncFocusSummary is required.
 *
 * The runtime factories wire the picker-owned controls onto the host view:
 * - initState(host, {candidateScope, viewSequence}) — selection/scope/requestKey
 *   fence/drag/interaction state fields (the `_slotRovings` array replaces the
 *   former hardcoded per-kind roving refresh).
 * - createScopeGroup(host) — compatible/backpack scope ChoiceGroup.
 * - createActionView(host, {onCommit, onTune, onUnequip, onReconcile, ...}) —
 *   verb-injected action bar.
 * - createCandidateState(host, {bindTooltip, onBlocked, onRetry, ...}) —
 *   five-state candidate list.
 *
 * §3.2 ports mapping for the character-build consumer: slotDescriptors come
 * from CharacterBuildTemplate; fetchCandidates/equip/remove/preview are
 * injected as CharacterBuildView constructor options (onSlotSelect,
 * onCandidateScopeChange, onCommitCandidate, onSlotDropEquip, onUnequip,
 * onCandidateSelect); eligibilityProvider is the drop-policy port; texts are
 * the per-leaf texts ports. Session, revision and write authority never enter
 * this layer.
 */
(function(root, factory) {
    'use strict';
    var components = typeof module !== 'undefined' && module.exports
        ? require('../workbench-components.js')
        : root && (root.WorkbenchComponents || root.CF7 && root.CF7.WorkbenchComponents);
    var candidateState = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker-candidate-state.js')
        : root && root.LoadoutPickerCandidateState;
    var actionView = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker-action-view.js')
        : root && root.LoadoutPickerActionView;
    var slotGrid = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker-slot-grid.js')
        : root && root.LoadoutPickerSlotGrid;
    var candidateDrag = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker-candidate-drag.js')
        : root && root.LoadoutPickerCandidateDrag;
    var candidatePane = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker-candidate-pane.js')
        : root && root.LoadoutPickerCandidatePane;
    var api = factory(
        components, candidateState, actionView, slotGrid, candidateDrag, candidatePane);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LoadoutPicker = api;
        root.LoadoutPicker = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchComponents, CandidateStateModule, ActionViewModule, SlotGridModule,
        CandidateDragModule, CandidatePaneModule) {
    'use strict';
    if (!WorkbenchComponents || typeof WorkbenchComponents.ChoiceGroup !== 'function') {
        throw new Error('loadout-picker.js requires ChoiceGroup');
    }
    if (!CandidateStateModule || !CandidateStateModule.CandidateState) {
        throw new Error('loadout-picker.js requires LoadoutPickerCandidateState');
    }
    if (!ActionViewModule || !ActionViewModule.ActionView) {
        throw new Error('loadout-picker.js requires LoadoutPickerActionView');
    }
    if (!SlotGridModule || typeof SlotGridModule.install !== 'function') {
        throw new Error('loadout-picker.js requires LoadoutPickerSlotGrid');
    }
    if (!CandidateDragModule || typeof CandidateDragModule.install !== 'function') {
        throw new Error('loadout-picker.js requires LoadoutPickerCandidateDrag');
    }
    if (!CandidatePaneModule || typeof CandidatePaneModule.install !== 'function') {
        throw new Error('loadout-picker.js requires LoadoutPickerCandidatePane');
    }

    function noop() {}

    var SCOPE_TEXTS = {
        ariaLabel:'背包候选范围',
        compatibleLabel:'兼容',
        compatibleAriaLabel:'只显示与当前槽位兼容的背包候选',
        backpackLabel:'背包',
        backpackAriaLabel:'显示背包全部物品'
    };
    function resolveTexts(overrides, defaults) {
        var texts = {};
        for (var key in defaults) {
            if (!Object.prototype.hasOwnProperty.call(defaults, key)) continue;
            texts[key] = overrides && typeof overrides[key] === 'string'
                && overrides[key] !== '' ? overrides[key] : defaults[key];
        }
        return texts;
    }
    function classPrefixOf(options) {
        return options && typeof options.classPrefix === 'string'
            && options.classPrefix !== '' ? options.classPrefix : 'character-build';
    }

    function install(prototype, ports) {
        if (!prototype) throw new Error('LoadoutPicker.install requires a view method target');
        ports = ports || {};
        SlotGridModule.install(prototype, ports.slotGrid);
        CandidateDragModule.install(prototype, ports.drag);
        CandidatePaneModule.install(prototype, ports.pane);
        return prototype;
    }

    function initState(host, options) {
        if (!host) throw new Error('LoadoutPicker.initState requires a host view');
        options = options || {};
        host._selectedSlotKey = '';
        host._selectedCandidateKey = '';
        host._activeSlotKey = '';
        host._activeCandidateKey = '';
        host._candidateRequestKey = '';
        host._candidateScope = CandidatePaneModule.normalizeScope(
            options.candidateScope) || 'backpack';
        host._candidateScopeGroup = null;
        host._candidateFence = 'candidate-view-' + options.viewSequence;
        host._candidateSequence = 0;
        host._candidateLoadFailed = false;
        host._candidateFailureCode = '';
        host._candidateRecoveryPending = false;
        host._candidateDrag = null;
        host._candidateDragBroker = null;
        host._candidateDragActive = false;
        host._dragCandidate = null;
        host._interactionState = 'opening';
        host._lockedFocusKey = '';
        host._slotRovings = [];
        return host;
    }

    function createScopeGroup(host, options) {
        options = options || {};
        var texts = resolveTexts(options.texts, SCOPE_TEXTS);
        host._candidateScopeGroup = new WorkbenchComponents.ChoiceGroup({
            document:host._document,
            value:host._candidateScope,
            ariaLabel:texts.ariaLabel,
            className:classPrefixOf(options) + '-candidate-scope',
            choices:[
                {value:'compatible', label:texts.compatibleLabel,
                    ariaLabel:texts.compatibleAriaLabel},
                {value:'backpack', label:texts.backpackLabel,
                    ariaLabel:texts.backpackAriaLabel}
            ],
            onChange:function(scope) { return host._changeCandidateScope(scope); }
        });
        host._candidateScopeGroup.mount(host._candidateScopeMount);
        return host._candidateScopeGroup;
    }

    function createActionView(host, options) {
        options = options || {};
        host._actionView = new ActionViewModule.ActionView({
            root:host.root, candidateList:host._candidateList, overlayCopy:host._overlayCopy,
            getCandidate:function(key) { return host._candidateByKey(key || host._selectedCandidateKey); },
            getCandidateKey:function() { return host._selectedCandidateKey; },
            getSlotKey:function() { return host._selectedSlotKey; },
            selectCandidate:function(key) { return host._selectCandidate(key); },
            clearCandidateSelection:function() { return host.clearCandidateSelection(); },
            onCommit:typeof options.onCommit === 'function' ? options.onCommit : noop,
            onTune:typeof options.onTune === 'function' ? options.onTune : noop,
            onUnequip:typeof options.onUnequip === 'function' ? options.onUnequip : noop,
            onReconcile:typeof options.onReconcile === 'function' ? options.onReconcile : noop,
            texts:options.texts,
            drugSlotKeyPrefix:options.drugSlotKeyPrefix
        });
        return host._actionView;
    }

    function createCandidateState(host, options) {
        options = options || {};
        host._candidateState = new CandidateStateModule.CandidateState({
            document:host._document,
            host:host._candidateList,
            countNode:host._candidateCount,
            renderOwnedSlot:host._renderOwnedSlot,
            iconHtml:host._iconHtml,
            bindTooltip:options.bindTooltip,
            onBlocked:options.onBlocked,
            onRetry:options.onRetry,
            copy:options.copy,
            texts:options.texts,
            classPrefix:options.classPrefix
        });
        return host._candidateState;
    }

    return {
        install:install,
        initState:initState,
        createScopeGroup:createScopeGroup,
        createActionView:createActionView,
        createCandidateState:createCandidateState,
        normalizeScope:CandidatePaneModule.normalizeScope
    };
});
