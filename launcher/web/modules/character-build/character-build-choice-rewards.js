/** Player choices are durable AS2 offers. This view only submits their identities. */
(function(root, factory) {
    'use strict';
    var components = typeof module !== 'undefined' && module.exports
        ? require('../workbench-components.js') : root.WorkbenchComponents;
    var grades = typeof module !== 'undefined' && module.exports
        ? require('../grade-presentation.js') : root && root.GradePresentation;
    var api = factory(components, grades);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildChoiceRewards = api;
})(typeof window !== 'undefined' ? window : globalThis, function(Components, Grades) {
    'use strict';
    if (!Grades || typeof Grades.normalize !== 'function') {
        throw new Error('character-build-choice-rewards.js requires grade-presentation.js');
    }
    function element(document, tag, text, className) {
        var node = document.createElement(tag);
        if (text) node.textContent = text;
        if (className) node.className = className;
        if (tag === 'button') node.type = 'button';
        return node;
    }
    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function plainToHtml(value) {
        return escapeHtml(value).replace(/\r?\n/g, '<br>');
    }
    function ChoiceView(options) {
        var self = this;
        this.options = options;
        this.document = options.view.root.ownerDocument;
        var win = this.document.defaultView;
        this.icons = win && win.Icons;
        this.tooltip = win && win.PanelTooltip;
        this.tooltipScope = this.tooltip && this.tooltip.createScope('choice-rewards', {profile:'dense-inspect'});
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
            onClose:function() { if (self.tooltipScope) self.tooltipScope.releaseTree(self.cards); self.updateState(self.state); }});
        this.page.mount(options.view.root);
        var header = element(this.document, 'header', '', 'character-build-choice-header');
        header.appendChild(element(this.document, 'h2', '选择你的配给'));
        this.back = element(this.document, 'button', '返回构筑');
        header.appendChild(this.back); this.page.bindBack(this.back);
        this.page.root.appendChild(header);
        this.context = element(this.document, 'div', '', 'character-build-choice-context');
        this.balance = element(this.document, 'p', '', 'character-build-choice-hint');
        this.context.appendChild(this.balance);
        this.context.appendChild(element(this.document, 'p', '每次选择一张。技能直接授予，主动技能需在技能页装备；物品优先进入背包，装不下的进入暂存。付费卡确认时扣除局内K点。', 'character-build-choice-hint'));
        this.offers = element(this.document, 'div', '', 'character-build-choice-offers');
        this.offers.setAttribute('role', 'group');
        this.offers.setAttribute('aria-label', '待选择的礼包');
        this.context.appendChild(this.offers);
        this.page.root.appendChild(this.context);
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
        this.confirm.setAttribute('data-choice-confirm', '');
        this.storage = element(this.document, 'button', '前往暂存物资'); this.storage.onclick = function() {
            if (self.state === 'idle') { self.page.close('storage'); options.storage(); }
        };
        [this.refresh, this.query, this.storage, this.confirm].forEach(function(node) { footer.appendChild(node); });
        this.page.root.appendChild(footer);
        this.updateState('idle');
    }
    ChoiceView.prototype.syncPresentationMode = function() {
        this.page.root.classList.toggle('reduced-presentation', Grades.isReducedPresentation());
    };
    ChoiceView.prototype.open = function() {
        var shell = this.options.view.root.closest('.inventory-workbench-panel');
        var header = shell && shell.querySelector('.workbench-header');
        this.syncPresentationMode();
        this.renderCards();
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
            var previousOffer = this.offerId;
            this.offerId = data.offers.some(function(o) { return o.offerId === wanted; }) ? wanted
                : data.offers.length ? data.offers[0].offerId : '';
            if (previousOffer !== this.offerId) this.selected = '';
            var self = this;
            var focusOffer = this.document.activeElement && this.document.activeElement.getAttribute('data-choice-offer');
            var scrollLeft = this.offers.scrollLeft;
            this.offers.textContent = '';
            data.offers.forEach(function(offer, index) {
                var row = element(self.document, 'button', offer.title + ' · ' + (index + 1));
                row.setAttribute('data-choice-offer', offer.offerId);
                row.setAttribute('aria-pressed', String(offer.offerId === self.offerId));
                row.onclick = function() {
                    if (self.state !== 'idle' || self.snapshot.pendingOperationId) return;
                    if (self.offerId === offer.offerId) return;
                    self.offerId = offer.offerId; self.selected = ''; self.cards.scrollTop = 0;
                    self.offers.querySelectorAll('[data-choice-offer]').forEach(function(node) {
                        node.setAttribute('aria-pressed', String(node.getAttribute('data-choice-offer') === self.offerId));
                    });
                    self.renderCards();
                };
                self.offers.appendChild(row);
                if (focusOffer === offer.offerId) row.focus({preventScroll:true});
            });
            this.offers.hidden = data.offers.length < 2;
            this.offers.scrollLeft = scrollLeft;
            this.renderCards();
        }
        this.updateState(this.state);
    };
    ChoiceView.prototype.renderCards = function() {
        var self = this;
        var scrollTop = this.cards.scrollTop;
        var focusOption = this.document.activeElement && this.document.activeElement.getAttribute('data-choice-option');
        var offer = this.snapshot && this.snapshot.offers.find(function(o) { return o.offerId === self.offerId; });
        if (this.tooltipScope) this.tooltipScope.releaseTree(this.cards);
        this.cards.textContent = '';
        if (!offer) { this.selected = ''; this.cards.appendChild(element(this.document, 'p', '暂无待选择的礼包。打开背包中的自选配给包后，就可以在这里继续选择。')); this.updateState(this.state); return; }
        this.cards.style.setProperty('--choice-columns', String(offer.options.length));
        if (!offer.options.some(function(o) { return o.optionId === self.selected; })) this.selected = '';
        offer.options.forEach(function(option) {
            var card = element(self.document, 'button', '', 'character-build-choice-card');
            card.setAttribute('data-choice-option', option.optionId);
            card.setAttribute('aria-pressed', String(self.selected === option.optionId));
            var grade = Grades.normalize(option.grade);
            var gradeLabel = Grades.label(grade);
            if (grade !== 'unknown') {
                card.classList.add('grade-' + grade);
                card.style.setProperty('--mod-grade-color', Grades.color(grade));
            }
            var title = element(self.document, 'strong', option.title);
            if (gradeLabel) {
                title.appendChild(element(self.document, 'span', gradeLabel,
                    'character-build-choice-grade'));
            }
            card.appendChild(title);
            card.appendChild(element(self.document, 'span', option.description, 'character-build-choice-description'));
            var items = element(self.document, 'span', '', 'character-build-choice-items');
            option.items.forEach(function(item) {
                var row = element(self.document, 'span', '', 'character-build-choice-item');
                var icon = element(self.document, 'span', '', 'character-build-choice-icon');
                icon.setAttribute('aria-hidden', 'true');
                function paintIcon() {
                    if (self.destroyed || !row.isConnected) return;
                    icon.innerHTML = self.icons.html(item.icon || item.itemName, 'item-icon');
                    if (!icon.firstChild) icon.textContent = '·';
                }
                var copy = element(self.document, 'span', '', 'character-build-choice-item-copy');
                copy.appendChild(element(self.document, 'span', item.displayName));
                copy.appendChild(element(self.document, 'small', '数量 ' + item.quantity + (item.level > 0 ? ' · 需要等级 ' + item.level : '')));
                row.append(icon, copy); items.appendChild(row);
                if (self.icons) self.icons.load(function() { Promise.resolve().then(paintIcon); });
                if (self.tooltipScope) self.bindItemPreview(row, item);

            });
            (option.skills || []).forEach(function(skill) {
                var row = element(self.document, 'span', '', 'character-build-choice-item');
                var icon = element(self.document, 'span', '', 'character-build-choice-icon');
                icon.setAttribute('aria-hidden', 'true');
                function paintSkillIcon() {
                    if (self.destroyed || !row.isConnected) return;
                    // 与物品同一图标管线：iconKey 缺省回退 skillKey（图标清单按技能名烘焙）。
                    icon.innerHTML = self.icons.html(skill.skillKey, 'item-icon');
                    if (!icon.firstChild) icon.textContent = '·';
                }
                var copy = element(self.document, 'span', '', 'character-build-choice-item-copy');
                copy.appendChild(element(self.document, 'strong', skill.skillKey + ' · ' + skill.level + '级'));
                copy.appendChild(element(self.document, 'small', skill.currentLevel ? '现有 ' + skill.currentLevel + '级 → ' + skill.level + '级' : '直接学会，不消耗SP'));
                // 技能注释可见性优先（速通场景悬停成本高）：完整描述留在 tooltip，卡内放可见小字行。
                if (skill.description) {
                    copy.appendChild(element(self.document, 'small', skill.description,
                        'character-build-choice-skill-description'));
                }
                row.append(icon, copy); items.appendChild(row);
                if (self.icons) self.icons.load(function() { Promise.resolve().then(paintSkillIcon); });
                if (self.tooltipScope) self.bindSkillPreview(row, skill, option.description);
            });
            card.appendChild(items);
            var price = element(self.document, 'strong', option.kCost ? option.kCost + ' K点' : '免费配给',
                'character-build-choice-price');
            price.setAttribute('data-paid', option.kCost ? 'true' : 'false');
            card.appendChild(price);
            card.onclick = function() {
                if (self.state !== 'idle' || self.snapshot.pendingOperationId) return;
                self.selected = option.optionId;
                self.grantedNote = '';
                self.cards.querySelectorAll('[data-choice-option]').forEach(function(node) {
                    node.setAttribute('aria-pressed', String(node.getAttribute('data-choice-option') === self.selected));
                });
                self.updateState(self.state);
            };
            self.cards.appendChild(card);
            if (focusOption === option.optionId) card.focus({preventScroll:true});
            if (self.tooltipScope) self.bindPreview(card, option);
        });
        this.cards.scrollTop = scrollTop;
        this.updateState(this.state);
    };
    ChoiceView.prototype.bindItemPreview = function(row, item) {
        // 与背包候选对比同一富 tooltip 通道：kshop-tt 富模板 + dynamicIconHtml 大图，
        // 内容由快照冻结的 icon/details 直供，无新增读取。
        if (!this.tooltipScope || !this.tooltip
                || typeof this.tooltip.buildItemRichHtml !== 'function') return;
        var tooltip = this.tooltip;
        this.tooltipScope.bindAsync(row, {key:item.itemName + '\n' + item.quantity + '\n' + (item.details || ''),
            item:item,
            renderBasic:function() {
                var iconKey = item.icon || item.itemName;
                var intro = '<div class="kshop-tt-header"><b>' + escapeHtml(item.displayName) + '</b></div>'
                    + '<span class="kshop-tt-dim">数量</span> ' + escapeHtml(item.quantity)
                    + (item.level > 0 ? '<br><span class="kshop-tt-dim">等级</span> ' + escapeHtml(item.level) : '');
                return tooltip.buildItemRichHtml({
                    iconHtml:tooltip.dynamicIconHtml(iconKey),
                    iconUrl:typeof tooltip.staticIconUrl === 'function' ? tooltip.staticIconUrl(iconKey) : '',
                    introWebHTML:intro,
                    descHTML:plainToHtml(item.details || ''),
                    rootClass:'kshop-tt-rich-context character-build-choice-tt-context',
                    layoutType:'wide'
                });
            }});
    };
    ChoiceView.prototype.bindSkillPreview = function(row, skill, fallbackDescription) {
        // 与技能页同一样式：skills-tooltip 模板 + 技能图标 + 注释。
        if (!this.tooltipScope || !this.tooltip
                || typeof this.tooltip.buildItemRichHtml !== 'function') return;
        var tooltip = this.tooltip;
        this.tooltipScope.bindAsync(row, {key:'skill\n' + skill.skillKey + '\n' + skill.level,
            item:skill,
            renderBasic:function() {
                var intro = '<div class="skills-tt-title"><b>' + escapeHtml(skill.skillKey) + '</b></div>'
                    + '<div class="skills-tt-meta">' + escapeHtml('奖励等级 Lv.' + skill.level
                        + (skill.currentLevel ? ' · 现有 Lv.' + skill.currentLevel : '')) + '</div>';
                return tooltip.buildItemRichHtml({
                    iconHtml:tooltip.dynamicIconHtml(skill.skillKey, 'skills-tt-icon'),
                    introWebHTML:intro,
                    descHTML:plainToHtml(skill.description || fallbackDescription || ''),
                    rootClass:'skills-tooltip',
                    layoutType:'wide',
                    splitMode:'auto'
                });
            }});
    };
    ChoiceView.prototype.bindPreview = function(node, option) {
        // 卡级 tooltip 也走富模板（窄版）：标题+整包说明；逐项明细由行级富 tooltip 承担，
        // 不再把全部物品细节堆进一个灰盒。
        if (!this.tooltip || typeof this.tooltip.buildItemRichHtml !== 'function') return;
        var tooltip = this.tooltip;
        var title = option.title;
        var details = option.description;
        this.tooltipScope.bindAsync(node, {key:title + '\n' + details, item:{},
            renderBasic:function() {
                var intro = '<div class="kshop-tt-header"><b>' + escapeHtml(title) + '</b></div>'
                    + '<span class="kshop-tt-dim">配给卡 · 点选后在底部确认</span>';
                return tooltip.buildItemRichHtml({
                    iconHtml:'',
                    introWebHTML:intro,
                    descHTML:plainToHtml(details || ''),
                    rootClass:'kshop-tt-rich-context character-build-choice-tt-context',
                    layoutType:'wide'
                });
            }});
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
        this.offers.querySelectorAll('[data-choice-offer]').forEach(function(node) { node.disabled = busy; });
        this.refresh.disabled = state === 'write_pending' || state === 'query_pending';
        this.query.hidden = state !== 'needs_reconcile' && !pending;
        this.query.disabled = state === 'query_pending' || state === 'write_pending';
        this.back.disabled = state === 'write_pending' || state === 'query_pending';
        this.cards.querySelectorAll('[data-choice-option]').forEach(function(node) { node.disabled = busy; });
        var offer = this.snapshot && this.snapshot.offers.find(function(o) { return o.offerId === this.offerId; }, this);
        var chosen = offer && offer.options.find(function(o) { return o.optionId === this.selected; }, this);
        var balance = this.snapshot && this.snapshot.kpoints || 0;
        this.balance.textContent = '本局 K点：' + balance + ' · 每次只扣所选卡片的价格';
        var affordable = !chosen || (chosen.kCost || 0) <= balance;
        this.confirm.disabled = this.confirm.disabled || !affordable || !!chosen && chosen.available === false;
        this.confirm.textContent = chosen ? (chosen.kCost ? '支付 ' + chosen.kCost + ' K点领取「' : '领取「') + chosen.title + '」' : '领取这套配给';
        if (state !== 'idle') this.grantedNote = '';
        this.status.textContent = this.loadFailed ? '配给列表暂时无法读取，请刷新重试。'
            : state === 'write_pending' ? '正在保存你的选择…'
            : state === 'query_pending' ? '正在核对领取结果…'
            : state === 'needs_reconcile' || pending ? '上次操作结果待确认，请先核对。'
            : this.grantedNote ? this.grantedNote
            : chosen && chosen.available === false ? '该技能已达到奖励等级，或当前状态不可领取，请改选其他配给。'
            : !affordable ? 'K点不足，可选择免费配给，或保留候选稍后领取。'
            : this.selected ? '确认后其余候选将放弃；只支付这一张卡片的价格。' : count ? '点选一套配给，再确认领取。' : '';
    };
    ChoiceView.prototype.destroy = function() {
        if (this.destroyed) return;
        this.destroyed = true; if (this.tooltipScope) this.tooltipScope.dispose(); this.page.destroy(); this.button.remove();
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
                    });
                }});
            return this._choiceRewards;
        };
        controller._refreshChoiceRewards = function(preferred, returnWhenFinished) {
            var view = this._ensureChoiceRewards();
            if (!view) return;
            var self = this;
            var request = this._choiceRefreshSequence = (this._choiceRefreshSequence || 0) + 1;
            if (preferred) view.open();
            this._itemUse.requestChoices(function(data) {
                if (view.destroyed || self._choiceRewards !== view) return;
                view.setSnapshot(data, preferred);
                // Only a committed choice may finish this workflow. An empty or
                // failed background read must never dismiss a pending receipt.
                if (!returnWhenFinished || !data || data.offers.length || data.pendingOperationId) return;
                self._itemUse.refreshInbox(function(response, accepted) {
                    var summary = response && response.inboxSummary;
                    if (accepted && summary && summary.remainingCount === 0 && summary.recoveryRequired !== true && summary.storeId === data.storeId
                            && summary.authorityRevision >= data.revision && request === self._choiceRefreshSequence
                            && !view.destroyed && self._choiceRewards === view && view.snapshot === data
                            && self._itemUse.debugState().state === 'idle' && view.page.isActive())
                        view.page.close('claimed');
                });
            });
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
