/**
 * Character-build candidate state and tile presentation.
 *
 * This leaf owns the five-state copy and blocked inspection semantics. It has
 * no transport authority: request/session fencing remains in the parent view.
 */
(function(root, factory) {
    'use strict';
    var primitives = typeof module !== 'undefined' && module.exports
        ? require('../workbench-primitives.js')
        : root && root.WorkbenchPrimitives;
    var api = factory(primitives);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildCandidateState = api;
        root.CharacterBuildCandidateState = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(WorkbenchPrimitives) {
    'use strict';

    if (!WorkbenchPrimitives || !WorkbenchPrimitives.EntityTile) {
        throw new Error('character-build-candidate-state.js requires EntityTile');
    }
    var COPY = {
        unselected:{
            statement:'先选择左侧槽位',
            nextStep:'从护具、武装或药剂区域选择一个槽位。'
        },
        loading:{
            statement:'正在查找可用装备',
            nextStep:'请稍候；读取完成前不会提交旧候选。'
        },
        empty:{
            statement:'此槽位暂无可用候选',
            nextStep:'可前往收纳整理背包，或在游戏中获取适合此槽位的物品。'
        },
        error:{
            statement:'暂时无法读取候选',
            nextStep:'检查连接后重试；重试只读取当前槽位，不会改动装备。'
        },
        ready:{
            statement:'候选与数量已同步',
            nextStep:'浏览候选并固定预览；只有明确确认才会改动装备。'
        }
    };
    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function copyFor(kind) {
        var source = COPY[kind] || COPY.unselected;
        return {kind:COPY[kind] ? kind : 'unselected',
            statement:source.statement, nextStep:source.nextStep};
    }
    function blockedReason(candidate) {
        return text(candidate && (
            candidate.blockedReason || candidate.reason || candidate.summary
        ), '此候选当前不可装备；当前装备保持不变。');
    }

    function CandidateState(options) {
        options = options || {};
        this._document = options.document;
        this._host = options.host;
        this._countNode = options.countNode;
        this._renderOwnedSlot = options.renderOwnedSlot;
        this._iconHtml = options.iconHtml;
        this._bindTooltip = typeof options.bindTooltip === 'function'
            ? options.bindTooltip : function() { return null; };
        this._onBlocked = typeof options.onBlocked === 'function'
            ? options.onBlocked : function() {};
        this._onRetry = typeof options.onRetry === 'function'
            ? options.onRetry : function() { return false; };
        if (!this._document || !this._host || !this._countNode
                || typeof this._renderOwnedSlot !== 'function') {
            throw new Error('CandidateState requires document, host, countNode and renderOwnedSlot');
        }
        this._kind = 'unselected';
        this._requestKey = '';
        this._candidates = [];
        this._bindings = [];
        this._destroyed = false;
        this._retryIssued = false;
        this._blockedActivations = 0;
        this._lastBlockedOrigin = '';
        this._onClick = this._handleClick.bind(this);
        this._host.addEventListener('click', this._onClick);
    }
    CandidateState.prototype._disposeBindings = function() {
        for (var i = this._bindings.length - 1; i >= 0; i--) {
            this._bindings[i].destroy();
        }
        this._bindings = [];
    };
    CandidateState.prototype._handleClick = function(event) {
        var retry = event.target && event.target.closest
            ? event.target.closest('[data-candidate-retry]') : null;
        if (!retry || !this._host.contains(retry) || this._kind !== 'error'
                || this._retryIssued || retry.disabled) return;
        event.preventDefault();
        this._retryIssued = true;
        retry.setAttribute('aria-disabled', 'true');
        this._onRetry(this._requestKey);
    };
    CandidateState.prototype._stateNode = function(kind) {
        var projection = copyFor(kind);
        var state = this._document.createElement('div');
        state.className = 'character-build-candidate-state';
        state.setAttribute('data-candidate-state-card', projection.kind);
        state.setAttribute('tabindex', '-1');
        var statement = this._document.createElement('strong');
        statement.className = 'character-build-candidate-statement';
        statement.textContent = projection.statement;
        var next = this._document.createElement('p');
        next.className = 'character-build-candidate-next-step';
        next.textContent = projection.nextStep;
        state.appendChild(statement);
        state.appendChild(next);
        if (kind === 'error') {
            var retry = this._document.createElement('button');
            retry.type = 'button';
            retry.className = 'character-build-candidate-retry';
            retry.setAttribute('data-candidate-retry', '');
            retry.textContent = '重试当前槽位';
            retry.setAttribute('aria-label', '重新读取当前槽位候选');
            state.appendChild(retry);
        }
        return state;
    };

    CandidateState.prototype._candidateNode = function(candidate, index) {
        var self = this;
        candidate = candidate || {};
        var key = text(candidate.key, 'candidate-' + index);
        var node = this._renderOwnedSlot('背包', {
            occupied:true,
            physicalSlot:candidate.physicalSlot == null ? index : candidate.physicalSlot,
            item:candidate.presentation || {}
        }, {iconHtml:this._iconHtml, allowDiscard:false});
        node.classList.add('character-build-candidate');
        node.setAttribute('role', 'option');
        node.setAttribute('data-roving-key', key);
        node.setAttribute('data-candidate-key', key);
        node.setAttribute('tabindex', '-1');
        node.setAttribute('aria-selected', 'false');
        node.setAttribute('aria-label', node.getAttribute('aria-label') + '，'
            + text(candidate.type, '背包候选') + '，' + text(candidate.summary, '可预览'));
        var delta = this._document.createElement('strong');
        delta.className = 'character-build-candidate-delta';
        delta.setAttribute('data-badge-kind',
            candidate.badgeKind === 'preview' ? 'preview' : 'delta');
        delta.textContent = candidate.delta || '±0';
        node.appendChild(delta);
        if (candidate.blocked === true) {
            var reason = this._document.createElement('span');
            reason.className = 'character-build-candidate-blocked-reason';
            node.appendChild(reason);
            node.setAttribute('data-blocked', 'true');
            this._bindings.push(WorkbenchPrimitives.EntityTile.bindActivation(node, {
                role:'option',
                selected:false,
                itemName:text(candidate.name, '未命名候选'),
                label:node.getAttribute('aria-label'),
                inspectable:true,
                actionable:false,
                reason:blockedReason(candidate),
                reasonNode:reason,
                onBlocked:function(event, context) {
                    if (event && event.preventDefault) event.preventDefault();
                    if (event && event.stopPropagation) event.stopPropagation();
                    try { node.focus({preventScroll:true}); } catch (_) { node.focus(); }
                    self._blockedActivations++;
                    self._lastBlockedOrigin = context.origin;
                    self._onBlocked(candidate, {
                        key:key,
                        node:node,
                        origin:context.origin,
                        reason:context.reason
                    });
                }
            }));
        }
        var tooltipBinding = this._bindTooltip(node, candidate);
        if (tooltipBinding && typeof tooltipBinding.destroy === 'function') {
            this._bindings.push(tooltipBinding);
        }
        return node;
    };

    CandidateState.prototype.render = function(kind, candidates, requestKey) {
        if (this._destroyed) return false;
        var projection = copyFor(kind);
        kind = projection.kind;
        candidates = kind === 'ready' && Array.isArray(candidates) ? candidates.slice() : [];
        var restoreRetryFocus = this._retryIssued;
        this._disposeBindings();
        this._kind = kind;
        this._requestKey = text(requestKey);
        this._candidates = candidates;
        if (kind !== 'loading') this._retryIssued = false;
        this._host.setAttribute('data-candidate-state', kind);
        this._host.setAttribute('data-candidate-statement', projection.statement);
        this._host.setAttribute('data-candidate-next-step', projection.nextStep);
        this._host.setAttribute('aria-busy', kind === 'loading' ? 'true' : 'false');
        this._host.setAttribute('role', kind === 'ready'
            ? 'listbox' : kind === 'error' ? 'alert' : 'status');
        this._host.setAttribute('aria-label', (kind === 'ready' ? '装备候选。' : '')
            + projection.statement + '。' + projection.nextStep);
        if (kind === 'ready') this._host.removeAttribute('aria-live');
        else this._host.setAttribute('aria-live', kind === 'error' ? 'assertive' : 'polite');
        var fragment = this._document.createDocumentFragment();
        if (kind === 'ready') {
            for (var i = 0; i < candidates.length; i++) {
                fragment.appendChild(this._candidateNode(candidates[i], i));
            }
        } else {
            fragment.appendChild(this._stateNode(kind));
        }
        this._host.innerHTML = '';
        this._host.appendChild(fragment);
        if (restoreRetryFocus && kind !== 'loading') {
            var focusTarget = this._host.querySelector(kind === 'ready'
                ? '[data-candidate-key]' : kind === 'error'
                    ? '[data-candidate-retry]' : '.character-build-candidate-state');
            if (focusTarget) {
                try { focusTarget.focus({preventScroll:true}); } catch (_) { focusTarget.focus(); }
            }
        }
        this._countNode.textContent = kind === 'ready'
            ? candidates.length + ' 项'
            : kind === 'loading' ? '读取中'
            : kind === 'error' ? '读取失败'
            : kind === 'empty' ? '0 项' : '未选择';
        return true;
    };
    CandidateState.prototype.getCandidate = function(key) {
        for (var i = 0; i < this._candidates.length; i++) {
            if (text(this._candidates[i] && this._candidates[i].key,
                    'candidate-' + i) === key) return this._candidates[i];
        }
        return null;
    };
    CandidateState.prototype.getCandidates = function() { return this._candidates.slice(); };
    CandidateState.prototype.focusCandidate = function(key, scroll) {
        var nodes = this._host.querySelectorAll('[data-candidate-key]');
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].getAttribute('data-candidate-key') !== key) continue;
            try { nodes[i].focus({preventScroll:true}); } catch (_) { nodes[i].focus(); }
            if (scroll && scroll.getBoundingClientRect && nodes[i].getBoundingClientRect) {
                var viewport = scroll.getBoundingClientRect(), item = nodes[i].getBoundingClientRect();
                var scale = (viewport.bottom - viewport.top) / Math.max(1, Number(scroll.clientHeight) || viewport.bottom - viewport.top);
                if (item.top < viewport.top) scroll.scrollTop -= (viewport.top - item.top) / scale;
                else if (item.bottom > viewport.bottom) scroll.scrollTop += (item.bottom - viewport.bottom) / scale;
            }
            return true;
        }
        return false;
    };
    CandidateState.prototype.debugState = function() {
        return {
            kind:this._kind,
            requestKey:this._requestKey,
            count:this._candidates.length,
            blockedActivations:this._blockedActivations,
            lastBlockedOrigin:this._lastBlockedOrigin
        };
    };
    CandidateState.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._disposeBindings();
        this._host.removeEventListener('click', this._onClick);
        return true;
    };
    return {
        CandidateState:CandidateState,
        copyFor:copyFor
    };
});
