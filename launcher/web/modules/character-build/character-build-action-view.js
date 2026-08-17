/**
 * Character-build CTA/unequip presentation and keyboard activation.
 *
 * This leaf owns no authority or transport state. It projects the session state
 * supplied by the view and delegates every action to injected callbacks.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildActionView = api;
        root.CharacterBuildActionView = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function closest(target, selector, boundary) {
        if (!target || typeof target.closest !== 'function') return null;
        var result = target.closest(selector);
        return result && boundary.contains(result) ? result : null;
    }
    function tuningCapability(item) {
        var level = Number(item && item.enhancementLevel);
        if (!item) return {available:false, code:'empty', reason:'当前槽位没有可调制装备'};
        if (item.itemKind !== 'equipment') return {
            available:false, code:'not_equipment',
            reason:item.itemKind === 'stack' && item.use === '手雷'
                ? '数量型手雷不能调制' : '该物品不属于可调制装备'
        };
        if (item.majorType !== '武器' && item.majorType !== '防具') return {
            available:false, code:'unsupported_type', reason:'仅武器与防具可以调制'
        };
        if (!isFinite(level) || Math.floor(level) !== level || level < 1) return {
            available:false, code:'invalid_level', reason:'该装备缺少有效的强化等级'
        };
        return {available:true, code:'available', reason:''};
    }
    function ActionView(options) {
        options = options || {};
        this._root = options.root;
        this._candidateList = options.candidateList;
        this._commitButton = this._root.querySelector('[data-build-action="commit"]');
        this._tuneButton = this._root.querySelector('[data-build-action="tune"]');
        this._unequipButton = this._root.querySelector('[data-build-action="unequip"]');
        this._overlayCopy = options.overlayCopy;
        this._getCandidate = options.getCandidate;
        this._getCandidateKey = options.getCandidateKey;
        this._getSlotKey = options.getSlotKey;
        this._selectCandidate = options.selectCandidate;
        this._clearCandidateSelection = options.clearCandidateSelection;
        this._onCommit = options.onCommit;
        this._onTune = options.onTune;
        this._onUnequip = options.onUnequip;
        this._onReconcile = options.onReconcile;
        this._state = 'opening';
        this._onClick = this._handleClick.bind(this);
        this._onKeyDown = this._handleKeyDown.bind(this);
        this._root.addEventListener('click', this._onClick);
        this._root.addEventListener('keydown', this._onKeyDown);
    }
    ActionView.prototype._handleClick = function(event) {
        var button = closest(event.target, '[data-build-action]', this._root);
        if (!button || button.disabled) return;
        var action = button.getAttribute('data-build-action');
        if (action === 'commit') {
            if (this._state === 'mutation_reconcile') this._onReconcile();
            else this._tryCommit(this._getCandidate());
        } else if (action === 'tune') this._onTune();
        else if (action === 'unequip') this._onUnequip();
    };
    ActionView.prototype._tryCommit = function(candidate) {
        if (this._state !== 'idle' || !candidate || candidate.blocked === true
                || this._commitButton.disabled) return false;
        this._onCommit(candidate);
        return true;
    };
    ActionView.prototype.commitCandidate = function(candidate) {
        return this._tryCommit(candidate);
    };
    ActionView.prototype._handleKeyDown = function(event) {
        var candidate = closest(event.target, '[data-candidate-key]', this._candidateList);
        if (!candidate || (event.key !== 'Enter' && event.key !== ' ')) return;
        event.preventDefault();
        var key = candidate.getAttribute('data-candidate-key');
        var selected = key === this._getCandidateKey();
        var value = this._getCandidate(key);
        if (event.key === 'Enter' && !event.repeat && selected) this._tryCommit(value);
        else if (event.key === ' ' && selected) this._clearCandidateSelection();
        else this._selectCandidate(key);
    };
    ActionView.prototype.sync = function() {
        var candidate = this._getCandidate();
        var slotKey = this._getSlotKey();
        var slot = slotKey && this._root.querySelector(
            '[data-roving-key="' + String(slotKey).replace(/"/g, '\\"') + '"]');
        var reconcile = this._state === 'mutation_reconcile';
        var drug = String(slotKey).indexOf('drug:') === 0;
        this._commitButton.textContent = reconcile ? '确认'
            : !slotKey ? '先选栏位' : drug ? '装入' : '装备';
        this._commitButton.setAttribute('aria-label', reconcile ? '重新确认结果'
            : !slotKey ? '先选择目标栏位'
                : drug ? '装入所选药剂' : '装备所选候选');
        this._commitButton.disabled = reconcile ? false
            : this._state !== 'idle' || !slotKey
                || !candidate || candidate.blocked === true;
        var occupiedEquipment = !!slot && slot.getAttribute('data-empty') !== 'true'
            && slot.getAttribute('data-slot-kind') !== 'drug';
        var candidateSelected = !!candidate && !!slot;
        var tunable = candidateSelected
            ? candidate.tunable === true && candidate.blocked !== true
            : occupiedEquipment && slot.getAttribute('data-tunable') === 'true'
            && slot.getAttribute('data-blocked') !== 'true';
        var tuningReason = candidateSelected
            ? candidate.tuningReason || '所选候选不能调制'
            : slot && slot.getAttribute('data-tuning-reason')
            || (slot && slot.getAttribute('data-blocked') === 'true'
                ? '当前装备状态不可用' : '该物品不能调制');
        this._tuneButton.hidden = !candidateSelected && !occupiedEquipment;
        this._tuneButton.textContent = tunable
            ? candidateSelected ? '调制候选' : '调制' : '不可调制';
        this._tuneButton.disabled = this._state !== 'idle' || !tunable;
        this._tuneButton.setAttribute('aria-disabled', this._tuneButton.disabled ? 'true' : 'false');
        this._tuneButton.setAttribute('aria-label', tunable
            ? candidateSelected ? '调制所选候选：' + String(candidate.name || '未命名候选')
                : '调制当前装备'
            : tuningReason);
        if (tunable) this._tuneButton.removeAttribute('title');
        else this._tuneButton.setAttribute('title', tuningReason);
        this._unequipButton.disabled = this._state !== 'idle'
            || !slot || slot.getAttribute('data-empty') === 'true';
    };
    ActionView.prototype.syncCandidateSelection = function(key) {
        var buttons = this._candidateList.querySelectorAll('[data-candidate-key]');
        for (var i = 0; i < buttons.length; i++) {
            var selected = buttons[i].getAttribute('data-candidate-key') === key;
            buttons[i].setAttribute('aria-selected', selected ? 'true' : 'false');
            buttons[i].classList.toggle('workbench-source-selected', selected);
        }
        this.sync();
        var candidate = this._getCandidate(key);
        this._overlayCopy.parentNode.hidden = !candidate;
        this._overlayCopy.textContent = candidate
            ? (this._getSlotKey() ? '预览 · ' : '已选 · ')
                + String(candidate.name || '候选') : '';
        return candidate;
    };
    ActionView.prototype.setState = function(state) {
        this._state = String(state || 'opening');
        this._root.setAttribute('data-interaction-state', this._state);
        var nodes = this._root.querySelectorAll('[data-roving-key]');
        for (var i = 0; i < nodes.length; i++) {
            var disabled = this._state !== 'idle';
            if ('disabled' in nodes[i]) nodes[i].disabled = disabled;
            else if (disabled) nodes[i].setAttribute('inert', ''); else nodes[i].removeAttribute('inert');
            nodes[i].setAttribute('aria-disabled', disabled
                || nodes[i].getAttribute('data-blocked') === 'true' ? 'true' : 'false');
        }
        this.sync();
    };
    ActionView.prototype.destroy = function() {
        this._root.removeEventListener('click', this._onClick);
        this._root.removeEventListener('keydown', this._onKeyDown);
    };
    return {ActionView:ActionView, tuningCapability:tuningCapability};
});
