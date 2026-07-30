/**
 * Workbench interaction and entity primitives.
 *
 * This module is intentionally domain-free. It owns repeated entity semantics,
 * catalog-card presentation, neutral offer/accept dispatch and pointer drag
 * lifecycle. workbench.js composes these primitives into the shared shell.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.WorkbenchPrimitives = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function makeElement(tag, className) {
        var element = document.createElement(tag || 'div');
        if (className) element.className = className;
        return element;
    }

    function viewKey(view) {
        return view && view.instanceKey ? String(view.instanceKey) : '';
    }

    /** Shared keyboard/focus contract for a repeated entity tile. */
    function EntityTile() {}

    var entityReasonSequence = 0;

    function optionValue(value, fallback) {
        if (typeof value === 'function') return value();
        return value == null ? fallback : value;
    }

    function interactionProjection(node, options) {
        options = options || {};
        var legacyDisabled = !!optionValue(options.disabled, false);
        var inspectable = !!optionValue(
            options.inspectable,
            !legacyDisabled
        );
        var actionable = !!optionValue(
            options.actionable,
            !legacyDisabled
        );
        if (actionable) inspectable = true;
        return {
            inspectable:inspectable,
            actionable:actionable,
            reason:String(optionValue(options.reason, '') || '').trim(),
            tabIndex:options.tabIndex == null ? 0 : options.tabIndex
        };
    }

    function resolveReasonNode(node, options) {
        if (!node || !options) return null;
        if (options.reasonNode && options.reasonNode.setAttribute) {
            return options.reasonNode;
        }
        if (options.reasonSelector && node.querySelector) {
            return node.querySelector(options.reasonSelector);
        }
        return null;
    }

    EntityTile.projectInteraction = function(node, options) {
        if (!node || !node.setAttribute) return null;
        options = options || {};
        var projection = interactionProjection(node, options);
        node.setAttribute(
            'aria-disabled',
            projection.actionable ? 'false' : 'true'
        );
        node.setAttribute(
            'tabindex',
            projection.inspectable ? String(projection.tabIndex) : '-1'
        );
        node.setAttribute(
            'data-entity-inspectable',
            projection.inspectable ? 'true' : 'false'
        );
        node.setAttribute(
            'data-entity-actionable',
            projection.actionable ? 'true' : 'false'
        );

        var reasonNode = resolveReasonNode(node, options);
        if (reasonNode) {
            reasonNode.textContent = projection.reason;
            reasonNode.hidden = !projection.reason;
            if (projection.reason) {
                if (!reasonNode.getAttribute('id')) {
                    reasonNode.setAttribute(
                        'id',
                        'workbench-entity-reason-' + (++entityReasonSequence)
                    );
                }
                reasonNode.setAttribute('data-entity-reason', '');
                node.setAttribute(
                    'aria-describedby',
                    reasonNode.getAttribute('id')
                );
            } else {
                node.removeAttribute('aria-describedby');
            }
        } else if (projection.reason) {
            node.setAttribute('data-entity-reason', projection.reason);
        } else {
            node.removeAttribute('data-entity-reason');
            node.removeAttribute('aria-describedby');
        }
        return projection;
    };

    EntityTile.labelWithItemName = function(itemName, label) {
        var name = String(itemName || '').trim();
        var text = String(label || '').trim();
        if (!name) return text;
        if (!text) return name;
        return text.indexOf(name) >= 0 ? text : name + '，' + text;
    };

    EntityTile.labelAction = function(action, itemName, label) {
        if (!action || !action.setAttribute) return;
        var actionLabel = label;
        if (actionLabel == null) actionLabel = action.getAttribute('aria-label') || action.textContent || '操作';
        action.setAttribute('aria-label', EntityTile.labelWithItemName(itemName, actionLabel));
    };

    EntityTile.setSelected = function(node, selected) {
        if (!node || !node.setAttribute) return false;
        node.setAttribute('aria-selected', selected ? 'true' : 'false');
        return !!selected;
    };

    EntityTile.setDisabled = function(node, disabled, tabIndex) {
        if (!node || !node.setAttribute) return false;
        disabled = !!disabled;
        EntityTile.projectInteraction(node, {
            inspectable:!disabled,
            actionable:!disabled,
            tabIndex:tabIndex
        });
        return disabled;
    };

    EntityTile.applySemantics = function(node, options) {
        if (!node || !node.setAttribute) return node;
        options = options || {};
        var itemName = String(options.itemName || options.name || '').trim();
        var role = options.role || 'option';
        var selected = typeof options.selected === 'function' ? !!options.selected() : !!options.selected;
        node.setAttribute('role', role);
        EntityTile.projectInteraction(node, options);
        EntityTile.setSelected(node, selected);
        if (options.label != null || itemName) {
            node.setAttribute('aria-label', EntityTile.labelWithItemName(itemName, options.label || itemName));
        }
        var actionSelector = options.actionSelector || 'button,[data-entity-action]';
        var actions = node.querySelectorAll ? node.querySelectorAll(actionSelector) : [];
        for (var i = 0; i < actions.length; i++) {
            var action = actions[i];
            var label = typeof options.actionLabel === 'function'
                ? options.actionLabel(action, itemName) : options.actionLabel;
            EntityTile.labelAction(action, itemName, label);
        }
        return node;
    };

    EntityTile.bindActivation = function(node, options) {
        if (!node || !node.addEventListener) return null;
        options = options || {};
        if (node.__workbenchEntityTileBinding && node.__workbenchEntityTileBinding.destroy) {
            node.__workbenchEntityTileBinding.destroy();
        }
        EntityTile.applySemantics(node, options);

        function activate(event, origin) {
            var projection = EntityTile.projectInteraction(node, options);
            if (!projection || !projection.inspectable) return false;
            if (!projection.actionable) {
                if (typeof options.onBlocked === 'function') {
                    options.onBlocked(event, {
                        origin:origin,
                        node:node,
                        reason:projection.reason
                    });
                    return true;
                }
                return false;
            }
            if (typeof options.onActivate !== 'function') return false;
            options.onActivate(event, { origin: origin, node: node });
            return true;
        }

        function onClick(event) {
            if (event.button != null && event.button !== 0) return;
            if (event.target !== node && event.target.closest) {
                var nestedControl = event.target.closest('button,a[href],input,select,textarea,[contenteditable="true"],[data-entity-action]');
                if (nestedControl && nestedControl !== node && node.contains(nestedControl)) return;
            }
            activate(event, 'pointer');
        }

        function onKeyDown(event) {
            if (event.target !== node || (event.key !== 'Enter' && event.key !== ' ')) return;
            var projection = interactionProjection(node, options);
            if (!projection.inspectable) return;
            event.preventDefault();
            activate(event, 'keyboard');
        }

        node.addEventListener('click', onClick);
        node.addEventListener('keydown', onKeyDown);
        var binding = {
            destroy: function() {
                node.removeEventListener('click', onClick);
                node.removeEventListener('keydown', onKeyDown);
                if (node.__workbenchEntityTileBinding === binding) node.__workbenchEntityTileBinding = null;
            }
        };
        node.__workbenchEntityTileBinding = binding;
        return binding;
    };

    function InteractionBroker(options) {
        options = options || {};
        this._onIntent = options.onIntent || function() {};
        this._onReject = options.onReject || function() {};
        this._onSelectionChange = options.onSelectionChange || function() {};
        this._selected = null;
    }

    InteractionBroker.prototype.select = function(view, item, node) {
        if (this._selected && this._selected.node) {
            this._selected.node.classList.remove('workbench-source-selected');
            EntityTile.setSelected(this._selected.node, false);
        }
        this._selected = view && item ? { view: view, item: item, node: node || null } : null;
        if (this._selected && this._selected.node) {
            this._selected.node.classList.add('workbench-source-selected');
            EntityTile.setSelected(this._selected.node, true);
        }
        this._onSelectionChange(this._selected);
        return !!this._selected;
    };

    InteractionBroker.prototype.clearSelection = function() {
        this.select(null, null, null);
    };

    InteractionBroker.prototype.dispatch = function(sourceView, sourceItem, targetView, targetHit, origin) {
        var offer = sourceView && typeof sourceView.exportOffer === 'function'
            ? sourceView.exportOffer(sourceItem, { origin: origin || 'pointer' })
            : null;
        if (!offer) {
            this._onReject({ reason: 'no_offer', origin: origin });
            return { accepted: false, reason: 'no_offer' };
        }
        var acceptance = targetView && typeof targetView.probeAccept === 'function'
            ? targetView.probeAccept(offer, targetHit || {})
            : null;
        if (!acceptance || !acceptance.accepted || !acceptance.operationId) {
            var reason = acceptance && acceptance.reason ? acceptance.reason : 'rejected';
            this._onReject({ reason: reason, offer: offer, acceptance: acceptance, origin: origin });
            return { accepted: false, reason: reason };
        }
        var intent = {
            operationId: acceptance.operationId,
            subjectKind: offer.subjectKind,
            sourceRef: offer.sourceRef || null,
            targetRef: acceptance.targetRef || null,
            hint: acceptance.hint || null,
            origin: origin || 'pointer'
        };
        this._onIntent(intent, { offer: offer, acceptance: acceptance, sourceItem: sourceItem });
        this.clearSelection();
        return { accepted: true, intent: intent };
    };

    InteractionBroker.prototype.activateSelected = function(targetView, targetHit, origin) {
        if (!this._selected) return { accepted: false, reason: 'nothing_selected' };
        return this.dispatch(this._selected.view, this._selected.item, targetView, targetHit, origin || 'click');
    };

    InteractionBroker.prototype.debugState = function() {
        return { selectedInstanceKey: this._selected ? viewKey(this._selected.view) : null };
    };

    InteractionBroker.prototype.isSelectedNode = function(node) {
        return !!this._selected && this._selected.node === node;
    };

    function PointerDragController(options) {
        options = options || {};
        this._sourceElement = options.sourceElement;
        this._getSource = options.getSource;
        this._resolveTarget = options.resolveTarget;
        this._renderGhost = options.renderGhost || null;
        this._onDragStart = options.onDragStart || function() {};
        this._onDragEnd = options.onDragEnd || function() {};
        this._broker = options.broker;
        this._allowInteractiveSource = options.allowInteractiveSource === true;
        this._threshold = Math.max(2, Number(options.threshold) || 5);
        this._timeoutMs = Math.max(50, Number(options.timeoutMs) || 1400);
        this._gesture = null;
        this._suppressedUntil = 0;
        this._boundDown = this._onPointerDown.bind(this);
        this._boundMove = this._onPointerMove.bind(this);
        this._boundUp = this._onPointerUp.bind(this);
        this._boundCancel = this.cancel.bind(this);
        if (this._sourceElement) this._sourceElement.addEventListener('pointerdown', this._boundDown);
    }

    PointerDragController.prototype._onPointerDown = function(event) {
        if (!this._sourceElement || !this._broker || event.button !== 0 || event.isPrimary === false) return;
        if (!this._allowInteractiveSource && event.target && event.target.closest
                && event.target.closest('button,input,textarea,select')) return;
        var source = this._getSource ? this._getSource(event.target, event) : null;
        if (!source || !source.view || !source.item || !source.node) return;
        this.cancel();
        var self = this;
        this._gesture = {
            pointerId: event.pointerId,
            startX: event.clientX,
            startY: event.clientY,
            source: source,
            dragging: false,
            ghost: null,
            target: null,
            captureNode: source.node,
            timer: setTimeout(function() { self.cancel('timeout'); }, this._timeoutMs)
        };
        this._broker.select(source.view, source.item, source.node);
        try { if (source.node.setPointerCapture) source.node.setPointerCapture(event.pointerId); } catch (_) {}
        document.addEventListener('pointermove', this._boundMove);
        document.addEventListener('pointerup', this._boundUp);
        document.addEventListener('pointercancel', this._boundCancel);
    };

    PointerDragController.prototype._onPointerMove = function(event) {
        var gesture = this._gesture;
        if (!gesture || event.pointerId !== gesture.pointerId) return;
        var dx = event.clientX - gesture.startX;
        var dy = event.clientY - gesture.startY;
        if (!gesture.dragging && Math.sqrt(dx * dx + dy * dy) < this._threshold) return;
        if (!gesture.dragging) {
            gesture.dragging = true;
            this._onDragStart(gesture.source);
            gesture.ghost = this._renderGhost ? this._renderGhost(gesture.source) : makeElement('div', 'workbench-drag-ghost');
            if (gesture.ghost) document.body.appendChild(gesture.ghost);
        }
        if (event.preventDefault) event.preventDefault();
        if (gesture.ghost) {
            gesture.ghost.style.left = (event.clientX + 14) + 'px';
            gesture.ghost.style.top = (event.clientY + 14) + 'px';
        }
        var nextTarget = this._resolveTarget ? this._resolveTarget(event.clientX, event.clientY, event) : null;
        if (gesture.target && gesture.target.node && (!nextTarget || nextTarget.node !== gesture.target.node)) {
            gesture.target.node.classList.remove('workbench-drop-active');
            gesture.target.node.classList.remove('workbench-drop-rejected');
        }
        gesture.target = nextTarget;
        if (gesture.target && gesture.target.node) {
            gesture.target.node.classList.remove(gesture.target.accepted === false
                ? 'workbench-drop-active' : 'workbench-drop-rejected');
            gesture.target.node.classList.add(gesture.target.accepted === false
                ? 'workbench-drop-rejected' : 'workbench-drop-active');
        }
    };

    PointerDragController.prototype._onPointerUp = function(event) {
        var gesture = this._gesture;
        if (!gesture || event.pointerId !== gesture.pointerId) return;
        if (gesture.dragging) {
            if (event.preventDefault) event.preventDefault();
            this._suppressedUntil = Date.now() + 80;
            if (gesture.target && gesture.target.view) {
                this._broker.dispatch(gesture.source.view, gesture.source.item, gesture.target.view, gesture.target.hit || {}, 'drag');
            }
        }
        this.cancel('complete');
    };

    PointerDragController.prototype.consumeClick = function() {
        return Date.now() < this._suppressedUntil;
    };

    PointerDragController.prototype.cancel = function() {
        var gesture = this._gesture;
        if (!gesture) return;
        clearTimeout(gesture.timer);
        if (gesture.target && gesture.target.node) {
            gesture.target.node.classList.remove('workbench-drop-active');
            gesture.target.node.classList.remove('workbench-drop-rejected');
        }
        if (gesture.ghost && gesture.ghost.parentNode) gesture.ghost.parentNode.removeChild(gesture.ghost);
        try {
            if (gesture.captureNode && gesture.captureNode.releasePointerCapture) {
                gesture.captureNode.releasePointerCapture(gesture.pointerId);
            }
        } catch (_) {}
        document.removeEventListener('pointermove', this._boundMove);
        document.removeEventListener('pointerup', this._boundUp);
        document.removeEventListener('pointercancel', this._boundCancel);
        this._gesture = null;
        if (gesture.dragging) this._onDragEnd(gesture.source);
    };

    PointerDragController.prototype.destroy = function() {
        this.cancel();
        if (this._sourceElement) this._sourceElement.removeEventListener('pointerdown', this._boundDown);
        this._sourceElement = null;
    };

    PointerDragController.prototype.debugState = function() {
        return {
            active: !!this._gesture,
            dragging: !!(this._gesture && this._gesture.dragging),
            hasGhost: !!(this._gesture && this._gesture.ghost),
            hasTarget: !!(this._gesture && this._gesture.target)
        };
    };

    /** Shared catalog-card presentation primitive. */
    function ItemCard() {}

    function balanceSource(value) {
        if (!value || typeof value !== 'object') return null;
        return Object.prototype.hasOwnProperty.call(value, 'balanceSummary')
            ? value.balanceSummary : value;
    }

    function balanceNumber(value, decimals) {
        var factor = Math.pow(10, decimals);
        var rounded = Math.round(Number(value) * factor) / factor;
        if (rounded === 0) rounded = 0;
        return String(rounded);
    }

    function signedBalanceNumber(value) {
        value = Number(value);
        return (value > 0 ? '+' : '') + balanceNumber(value, 2);
    }

    function normalizeBalanceSummary(value) {
        var summary = balanceSource(value);
        if (!summary || summary.state !== 'confirmed') return null;
        var allowedKeys = {state:true, weightLayers:true, formula:true, level:true};
        var keys = Object.keys(summary);
        if (keys.length !== 4) return null;
        for (var keyIndex = 0; keyIndex < keys.length; keyIndex++) {
            if (!allowedKeys[keys[keyIndex]]) return null;
        }
        var weightLayers = summary.weightLayers;
        if (typeof weightLayers !== 'number' || !isFinite(weightLayers)) return null;
        if (typeof summary.formula !== 'number' || summary.formula !== 1) return null;
        if (typeof summary.level !== 'number' || !isFinite(summary.level)) return null;
        return {
            state: 'confirmed',
            weightLayers: weightLayers === 0 ? 0 : weightLayers,
            formula: 1,
            level: summary.level === 0 ? 0 : summary.level
        };
    }

    function escapeBalanceHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    ItemCard.normalizeBalanceSummary = normalizeBalanceSummary;

    ItemCard.balanceAriaLabel = function(value) {
        var summary = normalizeBalanceSummary(value);
        if (!summary) return '';
        var parts = ['平衡标定已确认'];
        parts.push('等级 ' + balanceNumber(summary.level, 2));
        parts.push('同级加权 ' + signedBalanceNumber(summary.weightLayers));
        return parts.join('，');
    };

    ItemCard.renderBalanceBadge = function(value) {
        var summary = normalizeBalanceSummary(value);
        if (!summary) return null;
        var tone = summary.weightLayers > 0 ? 'positive'
            : summary.weightLayers < 0 ? 'negative' : 'neutral';
        var badge = makeElement('span', 'balance-weight-badge balance-weight-' + tone);
        badge.setAttribute('data-balance-state', 'confirmed');
        badge.setAttribute('data-balance-weight', String(summary.weightLayers));
        badge.setAttribute('aria-label', ItemCard.balanceAriaLabel(summary));
        var level = makeElement('span', 'balance-badge-level');
        level.textContent = 'Lv' + balanceNumber(summary.level, 2);
        badge.appendChild(level);
        var weight = makeElement('span', 'balance-badge-weight');
        weight.textContent = '◆' + signedBalanceNumber(summary.weightLayers);
        badge.appendChild(weight);
        return badge;
    };

    ItemCard.balanceTooltipMetaHtml = function(value) {
        var summary = normalizeBalanceSummary(value);
        if (!summary) return '';
        var aria = ItemCard.balanceAriaLabel(summary);
        var html = '<div class="balance-tooltip-meta" aria-label="' + escapeBalanceHtml(aria) + '">'
            + '<div class="balance-tooltip-summary"><span class="balance-tooltip-caption">同级加权</span>'
            + '<b class="balance-tooltip-weight">◆' + escapeBalanceHtml(signedBalanceNumber(summary.weightLayers)) + '</b>';
        return html + '</div></div>';
    };

    ItemCard.renderCatalog = function(options) {
        options = options || {};
        var skin = options.skin || 'kshop';
        if (skin !== 'kshop' && skin !== 'npcshop') throw new Error('Unsupported ItemCard skin: ' + skin);

        var locked = !!options.locked;
        var selected = !!options.selected;
        var nosale = !!options.nosale;
        var node = makeElement('article', 'item-card item-card-catalog item-card-' + skin);
        node.classList.add(skin === 'kshop' ? 'kshop-card' : 'npcshop-catalog-card');
        node.classList.toggle('item-card-locked', locked);
        node.classList.toggle('item-card-selected', selected);
        node.classList.toggle('item-card-disabled', nosale);

        if (skin === 'kshop') {
            node.classList.toggle('kshop-card-nosale', nosale);
            node.classList.toggle('kshop-card-locked', locked);
            node.setAttribute('data-idx', String(options.id));
            node.setAttribute('tabindex', locked || nosale ? '-1' : '0');
            node.setAttribute('aria-label', options.ariaLabel || '');
        } else {
            node.classList.toggle('locked', locked);
            node.classList.toggle('selected', selected);
            node.setAttribute('data-catalog-index', String(options.id));
            node.setAttribute('aria-pressed', selected ? 'true' : 'false');
            if (locked && options.lockTitle) node.setAttribute('aria-label', options.lockTitle);
        }

        var icon = makeElement(skin === 'kshop' ? 'div' : 'span', 'item-card-icon '
            + (skin === 'kshop' ? 'kshop-card-icon-frame' : 'npcshop-card-icon'));
        icon.innerHTML = options.iconHtml || '';
        var balanceValue = options.balanceSummary != null ? options.balanceSummary : options.item;
        var balanceBadge = ItemCard.renderBalanceBadge(balanceValue);
        if (balanceBadge) icon.appendChild(balanceBadge);
        node.appendChild(icon);

        var body = makeElement(skin === 'kshop' ? 'div' : 'span', 'item-card-body '
            + (skin === 'kshop' ? 'kshop-card-info' : 'npcshop-card-copy'));
        var name = makeElement(skin === 'kshop' ? 'div' : 'b', 'item-card-name'
            + (skin === 'kshop' ? ' kshop-card-name' : ''));
        name.textContent = options.name || '';
        body.appendChild(name);

        var meta;
        var blockedReason = locked
            ? (options.lockReason || options.lockTitle || '尚未解锁')
            : nosale
                ? (options.disabledReason || '当前不可购买')
                : '';
        if (locked || nosale) {
            meta = makeElement(
                skin === 'kshop' ? 'div' : 'small',
                'item-card-meta item-card-lock'
                    + (skin === 'kshop' ? ' kshop-lock' : '')
            );
            meta.textContent = blockedReason;
            meta.setAttribute('aria-label', blockedReason);
            meta.classList.add('item-card-interaction-reason');
        } else {
            meta = makeElement(skin === 'kshop' ? 'div' : 'small', 'item-card-meta'
                + (skin === 'kshop' ? ' kshop-card-type' : ''));
            meta.textContent = options.meta || '';
        }
        body.appendChild(meta);

        var price = makeElement(skin === 'kshop' ? 'div' : 'strong', 'item-card-price'
            + (skin === 'kshop' ? ' kshop-card-price' : ''));
        if (skin === 'kshop' && options.priceLabel) {
            var priceLabel = makeElement('span', 'item-card-price-label');
            priceLabel.textContent = options.priceLabel;
            price.appendChild(priceLabel);
            price.appendChild(document.createTextNode(' '));
        }
        price.appendChild(document.createTextNode(String(options.priceText != null ? options.priceText : options.price || '')));
        body.appendChild(price);
        node.appendChild(body);

        var overlays = makeElement('span', 'item-card-overlays');
        if (skin === 'npcshop') {
            var marker = makeElement('span', 'item-card-auxiliary item-card-selection-marker npcshop-selection-marker');
            marker.textContent = options.markerText || '';
            overlays.appendChild(marker);
        }
        if (options.extraHtml) {
            var extra = makeElement('span', 'item-card-extra');
            extra.innerHTML = options.extraHtml;
            while (extra.firstChild) overlays.appendChild(extra.firstChild);
        }
        node.appendChild(overlays);

        var stateLabel = options.ariaLabel || [
            options.name || '',
            options.priceText != null ? options.priceText : (options.price != null ? options.price : ''),
            blockedReason
        ].filter(function(part) { return part !== ''; }).join('，');
        var balanceAria = ItemCard.balanceAriaLabel(balanceValue);
        if (balanceAria) stateLabel += (stateLabel ? '，' : '') + balanceAria;
        EntityTile.applySemantics(node, {
            itemName: options.name || '',
            label: stateLabel,
            selected: selected,
            inspectable:true,
            actionable:!locked && !nosale,
            reason:blockedReason,
            reasonNode:meta,
            role: 'option'
        });

        return node;
    };

    return {
        EntityTile: EntityTile,
        ItemCard: ItemCard,
        InteractionBroker: InteractionBroker,
        PointerDragController: PointerDragController
    };
});
