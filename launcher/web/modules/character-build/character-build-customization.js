/** Equipment customization tab controller (Type-61 chest emergency injection). */
(function(root, factory) {
    'use strict';
    var controls = typeof module !== 'undefined' && module.exports
        ? require('./character-build-drug-controls.js') : root && root.CharacterBuildDrugControls;
    var api = factory(controls);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildCustomization = api;
        root.CharacterBuildCustomization = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(DrugControls) {
    'use strict';
    var DEFAULT_DISABLED = {v:1, enabled:false, physicalSlot:-1, itemKey:'', status:'disabled'};

    function escapeHtml(text) {
        return String(text == null ? '' : text)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function el(doc, tag, className, text) {
        var node = doc.createElement(tag);
        if (className) node.className = className;
        if (text !== undefined) node.textContent = String(text);
        return node;
    }
    function fallbackIconHtml(name, className) {
        return '<span class="' + escapeHtml(className || 'kshop-icon')
            + ' cb-mech-icon-fallback" aria-hidden="true">◇</span>';
    }
    function chestTargetKey(target) {
        if (!target) return '';
        return target.kind === 'backpack'
            ? 'backpack:' + target.slot + ':' + target.expectedLease
            : 'loadout:上装装备';
    }
    function statusSummaryText(cfg, snapshot) {
        if (!cfg) return '未设';
        if (cfg.status === 'unsupported_config') return '高版本锁定';
        if (!cfg.enabled || cfg.status === 'disabled') return '未设';
        var slotInfo = DrugControls.slotPresentation(snapshot, cfg.physicalSlot);
        if (cfg.status === 'empty') return slotInfo.shortcutLabel + ' 待补';
        if (cfg.status === 'item_changed') return '需重绑';
        return slotInfo.shortcutLabel;
    }
    function createEmptyRule(doc, title, detail) {
        var box = el(doc, 'div', 'cb-mech-rule');
        box.appendChild(el(doc, 'strong', '', title));
        box.appendChild(el(doc, 'span', '', detail));
        return box;
    }

    function createForSession(session, options) {
        options = options || {};
        var mutations = options.mutations || null;
        var listener = null;
        var unsubscribe = [];
        var controllerId = 'cb-mech-' + Math.random().toString(36).slice(2, 8);
        var confirmedCache = null;

        if (session && typeof session.subscribe === 'function') {
            ['snapshot', 'mutation_success', 'mutation_failed', 'mutation_unknown',
                'mutation_reconciled', 'mutation_start', 'mutation_reconcile_failed'].forEach(function(evt) {
                var off = session.subscribe(evt, function() {
                    if (evt === 'mutation_success' || evt === 'mutation_reconciled') {
                        var snap = session.getSnapshot && session.getSnapshot();
                        var targetCfg = snap && snap.targetEmergencyInjection;
                        var debug = session.debugState && session.debugState();
                        if (targetCfg && confirmedCache && debug) {
                            confirmedCache.config = targetCfg;
                            confirmedCache.drugRevision = Number(debug.drugRevision);
                        }
                        if (typeof options.onCommitted === 'function') options.onCommitted(evt, snap);
                    } else if (evt === 'snapshot') {
                        confirmedCache = null;
                    }
                    if (listener) listener();
                });
                if (typeof off === 'function') unsubscribe.push(off);
            });
        }

        function currentChestTarget(source) {
            var rev = session && typeof session.getLoadoutRevision === 'function'
                ? session.getLoadoutRevision()
                : (session && session.debugState ? session.debugState().loadoutRevision : null);
            return DrugControls.chestTargetFromSource(source, rev);
        }

        function resolveConfig(context) {
            var snap = session && session.getSnapshot ? session.getSnapshot() : null;
            var chestTarget = currentChestTarget(context && context.source);
            var key = chestTargetKey(chestTarget);
            var debug = session && session.debugState ? session.debugState() : null;
            if (chestTarget && chestTarget.kind === 'loadout') {
                return (snap && snap.emergencyInjection)
                    || (context && context.equipmentSnapshot && context.equipmentSnapshot.emergencyInjection)
                    || (context && context.item && context.item.emergencyInjection)
                    || DEFAULT_DISABLED;
            }
            if (confirmedCache && confirmedCache.key === key && confirmedCache.config
                    && debug && Number(debug.drugRevision) === confirmedCache.drugRevision) {
                return confirmedCache.config;
            }
            return (context && context.equipmentSnapshot && context.equipmentSnapshot.emergencyInjection)
                || (context && context.item && context.item.emergencyInjection)
                || DEFAULT_DISABLED;
        }

        function configure(chestTarget, enabled, drugSlot) {
            if (!chestTarget || !session || !DrugControls.validChestTarget(chestTarget)) return false;
            var target = enabled ? {kind:'drug', drugSlot:drugSlot} : null;
            var debug = session.debugState ? session.debugState() : null;
            confirmedCache = {
                key:chestTargetKey(chestTarget),
                drugRevision:debug ? Number(debug.drugRevision) : -1,
                config:null
            };
            if (mutations && typeof mutations.configureEmergencyInjection === 'function') {
                return mutations.configureEmergencyInjection(chestTarget, enabled, target);
            }
            if (typeof options.configureEmergencyInjection === 'function') {
                return options.configureEmergencyInjection(chestTarget, enabled, target);
            }
            var intent = DrugControls.intent(session.getSnapshot(), chestTarget, enabled, target);
            return !!(intent && session.configureEmergencyInjection(
                intent.chestTarget, intent.enabled, intent.drugSlot, intent.expectedItemName));
        }

        function reconcile() {
            if (mutations && typeof mutations.reconcile === 'function') return mutations.reconcile();
            return !!(session && session.reconcileMutation && session.reconcileMutation());
        }

        function isLocked() {
            if (!session) return false;
            var state = session.getState();
            return state === 'write_pending'
                || state === 'needs_reconcile'
                || state === 'mutation_reconcile'
                || !!(mutations && mutations.isPending && mutations.isPending());
        }

        var lastContext = null;

        function toggleSlot(slotIndex) {
            var context = lastContext;
            if (!context || !session) return false;
            var state = session.getState();
            if (state !== 'idle' || (mutations && mutations.isPending && mutations.isPending())) {
                return false;
            }
            var slot = Number(slotIndex);
            if (!isFinite(slot) || Math.floor(slot) !== slot || slot < 0 || slot > 7) return false;
            var snap = session.getSnapshot && session.getSnapshot();
            var drugs = snap && Array.isArray(snap.drugs) ? snap.drugs : [];
            var row = drugs[slot];
            var cfg = resolveConfig(context);
            if (!cfg || cfg.status === 'unsupported_config') return false;
            var chestTarget = currentChestTarget(context.source);
            if (!chestTarget) return false;

            var isCurrentlyBound = cfg.enabled === true && Number(cfg.physicalSlot) === slot;
            if (isCurrentlyBound) {
                return configure(chestTarget, false, -1);
            }
            if (!row || !row.occupied || !row.item) {
                if (options.toast) {
                    var info = DrugControls.slotPresentation(snap, slot);
                    options.toast('药剂槽 ' + info.shortcutLabel + ' 当前为空，请先在左侧放入药剂或点右侧其他有药槽位。');
                }
                return false;
            }
            return configure(chestTarget, true, slot);
        }

        function disableCurrent() {
            var context = lastContext;
            if (!context || !session) return false;
            var state = session.getState();
            if (state !== 'idle' || (mutations && mutations.isPending && mutations.isPending())) return false;
            var cfg = resolveConfig(context);
            if (!cfg || !cfg.enabled || cfg.status === 'unsupported_config') return false;
            var chestTarget = currentChestTarget(context.source);
            return chestTarget ? configure(chestTarget, false, -1) : false;
        }

        function buildDrugTile(doc, slotInfo, cfg, locked, iconHtmlFn) {
            var slot = slotInfo.slot;
            var row = slotInfo.row;
            var occupied = !!(row && row.occupied && row.item);
            var isBound = !!(cfg && cfg.enabled && Number(cfg.physicalSlot) === slot);
            var boundState = isBound ? String(cfg.status || 'authorized') : 'none';
            var tile = el(doc, 'button', 'cb-mech-tile');
            tile.type = 'button';
            tile.setAttribute('data-drug-slot', String(slot));
            tile.setAttribute('data-bound', isBound ? 'true' : 'false');
            tile.setAttribute('data-bound-state', boundState);
            tile.setAttribute('data-occupied', occupied ? 'true' : 'false');
            tile.setAttribute('data-active-bank', row && row.active ? 'true' : 'false');
            tile.setAttribute('data-tuning-focus-key', 'mech:drug:' + slot);
            tile.disabled = locked || (!occupied && !isBound) || (cfg && cfg.status === 'unsupported_config');

            var head = el(doc, 'div', 'cb-mech-tile-head');
            head.appendChild(el(doc, 'kbd', 'cb-mech-keycap', slotInfo.keyLabel));
            if (isBound) {
                var badgeText = cfg.status === 'empty' ? '已绑·空'
                    : cfg.status === 'item_changed' ? '已变更' : '应急';
                head.appendChild(el(doc, 'span', 'cb-mech-bound-tag', badgeText));
            } else if (occupied) {
                head.appendChild(el(doc, 'span', 'cb-mech-qty', '×' + Number(row.quantity || row.item.quantity || 1)));
            }
            tile.appendChild(head);

            var media = el(doc, 'div', 'cb-mech-tile-icon');
            if (occupied) {
                media.innerHTML = iconHtmlFn(row.item.icon || row.item.name, 'kshop-icon');
            } else {
                media.appendChild(el(doc, 'span', 'cb-mech-empty-slot-mark', '空槽'));
            }
            tile.appendChild(media);

            var nameText = occupied
                ? String(row.item.displayName || row.item.name)
                : (isBound && cfg.itemKey ? String(cfg.itemKey) + '（已空）' : '未放药剂');
            tile.appendChild(el(doc, 'span', 'cb-mech-tile-name', nameText));

            var aria = slotInfo.shortcutLabel + ' ' + (occupied ? nameText : '空槽')
                + (isBound ? '，当前已绑定应急注射，再次点击停用' : occupied ? '，点击设为应急注射药剂' : '，需先在左侧放入药剂');
            tile.setAttribute('aria-label', aria);
            tile.setAttribute('aria-pressed', isBound ? 'true' : 'false');
            tile.addEventListener('click', function() { toggleSlot(slot); });
            return tile;
        }

        function renderSummaryPill(context, onOpen) {
            if (!context || !context.item || !DrugControls.supportsChestItem(context.item)) return null;
            var doc = context.document;
            var snap = session && session.getSnapshot ? session.getSnapshot() : null;
            var cfg = resolveConfig(context);
            var status = cfg && cfg.status ? String(cfg.status) : 'disabled';
            var label = '应急药 · ' + statusSummaryText(cfg, snap);
            var pill = el(doc, 'button', 'cb-mech-pill' + (context.active ? ' is-active' : ''), label);
            pill.type = 'button';
            pill.setAttribute('data-tuning-focus-key', 'summary-mechanism');
            pill.setAttribute('data-mech-status', status);
            pill.disabled = !!context.disabled;
            var fullDesc = status === 'authorized'
                ? '应急注射：已绑定 ' + statusSummaryText(cfg, snap) + ' ' + cfg.itemKey + '，点击配置机制'
                : status === 'empty'
                    ? '应急注射：' + statusSummaryText(cfg, snap) + '（' + cfg.itemKey + ' 待补），点击调整'
                    : status === 'item_changed'
                        ? '应急注射：原槽药剂已更换，点击重新绑定'
                        : '应急注射：尚未设定药剂槽，点击选择';
            pill.setAttribute('aria-label', fullDesc);
            pill.addEventListener('click', function() {
                if (typeof onOpen === 'function') onOpen();
            });
            return pill;
        }

        function render(context) {
            lastContext = context || null;
            var doc = context.document;
            var snap = session && session.getSnapshot ? session.getSnapshot() : null;
            var drugs = snap && Array.isArray(snap.drugs) ? snap.drugs : [];
            var state = session ? session.getState() : 'idle';
            var cfg = resolveConfig(context);
            var chestTarget = currentChestTarget(context && context.source);
            var isWorn = !chestTarget || chestTarget.kind === 'loadout';
            var needsReconcile = state === 'needs_reconcile';
            var unsupported = cfg && cfg.status === 'unsupported_config';
            var busy = state !== 'idle' || !!(mutations && mutations.isPending && mutations.isPending());
            var locked = busy || needsReconcile || unsupported || !chestTarget;
            var iconHtmlFn = typeof context.iconHtml === 'function' ? context.iconHtml : fallbackIconHtml;

            var body = el(doc, 'section', 'cb-mech-panel');
            body.setAttribute('data-customization-panel', 'emergency-injection');
            body.setAttribute('data-target-kind', isWorn ? 'loadout' : 'backpack');
            body.setAttribute('data-config-status', String(cfg && cfg.status || 'disabled'));
            body.setAttribute('data-reconcile', needsReconcile ? 'required' : 'clear');
            body.setAttribute('aria-label', '61胸甲应急药剂注射配置');

            var reactor = el(doc, 'section', 'cb-mech-reactor');
            var reactorHead = el(doc, 'div', 'cb-mech-reactor-head');
            var scopeBadgeText = isWorn
                ? '当前穿戴 · 实时生效'
                : '背包第 ' + (chestTarget.slot + 1) + ' 格 · 穿戴后生效';
            reactorHead.appendChild(el(doc, 'span', 'cb-mech-target-badge' + (isWorn ? ' is-worn' : ''), scopeBadgeText));
            reactorHead.appendChild(el(doc, 'span', 'cb-mech-chest-name',
                String(context.item && (context.item.displayName || context.item.name) || '61式胸甲')));
            reactor.appendChild(reactorHead);

            var reactorMain = el(doc, 'div', 'cb-mech-reactor-main');
            var boundInfo = cfg && cfg.enabled ? DrugControls.slotPresentation(snap, cfg.physicalSlot) : null;
            var boundRow = cfg && cfg.enabled ? drugs[cfg.physicalSlot] : null;
            var summaryMedia = el(doc, 'div', 'cb-mech-reactor-icon');
            if (cfg && cfg.enabled && cfg.status === 'authorized') {
                summaryMedia.innerHTML = iconHtmlFn(boundRow && boundRow.item && (boundRow.item.icon || boundRow.item.name) || cfg.itemKey, 'kshop-icon');
            } else {
                summaryMedia.appendChild(el(doc, 'span', 'cb-mech-reactor-sigil', cfg && cfg.enabled ? '!' : '+'));
            }
            reactorMain.appendChild(summaryMedia);

            var summaryCopy = el(doc, 'div', 'cb-mech-reactor-copy');
            if (unsupported) {
                summaryCopy.appendChild(el(doc, 'strong', '', '检测到高版本或未知应急配置'));
                summaryCopy.appendChild(el(doc, 'span', '', '该胸甲持有当前面板不支持的配置版本，已锁定保护，不会自动覆盖。'));
            } else if (cfg && cfg.enabled && cfg.status === 'authorized' && boundInfo) {
                var qty = boundRow ? Number(boundRow.quantity || boundRow.item && boundRow.item.quantity || 1) : 0;
                summaryCopy.appendChild(el(doc, 'strong', '', '已绑定 ' + boundInfo.shortcutLabel + ' · ' + cfg.itemKey));
                summaryCopy.appendChild(el(doc, 'span', '', '剩余 ×' + qty + ' · 生命值跌至 ≤ 50% 时自动注入此槽位药剂'));
            } else if (cfg && cfg.enabled && cfg.status === 'empty' && boundInfo) {
                summaryCopy.appendChild(el(doc, 'strong', '', boundInfo.shortcutLabel + ' 当前空槽（原设：' + cfg.itemKey + '）'));
                summaryCopy.appendChild(el(doc, 'span', '', '重新补入「' + cfg.itemKey + '」将自动恢复激活，也可直接改选下列药剂槽'));
            } else if (cfg && cfg.enabled && cfg.status === 'item_changed' && boundInfo) {
                summaryCopy.appendChild(el(doc, 'strong', '', boundInfo.shortcutLabel + ' 药剂已更换（原设授权已失效）'));
                summaryCopy.appendChild(el(doc, 'span', '', '请点击下方任意有药剂槽位重新授权，或停用该胸甲的应急槽位'));
            } else {
                summaryCopy.appendChild(el(doc, 'strong', '', '未设定应急注射槽'));
                summaryCopy.appendChild(el(doc, 'span', '', '单击下方任意药剂图标或直接点按左侧药剂栏，一步完成绑定'));
            }
            reactorMain.appendChild(summaryCopy);

            var actionsBox = el(doc, 'div', 'cb-mech-reactor-actions');
            if (needsReconcile) {
                var reconcileBtn = el(doc, 'button', 'cb-mech-action is-warn', '重新确认结果');
                reconcileBtn.type = 'button';
                reconcileBtn.setAttribute('data-customization-reconcile', '');
                reconcileBtn.setAttribute('data-tuning-focus-key', 'mech:reconcile');
                reconcileBtn.addEventListener('click', function() { reconcile(); });
                actionsBox.appendChild(reconcileBtn);
            } else if (cfg && cfg.enabled && !unsupported) {
                var disableBtn = el(doc, 'button', 'cb-mech-action', '停用');
                disableBtn.type = 'button';
                disableBtn.setAttribute('data-customization-disable', '');
                disableBtn.setAttribute('data-tuning-focus-key', 'mech:disable');
                disableBtn.disabled = busy;
                disableBtn.addEventListener('click', function() { disableCurrent(); });
                actionsBox.appendChild(disableBtn);
            }
            if (actionsBox.childNodes.length) reactorMain.appendChild(actionsBox);
            reactor.appendChild(reactorMain);
            body.appendChild(reactor);

            var guide = el(doc, 'p', 'cb-mech-guide');
            guide.id = controllerId + '-status';
            guide.setAttribute('role', 'status');
            guide.setAttribute('aria-live', 'polite');
            if (needsReconcile) {
                guide.textContent = '上次修改结果尚未确认，已冻结写入；请点“重新确认结果”对账，切勿盲目重放。';
            } else if (state === 'write_pending') {
                guide.textContent = '正在提交胸甲应急授权…';
            } else if (unsupported) {
                guide.textContent = '当前配置版本受保护，禁止修改。';
            } else {
                guide.textContent = '左栏药剂槽联动开启：点右侧图标或左侧药剂格均可直接绑定；再点已绑定槽可取消。';
            }
            body.appendChild(guide);

            var occupiedCount = 0;
            for (var c = 0; c < 8; c++) {
                if (drugs[c] && drugs[c].occupied && drugs[c].item) occupiedCount++;
            }
            if (occupiedCount === 0 && !(cfg && cfg.enabled)) {
                var emptyBox = el(doc, 'div', 'cb-mech-empty-cta');
                emptyBox.appendChild(el(doc, 'p', '', '当前 I 组与 II 组共 8 个药剂栏均未放入药剂。'));
                if (typeof context.onNavigateToDrugSlots === 'function') {
                    var gotoBtn = el(doc, 'button', 'cb-mech-goto-drugs', '← 去左侧药剂栏装药');
                    gotoBtn.type = 'button';
                    gotoBtn.setAttribute('data-customization-goto-drugs', '');
                    gotoBtn.setAttribute('data-tuning-focus-key', 'mech:goto-drugs');
                    gotoBtn.disabled = busy || needsReconcile;
                    gotoBtn.addEventListener('click', function() { context.onNavigateToDrugSlots(); });
                    emptyBox.appendChild(gotoBtn);
                }
                body.appendChild(emptyBox);
            } else {
                var activeBank = snap && snap.drugLayout ? Number(snap.drugLayout.activeBank) : 0;
                var banksWrap = el(doc, 'div', 'cb-mech-banks');
                [0, 1].forEach(function(bankIndex) {
                    var bankSection = el(doc, 'section', 'cb-mech-bank');
                    bankSection.setAttribute('data-bank-index', String(bankIndex));
                    var isCurrent = bankIndex === activeBank;
                    var bankTitle = el(doc, 'header', 'cb-mech-bank-head');
                    bankTitle.appendChild(el(doc, 'span', '', bankIndex === 0 ? '第 I 组药剂' : '第 II 组药剂'));
                    bankTitle.appendChild(el(doc, 'small', isCurrent ? 'is-current' : '',
                        isCurrent ? '当前快捷栏' : '备用栏 · 应急可直接调用'));
                    bankSection.appendChild(bankTitle);

                    var grid = el(doc, 'div', 'cb-mech-grid');
                    for (var lane = 0; lane < 4; lane++) {
                        var slot = bankIndex * 4 + lane;
                        var slotInfo = DrugControls.slotPresentation(snap, slot);
                        grid.appendChild(buildDrugTile(doc, slotInfo, cfg, locked, iconHtmlFn));
                    }
                    bankSection.appendChild(grid);
                    banksWrap.appendChild(bankSection);
                });
                body.appendChild(banksWrap);
            }

            var footer = el(doc, 'footer', 'cb-mech-footer');
            var rules = el(doc, 'div', 'cb-mech-rules');
            rules.appendChild(createEmptyRule(doc, '触发与重置', 'HP ≤ 50% 触发一次；需回升至 ≥ 70% 才重新待命'));
            rules.appendChild(createEmptyRule(doc, '独立记忆', '每件 61 胸甲各自记忆绑定槽；穿戴即生效'));
            rules.appendChild(createEmptyRule(doc, '换药失效', '同槽改放其他药剂立即撤销授权；同名补药保持绑定'));
            footer.appendChild(rules);

            return {body:body, footer:footer};
        }

        return {
            isAvailable:function(source, item) {
                return DrugControls.supportsChestItem(item);
            },
            bind:function(next) { listener = next; },
            isLocked:isLocked,
            statusId:function() { return controllerId + '-status'; },
            toggleSlot:toggleSlot,
            disableCurrent:disableCurrent,
            renderSummaryPill:renderSummaryPill,
            render:render,
            destroy:function() {
                lastContext = null;
                confirmedCache = null;
                listener = null;
                while (unsubscribe.length) unsubscribe.pop()();
            }
        };
    }

    function createTuningPorts(tuning, baseOptions) {
        var customOptions = {};
        if (baseOptions && typeof baseOptions === 'object') {
            for (var key in baseOptions) {
                if (Object.prototype.hasOwnProperty.call(baseOptions, key)) customOptions[key] = baseOptions[key];
            }
        }
        customOptions.onCommitted = function() {
            if (tuning._active && tuning._candidateFlow && tuning._candidateFlow.isActive()
                    && tuning._tuningView
                    && typeof tuning._tuningView.refreshCustomizationSnapshot === 'function') {
                setTimeout(function() {
                    if (tuning._active && tuning._tuningView
                            && typeof tuning._tuningView.refreshCustomizationSnapshot === 'function') {
                        tuning._tuningView.refreshCustomizationSnapshot();
                    }
                }, 0);
            }
        };
        return {
            customization:createForSession(tuning._session, customOptions),
            onModeChange:function(active) {
                if (!tuning._buildView || !tuning._buildView.root) return;
                if (active && tuning._active) tuning._buildView.root.setAttribute('data-build-tuning-mode', 'customization');
                else tuning._buildView.root.removeAttribute('data-build-tuning-mode');
                if (typeof tuning._syncLoadoutSlots === 'function') tuning._syncLoadoutSlots();
            },
            onNavigateToDrugSlots:function() {
                tuning.exit(function(exited) {
                    if (exited && tuning._buildView && typeof tuning._buildView.focusDrugSlot === 'function') {
                        tuning._buildView.focusDrugSlot('drug1');
                    }
                });
            }
        };
    }
    function handleTuningDrugSlot(tuning, slotIndex) {
        return !!(tuning._active && tuning._tuningView
            && typeof tuning._tuningView.handleCustomizationDrugSlot === 'function'
            && tuning._tuningView.handleCustomizationDrugSlot(slotIndex));
    }

    return {
        createForSession:createForSession,
        createTuningPorts:createTuningPorts,
        handleTuningDrugSlot:handleTuningDrugSlot,
        refreshTuning:function() {
            if (this._tuningView) this._tuningView.refreshCustomization();
            if (this._active && typeof this._syncLoadoutSlots === 'function') this._syncLoadoutSlots();
        }
    };
});
