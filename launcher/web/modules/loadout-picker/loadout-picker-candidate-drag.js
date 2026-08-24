/**
 * Loadout picker candidate pointer-drag interaction.
 *
 * Owns the PointerDragController wiring, drop-hint presentation and the
 * drop-commit orchestration. Pure target/policy resolution lives in the
 * drop-policy leaf; authority and transport stay in the controller.
 * Subject kind, instance keys, class prefix and ghost copy are ports; the
 * defaults preserve the character-build vocabulary verbatim.
 */
(function(root, factory) {
    'use strict';
    var primitives = typeof module !== 'undefined' && module.exports
        ? require('../workbench-primitives.js')
        : root && root.WorkbenchPrimitives;
    var dropPolicy = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker-drop-policy.js')
        : root && root.LoadoutPickerDropPolicy;
    var api = factory(primitives, dropPolicy);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.LoadoutPickerCandidateDrag = api;
        root.LoadoutPickerCandidateDrag = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchPrimitives, DropPolicyModule) {
    'use strict';
    if (!WorkbenchPrimitives
            || typeof WorkbenchPrimitives.InteractionBroker !== 'function'
            || typeof WorkbenchPrimitives.PointerDragController !== 'function') {
        throw new Error('LoadoutPickerCandidateDrag requires workbench pointer primitives');
    }
    if (!DropPolicyModule || typeof DropPolicyModule.resolve !== 'function'
            || typeof DropPolicyModule.decide !== 'function') {
        throw new Error('LoadoutPickerCandidateDrag requires LoadoutPickerDropPolicy');
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

    function install(prototype, options) {
        if (!prototype) throw new Error('LoadoutPickerCandidateDrag.install requires a view method target');
        options = options || {};
        var policy = options.policy && typeof options.policy.resolve === 'function'
            ? options.policy : DropPolicyModule;
        var classPrefix = typeof options.classPrefix === 'string'
            && options.classPrefix !== '' ? options.classPrefix : 'character-build';
        var subjectKind = typeof options.subjectKind === 'string'
            && options.subjectKind !== '' ? options.subjectKind : 'character-build-candidate';
        var sourceInstanceKey = typeof options.sourceInstanceKey === 'string'
            && options.sourceInstanceKey !== ''
            ? options.sourceInstanceKey : 'character-build:filtered-candidates';
        var targetInstanceKey = typeof options.targetInstanceKey === 'string'
            && options.targetInstanceKey !== ''
            ? options.targetInstanceKey : 'character-build:selected-slot';
        var ghostFallback = options.texts && typeof options.texts.ghostFallback === 'string'
            && options.texts.ghostFallback !== '' ? options.texts.ghostFallback : '装备候选';
        var slotSelector = '.' + classPrefix + '-slot';
        var dropHintClass = classPrefix + '-drop-hint';
        var draggingClass = classPrefix + '-candidate-dragging';
        var dragSourceClass = classPrefix + '-drag-source';

        /* Pure resolution lives in the drop-policy leaf; this shim only
         * gathers live slot descriptors (scope-aware drop target model). */
        prototype._candidateDropTargets = function(candidate) {
            var nodes = this.root.querySelectorAll(slotSelector);
            var slots = [];
            for (var i = 0; i < nodes.length; i++) {
                slots.push({
                    rovingKey:nodes[i].getAttribute('data-roving-key'),
                    kind:nodes[i].getAttribute('data-slot-kind'),
                    id:nodes[i].getAttribute('data-slot-id')
                });
            }
            return policy.resolve(
                this._candidateScope, this._selectedSlotKey, candidate, slots);
        };

        prototype._candidateDropDecision = function(hit, candidate) {
            return policy.decide({
                interactionState:this._interactionState,
                snapshotBlocked:!this._snapshot || this._snapshot.blocked
            }, hit, candidate, this._candidateDropTargets(candidate));
        };

        prototype._commitDraggedCandidate = function(candidate, intent) {
            if (!candidate || !intent || intent.operationId !== policy.operationId
                    || !intent.targetRef
                    || this._candidateState.debugState().kind !== 'ready') return false;
            var slotKey = String(intent.targetRef.slotKey || '');
            if (!slotKey) return false;
            var current = this._candidateByKey(candidate.key);
            if (!current || current !== candidate
                    || !this._candidateDropDecision({
                        slotKey:slotKey,
                        node:this.root.querySelector('[data-roving-key="'
                            + slotKey.replace(/"/g, '\\"') + '"]')
                    }, candidate).accepted) return false;
            // 选中态只用于预览高亮；跨槽落点的候选与当前选中槽位不兼容时
            // （blocked===true）跳过选中，仍按落点槽位提交。
            if (current.blocked !== true && !this._selectCandidate(candidate.key)) return false;
            return this._onSlotDropEquip(slotKey, current) !== false;
        };

        prototype._markDropHints = function(candidate, active) {
            var hinted = this.root.querySelectorAll('.' + dropHintClass);
            for (var i = 0; i < hinted.length; i++) {
                hinted[i].classList.remove(dropHintClass);
            }
            var targets = active && candidate
                ? this._candidateDropTargets(candidate) : {slots:[]};
            for (i = 0; i < targets.slots.length; i++) {
                var node = this.root.querySelector('[data-roving-key="'
                    + String(targets.slots[i]).replace(/"/g, '\\"') + '"]');
                if (node && !node.disabled && node.getAttribute('data-blocked') !== 'true') {
                    node.classList.add(dropHintClass);
                }
            }
            return targets.slots.length > 0;
        };

        prototype._setCandidateDragActive = function(active, source) {
            this._candidateDragActive = active === true;
            this.root.classList.toggle(draggingClass, this._candidateDragActive);
            if (source && source.node) {
                source.node.classList.toggle(dragSourceClass, this._candidateDragActive);
            }
            if (this._candidateDragActive && this._tooltip
                    && typeof this._tooltip.hide === 'function') this._tooltip.hide();
        };

        prototype._installCandidateDrag = function() {
            var self = this;
            var sourceView = {
                instanceKey:sourceInstanceKey,
                exportOffer:function(candidate) {
                    if (!candidate || self._interactionState !== 'idle'
                            || !self._snapshot || self._snapshot.blocked
                            || self._candidateState.debugState().kind !== 'ready') return null;
                    return {
                        subjectKind:subjectKind,
                        sourceRef:{candidateKey:String(candidate.key || ''),
                            requestKey:self._candidateRequestKey}
                    };
                }
            };
            var targetView = {
                instanceKey:targetInstanceKey,
                probeAccept:function(offer, hit) {
                    var candidate = offer && offer.subjectKind === subjectKind
                            && offer.sourceRef
                            && offer.sourceRef.requestKey === self._candidateRequestKey
                        ? self._candidateByKey(offer.sourceRef.candidateKey) : null;
                    if (!candidate) return {accepted:false, reason:'stale_candidate'};
                    return self._candidateDropDecision(hit, candidate);
                }
            };
            this._candidateDragBroker = new WorkbenchPrimitives.InteractionBroker({
                onIntent:function(intent, context) {
                    self._commitDraggedCandidate(context && context.sourceItem, intent);
                },
                onReject:function(result) {
                    if (!result || result.origin !== 'drag') return;
                    self._showStatusNotice('blocked',
                        policy.rejectCopy(result.reason));
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
                    return candidate && self._candidateDropTargets(candidate).slots.length
                        ? {view:sourceView, item:candidate, node:node} : null;
                },
                resolveTarget:function(clientX, clientY) {
                    var target = self._document.elementFromPoint(clientX, clientY);
                    var node = closest(target, slotSelector, self.root);
                    if (!node) return null;
                    var hit = {slotKey:node.getAttribute('data-roving-key'), node:node};
                    return {view:targetView, hit:hit, node:node,
                        accepted:self._candidateDropDecision(hit, self._dragCandidate).accepted};
                },
                renderGhost:function(source) {
                    var item = source.item && source.item.presentation || {};
                    var ghost = self._document.createElement('div');
                    ghost.className = 'workbench-drag-ghost inventory-drag-ghost '
                        + classPrefix + '-drag-ghost';
                    ghost.innerHTML = self._iconHtml(item.icon || '', 'inventory-owned-icon')
                        + '<span>' + escapeHtml(item.displayName || source.item.name || ghostFallback)
                        + '</span>';
                    return ghost;
                },
                onDragStart:function(source) {
                    self._dragCandidate = source && source.item || null;
                    self._setCandidateDragActive(true, source);
                    self._markDropHints(self._dragCandidate, true);
                },
                onDragEnd:function(source) {
                    self._markDropHints(self._dragCandidate, false);
                    self._dragCandidate = null;
                    self._setCandidateDragActive(false, source);
                }
            });
        };

        return prototype;
    }

    return {install:install};
});
