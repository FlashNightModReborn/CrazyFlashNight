/**
 * TeamShared — 战队面板（佣兵 / 伙伴 / 战宠 / 机械）共享纯 DOM 工具层。
 *
 * 职责边界（双栏工作台翻新 Phase A 基座）：
 *  - escapeHtml / escapeAttr：统一转义（归一 pet 的 escapeHtml 与 merc 的 escHtml 两套写法）；
 *  - fmtMoney：金币格式化（逻辑搬自 pet-panel.js formatMoney，保持玩家可见输出不变）；
 *  - toast：共享 Toast.add 包装（同 skills.js 模式，替代 pet 三色队列与 merc 单 toast）；
 *  - setPending：按钮 pending 投影（team-is-pending + aria-busy + disabled），
 *    语义对齐 pet-panel beginOp/endOp 与 merc-panel setPending；
 *  - buildEmptyState：{kind, statement, nextStep} 空态 DOM（.workbench-empty-state + data-empty-kind，
 *    样式由 css/workbench/states.css 提供）；
 *  - createDropdown：可键盘操作的排序/筛选下拉（真 button 触发器与选项、Esc 关闭并归还焦点、
 *    document 外点关闭、destroy 幂等），替代 pet-panel 自绘 pet-dropdown。
 *
 * 本模块无外部依赖（纯 DOM），不持有 Bridge / session / 业务状态；由 panels-lazy-registry
 * 按 共享层 → 领域 → 壳 的顺序在 pet-panel / merc-panel / team-panel 之前加载。
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.TeamShared = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    // ── 转义 ──
    // escapeHtml 用于文本节点/innerHTML 拼接；escapeAttr 用于属性值拼接（额外转义引号）。
    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }
    function escapeAttr(s) {
        return escapeHtml(s);
    }

    // ── 金币格式化（搬自 pet-panel.js formatMoney，行为保持一致）──
    function fmtMoney(n) {
        if (n == null || isNaN(n)) return '--';
        n = Number(n);
        if (n >= 100000000) return (n / 100000000).toFixed(2) + '亿';
        if (n >= 10000) return (n / 10000).toFixed(1) + '万';
        return n.toLocaleString ? n.toLocaleString() : String(n);
    }

    // ── Toast（共享 Toast.add 包装，同 skills.js 模式）──
    function toast(msg) {
        if (typeof Toast !== 'undefined' && Toast.add) Toast.add(msg);
    }

    // ── 按钮 pending 投影 ──
    // 进入 pending：记录原 disabled、强制 disabled、挂 aria-busy 与统一 class；
    // 退出 pending：只恢复自己写下的状态（原本就 disabled 的按钮保持 disabled）。幂等。
    function setPending(btn, on) {
        if (!btn) return;
        var pending = !!on;
        if (pending === (btn.getAttribute('data-team-pending') === '1')) return;
        if (pending) {
            btn.setAttribute('data-team-pending', '1');
            btn.setAttribute('data-team-pending-disabled', btn.disabled ? '1' : '0');
            btn.disabled = true;
        } else {
            btn.removeAttribute('data-team-pending');
            if (btn.getAttribute('data-team-pending-disabled') !== '1') btn.disabled = false;
            btn.removeAttribute('data-team-pending-disabled');
        }
        btn.setAttribute('aria-busy', pending ? 'true' : 'false');
        btn.classList.toggle('team-is-pending', pending);
    }

    // ── 空态 ──
    // 规范 §2.3/§5.3：kind ∈ empty/filtered/error/unavailable，文案 = 一句陈述 + 下一步动作/原因。
    var EMPTY_KINDS = { empty: true, filtered: true, error: true, unavailable: true };
    function buildEmptyState(options) {
        var opts = options || {};
        var kind = EMPTY_KINDS[opts.kind] ? opts.kind : 'empty';
        var rootEl = document.createElement('div');
        rootEl.className = 'workbench-empty-state';
        rootEl.setAttribute('data-empty-kind', kind);
        var statement = document.createElement('strong');
        statement.className = 'workbench-empty-statement';
        statement.textContent = opts.statement == null ? '' : String(opts.statement);
        var nextStep = document.createElement('p');
        nextStep.className = 'workbench-empty-next-step';
        nextStep.textContent = opts.nextStep == null ? '' : String(opts.nextStep);
        rootEl.appendChild(statement);
        rootEl.appendChild(nextStep);
        return rootEl;
    }

    // ── 排序/筛选下拉 ──
    // 触发器与选项均为真 button（原生 Enter/Space 激活）；Esc 关闭并归还焦点给触发器；
    // document 捕获相 pointerdown 外点关闭；destroy 幂等并清理 document listener。
    function createDropdown(options) {
        var opts = options || {};
        var label = opts.label == null ? '' : String(opts.label);
        var onSelect = typeof opts.onSelect === 'function' ? opts.onSelect : function() {};

        // 归一化选项：{value, label}，label 缺省回退 value 字符串
        var items = [];
        var rawOptions = opts.options || [];
        for (var i = 0; i < rawOptions.length; i++) {
            var raw = rawOptions[i] || {};
            items.push({
                value: raw.value,
                label: raw.label == null ? String(raw.value) : String(raw.label)
            });
        }

        var rootEl = document.createElement('div');
        rootEl.className = 'team-dropdown';

        var trigger = document.createElement('button');
        trigger.type = 'button';
        trigger.className = 'team-dropdown-trigger';
        trigger.setAttribute('aria-haspopup', 'listbox');
        trigger.setAttribute('aria-expanded', 'false');
        if (opts.ariaLabel) trigger.setAttribute('aria-label', String(opts.ariaLabel));
        var triggerText = document.createElement('span');
        triggerText.className = 'team-dropdown-text';
        var caret = document.createElement('span');
        caret.className = 'team-dropdown-caret';
        caret.setAttribute('aria-hidden', 'true');
        caret.textContent = '▾';
        trigger.appendChild(triggerText);
        trigger.appendChild(caret);
        rootEl.appendChild(trigger);

        var menu = document.createElement('div');
        menu.className = 'team-dropdown-menu';
        menu.setAttribute('role', 'listbox');
        if (opts.ariaLabel) menu.setAttribute('aria-label', String(opts.ariaLabel));
        menu.hidden = true;

        var optionButtons = [];
        for (var o = 0; o < items.length; o++) {
            var optionButton = document.createElement('button');
            optionButton.type = 'button';
            optionButton.className = 'team-dropdown-option';
            optionButton.setAttribute('role', 'option');
            optionButton.setAttribute('aria-selected', 'false');
            optionButton.textContent = items[o].label;
            bindOptionClick(optionButton, items[o].value);
            optionButtons.push(optionButton);
            menu.appendChild(optionButton);
        }
        rootEl.appendChild(menu);

        var isOpen = false;
        var destroyed = false;
        var activeIndex = items.length ? 0 : -1;
        if (opts.activeValue !== undefined) {
            for (var a = 0; a < items.length; a++) {
                if (items[a].value === opts.activeValue) { activeIndex = a; break; }
            }
        }

        function bindOptionClick(button, value) {
            button.addEventListener('click', function() {
                setActive(value);
                closeMenu(true);
                onSelect(value, labelOf(value));
            });
        }
        function labelOf(value) {
            for (var i = 0; i < items.length; i++) {
                if (items[i].value === value) return items[i].label;
            }
            return '';
        }
        function renderTriggerText() {
            var current = activeIndex >= 0 && activeIndex < items.length ? items[activeIndex].label : '';
            triggerText.textContent = label ? (current ? label + ' · ' + current : label) : current;
        }
        function setActive(value) {
            for (var i = 0; i < items.length; i++) {
                var active = items[i].value === value;
                optionButtons[i].setAttribute('aria-selected', active ? 'true' : 'false');
                optionButtons[i].classList.toggle('team-dropdown-option-active', active);
                if (active) activeIndex = i;
            }
            renderTriggerText();
        }
        function focusOption(index) {
            if (index < 0 || index >= optionButtons.length) return;
            optionButtons[index].focus();
        }
        function open() {
            if (destroyed || isOpen) return;
            isOpen = true;
            menu.hidden = false;
            trigger.setAttribute('aria-expanded', 'true');
            rootEl.classList.add('team-dropdown-open');
            document.addEventListener('pointerdown', onDocumentPointerDown, true);
        }
        function closeMenu(restoreFocus) {
            if (!isOpen) return;
            isOpen = false;
            menu.hidden = true;
            trigger.setAttribute('aria-expanded', 'false');
            rootEl.classList.remove('team-dropdown-open');
            document.removeEventListener('pointerdown', onDocumentPointerDown, true);
            if (restoreFocus) trigger.focus();
        }
        function onDocumentPointerDown(event) {
            if (rootEl.contains(event.target)) return;
            closeMenu(false);
        }

        trigger.addEventListener('click', function() {
            if (isOpen) closeMenu(false);
            else open();
        });
        // 触发器上 ArrowDown/ArrowUp：打开并把焦点送入菜单首/末项
        // （stopPropagation：避免冒泡到 rootEl 的菜单导航处理器被二次消费）
        trigger.addEventListener('keydown', function(event) {
            if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
            event.preventDefault();
            event.stopPropagation();
            if (!isOpen) open();
            focusOption(event.key === 'ArrowDown' ? 0 : optionButtons.length - 1);
        });
        // Esc 分层：打开状态下拉先消费，关闭并归还焦点给触发器
        rootEl.addEventListener('keydown', function(event) {
            if (event.key === 'Escape' && isOpen) {
                event.preventDefault();
                event.stopPropagation();
                closeMenu(true);
                return;
            }
            if (!isOpen) return;
            if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                event.preventDefault();
                var index = optionButtons.indexOf(document.activeElement);
                if (event.key === 'ArrowDown') index = index < 0 ? 0 : (index + 1) % optionButtons.length;
                else index = index <= 0 ? optionButtons.length - 1 : index - 1;
                focusOption(index);
            } else if (event.key === 'Home') {
                event.preventDefault();
                focusOption(0);
            } else if (event.key === 'End') {
                event.preventDefault();
                focusOption(optionButtons.length - 1);
            }
        });

        setActive(activeIndex >= 0 ? items[activeIndex].value : undefined);
        renderTriggerText();

        return {
            root: rootEl,
            setActive: setActive,
            open: open,
            close: function() { closeMenu(false); },
            destroy: function() {
                if (destroyed) return;
                destroyed = true;
                closeMenu(false);
                document.removeEventListener('pointerdown', onDocumentPointerDown, true);
            }
        };
    }

    return {
        escapeHtml: escapeHtml,
        escapeAttr: escapeAttr,
        fmtMoney: fmtMoney,
        toast: toast,
        setPending: setPending,
        buildEmptyState: buildEmptyState,
        createDropdown: createDropdown
    };
});
