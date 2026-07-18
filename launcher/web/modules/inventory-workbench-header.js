/** Presentation-only header controller for InventoryWorkbench's tuning affordances. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchHeader = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function noop() {}

    function TuningHeaderController(options) {
        options = options || {};
        if (!options.document || !options.shell) throw new Error('TuningHeaderController requires document and shell ports');
        this._document = options.document;
        this._shell = options.shell;
        this._onSwitch = typeof options.onSwitch === 'function' ? options.onSwitch : noop;
        this._onHelp = typeof options.onHelp === 'function' ? options.onHelp : noop;
        this._onConfirmationChange = typeof options.onConfirmationChange === 'function'
            ? options.onConfirmationChange : noop;
        this._mode = options.confirmationMode === 'fast' ? 'fast' : 'safe';
        this._view = options.view === 'tuning' ? 'tuning' : 'storage';
        this._disabled = !!options.disabled;
        this._buttons = {};
        this._listeners = [];
        this.confirmationRoot = this._createConfirmationToggle();
        this.switchButton = this._createSwitchButton();
        this.helpButton = this._createHelpButton();
        this._shell.addHeaderAction(this.confirmationRoot);
        this._shell.addHeaderAction(this.switchButton);
        this._shell.addHeaderAction(this.helpButton);
        this.update({view:this._view, confirmationMode:this._mode});
    }

    TuningHeaderController.prototype._listen = function(node, type, handler) {
        node.addEventListener(type, handler);
        this._listeners.push(function() { node.removeEventListener(type, handler); });
    };
    TuningHeaderController.prototype._createConfirmationToggle = function() {
        var self = this;
        var root = this._document.createElement('div');
        root.className = 'equipment-tuning-mode-switch equipment-tuning-confirmation-toggle';
        var label = this._document.createElement('span');
        label.className = 'equipment-tuning-mode-label';
        label.textContent = '配件';
        root.appendChild(label);
        [['safe','安全'],['fast','快速']].forEach(function(pair) {
            var button = self._document.createElement('button');
            button.type = 'button';
            button.className = 'equipment-tuning-mode-option equipment-tuning-confirmation-option';
            button.textContent = pair[1];
            button.setAttribute('data-confirmation-mode', pair[0]);
            button.setAttribute('aria-label', '配件操作' + pair[1] + '模式');
            self._listen(button, 'click', function() { self._onConfirmationChange(pair[0]); });
            self._buttons[pair[0]] = button;
            root.appendChild(button);
        });
        return root;
    };
    TuningHeaderController.prototype._createSwitchButton = function() {
        var self = this;
        var button = this._document.createElement('button');
        button.type = 'button';
        button.className = 'workbench-mode-btn equipment-tuning-view-switch';
        this._listen(button, 'click', function() { self._onSwitch(self._view === 'tuning' ? 'storage' : 'tuning'); });
        return button;
    };
    TuningHeaderController.prototype._createHelpButton = function() {
        var self = this;
        var button = this._document.createElement('button');
        button.type = 'button';
        button.className = 'workbench-mode-btn equipment-tuning-help-btn';
        button.textContent = '?';
        button.setAttribute('aria-label', '查看装备调制帮助');
        this._listen(button, 'click', function() { self._onHelp(); });
        return button;
    };
    TuningHeaderController.prototype.update = function(state) {
        state = state || {};
        if (state.view === 'storage' || state.view === 'tuning') this._view = state.view;
        if (state.confirmationMode === 'safe' || state.confirmationMode === 'fast') this._mode = state.confirmationMode;
        this.confirmationRoot.hidden = this._view !== 'tuning';
        this.switchButton.textContent = this._view === 'tuning' ? '返回收纳' : '装备调制';
        this.switchButton.setAttribute('aria-pressed', this._view === 'tuning' ? 'true' : 'false');
        this.helpButton.hidden = this._view !== 'tuning';
        if (state.disabled != null) this._disabled = !!state.disabled;
        this.switchButton.disabled = this._disabled;
        this.helpButton.disabled = this._disabled;
        for (var key in this._buttons) {
            this._buttons[key].setAttribute('aria-pressed', key === this._mode ? 'true' : 'false');
            this._buttons[key].disabled = this._disabled;
        }
        return true;
    };
    TuningHeaderController.prototype.destroy = function() {
        for (var i = this._listeners.length - 1; i >= 0; i--) this._listeners[i]();
        this._listeners = [];
        this._buttons = {};
        return true;
    };

    return {TuningHeaderController:TuningHeaderController};
});
