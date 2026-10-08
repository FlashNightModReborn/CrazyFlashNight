/**
 * Item-use reveal layer: the committed receipt becomes a complete result grid
 * in the same frame, on a SecondaryPage. Zero flourish by design — any input
 * (click anywhere, Esc, the focused close button) dismisses straight to the
 * terminal state; no extra click is required to reach the result.
 *
 * DORMANT（2026-10-08 起）：协议冻结面让 open/openMany 回包只携带
 * {ordinal,batchId,entryCount}，逐物身份不可读（modern v2 store 无按批次枚举
 * 条目的读通道，且"优先入包"分流使暂存侧不完整）。无内容物的揭晓页属
 * 名不副实，已全部下线为内联消息；本模块的渲染器（结果网格/聚合/汇总）
 * 保留并被 harness 直接驱动覆盖，待协议扩展批量内容投影后重新接通。
 */
(function(root, factory) {
    'use strict';
    var components = typeof module !== 'undefined' && module.exports
        ? require('../workbench-components.js') : root && root.WorkbenchComponents;
    var grades = typeof module !== 'undefined' && module.exports
        ? require('../grade-presentation.js') : root && root.GradePresentation;
    var api = factory(components, grades);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildItemUseReveal = api;
})(typeof window !== 'undefined' ? window : globalThis, function(Components, Grades) {
    'use strict';

    function element(document, tag, text, className) {
        var node = document.createElement(tag);
        if (text) node.textContent = text;
        if (className) node.className = className;
        if (tag === 'button') node.type = 'button';
        return node;
    }

    /** Aggregate identical drops and group rows by grade for summary views. */
    function summarize(items, fallbackGrade) {
        var byKey = {};
        var order = [];
        (items || []).forEach(function(item) {
            if (!item) return;
            var name = String(item.itemName || item.displayName || '');
            if (!name) return;
            var level = Math.max(0, Math.floor(Number(item.level) || 0));
            var key = name + '#' + level;
            if (!byKey[key]) {
                byKey[key] = {
                    itemName:name,
                    displayName:String(item.displayName || name),
                    level:level,
                    icon:String(item.icon || name),
                    grade:Grades.normalize(item.grade != null ? item.grade : fallbackGrade),
                    quantity:0
                };
                order.push(key);
            }
            byKey[key].quantity += Math.max(0, Math.floor(Number(item.quantity) || 0));
        });
        var groups = [];
        Grades.GROUP_ORDER.forEach(function(grade) {
            var rows = order.map(function(key) { return byKey[key]; })
                .filter(function(row) { return row.grade === grade; });
            if (rows.length) {
                groups.push({grade:grade, label:Grades.label(grade), rows:rows});
            }
        });
        return groups;
    }

    function RevealView(options) {
        var self = this;
        this.options = options || {};
        this.document = this.options.view.root.ownerDocument;
        var win = this.document.defaultView;
        this.icons = win && win.Icons;
        this.destroyed = false;
        this.page = new Components.SecondaryPage({document:this.document, role:'dialog',
            ariaLabel:'开箱结果', className:'character-build-reveal-page',
            underlay:this.options.view._underlay,
            onBack:function() { return true; }});
        this.page.mount(this.options.view.root);
        var header = element(this.document, 'header', '', 'character-build-reveal-header');
        this.title = element(this.document, 'h2', '开箱结果');
        header.appendChild(this.title);
        this.close = element(this.document, 'button', '收下', 'character-build-reveal-close');
        this.close.setAttribute('data-reveal-close', '');
        header.appendChild(this.close);
        this.page.bindClose(this.close);
        this.page.root.appendChild(header);
        this.grid = element(this.document, 'div', '', 'character-build-reveal-grid');
        this.grid.setAttribute('role', 'group');
        this.grid.setAttribute('aria-label', '获得的物资');
        this.page.root.appendChild(this.grid);
        var footer = element(this.document, 'footer', '', 'character-build-reveal-footer');
        this.hint = element(this.document, 'p', '', 'character-build-reveal-hint');
        this.hint.setAttribute('role', 'status');
        footer.appendChild(this.hint);
        this.storage = element(this.document, 'button', '前往暂存物资');
        this.storage.onclick = function(event) {
            if (event && event.stopPropagation) event.stopPropagation();
            self.page.close('storage');
            if (self.options.storage) self.options.storage();
        };
        footer.appendChild(this.storage);
        this.page.root.appendChild(footer);
        // 任意指针输入即达终态：页内任意位置点击等同于确认收下。
        this.page.root.addEventListener('click', function(event) {
            if (event.target === self.storage || self.storage.contains(event.target)) return;
            if (event.target === self.close || self.close.contains(event.target)) return;
            self.page.close('dismiss');
        });
    }
    RevealView.prototype._rowIcon = function(row, iconKey) {
        var icon = element(this.document, 'span', '', 'kshop-tt-icon character-build-reveal-icon');
        icon.setAttribute('aria-hidden', 'true');
        if (this.icons) {
            var self = this;
            // 与配给卡同一惯例：延迟到微任务，行先完成挂载再绘制（同步回调时行尚未连接）。
            this.icons.load(function() {
                Promise.resolve().then(function() {
                    if (self.destroyed || !icon.isConnected) return;
                    icon.innerHTML = self.icons.html(iconKey, 'item-icon');
                });
            });
        }
        row.appendChild(icon);
    };
    RevealView.prototype._renderItems = function(result) {
        var self = this;
        var groups = summarize(result.items, result.grade);
        if (!groups.length && !(result.skills || []).length) {
            this.grid.appendChild(element(this.document, 'p', '该配给没有实体物资。'));
        }
        groups.forEach(function(group) {
            if (group.label) {
                var heading = element(self.document, 'p', group.label,
                    'character-build-reveal-group grade-' + group.grade);
                heading.style.setProperty('--mod-grade-color', Grades.color(group.grade));
                self.grid.appendChild(heading);
            }
            group.rows.forEach(function(item) {
                var row = element(self.document, 'div', '',
                    'character-build-reveal-item grade-' + item.grade);
                row.style.setProperty('--mod-grade-color', Grades.color(item.grade));
                self._rowIcon(row, item.icon);
                var copy = element(self.document, 'span', '', 'character-build-reveal-copy');
                copy.appendChild(element(self.document, 'strong', item.displayName));
                copy.appendChild(element(self.document, 'small',
                    '数量 ' + item.quantity + (item.level > 0 ? ' · 强化等级 ' + item.level : '')));
                row.appendChild(copy);
                self.grid.appendChild(row);
            });
        });
        (result.skills || []).forEach(function(skill) {
            var skillGrade = Grades.normalize(result.grade);
            var row = element(self.document, 'div', '',
                'character-build-reveal-item' + (skillGrade !== 'unknown' ? ' grade-' + skillGrade : ''));
            if (skillGrade !== 'unknown') {
                row.style.setProperty('--mod-grade-color', Grades.color(skillGrade));
            }
            // 技能图标与物品同管线：iconKey 缺省回退 skillKey（图标清单按技能名烘焙）。
            self._rowIcon(row, String(skill.skillKey || ''));
            var copy = element(self.document, 'span', '', 'character-build-reveal-copy');
            copy.appendChild(element(self.document, 'strong',
                String(skill.skillKey || '') + ' · ' + (Number(skill.level) || 0) + '级'));
            copy.appendChild(element(self.document, 'small', '技能已直接授予，主动技能请在技能页装备'));
            if (skill.description) {
                copy.appendChild(element(self.document, 'small', String(skill.description),
                    'character-build-reveal-skill-description'));
            }
            row.appendChild(copy);
            self.grid.appendChild(row);
        });
    };
    /**
     * 内容物揭晓受协议冻结面阻塞（回包不含逐物身份）：当前所有结算种类都
     * 不自动开页，一律内联。待协议扩展批量内容投影后，通道恢复按
     * "结果是否在操作前已知情"分级（choiceSelect/fixed 内联，随机/批量开页）。
     * 本模块当前只被 harness 直接驱动覆盖渲染器。
     */
    RevealView.prototype.show = function(result) {
        if (this.destroyed || !result) return false;
        var count = Math.max(1, Math.floor(Number(result.count) || 0));
        this.page.root.classList.toggle('reduced-presentation', Grades.isReducedPresentation());
        this.grid.textContent = '';
        if (result.kind === 'choiceSelect') {
            this.title.textContent = '已领取「' + String(result.title || '所选配给') + '」';
            this._renderItems(result);
            this.hint.textContent = (result.kCost > 0 ? '已扣除 ' + result.kCost + ' K点。' : '')
                + '物品优先进入背包，装不下的进入暂存。';
            this.storage.hidden = true;
        } else {
            var entries = 0;
            (result.packages || []).forEach(function(pack) {
                entries += Math.max(0, Math.floor(Number(pack && pack.entryCount) || 0));
            });
            this.title.textContent = '已打开「' + String(result.name || '礼包') + '」'
                + (count > 1 ? ' ×' + count : '');
            var row = element(this.document, 'div', '', 'character-build-reveal-item');
            this._rowIcon(row, String(result.icon || result.name || ''));
            var copy = element(this.document, 'span', '', 'character-build-reveal-copy');
            copy.appendChild(element(this.document, 'strong', String(result.name || '礼包')));
            copy.appendChild(element(this.document, 'small',
                '打开 ' + count + ' 个' + (entries > 0 ? ' · 入账 ' + entries + ' 件物资' : '')));
            row.appendChild(copy);
            this.grid.appendChild(row);
            this.hint.textContent = '明细以暂存物资为准：物资优先入包，溢出部分留在暂存'
                + (result.inboxRemaining != null ? '（当前 ' + result.inboxRemaining + ' 件）' : '') + '。';
            this.storage.hidden = false;
        }
        return this.page.open({opener:this.options.opener || null, initialFocus:this.close,
            underlay:this.options.view._underlay});
    };
    RevealView.prototype.isActive = function() { return this.page.isActive(); };
    RevealView.prototype.destroy = function() {
        if (this.destroyed) return;
        this.destroyed = true;
        this.page.destroy();
    };

    function whole(value) {
        value = Number(value);
        return isFinite(value) && value >= 0 && Math.floor(value) === value ? value : null;
    }
    /**
     * Build the reveal payload for a committed settlement; null when the
     * settlement has nothing revealable. choiceSelect contents come from the
     * frozen offer snapshot (same frame); open/openMany stay pack-level
     * because the frozen receipt carries only package descriptors.
     */
    function fromSettlement(choiceSnapshot, receipt, pending, inboxSummary) {
        receipt = receipt || {};
        if (receipt.kind === 'choiceSelect' && choiceSnapshot) {
            var offers = choiceSnapshot.offers || [];
            for (var i = 0; i < offers.length; i++) {
                if (offers[i].offerId !== receipt.offerId) continue;
                var options = offers[i].options || [];
                for (var j = 0; j < options.length; j++) {
                    if (options[j].optionId === receipt.optionId) {
                        return {kind:'choiceSelect', title:options[j].title,
                            grade:options[j].grade, kCost:options[j].kCost || 0,
                            items:options[j].items || [], skills:options[j].skills || []};
                    }
                }
            }
            return null;
        }
        if (pending && (pending.command === 'open' || pending.command === 'openMany')
                && (receipt.kind === 'open' || receipt.kind === 'openMany')) {
            var candidate = pending.candidate || {};
            var candidateAction = candidate.useAction || candidate.raw && candidate.raw.useAction || {};
            var item = candidate.raw && candidate.raw.item || candidate.presentation || {};
            var summary = receipt.inboxSummary || inboxSummary || {};
            return {kind:pending.command,
                name:String(candidate.name || item.displayName || item.name || '礼包'),
                icon:String(item.icon || item.name || candidate.name || ''),
                packMode:String(candidateAction.packMode || ''),
                count:whole(receipt.consumed) || 1,
                packages:receipt.packages || [],
                inboxRemaining:whole(summary.remainingCount)};
        }
        return null;
    }

    /** 内联授予消息：走内联路径（不开揭晓页）的 choiceSelect 由这段携带内容清单。 */
    function formatGrantMessage(details) {
        if (!details) return null;
        var parts = [];
        (details.items || []).forEach(function(item) {
            parts.push(String(item.displayName || item.itemName || '') + ' ×' + (Number(item.quantity) || 1));
        });
        (details.skills || []).forEach(function(skill) {
            parts.push(String(skill.skillKey || '') + ' · ' + (Number(skill.level) || 0) + '级');
        });
        var tail = '';
        if ((details.skills || []).length) tail += '技能已直接授予，主动技能请在技能页装备。';
        if ((details.items || []).length) tail += '物品优先进入背包，装不下的进入暂存。';
        return '已领取「' + String(details.title || '所选配给') + '」'
            + (parts.length ? '：' + parts.join('、') : '') + '。' + tail;
    }

    function install(controller) {
        controller._ensureItemUseReveal = function() {
            if (this._itemUseReveal || this._itemUseRevealFailed) return this._itemUseReveal || null;
            if (!this._view || !this._view.root || !this._view.root.ownerDocument
                    || !Components || typeof Components.SecondaryPage !== 'function') {
                return null;
            }
            var self = this;
            try {
                this._itemUseReveal = new RevealView({view:this._view,
                    storage:function() { self._openRewardInbox(); }});
            } catch (error) {
                this._itemUseRevealFailed = true;
                return null;
            }
            return this._itemUseReveal;
        };
        controller._showItemUseReveal = function(result) {
            var reveal = this._ensureItemUseReveal();
            return !!(reveal && reveal.show(result));
        };
        controller._destroyItemUseReveal = function() {
            if (this._itemUseReveal) this._itemUseReveal.destroy();
            this._itemUseReveal = null;
        };
    }

    return {install:install, RevealView:RevealView, summarize:summarize, fromSettlement:fromSettlement,
        formatGrantMessage:formatGrantMessage};
});
