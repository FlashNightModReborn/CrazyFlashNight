/** Player choices are durable AS2 offers. This view only submits their identities. */
(function(root, factory) {
    'use strict';
    var components = typeof module !== 'undefined' && module.exports
        ? require('../workbench-components.js') : root.WorkbenchComponents;
    var api = factory(components);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildChoiceRewards = api;
})(typeof window !== 'undefined' ? window : globalThis, function(Components) {
    'use strict';
    function element(document, tag, text, className) {
        var node = document.createElement(tag);
        if (text) node.textContent = text;
        if (className) node.className = className;
        if (tag === 'button') node.type = 'button';
        return node;
    }
    function ChoiceView(options) {
        var self = this;
        this.options = options;
        this.document = options.view.root.ownerDocument;
        this.snapshot = null; this.selected = ''; this.offerId = ''; this.state = 'idle';
        this.signature = ''; this.destroyed = false;
        var entryHost = options.view.root.querySelector('[data-build-pane="candidates"] .character-build-pane-heading .character-build-pane-tools');
        this.button = element(this.document, 'button', '自选礼包', 'character-build-choice-entry');
        this.button.setAttribute('data-choice-rewards-open', ''); this.button.hidden = true;
        entryHost.insertBefore(this.button, entryHost.firstChild);
        this.button.onclick = function() { options.open(); };
        this.page = new Components.SecondaryPage({document:this.document, role:'dialog', ariaLabel:'自选礼包',
            className:'character-build-choice-page', underlay:options.view._underlay,
            onBack:function() { return self.state !== 'write_pending' && self.state !== 'query_pending'; },
            onClose:function() { self.updateState(self.state); }});
        this.page.mount(options.view.root);
        var header = element(this.document, 'header', '', 'character-build-choice-header');
        header.appendChild(element(this.document, 'h2', '选择你的配给'));
        this.back = element(this.document, 'button', '稍后再选');
        header.appendChild(this.back); this.page.bindBack(this.back);
        this.page.root.appendChild(header);
        this.page.root.appendChild(element(this.document, 'p', '每个礼包只能选一套。候选已经保留，关闭后可继续选择；选定后到暂存物资领取。', 'character-build-choice-hint'));
        this.select = element(this.document, 'select'); this.select.setAttribute('aria-label', '待选择的礼包');
        this.select.onchange = function() { self.offerId = self.select.value; self.selected = ''; self.renderCards(); };
        this.page.root.appendChild(this.select);
        this.cards = element(this.document, 'div', '', 'character-build-choice-cards');
        this.cards.setAttribute('role', 'group'); this.cards.setAttribute('aria-label', '配给候选');
        this.page.root.appendChild(this.cards);
        var footer = element(this.document, 'footer', '', 'character-build-choice-footer');
        this.status = element(this.document, 'p'); this.status.setAttribute('role', 'status');
        footer.appendChild(this.status);
        this.refresh = element(this.document, 'button', '刷新'); this.refresh.onclick = function() { options.refresh(); };
        this.query = element(this.document, 'button', '核对领取结果'); this.query.onclick = function() { options.reconcile(); };
        this.confirm = element(this.document, 'button', '领取这套配给'); this.confirm.onclick = function() {
            if (!self.confirm.disabled && self.snapshot) options.choose(self.snapshot, self.offerId, self.selected);
        };
        this.storage = element(this.document, 'button', '前往暂存物资'); this.storage.onclick = function() {
            if (self.state === 'idle') { self.page.close('storage'); options.storage(); }
        };
        [this.refresh, this.query, this.storage, this.confirm].forEach(function(node) { footer.appendChild(node); });
        this.page.root.appendChild(footer);
        this.updateState('idle');
    }
    ChoiceView.prototype.open = function() {
        var shell = this.options.view.root.closest('.inventory-workbench-panel');
        var header = shell && shell.querySelector('.workbench-header');
        return this.page.open({opener:this.button, initialFocus:this.back,
            underlay:header ? [this.options.view._underlay, header] : this.options.view._underlay});
    };
    ChoiceView.prototype.setSnapshot = function(data, preferred) {
        if (this.destroyed) return;
        if (!data) { this.loadFailed = true; this.updateState(this.state); return; }
        this.loadFailed = false;
        this.snapshot = data;
        var signature = JSON.stringify(data);
        if (signature !== this.signature || preferred && preferred !== this.offerId) {
            this.signature = signature;
            var wanted = preferred || this.offerId;
            this.offerId = data.offers.some(function(o) { return o.offerId === wanted; }) ? wanted
                : data.offers.length ? data.offers[0].offerId : '';
            this.select.textContent = '';
            for (var i = 0; i < data.offers.length; i++) {
                var row = element(this.document, 'option', data.offers[i].title + ' · ' + (i + 1));
                row.value = data.offers[i].offerId; this.select.appendChild(row);
            }
            this.select.value = this.offerId; this.select.hidden = data.offers.length < 2;
            this.renderCards();
        }
        this.updateState(this.state);
    };
    ChoiceView.prototype.renderCards = function() {
        var self = this;
        var offer = this.snapshot && this.snapshot.offers.find(function(o) { return o.offerId === self.offerId; });
        this.cards.textContent = '';
        if (!offer) { this.selected = ''; this.cards.appendChild(element(this.document, 'p', '暂无待选择的礼包。打开背包中的自选配给包后，就可以在这里继续选择。')); this.updateState(this.state); return; }
        this.cards.style.setProperty('--choice-columns', String(offer.options.length));
        if (!offer.options.some(function(o) { return o.optionId === self.selected; })) this.selected = '';
        offer.options.forEach(function(option) {
            var card = element(self.document, 'button', '', 'character-build-choice-card');
            card.setAttribute('data-choice-option', option.optionId);
            card.setAttribute('aria-pressed', String(self.selected === option.optionId));
            card.appendChild(element(self.document, 'strong', option.title));
            card.appendChild(element(self.document, 'span', option.description, 'character-build-choice-description'));
            var items = element(self.document, 'span', '', 'character-build-choice-items');
            option.items.forEach(function(item) {
                items.appendChild(element(self.document, 'span', item.displayName + ' ×' + item.quantity
                    + (item.level > 0 ? '　Lv.' + item.level : '')));
            });
            card.appendChild(items);
            card.onclick = function() {
                if (self.state !== 'idle' || self.snapshot.pendingOperationId) return;
                self.selected = option.optionId;
                self.cards.querySelectorAll('[data-choice-option]').forEach(function(node) {
                    node.setAttribute('aria-pressed', String(node.getAttribute('data-choice-option') === self.selected));
                });
                self.updateState(self.state);
            };
            self.cards.appendChild(card);
        });
        this.updateState(this.state);
    };
    ChoiceView.prototype.updateState = function(state) {
        if (this.destroyed) return;
        this.state = state;
        var pending = this.snapshot && this.snapshot.pendingOperationId;
        var busy = state !== 'idle' || !!pending;
        var count = this.snapshot ? this.snapshot.offers.length : 0;
        this.button.hidden = count === 0 && !pending && !this.choicePending && !this.page.isActive();
        this.button.textContent = count ? '自选礼包 ' + count : pending || this.choicePending ? '自选·待确认' : '自选礼包';
        this.button.disabled = state === 'write_pending' || state === 'query_pending';
        this.confirm.disabled = busy || this.loadFailed || !this.selected || !this.snapshot;
        this.storage.disabled = busy;
        this.select.disabled = busy;
        this.refresh.disabled = state === 'write_pending' || state === 'query_pending';
        this.query.hidden = state !== 'needs_reconcile' && !pending;
        this.query.disabled = state === 'query_pending' || state === 'write_pending';
        this.back.disabled = state === 'write_pending' || state === 'query_pending';
        this.cards.querySelectorAll('[data-choice-option]').forEach(function(node) { node.disabled = busy; });
        this.status.textContent = this.loadFailed ? '配给列表暂时无法读取，请刷新重试。'
            : state === 'write_pending' ? '正在保存你的选择…'
            : state === 'query_pending' ? '正在核对领取结果…'
            : state === 'needs_reconcile' || pending ? '上次操作结果待确认，请先核对。'
            : this.selected ? '已选中一套配给，确认后其余候选将放弃。' : count ? '点选一套配给，再确认领取。' : '';
    };
    ChoiceView.prototype.destroy = function() {
        if (this.destroyed) return;
        this.destroyed = true; this.page.destroy(); this.button.remove();
    };
    function install(controller) {
        controller._ensureChoiceRewards = function() {
            if (this._choiceRewards || !this._view || !this._view.root) return this._choiceRewards;
            var self = this;
            this._choiceRewards = new ChoiceView({view:this._view,
                open:function() { self._choiceRewards.open(); self._refreshChoiceRewards(); },
                refresh:function() { self._refreshChoiceRewards(); },
                storage:function() { self._openRewardInbox(); },
                reconcile:function() {
                    if (self._itemUse.debugState().state === 'needs_reconcile') self._itemUse.reconcile();
                    else if (self._choiceRewards.snapshot && self._choiceRewards.snapshot.pendingOperationId)
                        self._itemUse.resumeStash(self._choiceRewards.snapshot.pendingOperationId, function() { self._refreshChoiceRewards(); self._itemUse.refreshInbox(); });
                },
                choose:function(snapshot, offerId, optionId) {
                    if (self._session.getState() !== 'idle') return;
                    self._itemUse.invokeStash('stashChoose', {storeId:snapshot.storeId, expectedRevision:snapshot.revision,
                        offerId:offerId, optionId:optionId}, function(response, committed) {
                        self._itemUseSettled(response, committed, {command:'stashChoose'});
                        self._refreshChoiceRewards();
                    });
                }});
            return this._choiceRewards;
        };
        controller._refreshChoiceRewards = function(preferred) {
            var view = this._ensureChoiceRewards();
            if (!view) return;
            if (preferred) view.open();
            this._itemUse.requestChoices(function(data) { if (!view.destroyed) view.setSnapshot(data, preferred); });
        };
        controller._choiceRewardsStateChanged = function(state) {
            if (this._choiceRewards) {
                var pending = this._itemUse.debugState().pending;
                this._choiceRewards.choicePending = !!(pending && pending.choice);
                this._choiceRewards.updateState(state);
            }
        };
        controller._destroyChoiceRewards = function() {
            if (this._choiceRewards) this._choiceRewards.destroy(); this._choiceRewards = null;
        };
    }
    return {install:install, ChoiceView:ChoiceView};
});
