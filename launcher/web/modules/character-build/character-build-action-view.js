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
    function ActionView(options) {
        options = options || {};
        this._root = options.root;
        this._candidateList = options.candidateList;
        this._commitButton = this._root.querySelector('[data-build-action="commit"]');
        this._tuneButton = this._root.querySelector('[data-build-action="tune"]');
        this._unequipButton = this._root.querySelector('[data-build-action="unequip"]');
        this._getCandidate = options.getCandidate;
        this._getCandidateKey = options.getCandidateKey;
        this._getSlotKey = options.getSlotKey;
        this._selectCandidate = options.selectCandidate;
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
    ActionView.prototype._handleKeyDown = function(event) {
        var candidate = closest(event.target, '[data-candidate-key]', this._candidateList);
        if (!candidate || (event.key !== 'Enter' && event.key !== ' ')) return;
        event.preventDefault();
        var key = candidate.getAttribute('data-candidate-key');
        var selected = key === this._getCandidateKey();
        var value = this._getCandidate(key);
        if (event.key === 'Enter' && !event.repeat && selected) this._tryCommit(value);
        else this._selectCandidate(key);
    };
    ActionView.prototype.sync = function() {
        var candidate = this._getCandidate();
        var slotKey = this._getSlotKey();
        var slot = slotKey && this._root.querySelector(
            '[data-roving-key="' + String(slotKey).replace(/"/g, '\\"') + '"]');
        var reconcile = this._state === 'mutation_reconcile';
        var drug = String(slotKey).indexOf('drug:') === 0;
        this._commitButton.textContent = reconcile ? '确认' : drug ? '装入' : '装备';
        this._commitButton.setAttribute('aria-label', reconcile ? '重新确认结果'
            : drug ? '装入所选药剂' : '装备所选候选');
        this._commitButton.disabled = reconcile ? false
            : this._state !== 'idle' || !candidate || candidate.blocked === true;
        var tunable = !!slot && slot.getAttribute('data-empty') !== 'true'
            && slot.getAttribute('data-slot-kind') !== 'drug'
            && slot.getAttribute('data-blocked') !== 'true';
        this._tuneButton.hidden = !tunable;
        this._tuneButton.disabled = this._state !== 'idle' || !tunable;
        this._unequipButton.disabled = this._state !== 'idle'
            || !slot || slot.getAttribute('data-empty') === 'true';
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
    return {ActionView:ActionView};
});
