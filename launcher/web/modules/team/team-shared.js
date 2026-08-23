/**
 * TeamShared — 战队面板（佣兵 / 伙伴 / 战宠 / 机械）共享纯 DOM 工具层。
 *
 * 职责边界（双栏工作台翻新 Phase A 基座）：
 *  - escapeHtml：统一转义（归一 pet 的 escapeHtml 与 merc 的 escHtml 两套写法；
 *    引号一并转义，文本节点 / innerHTML 与属性值拼接通用）；
 *  - fmtMoney：金币格式化（逻辑搬自 pet-panel.js formatMoney，保持玩家可见输出不变）；
 *  - toast：共享 Toast.add 包装（同 skills.js 模式，替代 pet 三色队列与 merc 单 toast）；
 *  - setPending：按钮 pending 投影（team-is-pending + aria-busy + disabled），
 *    语义对齐 pet-panel beginOp/endOp 与 merc-panel setPending；
 *  - buildEmptyState：{kind, statement, nextStep} 空态 DOM（.workbench-empty-state + data-empty-kind，
 *    样式由 css/workbench/states.css 提供）；
 *  - createDropdown：可键盘操作的排序/筛选下拉（真 button 触发器与选项、Esc 关闭并归还焦点、
 *    document 外点关闭、destroy 幂等），替代 pet-panel 自绘 pet-dropdown。
 *
 * 2026-08-23 佣兵装备托管一期追加（设计 §8 的三件公共能力）：
 *  - createPanelRequester：超时版 panel 请求传输层，四个 tab 共用（callId 请求-响应、
 *    capability/session 迟到回包守卫、可配 requestTimeoutMs 合成 client_timeout、
 *    未受理/失效合成 not_sent / panel_instance_expired）。对账（reconcile）锁是各面板
 *    controller 私有状态机，不在本层；可疑回包经 controller 传入的 callback 原样上报。
 *  - createCandidateBrowser：托管交付类候选浏览器（自 pet-panel.js T800 长枪浏览器参数化：
 *    兼容/背包双视图、候选卡渲染钩子、锁定原因映射、密度控制挂接、列表独立滚动、单选确认）。
 *  - custodyBadgeSpec / buildCustodyBadge：托管三态徽章（预设/托管/托管异常 tone，
 *    复用 .team-managed-gun-readout 的 default/managed/danger 色板）。
 *
 * 本模块无加载期外部依赖（纯 DOM；ChoiceGroup / Workbench 在使用点惰性解析）；由 panels-lazy-registry
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
    // escapeHtml 引号一并转义，文本节点 / innerHTML 拼接与属性值拼接通用。
    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
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
    // severity 透传契约 §6 结果音挂钩：'success'/'error' 分别播 success/rejected；缺省静默。
    // 只在无任何显式结果音的静默路径上传 severity（防双响 §5.3）。
    function toast(msg, severity) {
        if (typeof Toast !== 'undefined' && Toast.add) Toast.add(msg, severity);
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
    // document 捕获相 pointerdown 外点关闭；focusout（Tab 离开 rootEl）收起且不抢焦点；
    // destroy 幂等并清理 document listener。
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
            // activeValue 提供但未命中任何选项时保持 -1，不误选首项（renderTriggerText 兼容 -1）
            activeIndex = -1;
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

        // Tab 离开收起：focusout 后 setTimeout(0) 等焦点落定再判——activeElement 已移出
        // rootEl（含菜单）才关，且不抢焦点（用户主动 Tab 走，尊重其去向）；菜单内 Tab
        // 顺序移动 contains 为真不关。监听挂在 rootEl 上随 DOM 销毁，destroy 无需额外清理。
        rootEl.addEventListener('focusout', function() {
            setTimeout(function() {
                if (isOpen && !rootEl.contains(document.activeElement)) closeMenu(false);
            }, 0);
        });

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

    // ── 超时版 panel 请求传输层（team 四个 tab 共用）──
    // 只承担无状态传输：callId 请求-响应注册、panelInstanceId/session 迟到回包守卫、
    // 可配 requestTimeoutMs 超时合成 client_timeout、Bridge.send 未受理合成 not_sent、
    // capability 非法合成 panel_instance_expired。对账（reconcile）锁是各面板 controller
    // 私有状态机，不在本层；超时/未达回包经 controller 传入的 callback 原样上报，
    // 由 controller 决定锁存与重拉。注册项超时即删，迟到回包无处投递、自然不复活。
    //
    // options:
    //   panel            面板域（'pets' / 'mercs'）
    //   callIdPrefix     callId 前缀（缺省 panel + '_'）
    //   configKeys       超时配置全局键，按序取「第一个已定义对象」读 requestTimeoutMs
    //                    （pet：['__TEAM_PET_CONFIG__']；merc：['__TEAM_MERC_CONFIG__','__TEAM_PET_CONFIG__']；
    //                    语义 = 现役写法 cfgA || cfgB：首个已定义对象生效，其值无效时不穿透 fallback），
    //                    缺省 12000ms（Host 权威 timeout 10s，Web 多留 2s 兜底回包真丢失）
    //   strictSendAccept true 时 Bridge.send 必须 === true 才算受理（merc 现役语义）；
    //                    否则 !== false 即受理（pet 现役语义）
    //   getSession() / getInstanceId()  读取 controller 当前 session 与 capability
    // 返回 { send, clearPending }；send(cmd, extra, cb) 返回 callId（未发出为 ''）。
    function createPanelRequester(options) {
        var opts = options || {};
        var panel = String(opts.panel || '');
        var prefix = String(opts.callIdPrefix || (panel + '_'));
        var configKeys = opts.configKeys || [];
        var strictSendAccept = opts.strictSendAccept === true;
        var getSession = typeof opts.getSession === 'function' ? opts.getSession : function() { return 0; };
        var getInstanceId = typeof opts.getInstanceId === 'function' ? opts.getInstanceId : function() { return ''; };
        var pendingReq = {};
        var reqSeq = 0;

        function globalRef() {
            if (typeof window !== 'undefined') return window;
            if (typeof globalThis !== 'undefined') return globalThis;
            return {};
        }

        function resolveTimeoutMs() {
            var g = globalRef();
            for (var i = 0; i < configKeys.length; i++) {
                var cfg = g[configKeys[i]];
                if (!cfg) continue;
                var configured = Number(cfg.requestTimeoutMs);
                return isFinite(configured) && configured >= 50 ? configured : 12000;
            }
            return 12000;
        }

        function clearPending() {
            for (var callId in pendingReq) {
                if (pendingReq.hasOwnProperty(callId) && pendingReq[callId].timer) {
                    clearTimeout(pendingReq[callId].timer);
                }
            }
            pendingReq = {};
        }

        function send(cmd, extra, cb) {
            var callId = prefix + (++reqSeq) + '_' + Date.now();
            var instance = getInstanceId();
            var requestSession = getSession();
            if (!/^[A-Za-z0-9._~-]{1,160}$/.test(instance)) {
                if (cb) setTimeout(function() {
                    if (requestSession !== getSession() || getInstanceId() !== instance) return;
                    cb({ type:'panel_resp', panel:panel, cmd:cmd, callId:callId,
                        panelInstanceId:instance, success:false,
                        error:'panel_instance_expired', clientSynthetic:true });
                }, 0);
                return '';
            }
            if (cb) {
                pendingReq[callId] = {
                    cmd: cmd,
                    panelInstanceId: instance,
                    session: requestSession,
                    callback: cb,
                    timer: setTimeout(function() {
                        var pending = pendingReq[callId];
                        if (!pending) return;
                        delete pendingReq[callId];
                        if (requestSession !== getSession() || getInstanceId() !== instance) return;
                        pending.callback({
                            type:'panel_resp', panel:panel, cmd:cmd, callId:callId,
                            panelInstanceId:instance, success:false,
                            error:'client_timeout', clientSynthetic:true
                        });
                    }, resolveTimeoutMs())
                };
            }
            var msg = { type:'panel', panel:panel, cmd:cmd, callId:callId,
                panelInstanceId:instance };
            if (extra) {
                for (var k in extra) {
                    if (extra.hasOwnProperty(k) && k !== 'type' && k !== 'panel'
                            && k !== 'cmd' && k !== 'callId' && k !== 'panelInstanceId') {
                        msg[k] = extra[k];
                    }
                }
            }
            var accepted = false;
            try {
                var sent = Bridge.send(msg);
                accepted = strictSendAccept ? (sent === true) : (sent !== false);
            } catch (error) { accepted = false; }
            if (!accepted) {
                var rejected = pendingReq[callId];
                delete pendingReq[callId];
                if (rejected && rejected.timer) clearTimeout(rejected.timer);
                if (cb) setTimeout(function() {
                    if (requestSession !== getSession() || getInstanceId() !== instance) return;
                    cb({ type:'panel_resp', panel:panel, cmd:cmd, callId:callId,
                        panelInstanceId:instance, success:false,
                        error:'not_sent', clientSynthetic:true });
                }, 0);
                return '';
            }
            return callId;
        }

        // 响应分发：panel + 当前 capability + session + cmd 四重对齐后才投递；
        // 超时/已应答的注册项已删除，迟到回包直接丢弃（不复活）。
        if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.on === 'function') {
            Bridge.on('panel_resp', function(data) {
                if (!data || data.type !== 'panel_resp' || data.panel !== panel) return;
                var instance = getInstanceId();
                if (!instance || data.panelInstanceId !== instance) return;
                var pending = pendingReq[data.callId];
                if (pending && pending.session === getSession()
                        && pending.panelInstanceId === instance
                        && data.cmd === pending.cmd) {
                    delete pendingReq[data.callId];
                    if (pending.timer) clearTimeout(pending.timer);
                    pending.callback(data);
                }
            });
        }

        return { send: send, clearPending: clearPending };
    }

    // ── 托管三态徽章（预设 / 托管 / 托管异常）──
    // 纯映射 + DOM 投影；tone 复用 .team-managed-gun-readout 的 default/managed/danger
    // 色板（team.css）。未知 state 按托管异常投影（fail-closed，未知即视为不可操作）。
    var CUSTODY_BADGE_SPECS = {
        preset:          { label: '预设',   tone: 'default' },
        custody:         { label: '托管',   tone: 'managed' },
        custody_corrupt: { label: '托管异常', tone: 'danger' }
    };
    function custodyBadgeSpec(state) {
        return CUSTODY_BADGE_SPECS[state] || CUSTODY_BADGE_SPECS.custody_corrupt;
    }
    function buildCustodyBadge(state) {
        var spec = custodyBadgeSpec(state);
        var badge = document.createElement('span');
        badge.className = 'team-custody-badge';
        badge.setAttribute('data-custody-tone', spec.tone);
        badge.textContent = spec.label;
        return badge;
    }

    // ── 托管交付类候选浏览器（T800 长枪 / 佣兵装备托管共用）──
    // 自 pet-panel.js 托管长枪浏览器（renderManagedLongGun 内联块）参数化抽取：
    // 兼容/背包双视图 ChoiceGroup、候选卡（图标/强化角标/锁定原因）、单选确认、
    // 密度控制挂接、候选列表独立滚动区。组件只投影与回调，不持有协议/会话状态；
    // 候选数据、锁定原因文案与提交动作全部由调用方注入。
    // options:
    //   candidates       [{source:{containerId,slot,expectedLease}, item, eligible, lockReason, requirementLevel, ...}]
    //   scope            初始视图 key（缺省取首个 scopeChoice）
    //   selectedKey      初始选中候选 key（缺省自动挑首个可交付，再次首个可见）
    //   scopeChoices     [{value,label,ariaLabel,eligibleOnly}]，缺省 兼容(eligibleOnly)/背包
    //   scopeLabel       视图切换标签文案，缺省「浏览方式」
    //   scopeAriaLabel   ChoiceGroup aria-label；listAriaLabel 候选列表 aria-label
    //   scrollRegion     候选列表 data-scroll-region（独立滚动区标识）
    //   commitLabel      确认按钮文案（「交付所选长枪」/「确认交付」/「确认替换」…）
    //   texts            {unknownItem,noSelection,pickHint,emptyScope,emptyNone,emptyFiltered,eligible,selectFirst}
    //   combatLockedReason  战斗锁定时确认钮的可读禁用原因；'' 表示可操作
    //   keyOf(candidate)    候选唯一键（缺省 containerId:slot:expectedLease）
    //   nameOf(item) / iconOf(item) / enhancementOf(item)  卡片渲染钩子（有缺省）
    //   bitsOf(candidate)     元信息串数组（需求等级 / 强化 / 插件…）
    //   lockTextOf(candidate) 锁定原因映射
    //   bindTip(row, candidate)  候选卡 tooltip 挂接（PanelTooltip 模式，可空）
    //   density          GridDensityController（可空；登记候选网格，destroy 时反登记）
    //   onScopeChange(scope) / onSelectionChange(key)  状态外溢回调（供调用方跨重建保持）
    //   onCommit(candidate, commitBtn)  确认提交（单选）
    // 返回 { root, getScope, getSelectedKey, destroy }。
    function createCandidateBrowser(options) {
        var opts = options || {};
        if (typeof WorkbenchComponents === 'undefined' || !WorkbenchComponents
                || typeof WorkbenchComponents.ChoiceGroup !== 'function') {
            throw new Error('TeamShared.createCandidateBrowser 需要先加载 workbench-components.js（ChoiceGroup）');
        }
        var texts = opts.texts || {};
        function textOf(key, fallback) { return texts[key] != null ? String(texts[key]) : fallback; }
        var keyOf = typeof opts.keyOf === 'function' ? opts.keyOf : function(candidate) {
            var source = candidate && candidate.source || {};
            return String(source.containerId || '') + ':' + String(source.slot) + ':'
                + String(source.expectedLease || '');
        };
        var nameOf = typeof opts.nameOf === 'function' ? opts.nameOf : function(item) {
            item = item || {};
            return item.displayName || item.displayname || item.name || textOf('unknownItem', '未知物品');
        };
        var iconOf = typeof opts.iconOf === 'function' ? opts.iconOf : function(item) {
            item = item || {};
            return item.icon || item.name || '';
        };
        var enhancementOf = typeof opts.enhancementOf === 'function' ? opts.enhancementOf : function(item) {
            item = item || {};
            return Number(item.enhancementLevel) || 0;
        };
        var bitsOf = typeof opts.bitsOf === 'function' ? opts.bitsOf : function() { return []; };
        var lockTextOf = typeof opts.lockTextOf === 'function' ? opts.lockTextOf : function() {
            return textOf('lockFallback', '该物品当前不可交付');
        };

        // blocked 投影与两面板现役 setActionBlocked/guardBlocked 逐点一致：
        // aria-disabled + 可读原因（title + 点击 toast），禁用 silent no-op
        function applyBlocked(btn, reason) {
            if (reason) {
                btn.setAttribute('aria-disabled', 'true');
                btn.setAttribute('data-blocked-reason', reason);
                btn.title = reason;
            } else {
                btn.removeAttribute('aria-disabled');
                btn.removeAttribute('data-blocked-reason');
            }
        }
        function guardBlocked(btn) {
            var reason = btn.getAttribute('data-blocked-reason');
            if (reason) {
                // 锁定/禁用拦截（契约 §2 illegal）：aria-disabled 已抑制声明式 cue，命令式补拦截音
                var A = typeof window !== 'undefined' ? window.BootstrapAudio : null;
                if (A && typeof A.cue === 'function') A.cue('illegal');
                toast(reason);
                return true;
            }
            return false;
        }
        function clearChildren(el) {
            if (!el) return;
            if (typeof Workbench !== 'undefined' && Workbench && Workbench.clearElement) {
                Workbench.clearElement(el);   // 重渲染是生命周期边界：先释放 tooltip/tile 绑定再摘节点
                return;
            }
            while (el.firstChild) el.removeChild(el.firstChild);
        }

        var scopeChoices = (opts.scopeChoices && opts.scopeChoices.length ? opts.scopeChoices : [
            { value:'compatible', label:'兼容', ariaLabel:'只显示可交付的候选', eligibleOnly:true },
            { value:'backpack', label:'背包', ariaLabel:'显示背包中的全部候选' }
        ]).map(function(choice) {
            return {
                value: String(choice.value),
                label: choice.label != null ? String(choice.label) : String(choice.value),
                ariaLabel: choice.ariaLabel,
                eligibleOnly: choice.eligibleOnly === true
            };
        });
        var eligibleOnlyByScope = {};
        for (var sc = 0; sc < scopeChoices.length; sc++) {
            eligibleOnlyByScope[scopeChoices[sc].value] = scopeChoices[sc].eligibleOnly;
        }
        var currentScope = opts.scope != null ? String(opts.scope) : '';
        if (!eligibleOnlyByScope.hasOwnProperty(currentScope)) currentScope = scopeChoices[0].value;
        var selectedKey = opts.selectedKey != null ? String(opts.selectedKey) : '';
        var candidates = Array.isArray(opts.candidates) ? opts.candidates : [];
        var visibleCandidates = [];
        var selectedCandidate = null;
        var destroyed = false;

        var root = document.createElement('div');
        root.className = 'team-managed-gun-browser';

        var context = document.createElement('div');
        context.className = 'team-managed-gun-context';
        var scopeLabelEl = document.createElement('span');
        scopeLabelEl.className = 'team-managed-gun-scope-label';
        scopeLabelEl.textContent = opts.scopeLabel != null ? String(opts.scopeLabel) : '浏览方式';
        context.appendChild(scopeLabelEl);
        var scopeMount = document.createElement('div');
        scopeMount.className = 'team-managed-gun-scope-mount';
        context.appendChild(scopeMount);
        var count = document.createElement('span');
        count.className = 'team-managed-gun-count';
        context.appendChild(count);
        root.appendChild(context);

        var selection = document.createElement('div');
        selection.className = 'team-managed-gun-selection';
        var selectedInfo = document.createElement('div');
        selectedInfo.className = 'team-managed-gun-candidate-info';
        var selectedName = document.createElement('div');
        selectedName.className = 'team-managed-gun-candidate-name';
        var selectedMeta = document.createElement('div');
        selectedMeta.className = 'team-managed-gun-meta';
        selectedInfo.appendChild(selectedName);
        selectedInfo.appendChild(selectedMeta);
        selection.appendChild(selectedInfo);
        var commitBtn = document.createElement('button');
        commitBtn.type = 'button';
        commitBtn.className = 'team-promo-btn team-managed-gun-action team-managed-gun-commit';
        commitBtn.textContent = String(opts.commitLabel || '交付所选');
        selection.appendChild(commitBtn);
        root.appendChild(selection);

        var list = document.createElement('div');
        list.className = 'team-managed-gun-candidates inventory-owned-grid';
        list.setAttribute('role', 'listbox');
        if (opts.listAriaLabel) list.setAttribute('aria-label', String(opts.listAriaLabel));
        if (opts.scrollRegion) list.setAttribute('data-scroll-region', String(opts.scrollRegion));
        root.appendChild(list);
        if (opts.density && typeof opts.density.register === 'function') opts.density.register(list);

        function findCandidate(key, source) {
            for (var i = 0; i < source.length; i++) {
                if (keyOf(source[i]) === key) return source[i];
            }
            return null;
        }

        function updateSelection() {
            selectedCandidate = findCandidate(selectedKey, visibleCandidates);
            var cards = list.querySelectorAll('.team-managed-gun-candidate');
            for (var i = 0; i < cards.length; i++) {
                var selected = cards[i].getAttribute('data-candidate-key') === selectedKey;
                cards[i].classList.toggle('team-managed-gun-selected', selected);
                cards[i].setAttribute('aria-pressed', selected ? 'true' : 'false');
                cards[i].setAttribute('aria-selected', selected ? 'true' : 'false');
            }

            commitBtn.removeAttribute('title');
            if (!selectedCandidate) {
                selectedName.textContent = textOf('noSelection', '未选择');
                selectedMeta.textContent = visibleCandidates.length === 0
                    ? textOf('emptyScope', '当前范围没有候选')
                    : textOf('pickHint', '从下方候选中选择');
                applyBlocked(commitBtn, textOf('selectFirst', '请先选择候选'));
                return;
            }

            selectedName.textContent = nameOf(selectedCandidate.item);
            var bits = bitsOf(selectedCandidate).slice();
            if (!selectedCandidate.eligible) bits.push(lockTextOf(selectedCandidate));
            selectedMeta.textContent = bits.join(' · ');
            var blocked = opts.combatLockedReason || '';
            if (!blocked && !selectedCandidate.eligible) blocked = lockTextOf(selectedCandidate);
            applyBlocked(commitBtn, blocked);
        }

        function renderCandidates() {
            clearChildren(list);
            visibleCandidates = [];
            for (var i = 0; i < candidates.length; i++) {
                if (!eligibleOnlyByScope[currentScope] || candidates[i].eligible) {
                    visibleCandidates.push(candidates[i]);
                }
            }
            count.textContent = visibleCandidates.length + ' 项';

            if (!findCandidate(selectedKey, visibleCandidates)) {
                selectedKey = '';
                for (var j = 0; j < visibleCandidates.length; j++) {
                    if (visibleCandidates[j].eligible) {
                        selectedKey = keyOf(visibleCandidates[j]);
                        break;
                    }
                }
                if (!selectedKey && visibleCandidates.length > 0) {
                    selectedKey = keyOf(visibleCandidates[0]);
                }
                notifySelection();
            }

            if (visibleCandidates.length === 0) {
                var empty = document.createElement('div');
                empty.className = 'team-managed-gun-empty';
                empty.textContent = candidates.length === 0
                    ? textOf('emptyNone', '背包中暂无候选。')
                    : textOf('emptyFiltered', '当前范围没有可交付候选；切换到另一视图可查看锁定原因。');
                list.appendChild(empty);
            } else {
                for (var k = 0; k < visibleCandidates.length; k++) {
                    list.appendChild(candidateNode(visibleCandidates[k]));
                }
            }
            updateSelection();
        }

        function candidateNode(candidate) {
            var row = document.createElement('button');
            row.type = 'button';
            row.className = 'team-managed-gun-candidate inventory-slot-card occupied';
            var key = keyOf(candidate);
            row.setAttribute('data-candidate-key', key);
            row.setAttribute('role', 'option');
            row.setAttribute('aria-pressed', 'false');
            row.setAttribute('aria-selected', 'false');
            if (!candidate.eligible) row.classList.add('team-managed-gun-locked');

            var item = candidate.item || {};
            var icon = document.createElement('span');
            icon.className = 'team-managed-gun-icon inventory-slot-icon-frame';
            var iconHtml = (typeof Icons !== 'undefined' && Icons && typeof Icons.html === 'function')
                ? Icons.html(iconOf(item), 'team-managed-gun-icon-image inventory-owned-icon') : '';
            if (iconHtml) icon.innerHTML = iconHtml;
            else icon.textContent = '◇';
            var enhancement = enhancementOf(item);
            if (enhancement > 0) {
                var badge = document.createElement('span');
                badge.className = 'merc-equip-badge';
                badge.textContent = enhancement;
                icon.appendChild(badge);
            }
            row.appendChild(icon);

            var info = document.createElement('span');
            info.className = 'team-managed-gun-candidate-info item-card-body';
            var name = document.createElement('span');
            name.className = 'team-managed-gun-candidate-name';
            name.textContent = nameOf(item);
            var desc = document.createElement('span');
            desc.className = 'team-managed-gun-meta';
            desc.textContent = bitsOf(candidate).join(' · ');
            info.appendChild(name);
            info.appendChild(desc);
            row.appendChild(info);

            if (!candidate.eligible) {
                var lock = document.createElement('span');
                lock.className = 'team-managed-gun-lock';
                lock.textContent = lockTextOf(candidate);
                row.appendChild(lock);
            }
            row.setAttribute('aria-label', nameOf(item) + '，'
                + bitsOf(candidate).join('，')
                + (candidate.eligible ? '，' + textOf('eligible', '可交付') : '，' + lockTextOf(candidate)));
            row.addEventListener('click', function() {
                selectedKey = keyOf(candidate);
                notifySelection();
                updateSelection();
            });
            if (typeof opts.bindTip === 'function') opts.bindTip(row, candidate);
            return row;
        }

        function notifySelection() {
            if (typeof opts.onSelectionChange === 'function') opts.onSelectionChange(selectedKey);
        }

        var scopeGroup = new WorkbenchComponents.ChoiceGroup({
            document: document,
            value: currentScope,
            ariaLabel: opts.scopeAriaLabel || '候选范围',
            className: 'team-managed-gun-scope',
            choices: scopeChoices,
            onChange: function(next) {
                currentScope = next;
                if (typeof opts.onScopeChange === 'function') opts.onScopeChange(next);
                renderCandidates();
                return true;
            }
        });
        scopeGroup.mount(scopeMount);
        commitBtn.addEventListener('click', function() {
            if (guardBlocked(this) || !selectedCandidate) return;
            if (typeof opts.onCommit === 'function') opts.onCommit(selectedCandidate, this);
        });
        renderCandidates();

        return {
            root: root,
            getScope: function() { return currentScope; },
            getSelectedKey: function() { return selectedKey; },
            destroy: function() {
                if (destroyed) return;
                destroyed = true;
                scopeGroup.destroy();
                if (opts.density && typeof opts.density.unregister === 'function') {
                    opts.density.unregister(list);
                }
                clearChildren(root);
                if (root.parentNode) root.parentNode.removeChild(root);
            }
        };
    }

    return {
        escapeHtml: escapeHtml,
        fmtMoney: fmtMoney,
        toast: toast,
        setPending: setPending,
        buildEmptyState: buildEmptyState,
        createDropdown: createDropdown,
        createPanelRequester: createPanelRequester,
        custodyBadgeSpec: custodyBadgeSpec,
        buildCustodyBadge: buildCustodyBadge,
        createCandidateBrowser: createCandidateBrowser
    };
});
