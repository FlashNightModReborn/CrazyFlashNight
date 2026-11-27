/**
 * Standalone Equipment Tuning loadout & Type-61 customization coordinator.
 *
 * Allows standalone view:"tuning" to switch its left-pane source between
 * 背包 and 已穿戴 (11 equipment slots) and unlocks 61-chestplate emergency
 * injection customization for both worn and backpack chestplates using the
 * single shared workbench-level CharacterBuildSession authority.
 */
(function(root, factory) {
    'use strict';
    var model = typeof module !== 'undefined' && module.exports
        ? require('./equipment-tuning-model.js') : root && root.EquipmentTuningModel;
    var actionView = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker/loadout-picker-action-view.js') : root && root.LoadoutPickerActionView;
    var sourceMarker = typeof module !== 'undefined' && module.exports
        ? require('./equipment-tuning-source-marker.js') : root && root.EquipmentTuningSourceMarker;
    var tuningAdapter = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-tuning-adapter.js') : root && root.CharacterBuildTuningAdapter;
    var customization = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-customization.js') : root && root.CharacterBuildCustomization;
    var drugControls = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-drug-controls.js') : root && root.CharacterBuildDrugControls;
    var mutation = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-mutation.js') : root && root.CharacterBuildMutation;
    var api = factory(model, actionView, sourceMarker, tuningAdapter, customization, drugControls, mutation, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchLoadoutTuning = api;
})(typeof window !== 'undefined' ? window : globalThis,
function(TuningModel, ActionView, SourceMarker, TuningAdapter, Customization, DrugControls, Mutation, global) {
    'use strict';

    var ARMOR_SLOTS = [
        {id:'头部装备', label:'头部'}, {id:'上装装备', label:'上装'},
        {id:'下装装备', label:'下装'}, {id:'手部装备', label:'手部'},
        {id:'脚部装备', label:'脚部'}, {id:'颈部装备', label:'颈部'}
    ];
    var WEAPON_SLOTS = [
        {id:'长枪', label:'长枪'}, {id:'手枪', label:'手枪'},
        {id:'手枪2', label:'手枪 2'}, {id:'刀', label:'刀'}, {id:'手雷', label:'手雷'}
    ];

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function basicTooltipHtml(item, slotLabel) {
        item = item || {};
        var enhancement = Number(item.enhancementLevel);
        var header = '<div class="kshop-tt-header"><b>' + escapeHtml(item.displayName || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div>'
            + '<span class="kshop-tt-dim">槽位</span> ' + escapeHtml(slotLabel || '已装备') + '<br>';
        if (isFinite(enhancement) && enhancement > 0) {
            header += '<span class="kshop-tt-dim">强化</span> +' + enhancement + '<br>';
        }
        return '<div class="character-build-loadout-tt-context">' + header
            + '<div class="kshop-tt-loading">正在读取完整说明…</div></div>';
    }
    function richTooltipHtml(item, slotLabel, tooltip, response) {
        var data = response && response.payload;
        if (!data || !tooltip || typeof tooltip.buildItemRichHtml !== 'function') {
            return basicTooltipHtml(item, slotLabel);
        }
        var iconKey = data.iconName || item && item.icon || '';
        return tooltip.buildItemRichHtml({
            iconHtml:tooltip.dynamicIconHtml ? tooltip.dynamicIconHtml(iconKey) : '',
            iconUrl:tooltip.staticIconUrl ? tooltip.staticIconUrl(iconKey) : '',
            introHTML:data.introHTML || '',
            descHTML:data.descHTML || '',
            document:data.document,
            metaHTML:'<div class="character-build-loadout-tt-slot"><span class="kshop-tt-dim">当前槽位</span> '
                + escapeHtml(slotLabel || '已装备') + '</div>',
            rootClass:'kshop-tt-rich-context character-build-loadout-tt-context',
            layoutType:tooltip.inferLayoutType
                ? tooltip.inferLayoutType(data.itemType || item && (item.majorType || item.use)) : undefined
        });
    }

    function create(options) {
        options = options || {};
        var _doc = options.document || global.document;
        var _acquireSession = typeof options.acquireLoadoutSession === 'function'
            ? options.acquireLoadoutSession : null;
        var _beginWrite = typeof options.beginWrite === 'function' ? options.beginWrite : null;
        var _completeWrite = typeof options.completeWrite === 'function' ? options.completeWrite : null;
        var _iconHtml = typeof options.iconHtml === 'function' ? options.iconHtml : function() { return ''; };
        var _toast = typeof options.toast === 'function' ? options.toast : function() {};
        var _tooltip = options.tooltip || function() { return global.PanelTooltip; };

        var _backpackView = null, _tuningView = null;
        var _viewMode = 'storage', _leftSource = 'backpack';
        var _switchEl = null, _bagTab = null, _equippedTab = null, _loadoutPane = null;
        var _session = null, _mutations = null, _ownsMutations = false;
        var _sessionState = 'idle'; // idle | opening | ready | unavailable
        var _activeSlotKey = '', _entrySource = null;
        var _customController = null, _customListener = null;
        var _sessionUnsub = [];
        var _tooltipScope = null, _tooltipCache = {}, _tooltipEpoch = 0;
        var _destroyed = false;

        function clearTooltips() {
            _tooltipEpoch++;
            _tooltipCache = {};
            if (_tooltipScope && _tooltipScope.dispose) _tooltipScope.dispose();
            _tooltipScope = null;
            var tt = _tooltip();
            if (!_destroyed && tt && typeof tt.createScope === 'function') {
                _tooltipScope = tt.createScope('standalone-loadout-tuning-' + _tooltipEpoch, {profile:'dense-inspect'});
            }
        }
        function bindLoadoutTooltip(node, key, slotLabel, item, slotKey, isSuppressed) {
            if (!node || !item || !slotKey || !_session) return null;
            var tt = _tooltip();
            var binder = _tooltipScope || tt;
            if (!binder || typeof binder.bindAsync !== 'function') return null;
            node.setAttribute('data-loadout-tooltip', 'authoritative');
            return binder.bindAsync(node, {
                key:'standalone-loadout:' + _tooltipEpoch + ':' + key,
                item:item,
                cache:_tooltipCache,
                placement:'right',
                isSuppressed:function() {
                    return !_session || _session.getState() !== 'idle'
                        || (typeof isSuppressed === 'function' && isSuppressed());
                },
                renderBasic:function(value) { return basicTooltipHtml(value, slotLabel); },
                renderRich:function(value, response) { return richTooltipHtml(value, slotLabel, tt, response); },
                renderFailure:function(value) {
                    return basicTooltipHtml(value, slotLabel).replace('正在读取完整说明…', '说明读取失败；重新悬停可重试。');
                },
                fetch:function(_, callback) {
                    if (!_session) { callback({success:false, error:'unavailable'}); return; }
                    var callId = _session.requestLoadoutTooltip({kind:'equipment', slotKey:slotKey}, function(response, accepted) {
                        callback(accepted ? response : {success:false, error:response && response.error || 'failed'});
                    });
                    if (!callId) callback({success:false, error:'busy'});
                }
            });
        }

        function teardownCustomization() {
            if (_customController && _customController.destroy) _customController.destroy();
            _customController = null;
            if (_ownsMutations && _mutations && _mutations.destroy) _mutations.destroy();
            _mutations = null;
            _ownsMutations = false;
            while (_sessionUnsub.length) { try { _sessionUnsub.pop()(); } catch (_) {} }
        }

        function bindSessionHandle(handle) {
            if (_destroyed) return;
            if (!handle || !handle.session) { _sessionState = 'unavailable'; renderLoadoutPane(); return; }
            if (_session === handle.session) { _sessionState = 'ready'; renderLoadoutPane(); return; }
            teardownCustomization();
            _session = handle.session; _sessionState = 'ready'; clearTooltips();
            if (handle.mutations) { _mutations = handle.mutations; _ownsMutations = false; }
            else if (Mutation && typeof Mutation.MutationCoordinator === 'function') {
                _mutations = new Mutation.MutationCoordinator({
                    session:_session,
                    ports:{
                        beginExternalWrite:function(owner) { return _beginWrite ? _beginWrite(owner) : {local:true}; },
                        completeExternalWrite:function(op, snapshots, cb) { return _completeWrite ? _completeWrite(op, snapshots || null, cb, false) : (cb && cb({success:true}), true); },
                        toast:_toast
                    },
                    onApplied:function() { clearTooltips(); renderLoadoutPane(); }
                });
                _ownsMutations = true;
            }
            if (Customization && typeof Customization.createForSession === 'function') {
                _customController = Customization.createForSession(_session, {
                    mutations:_mutations,
                    toast:_toast,
                    onCommitted:function() {
                        renderLoadoutPane();
                        if (_tuningView && typeof _tuningView.refreshCustomizationSnapshot === 'function') {
                            setTimeout(function() {
                                if (!_destroyed && _tuningView && typeof _tuningView.refreshCustomizationSnapshot === 'function') {
                                    _tuningView.refreshCustomizationSnapshot();
                                }
                            }, 0);
                        }
                    }
                });
                if (_customListener) _customController.bind(_customListener);
            }
            if (typeof _session.subscribe === 'function') {
                ['opened', 'snapshot', 'mutation_success', 'mutation_reconciled'].forEach(function(evt) {
                    var off = _session.subscribe(evt, function() {
                        clearTooltips();
                        renderLoadoutPane();
                    });
                    if (typeof off === 'function') _sessionUnsub.push(off);
                });
            }
            renderLoadoutPane();
            if (_customListener) _customListener();
        }

        function ensureSession() {
            if (_destroyed || !_acquireSession) return false;
            if (_session && (_session.getState() === 'idle' || _session.getState() === 'flush_failed')) {
                _sessionState = 'ready';
                return true;
            }
            if (_sessionState === 'opening') return true;
            _sessionState = 'opening';
            renderLoadoutPane();
            var started = _acquireSession(function(handle) {
                bindSessionHandle(handle);
            });
            if (!started && _sessionState === 'opening') {
                _sessionState = 'unavailable';
                renderLoadoutPane();
            }
            return !!started;
        }

        function updateLeftVisibility() {
            var tuning = _viewMode === 'tuning';
            if (_switchEl) _switchEl.hidden = !tuning;
            var equipped = tuning && _leftSource === 'equipped';
            if (_bagTab) {
                _bagTab.setAttribute('aria-selected', equipped ? 'false' : 'true');
                _bagTab.tabIndex = equipped ? -1 : 0;
                _bagTab.classList.toggle('is-active', !equipped);
            }
            if (_equippedTab) {
                _equippedTab.setAttribute('aria-selected', equipped ? 'true' : 'false');
                _equippedTab.tabIndex = equipped ? 0 : -1;
                _equippedTab.classList.toggle('is-active', equipped);
            }
            if (_backpackView) {
                if (_backpackView.renderer && _backpackView.renderer.root) {
                    _backpackView.renderer.root.hidden = equipped;
                }
                if (_backpackView.chrome && _backpackView.chrome.toolbar) {
                    _backpackView.chrome.toolbar.hidden = equipped;
                }
            }
            if (_loadoutPane) _loadoutPane.hidden = !equipped;
        }

        function switchLeftSource(next, focusTab) {
            if (next !== 'backpack' && next !== 'equipped') return false;
            if (_viewMode !== 'tuning') return false;
            if (_tuningView && typeof _tuningView.canClose === 'function' && !_tuningView.canClose()) {
                _toast('调制操作尚未完成，请稍候切换来源。', 'warning');
                return false;
            }
            var changed = _leftSource !== next;
            _leftSource = next;
            if (changed && _tuningView && typeof _tuningView.clearSelection === 'function') {
                var st = _tuningView.debugState && _tuningView.debugState();
                var srcKind = st && st.source && st.source.sourceKind;
                if ((next === 'backpack' && srcKind === 'loadout') || (next === 'equipped' && srcKind === 'inventory')) {
                    _tuningView.clearSelection();
                }
            }
            updateLeftVisibility();
            if (focusTab) {
                var activeTab = next === 'equipped' ? _equippedTab : _bagTab;
                if (activeTab && typeof activeTab.focus === 'function') activeTab.focus();
            }
            if (next === 'equipped') {
                if (_sessionState !== 'ready') ensureSession();
                else renderLoadoutPane();
            } else { syncMarkers(); }
            return true;
        }

        function selectEquippedSlot(slotKey) {
            if (!_session || !_tuningView || _viewMode !== 'tuning') return false;
            var snap = _session.getSnapshot && _session.getSnapshot();
            var item = TuningAdapter ? TuningAdapter.findEquipment(snap, slotKey) : null;
            var source = TuningAdapter ? TuningAdapter.loadoutSourceFor(_session, slotKey) : null;
            if (!item || !source) {
                _toast('该已穿戴槽位无可调制装备。', 'warning');
                return false;
            }
            var prevSlot = _activeSlotKey, prevSource = _entrySource;
            _activeSlotKey = slotKey;
            _entrySource = source;
            if (!_tuningView.handleLoadoutSelection(source, item)) {
                _activeSlotKey = prevSlot;
                _entrySource = prevSource;
                return false;
            }
            syncMarkers();
            return true;
        }

        function syncMarkers(tuningState) {
            if (!_loadoutPane || !SourceMarker || typeof SourceMarker.projectLoadout !== 'function') return;
            var state = tuningState || (_tuningView && _tuningView.debugState ? _tuningView.debugState() : null);
            var isLoadout = _viewMode === 'tuning' && state && state.source && state.source.sourceKind === 'loadout';
            var slotKey = isLoadout ? String(state.source.slotKey || '') : '';
            if (isLoadout) {
                _activeSlotKey = slotKey;
                _entrySource = state.source;
            } else {
                _activeSlotKey = '';
                _entrySource = null;
            }
            var locked = !!(_tuningView && typeof _tuningView.canClose === 'function' && !_tuningView.canClose());
            SourceMarker.projectLoadout(_loadoutPane, slotKey, locked);
        }

        function buildSlotCard(def, row) {
            var item = row && row.occupied === true ? row.item : null;
            var cap = ActionView && typeof ActionView.tuningCapability === 'function'
                ? ActionView.tuningCapability(item)
                : {available:!!(item && item.itemKind === 'equipment'), reason:item ? '' : '空槽'};
            var btn = _doc.createElement('button');
            btn.type = 'button';
            btn.className = 'character-build-slot inventory-tuning-loadout-card'
                + (cap.available ? ' is-tunable' : ' is-disabled');
            btn.setAttribute('data-slot-kind', 'equipment');
            btn.setAttribute('data-slot-protocol-key', def.id);
            btn.setAttribute('data-empty', item ? 'false' : 'true');
            btn.setAttribute('data-blocked', cap.available ? 'false' : 'true');
            btn.disabled = !cap.available;
            var labelText = item ? String(item.displayName || item.name) : '空槽';
            btn.setAttribute('aria-label', def.label + '：' + labelText
                + (cap.available ? '，点击调制' : (cap.reason ? '（' + cap.reason + '）' : '')));

            var iconBox = _doc.createElement('span');
            iconBox.className = 'inventory-tuning-loadout-icon';
            iconBox.innerHTML = item ? _iconHtml(item.icon || '', 'kshop-row-icon')
                : '<span class="inventory-tuning-loadout-empty-glyph">—</span>';
            btn.appendChild(iconBox);

            var copy = _doc.createElement('span');
            copy.className = 'inventory-tuning-loadout-copy';
            var top = _doc.createElement('span');
            top.className = 'inventory-tuning-loadout-top';
            var slotTag = _doc.createElement('em');
            slotTag.className = 'inventory-tuning-loadout-slot-tag';
            slotTag.textContent = def.label;
            var nameNode = _doc.createElement('b');
            nameNode.textContent = labelText;
            top.appendChild(slotTag);
            top.appendChild(nameNode);
            copy.appendChild(top);

            var meta = _doc.createElement('small');
            meta.className = 'inventory-tuning-loadout-meta';
            if (!item) {
                meta.textContent = '未穿戴';
            } else if (!cap.available) {
                meta.textContent = cap.reason || '不可调制';
            } else {
                var parts = [];
                var enh = Number(item.enhancementLevel) || 0;
                if (enh > 0) parts.push('+' + enh);
                var modCap = Number(item.modSlotCapacity) || 0;
                if (modCap > 0) parts.push('插件 ' + (Number(item.modSlotUsed) || 0) + '/' + modCap);
                if (DrugControls && DrugControls.supportsChestItem(item)) parts.push('应急机制');
                meta.textContent = parts.length ? parts.join(' · ') : '可调制';
            }
            copy.appendChild(meta);
            btn.appendChild(copy);

            if (cap.available) {
                btn.addEventListener('click', function() { selectEquippedSlot(def.id); });
            }
            if (item && _session) {
                var rev = _session.getLoadoutRevision ? _session.getLoadoutRevision() : 0;
                bindLoadoutTooltip(btn, 'list:' + def.id + ':' + rev + ':' + item.name, def.label, item, def.id);
            }
            return btn;
        }

        function renderLoadoutPane() {
            if (!_loadoutPane || _destroyed) return;
            if (_tooltipScope && _tooltipScope.releaseTree) _tooltipScope.releaseTree(_loadoutPane);
            while (_loadoutPane.firstChild) _loadoutPane.removeChild(_loadoutPane.firstChild);

            if (_sessionState === 'opening') {
                var loading = _doc.createElement('div');
                loading.className = 'inventory-tuning-loadout-empty';
                loading.textContent = '正在读取已穿戴装备…';
                _loadoutPane.appendChild(loading);
                return;
            }
            if (_sessionState !== 'ready' || !_session || !_session.getSnapshot()) {
                var unavailable = _doc.createElement('div');
                unavailable.className = 'inventory-tuning-loadout-empty';
                var msg = _doc.createElement('p');
                msg.textContent = '当前无法读取已穿戴装备，背包调制仍可正常使用。';
                var retry = _doc.createElement('button');
                retry.type = 'button';
                retry.className = 'workbench-mode-btn';
                retry.textContent = '重试读取';
                retry.addEventListener('click', function() {
                    _sessionState = 'idle';
                    ensureSession();
                });
                unavailable.appendChild(msg);
                unavailable.appendChild(retry);
                _loadoutPane.appendChild(unavailable);
                return;
            }
            var snap = _session.getSnapshot();
            var bySlot = {};
            var rows = Array.isArray(snap.equipment) ? snap.equipment : [];
            for (var i = 0; i < rows.length; i++) {
                if (rows[i] && rows[i].slotKey) bySlot[rows[i].slotKey] = rows[i];
            }
            [
                {title:'护具', slots:ARMOR_SLOTS},
                {title:'武装', slots:WEAPON_SLOTS}
            ].forEach(function(group) {
                var sec = _doc.createElement('section');
                sec.className = 'inventory-tuning-loadout-section';
                var h = _doc.createElement('h3');
                h.textContent = group.title;
                sec.appendChild(h);
                var grid = _doc.createElement('div');
                grid.className = 'inventory-tuning-loadout-grid';
                for (var j = 0; j < group.slots.length; j++) {
                    grid.appendChild(buildSlotCard(group.slots[j], bySlot[group.slots[j].id] || null));
                }
                sec.appendChild(grid);
                _loadoutPane.appendChild(sec);
            });
            syncMarkers();
        }

        function customizationProxy() {
            return {
                isAvailable:function(source, item) {
                    return !!(DrugControls && DrugControls.supportsChestItem(item)
                        && _customController && _customController.isAvailable(source, item));
                },
                bind:function(next) {
                    _customListener = next;
                    if (_customController && _customController.bind) _customController.bind(next);
                },
                isLocked:function() {
                    return !!(_customController && _customController.isLocked && _customController.isLocked());
                },
                statusId:function() {
                    return _customController && _customController.statusId ? _customController.statusId() : '';
                },
                toggleSlot:function(slot) {
                    return !!(_customController && _customController.toggleSlot && _customController.toggleSlot(slot));
                },
                disableCurrent:function() {
                    return !!(_customController && _customController.disableCurrent && _customController.disableCurrent());
                },
                renderSummaryPill:function(ctx, onOpen) {
                    return _customController && _customController.renderSummaryPill
                        ? _customController.renderSummaryPill(ctx, onOpen) : null;
                },
                render:function(ctx) {
                    return _customController && _customController.render
                        ? _customController.render(ctx) : {body:_doc.createElement('div'), footer:null};
                },
                destroy:function() { _customListener = null; }
            };
        }

        function decorateOptions(tuningOptions) {
            tuningOptions = tuningOptions || {};
            var baseComplete = tuningOptions.completeWrite;
            var baseTooltip = tuningOptions.bindSourceTooltip;
            tuningOptions.completeWrite = function(operation, needsRefresh, callback, snapshots) {
                return baseComplete ? baseComplete(operation, !!needsRefresh, callback, snapshots || null) : false;
            };
            tuningOptions.refreshLoadout = function(source, callback) {
                if (!_session || !TuningAdapter) return false;
                var slotKey = source && source.slotKey ? String(source.slotKey) : _activeSlotKey;
                return TuningAdapter.refreshLoadout({
                    session:_session,
                    slotKey:slotKey,
                    entrySource:_entrySource || source,
                    active:function() { return !_destroyed && _viewMode === 'tuning'; },
                    adopt:function() { clearTooltips(); renderLoadoutPane(); },
                    sync:function() { syncMarkers(); }
                }, source, callback);
            };
            tuningOptions.bindSourceTooltip = function(node, item, source, isSuppressed) {
                if (source && source.sourceKind === 'loadout') {
                    var slotKey = String(source.slotKey || '');
                    return slotKey ? bindLoadoutTooltip(
                        node,
                        'source:' + String(source.sessionGeneration || '') + ':' + slotKey
                            + ':' + String(source.expectedLoadoutRevision || '') + ':' + String(item && item.name || ''),
                        slotKey.replace(/装备$/, ''), item, slotKey, isSuppressed) : null;
                }
                return baseTooltip ? baseTooltip(node, item, source, isSuppressed) : null;
            };
            if (Customization && DrugControls) {
                tuningOptions.customization = customizationProxy();
            }
            return tuningOptions;
        }

        function attach(context) {
            context = context || {};
            _backpackView = context.backpackView || null;
            _tuningView = context.tuningView || null;
            _viewMode = context.viewMode || 'storage';
            if (!_backpackView || !_backpackView.root) return false;
            if (!_switchEl) {
                var idBase = 'inv-tuning-src-' + Math.random().toString(36).slice(2, 7);
                _switchEl = _doc.createElement('div');
                _switchEl.className = 'inventory-tuning-source-switch';
                _switchEl.setAttribute('role', 'tablist');
                _switchEl.setAttribute('aria-label', '装备来源');
                _bagTab = _doc.createElement('button');
                _bagTab.type = 'button'; _bagTab.id = idBase + '-bag';
                _bagTab.className = 'workbench-mode-btn inventory-tuning-source-tab';
                _bagTab.setAttribute('role', 'tab');
                _bagTab.setAttribute('data-tuning-left-source', 'backpack');
                _bagTab.textContent = '背包';
                _bagTab.addEventListener('click', function() { switchLeftSource('backpack'); });
                _equippedTab = _doc.createElement('button');
                _equippedTab.type = 'button'; _equippedTab.id = idBase + '-eq';
                _equippedTab.className = 'workbench-mode-btn inventory-tuning-source-tab';
                _equippedTab.setAttribute('role', 'tab');
                _equippedTab.setAttribute('data-tuning-left-source', 'equipped');
                _equippedTab.textContent = '已穿戴';
                _equippedTab.addEventListener('click', function() { switchLeftSource('equipped'); });
                _switchEl.addEventListener('keydown', function(ev) {
                    var k = ev && ev.key;
                    if (k === 'ArrowLeft' || k === 'ArrowRight' || k === 'Home' || k === 'End') {
                        if (ev.preventDefault) ev.preventDefault();
                        switchLeftSource(k === 'Home' ? 'backpack' : k === 'End' ? 'equipped'
                            : (_leftSource === 'backpack' ? 'equipped' : 'backpack'), true);
                    }
                });
                _switchEl.appendChild(_bagTab);
                _switchEl.appendChild(_equippedTab);
                if (_backpackView.chrome && _backpackView.chrome.titleRow) {
                    _backpackView.chrome.titleRow.appendChild(_switchEl);
                }
            }
            if (!_loadoutPane) {
                _loadoutPane = _doc.createElement('div');
                _loadoutPane.id = _equippedTab.id + '-panel';
                _loadoutPane.className = 'inventory-tuning-loadout-pane';
                _loadoutPane.setAttribute('role', 'tabpanel');
                _loadoutPane.setAttribute('aria-labelledby', _equippedTab.id);
                _loadoutPane.hidden = true;
                _equippedTab.setAttribute('aria-controls', _loadoutPane.id);
                if (_backpackView.renderer && _backpackView.renderer.root) {
                    if (!_backpackView.renderer.root.id) _backpackView.renderer.root.id = _bagTab.id + '-panel';
                    _bagTab.setAttribute('aria-controls', _backpackView.renderer.root.id);
                }
                var host = (_backpackView.renderer && _backpackView.renderer.root
                    && _backpackView.renderer.root.parentNode) || _backpackView.root;
                host.appendChild(_loadoutPane);
            }
            updateLeftVisibility();
            if (_viewMode === 'tuning') ensureSession();
            return true;
        }

        function onViewMode(mode) {
            _viewMode = mode || 'storage';
            if (_viewMode !== 'tuning') _leftSource = 'backpack';
            updateLeftVisibility();
            if (_viewMode === 'tuning') ensureSession();
        }

        function canClose() {
            if (_mutations && typeof _mutations.isPending === 'function' && _mutations.isPending()) return false;
            if (_customController && typeof _customController.isLocked === 'function' && _customController.isLocked()) return false;
            return true;
        }

        function destroy() {
            if (_destroyed) return false;
            _destroyed = true;
            teardownCustomization();
            if (_tooltipScope && _tooltipScope.dispose) _tooltipScope.dispose();
            _tooltipScope = null;
            if (_switchEl && _switchEl.parentNode) _switchEl.parentNode.removeChild(_switchEl);
            if (_loadoutPane && _loadoutPane.parentNode) _loadoutPane.parentNode.removeChild(_loadoutPane);
            _switchEl = null; _bagTab = null; _equippedTab = null; _loadoutPane = null;
            _backpackView = null; _tuningView = null; _session = null;
            return true;
        }

        return {
            decorateOptions:decorateOptions,
            attach:attach,
            onViewMode:onViewMode,
            onTuningState:syncMarkers,
            switchLeftSource:switchLeftSource,
            selectEquippedSlot:selectEquippedSlot,
            canClose:canClose,
            destroy:destroy,
            debugState:function() {
                return {
                    leftSource:_leftSource,
                    sessionState:_sessionState,
                    activeSlotKey:_activeSlotKey,
                    hasSession:!!_session,
                    hasCustomization:!!_customController,
                    mutationPending:!!(_mutations && _mutations.isPending && _mutations.isPending())
                };
            }
        };
    }

    return {create:create, ARMOR_SLOTS:ARMOR_SLOTS, WEAPON_SLOTS:WEAPON_SLOTS};
});
