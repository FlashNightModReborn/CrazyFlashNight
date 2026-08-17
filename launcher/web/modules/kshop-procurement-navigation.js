(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.KShopProcurementNavigation = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function required(options, name) {
        if (!options || typeof options[name] !== 'function') {
            throw new Error('KShop procurement navigation requires ' + name);
        }
        return options[name];
    }

    function Controller(options) {
        options = options || {};
        this._protocol = options.protocol;
        this._bridge = options.bridge;
        this._write = options.writeCoordinator;
        this._getOwner = required(options, 'getOwner');
        this._getCatalog = required(options, 'getCatalog');
        this._getRenderer = required(options, 'getRenderer');
        this._getShopReady = required(options, 'getShopReady');
        this._getInventoryState = required(options, 'getInventoryState');
        this._getWriteState = required(options, 'getWriteState');
        this._isOpen = required(options, 'isOpen');
        this._refreshControls = required(options, 'refreshControls');
        this._toast = options.toast || function() {};
        this._target = null;
        this._returnIntent = null;
        this._returnTimer = null;
        this._returnSequence = 0;
        this._returnError = '';
        this._group = null;
        this._button = null;
        this._status = null;
        var self = this;
        this._bridge.on('panel_resp', function(data) { self._handleFailure(data); });
    }

    Controller.prototype.configure = function(initData) {
        this.cleanup();
        this._target = this._protocol.parseProcurementNavigationInit(initData || {});
        this.refreshControls();
        return !!this._target;
    };

    Controller.prototype.createReturnAction = function(shell) {
        var group = document.createElement('span');
        group.className = 'kshop-procurement-return-group';
        group.hidden = true;
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'workbench-mode-btn kshop-procurement-return-btn';
        button.textContent = '← 返回合成配方';
        button.setAttribute('data-audio-cue', 'back');
        var self = this;
        button.addEventListener('click', function(event) { self.requestReturn(event); });
        var status = document.createElement('small');
        status.className = 'kshop-procurement-return-status';
        status.setAttribute('role', 'status');
        status.setAttribute('aria-live', 'polite');
        group.appendChild(button);
        group.appendChild(status);
        shell.addHeaderAction(group);
        this._group = group;
        this._button = button;
        this._status = status;
        return group;
    };

    Controller.prototype.isReturning = function() { return !!this._returnIntent; };

    Controller.prototype.refreshControls = function() {
        if (!this._group || !this._button || !this._status) return;
        var visible = !!this._target;
        this._group.hidden = !visible;
        if (!visible) return;
        var inventory = this._getInventoryState() || {};
        var write = this._getWriteState() || {};
        var blocked = !this._getShopReady() || !inventory.ready
            || !!inventory.busyOwner || !!inventory.refreshRequired
            || !!this._returnIntent || write.canStartWrite === false;
        this._button.disabled = blocked;
        this._button.textContent = this._returnIntent ? '返回中…'
            : this._returnError ? '重试返回合成配方' : '← 返回合成配方';
        this._button.setAttribute('aria-busy', this._returnIntent ? 'true' : 'false');
        var text = this._returnIntent
            ? (this._returnIntent.stage === 'saving'
                ? '正在保存购物车…' : '正在返回原合成配方…')
            : this._returnError || this._target.locationError || '';
        this._status.textContent = text;
        this._status.hidden = !text;
        this._status.setAttribute('data-navigation-state', this._returnIntent
            ? 'pending' : text ? 'error' : 'idle');
    };

    Controller.prototype._clearFocus = function() {
        var renderer = this._getRenderer();
        if (!renderer || !renderer.root) return;
        var nodes = renderer.root.querySelectorAll('.kshop-procurement-focus');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].classList.remove('kshop-procurement-focus');
            nodes[i].removeAttribute('data-navigation-focus');
            var hint = nodes[i].querySelector('.kshop-procurement-focus-hint');
            if (hint && hint.parentNode) hint.parentNode.removeChild(hint);
        }
    };

    Controller.prototype.applyTarget = function(requestFocus) {
        var target = this._target;
        var renderer = this._getRenderer();
        if (!target || !this._getShopReady() || !renderer || !renderer.root) return false;
        this._clearFocus();
        var matches = this._getCatalog().filter(function(item) {
            return item && Number(item.idx) === target.preferredCatalogIndex
                && String(item.item || '') === target.preferredItemName
                && String(item.id || '') === target.preferredEntryId
                && String(item.type || '') === target.preferredKShopCategory;
        });
        var nodes = renderer.root.querySelectorAll('[data-workbench-key]');
        var nodeMatches = [];
        for (var i = 0; i < nodes.length; i++) {
            if (String(nodes[i].getAttribute('data-workbench-key'))
                    === String(target.preferredCatalogIndex)) nodeMatches.push(nodes[i]);
        }
        if (matches.length !== 1 || nodeMatches.length !== 1) {
            target.locationError = '未能定位该材料：K 点商城目录已经变化。';
            this.refreshControls();
            return false;
        }
        target.locationError = '';
        var node = nodeMatches[0];
        node.classList.add('kshop-procurement-focus');
        node.setAttribute('data-navigation-focus', 'true');
        var hint = document.createElement('span');
        hint.className = 'kshop-procurement-focus-hint';
        hint.textContent = '从合成缺口定位';
        node.appendChild(hint);
        if (requestFocus && !target.focusConsumed) {
            target.focusConsumed = true;
            if (typeof node.scrollIntoView === 'function') {
                node.scrollIntoView({block:'nearest', inline:'nearest'});
            }
            if (typeof node.focus === 'function') node.focus();
        }
        this.refreshControls();
        return true;
    };

    Controller.prototype._message = function(error) {
        var messages = {
            invalid_payload:'返回入口数据无效，请重新从合成界面进入。',
            stale_source:'原合成配方或商品来源已经变化。',
            navigation_unavailable:'启动器暂时无法返回合成界面。',
            access_denied:'当前状态不能返回该合成配方。',
            source_not_settled:'商城状态仍在同步，请稍后重试。',
            admission_failed:'合成界面暂时无法打开，请重试。',
            timeout:'返回合成界面超时，请重试。',
            busy:'另一项面板导航正在进行，请稍后重试。',
            return_unavailable:'原合成配方返回入口已经失效。'
        };
        return messages[String(error || '')] || '暂时无法返回合成界面，请重试。';
    };

    Controller.prototype.requestReturn = function(event) {
        if (event && typeof event.preventDefault === 'function') event.preventDefault();
        var inventory = this._getInventoryState() || {};
        var write = this._getWriteState() || {};
        if (!this._target || this._returnIntent || !this._getShopReady()
                || !inventory.ready || inventory.busyOwner || inventory.refreshRequired
                || write.canStartWrite === false) return false;
        var owner = this._getOwner();
        var callId = 'kshop-recipe-return-' + (++this._returnSequence);
        var message = this._protocol.createReturnCraftingRecipeMessage({
            callId:callId, panelInstanceId:owner.panelInstanceId
        });
        if (!message) {
            this._returnError = this._message('invalid_payload');
            this.refreshControls();
            return false;
        }
        var intent = {callId:callId,panelInstanceId:owner.panelInstanceId,
            message:message,stage:'saving',saved:false};
        this._returnError = '';
        this._returnIntent = intent;
        this.refreshControls();
        var self = this;
        if (!this._write.close(function(result) {
            if (self._returnIntent !== intent || !self._isOpen()) return;
            if (!result || result.success !== true) {
                self._fail(intent, result && result.error || 'source_not_settled', false);
                return;
            }
            intent.saved = true;
            intent.stage = 'navigation';
            self.refreshControls();
            var sent = false;
            try { sent = self._bridge.send(intent.message) !== false; }
            catch (_) { sent = false; }
            if (!sent) return self._fail(intent, 'navigation_unavailable', true);
            self._returnTimer = setTimeout(function() {
                if (self._returnIntent === intent) self._fail(intent, 'timeout', true);
            }, self._protocol.NAVIGATION_WATCHDOG_MS);
        })) {
            this._fail(intent, 'source_not_settled', false);
            return false;
        }
        this._refreshControls();
        return true;
    };

    Controller.prototype._fail = function(intent, error, rearmWrite) {
        if (this._returnIntent !== intent) return false;
        if (this._returnTimer !== null) {
            clearTimeout(this._returnTimer);
            this._returnTimer = null;
        }
        this._returnIntent = null;
        if (rearmWrite && intent.saved) this._write.open();
        this._returnError = this._message(error);
        this._refreshControls();
        return false;
    };

    Controller.prototype._handleFailure = function(data) {
        var intent = this._returnIntent;
        if (!intent || intent.stage !== 'navigation'
                || !this._protocol.validateReturnCraftingRecipeFailure(data, {
                    callId:intent.callId,panelInstanceId:intent.panelInstanceId
                })) return false;
        return this._fail(intent, data.error, true);
    };

    Controller.prototype.cleanup = function() {
        if (this._returnTimer !== null) {
            clearTimeout(this._returnTimer);
            this._returnTimer = null;
        }
        this._clearFocus();
        this._target = null;
        this._returnIntent = null;
        this._returnError = '';
        if (this._group) this._group.hidden = true;
    };

    Controller.prototype.debugState = function() {
        return {hasTarget:!!this._target,returning:!!this._returnIntent,
            returnError:this._returnError,
            preferredCatalogIndex:this._target
                ? this._target.preferredCatalogIndex : null};
    };

    return {create:function(options) { return new Controller(options); }};
});
