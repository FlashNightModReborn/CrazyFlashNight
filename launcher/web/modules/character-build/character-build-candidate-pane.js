/** Candidate-pane scope, selection, recovery and pointer-drag interaction. */
(function(root, factory) {
    'use strict';
    var primitives = typeof module !== 'undefined' && module.exports
        ? require('../workbench-primitives.js')
        : root && root.WorkbenchPrimitives;
    var facets = typeof module !== 'undefined' && module.exports
        ? require('./character-build-facet-counts.js')
        : root && root.CharacterBuildFacetCounts;
    var api = factory(primitives, facets);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildCandidatePane = api;
        root.CharacterBuildCandidatePane = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchPrimitives, FacetCountsModule) {
    'use strict';
    if (!WorkbenchPrimitives
            || typeof WorkbenchPrimitives.InteractionBroker !== 'function'
            || typeof WorkbenchPrimitives.PointerDragController !== 'function') {
        throw new Error('CharacterBuildCandidatePane requires workbench pointer primitives');
    }
    if (!FacetCountsModule || typeof FacetCountsModule.syncFocusSummary !== 'function') {
        throw new Error('CharacterBuildCandidatePane requires CharacterBuildFacetCounts');
    }

    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function normalizeScope(value) {
        value = String(value || '');
        return value === 'backpack' ? 'backpack'
            : value === 'compatible' ? 'compatible' : '';
    }
    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function closest(target, selector, root) {
        if (!target || typeof target.closest !== 'function') return null;
        var match = target.closest(selector);
        return match && (!root || root.contains(match)) ? match : null;
    }

    function install(prototype) {
        if (!prototype) throw new Error('CharacterBuildCandidatePane.install requires a view method target');

        prototype._candidateDropDecision = function(hit) {
            if (this._interactionState !== 'idle') return {accepted:false, reason:'write_locked'};
            if (!this._snapshot || this._snapshot.blocked) {
                return {accepted:false, reason:'build_blocked'};
            }
            if (!hit || !hit.slotKey || hit.slotKey !== this._selectedSlotKey) {
                return {accepted:false, reason:'target_mismatch'};
            }
            var node = hit.node;
            if (!node || node.disabled || node.getAttribute('data-blocked') === 'true') {
                return {accepted:false, reason:'target_blocked'};
            }
            return {accepted:true, operationId:'character-build.equip-candidate',
                targetRef:{slotKey:this._selectedSlotKey}};
        };

        prototype._commitDraggedCandidate = function(candidate, intent) {
            if (!candidate || !intent || intent.operationId !== 'character-build.equip-candidate'
                    || !intent.targetRef
                    || intent.targetRef.slotKey !== this._selectedSlotKey
                    || this._candidateState.debugState().kind !== 'ready') return false;
            var current = this._candidateByKey(candidate.key);
            if (!current || current !== candidate || current.blocked === true
                    || !this._candidateDropDecision({
                        slotKey:this._selectedSlotKey,
                        node:this.root.querySelector('[data-roving-key="'
                            + this._selectedSlotKey.replace(/"/g, '\\"') + '"]')
                    }).accepted) return false;
            if (!this._selectCandidate(candidate.key)) return false;
            return this._onCommitCandidate(current) !== false;
        };

        prototype._setCandidateDragActive = function(active, source) {
            this._candidateDragActive = active === true;
            this.root.classList.toggle('character-build-candidate-dragging', this._candidateDragActive);
            if (source && source.node) {
                source.node.classList.toggle('character-build-drag-source', this._candidateDragActive);
            }
            if (this._candidateDragActive && this._tooltip
                    && typeof this._tooltip.hide === 'function') this._tooltip.hide();
        };

        prototype._installCandidateDrag = function() {
            var self = this;
            var sourceView = {
                instanceKey:'character-build:filtered-candidates',
                exportOffer:function(candidate) {
                    if (!candidate || candidate.blocked === true
                            || self._interactionState !== 'idle'
                            || !self._snapshot || self._snapshot.blocked
                            || self._candidateState.debugState().kind !== 'ready') return null;
                    return {
                        subjectKind:'character-build-candidate',
                        sourceRef:{candidateKey:String(candidate.key || ''),
                            requestKey:self._candidateRequestKey}
                    };
                }
            };
            var targetView = {
                instanceKey:'character-build:selected-slot',
                probeAccept:function(offer, hit) {
                    if (!offer || offer.subjectKind !== 'character-build-candidate'
                            || !offer.sourceRef
                            || offer.sourceRef.requestKey !== self._candidateRequestKey
                            || !self._candidateByKey(offer.sourceRef.candidateKey)) {
                        return {accepted:false, reason:'stale_candidate'};
                    }
                    return self._candidateDropDecision(hit);
                }
            };
            this._candidateDragBroker = new WorkbenchPrimitives.InteractionBroker({
                onIntent:function(intent, context) {
                    self._commitDraggedCandidate(context && context.sourceItem, intent);
                },
                onReject:function(result) {
                    if (!result || result.origin !== 'drag') return;
                    self._showStatusNotice('blocked', result.reason === 'write_locked'
                        ? '构筑正在处理写入，当前拖拽已取消。'
                        : result.reason === 'target_blocked' || result.reason === 'build_blocked'
                            ? '当前目标不可装备此候选，现有装备保持不变。'
                            : '筛选候选只可拖到当前已选槽位。');
                }
            });
            var brokerPort = {
                select:function() { return true; },
                dispatch:function(source, item, target, hit, origin) {
                    return self._candidateDragBroker.dispatch(source, item, target, hit, origin);
                }
            };
            this._candidateDrag = new WorkbenchPrimitives.PointerDragController({
                sourceElement:this._candidateList,
                broker:brokerPort,
                getSource:function(target) {
                    if (self._interactionState !== 'idle' || !self._snapshot
                            || self._snapshot.blocked
                            || self._candidateState.debugState().kind !== 'ready') return null;
                    var node = closest(target, '[data-candidate-key]', self._candidateList);
                    var candidate = node && self._candidateByKey(
                        node.getAttribute('data-candidate-key'));
                    return candidate && candidate.blocked !== true
                        ? {view:sourceView, item:candidate, node:node} : null;
                },
                resolveTarget:function(clientX, clientY) {
                    var target = self._document.elementFromPoint(clientX, clientY);
                    var node = closest(target, '.character-build-slot', self.root);
                    if (!node) return null;
                    var hit = {slotKey:node.getAttribute('data-roving-key'), node:node};
                    return {view:targetView, hit:hit, node:node,
                        accepted:self._candidateDropDecision(hit).accepted};
                },
                renderGhost:function(source) {
                    var item = source.item && source.item.presentation || {};
                    var ghost = self._document.createElement('div');
                    ghost.className = 'workbench-drag-ghost inventory-drag-ghost character-build-drag-ghost';
                    ghost.innerHTML = self._iconHtml(item.icon || '', 'inventory-owned-icon')
                        + '<span>' + escapeHtml(item.displayName || source.item.name || '装备候选')
                        + '</span>';
                    return ghost;
                },
                onDragStart:function(source) { self._setCandidateDragActive(true, source); },
                onDragEnd:function(source) { self._setCandidateDragActive(false, source); }
            });
        };

        prototype._candidateScopePending = function() {
            return !!this._candidateState
                && this._candidateState.debugState().kind === 'loading';
        };

        prototype._syncCandidateScopeControl = function() {
            if (!this._candidateScopeGroup) return false;
            this._candidateScopeGroup.update({
                value:this._candidateScope,
                disabled:this._interactionState !== 'idle'
                    || this._candidateScopePending()
            });
            return true;
        };

        prototype._changeCandidateScope = function(scope) {
            scope = normalizeScope(scope);
            if (!scope || scope === this._candidateScope) return !!scope;
            if (this._destroyed || this._interactionState !== 'idle'
                    || this._candidateScopePending()) return false;

            var scroll = this._candidateList.parentNode;
            var previousCandidateState = this._candidateState.debugState();
            var previous = {
                scope:this._candidateScope,
                requestKey:this._candidateRequestKey,
                selectedCandidateKey:this._selectedCandidateKey,
                activeCandidateKey:this._activeCandidateKey,
                candidateLoadFailed:this._candidateLoadFailed,
                candidateFailureCode:this._candidateFailureCode,
                candidateRecoveryPending:this._candidateRecoveryPending,
                kind:previousCandidateState.kind,
                candidates:this._candidateState.getCandidates(),
                scrollTop:scroll ? scroll.scrollTop : 0
            };
            var previousCandidate = this._candidateByKey(previous.selectedCandidateKey);
            this._candidateScope = scope;
            if (scroll) scroll.scrollTop = 0;

            if (!this._selectedSlotKey) {
                if (this._onCandidateScopeChange(scope, null) === false) {
                    this._candidateScope = previous.scope;
                    this._syncCandidateScopeControl();
                    return false;
                }
                this._syncCandidateScopeControl();
                return true;
            }

            this._selectedCandidateKey = '';
            this._activeCandidateKey = '';
            this._candidateLoadFailed = false;
            this._candidateFailureCode = '';
            this._candidateRecoveryPending = false;
            this._syncCandidateSelection();
            this._onCandidateSelect(null, {
                slotKey:this._selectedSlotKey,
                requestKey:this._candidateRequestKey
            });
            this._candidateRequestKey = this._candidateFence + ':'
                + this._selectedSlotKey + ':' + scope + ':' + (++this._candidateSequence);
            this._setCandidateState('loading', [], this._candidateRequestKey);
            this._showBrowsingNotice(scope === 'backpack'
                ? '正在读取背包全部物品；不兼容物品仅可查看说明…'
                : '正在读取与当前槽位兼容的背包候选…');
            var parts = this._selectedSlotKey.split(':');
            var selection = {
                key:this._selectedSlotKey,
                kind:parts.shift(),
                id:parts.join(':'),
                requestKey:this._candidateRequestKey,
                candidateScope:scope
            };
            var result = this._onCandidateScopeChange(scope, selection);
            if (result === false || result == null) {
                this._candidateScope = previous.scope;
                this._candidateRequestKey = previous.requestKey;
                this._selectedCandidateKey = previous.selectedCandidateKey;
                this._activeCandidateKey = previous.activeCandidateKey;
                this._candidateLoadFailed = previous.candidateLoadFailed;
                this._candidateFailureCode = previous.candidateFailureCode;
                this._candidateRecoveryPending = previous.candidateRecoveryPending;
                this._setCandidateState(
                    previous.kind,
                    previous.candidates,
                    previous.requestKey);
                if (scroll) scroll.scrollTop = previous.scrollTop;
                if (previousCandidate) {
                    this._onCandidateSelect(previousCandidate, {
                        slotKey:this._selectedSlotKey,
                        requestKey:previous.requestKey
                    });
                }
                this._syncCandidateScopeControl();
                this._showStatusNotice(
                    'error', '候选范围切换未完成；当前候选保持不变。');
                return false;
            }
            if (Array.isArray(result)) this.setCandidates(selection.requestKey, result);
            return true;
        };

        prototype._setCandidateState = function(kind, candidates, requestKey) {
            if (this._candidateDrag) this._candidateDrag.cancel('candidate_render');
            var activeElement = this._document.activeElement;
            var restoreFocus = !!(activeElement && this._candidateList.contains(activeElement));
            this._candidateState.render(kind, candidates, requestKey);
            this._candidateRoving.refresh({preferredKey:this._activeCandidateKey, focus:restoreFocus});
            this._syncCandidateSelection();
            this._syncCandidateScopeControl();
            return true;
        };

        prototype._syncCandidateSelection = function() {
            this._actionView.syncCandidateSelection(this._selectedCandidateKey);
        };

        prototype._candidateByKey = function(key) {
            return this._selectedSlotKey ? this._candidateState.getCandidate(key) : null;
        };

        prototype._syncSlotSelection = function() {
            var slots = this.root.querySelectorAll('.character-build-slot');
            for (var i = 0; i < slots.length; i++) {
                var selected = slots[i].getAttribute('data-roving-key') === this._selectedSlotKey;
                slots[i].setAttribute('aria-selected', selected ? 'true' : 'false');
                var card = slots[i].querySelector('.character-build-slot-card');
                if (card) {
                    card.classList.toggle('workbench-source-selected', selected);
                }
            }
            this._actionView.sync();
        };

        prototype.setInteractionState = function(state) {
            state = String(state || 'opening');
            if (state !== 'idle' && this._candidateDrag) {
                this._candidateDrag.cancel('interaction_locked');
            }
            var previous = this._interactionState;
            if (previous === 'idle' && state !== 'idle'
                    && this._tooltip && typeof this._tooltip.hide === 'function') {
                this._tooltip.hide();
            }
            var active = closest(this._document.activeElement, '[data-roving-key]', this.root);
            if (previous === 'idle' && state !== 'idle') {
                this._lockedFocusKey = active ? active.getAttribute('data-roving-key') : '';
            }
            this._interactionState = state;
            this._actionView.setState(state);
            this.root.setAttribute('aria-busy',
                state !== 'idle' && state !== 'flush_failed' ? 'true' : 'false');
            this._armorRoving.refresh({preferredKey:this._activeSlotKey});
            this._weaponRoving.refresh({preferredKey:this._activeSlotKey});
            this._drugRoving.refresh({preferredKey:this._activeSlotKey});
            this._candidateRoving.refresh({preferredKey:this._activeCandidateKey});
            this._syncCandidateScopeControl();
            if (state === 'write_pending') {
                this._showStatusNotice(
                    'write',
                    '正在写入构筑；槽位、候选与页面切换暂时锁定。');
            } else if (state === 'mutation_reconcile') {
                this._showStatusNotice(
                    'reconcile',
                    '写入结果未知；仅可重新确认结果，不会重复提交。');
            } else if (state === 'idle' && previous !== 'idle') {
                var node = this._lockedFocusKey && this.root.querySelector(
                    '[data-roving-key="' + this._lockedFocusKey.replace(/"/g, '\\"') + '"]');
                this._lockedFocusKey = '';
                this._showBrowsingNotice('交互已恢复；可继续选择槽位或候选。');
                if (node && !node.disabled) {
                    try { node.focus({preventScroll:true}); } catch (_) { node.focus(); }
                }
            }
            return true;
        };
        prototype._focusSlot = function(key) {
            this._activeSlotKey = FacetCountsModule.syncFocusSummary(
                this.root, this._slotFocusSummary, this._facetCounts, key);
            return true;
        };
        prototype._focusCandidate = function(key) {
            if (!key) return false;
            this._activeCandidateKey = String(key);
            var candidate = this._candidateByKey(this._activeCandidateKey);
            this._candidateFocusSummary.textContent = candidate
                ? '浏览：' + text(candidate.name, '未命名候选') + ' · '
                    + text(candidate.summary, this._activeCandidateKey === this._selectedCandidateKey
                        ? '已固定预览；再次点击或按 Space 取消，按 Enter 提交。'
                        : 'Enter 或 Space 固定预览；再次点击或按 Space 取消。')
                : '方向键只浏览摘要；Enter 或 Space 固定预览；再次点击或按 Space 取消。';
            this._candidateFocusSummary.title = this._candidateFocusSummary.textContent;
            return true;
        };
        prototype._selectSlot = function(key) {
            if (!key) return false;
            var nextKey = String(key);
            var changed = this._selectedSlotKey !== nextKey;
            var previousCandidateState = this._candidateState.debugState();
            var previous = {
                selectedSlotKey:this._selectedSlotKey,
                selectedCandidateKey:this._selectedCandidateKey,
                activeCandidateKey:this._activeCandidateKey,
                candidateRequestKey:this._candidateRequestKey,
                candidateLoadFailed:this._candidateLoadFailed,
                candidateFailureCode:this._candidateFailureCode,
                candidateRecoveryPending:this._candidateRecoveryPending,
                candidateState:previousCandidateState.kind,
                candidates:this._candidateState.getCandidates()
            };
            var previousCandidate = this._candidateByKey(previous.selectedCandidateKey);
            this._selectedSlotKey = nextKey;
            this._syncSlotSelection();
            if (changed || this._candidateLoadFailed) {
                this.clearCandidateSelection();
                this._activeCandidateKey = '';
                this._candidateLoadFailed = false;
                this._candidateFailureCode = '';
                this._candidateRecoveryPending = false;
                this._candidateRequestKey = this._candidateFence + ':'
                    + this._selectedSlotKey + ':' + this._candidateScope
                    + ':' + (++this._candidateSequence);
                this._setCandidateState('loading', [], this._candidateRequestKey);
                this._showBrowsingNotice('正在读取当前槽位的背包候选…');
                var parts = this._selectedSlotKey.split(':');
                var selection = {
                    key:this._selectedSlotKey,
                    kind:parts.shift(),
                    id:parts.join(':'),
                    requestKey:this._candidateRequestKey,
                    candidateScope:this._candidateScope
                };
                var result = this._onSlotSelect(selection), deferredSelection = result && result.deferSelection === true;
                if (result === false || result == null || deferredSelection) {
                    this._selectedSlotKey = previous.selectedSlotKey;
                    this._selectedCandidateKey = previous.selectedCandidateKey;
                    this._activeCandidateKey = previous.activeCandidateKey;
                    this._candidateRequestKey = previous.candidateRequestKey;
                    this._candidateLoadFailed = previous.candidateLoadFailed;
                    this._candidateFailureCode = previous.candidateFailureCode;
                    this._candidateRecoveryPending = previous.candidateRecoveryPending;
                    this._setCandidateState(previous.candidateState, previous.candidates,
                        previous.candidateRequestKey);
                    this._syncSlotSelection();
                    if (previousCandidate) {
                        this._onCandidateSelect(previousCandidate, {
                            slotKey:previous.selectedSlotKey,
                            requestKey:previous.candidateRequestKey
                        });
                    }
                    this._showStatusNotice(
                        deferredSelection ? 'pending' : 'error',
                        deferredSelection ? '正在退出当前调制；完成后将打开目标槽位。' : '槽位切换未完成；当前选择与候选保持不变。');
                    return deferredSelection;
                }
                if (result && result.deferCandidates === true) {
                    this._candidateLoadFailed = true;
                    this._showBrowsingNotice(
                        '已切换调制目标；返回候选后将读取当前槽位。');
                }
                if (Array.isArray(result)) this.setCandidates(selection.requestKey, result);
            }
            return true;
        };
        prototype._retryCandidates = function(requestKey) {
            if (this._destroyed || !this._candidateLoadFailed || !this._selectedSlotKey
                    || requestKey !== this._candidateRequestKey
                    || this._candidateState.debugState().kind !== 'error') return false;
            return this._selectSlot(this._selectedSlotKey);
        };
        prototype._explainBlockedCandidate = function(candidate, context) {
            var reason = text(context && context.reason || candidate && (
                candidate.blockedReason || candidate.reason || candidate.summary
            ), '此候选当前不可装备。');
            this._candidateFocusSummary.textContent = '不可装备：' + reason;
            this._candidateFocusSummary.title = this._candidateFocusSummary.textContent;
            this._showStatusNotice('blocked', reason + ' 当前装备保持不变。');
            return true;
        };
        prototype._selectCandidate = function(key) {
            if (!key || this._interactionState !== 'idle') return false;
            var candidate = this._candidateByKey(key);
            if (!candidate || candidate.blocked === true) return false;
            this._selectedCandidateKey = String(key);
            this._syncCandidateSelection();
            this._onCandidateSelect(candidate, {
                slotKey:this._selectedSlotKey,
                requestKey:this._candidateRequestKey
            });
            return true;
        };
        prototype.clearCandidateSelection = function() {
            if (!this._selectedCandidateKey) return false;
            this._selectedCandidateKey = '';
            this._syncCandidateSelection();
            this._onCandidateSelect(null, {
                slotKey:this._selectedSlotKey,
                requestKey:this._candidateRequestKey
            });
            this._showBrowsingNotice('候选预览已清除，当前装备保持不变。');
            return true;
        };

        prototype.setCandidates = function(requestKey, candidates) {
            if (this._destroyed || !requestKey || requestKey !== this._candidateRequestKey
                    || !this._selectedSlotKey) return false;
            candidates = Array.isArray(candidates) ? candidates.slice() : [];
            this._candidateLoadFailed = false;
            this._candidateFailureCode = '';
            this._candidateRecoveryPending = false;
            this._selectedCandidateKey = '';
            this._activeCandidateKey = '';
            this._setCandidateState(candidates.length ? 'ready' : 'empty',
                candidates, requestKey);
            if (this._snapshot && this._snapshot.blocked) {
                this._notice.textContent = text(
                    this._snapshot.blockedReason, '部分角色数据不可用；请检查候选阻断原因。');
                this._notice.setAttribute('data-notice-kind', 'blocked');
            } else {
                this._showBrowsingNotice(candidates.length
                    ? this._candidateScope === 'backpack'
                        ? '已读取背包全部物品；不兼容物品可查看说明但不能装备。'
                        : '已读取当前槽位候选；选择候选只会更新临时预览。'
                    : this._candidateScope === 'backpack'
                        ? '当前背包没有可显示的物品。'
                        : '当前背包没有可用于该槽位的候选。');
            }
            return true;
        };
        prototype.beginCandidateRecovery = function(requestKey) {
            if (this._destroyed || !requestKey || requestKey !== this._candidateRequestKey
                    || !this._selectedSlotKey) return false;
            this._candidateLoadFailed = false;
            this._candidateFailureCode = 'stale_state';
            this._candidateRecoveryPending = true;
            this._setCandidateState('loading', [], requestKey);
            this._showStatusNotice(
                'pending', '装备状态已更新；正在刷新当前槽位与可用候选…');
            return true;
        };
        prototype.setCandidateFailure = function(requestKey, error) {
            if (this._destroyed || !requestKey || requestKey !== this._candidateRequestKey
                    || !this._selectedSlotKey) return false;
            this._candidateLoadFailed = true;
            this._candidateFailureCode = text(error, 'candidate_read_failed');
            this._candidateRecoveryPending = false;
            this._setCandidateState('error', [], requestKey);
            this._showStatusNotice('error', this._candidateFailureCode === 'snapshot_refresh_failed'
                ? '装备状态刷新失败；可安全重试当前槽位，不会改动装备。'
                : '候选读取失败；可安全重试当前槽位，不会改动装备。');
            return true;
        };
        prototype.restoreSlot = function(key) {
            if (this._destroyed || !key) return false;
            var node = this.root.querySelector('[data-roving-key="' + String(key).replace(/"/g, '\\"') + '"]');
            if (!node) return false;
            this._activeSlotKey = String(key);
            this._candidateList.parentNode.scrollTop = 0;
            if (!this._selectSlot(this._activeSlotKey)) return false;
            try { node.focus({preventScroll:true}); } catch (_) { node.focus(); }
            return true;
        };
        prototype.getCandidates = function() {
            return this._candidateState.getCandidates();
        };
        prototype.restoreCandidateTuning = function(plan, state) {
            if (this._destroyed || !plan || !state || !this.restoreSlot(state.slotKey)) return false;
            var scroll = this.root.querySelector('.character-build-candidate-scroll');
            if (scroll) scroll.scrollTop = Number(state.scrollTop) || 0;
            var candidate = plan.candidate;
            if (candidate) {
                this._activeCandidateKey = String(candidate.key || '');
                if (!this._selectCandidate(this._activeCandidateKey)) return false;
                this._candidateRoving.refresh({preferredKey:this._activeCandidateKey});
                this._candidateState.focusCandidate(this._activeCandidateKey, scroll);
                if (plan.kind === 'adjacent') this._showStatusNotice(
                    'changed', '原候选已移动或不再可用，已转到相邻候选。');
                else this._showBrowsingNotice('已返回调制后的同一候选。');
            } else {
                var heading = this.root.querySelector('#character-build-candidate-title');
                if (heading) {
                    heading.setAttribute('tabindex', '-1');
                    try { heading.focus({preventScroll:true}); } catch (_) { heading.focus(); }
                }
                this._showStatusNotice(
                    'changed', '原候选已移动或不再可用，当前槽位已没有可恢复的候选。');
            }
            return true;
        };
        return prototype;
    }

    return {install:install, normalizeScope:normalizeScope};
});
