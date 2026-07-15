/**
 * Workbench Gate A1 primitives.
 *
 * This module owns layout, view lifecycle, grid rendering and pointer gesture matching only.
 * Domain coordinators are injected by consumers through neutral OperationIntent callbacks.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.Workbench = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function makeElement(tag, className) {
        var element = document.createElement(tag || 'div');
        if (className) element.className = className;
        return element;
    }

    function clearElement(element) {
        while (element && element.firstChild) element.removeChild(element.firstChild);
    }

    function includes(list, value) {
        if (!list) return false;
        for (var i = 0; i < list.length; i++) if (list[i] === value) return true;
        return false;
    }

    function viewKey(view) {
        return view && view.instanceKey ? String(view.instanceKey) : '';
    }

    function isBindingSingleton(view) {
        return !!view && view.instancePolicy === 'singletonByBinding' && !!viewKey(view);
    }

    function WorkbenchViewHost(slotId, shell, root) {
        this.slotId = slotId;
        this.shell = shell;
        this.root = root;
        this.currentView = null;
        this._subscriptionCleanup = null;
    }

    WorkbenchViewHost.prototype.canMount = function(view) {
        if (!view || typeof view.mount !== 'function' || typeof view.unmount !== 'function') return false;
        return !view.allowedSlots || includes(view.allowedSlots, this.slotId);
    };

    WorkbenchViewHost.prototype._detach = function() {
        var previous = this.currentView;
        if (!previous) return null;
        this.currentView = null;
        if (typeof this._subscriptionCleanup === 'function') this._subscriptionCleanup();
        this._subscriptionCleanup = null;
        previous.unmount({ slotId: this.slotId, shell: this.shell, host: this });
        clearElement(this.root);
        this.root.removeAttribute('data-instance-key');
        this.root.removeAttribute('data-view-kind');
        return previous;
    };

    WorkbenchViewHost.prototype._attach = function(view) {
        if (!this.canMount(view)) throw new Error('view cannot mount in slot ' + this.slotId);
        clearElement(this.root);
        this.currentView = view;
        this.root.setAttribute('data-instance-key', viewKey(view));
        this.root.setAttribute('data-view-kind', view.viewKind || 'workbench');
        var context = { slotId: this.slotId, shell: this.shell, host: this };
        view.mount(this.root, context);
        if (typeof view.subscribe === 'function') this._subscriptionCleanup = view.subscribe(context) || null;
        if (typeof view.render === 'function') view.render();
        return view;
    };

    WorkbenchViewHost.prototype.mount = function(view) {
        if (this.currentView === view) {
            if (typeof view.render === 'function') view.render();
            return true;
        }
        if (!this.canMount(view)) return false;
        this._detach();
        this._attach(view);
        return true;
    };

    WorkbenchViewHost.prototype.unmount = function() {
        this._detach();
    };

    function DualPaneShell(options) {
        options = options || {};
        this._views = {};
        this._defaults = { L: null, R: null };
        this._root = makeElement('div', 'workbench-shell');
        this._root.setAttribute('data-workbench-version', '1');

        this._header = makeElement('header', 'workbench-header');
        var identity = makeElement('div', 'workbench-identity');
        this._eyebrow = makeElement('div', 'workbench-eyebrow');
        this._title = makeElement('div', 'workbench-title');
        this._subtitle = makeElement('div', 'workbench-subtitle');
        this._eyebrow.textContent = options.eyebrow == null ? '' : String(options.eyebrow);
        this._title.textContent = options.title || '工作台';
        this._subtitle.textContent = options.subtitle || '';
        identity.appendChild(this._eyebrow);
        identity.appendChild(this._title);
        identity.appendChild(this._subtitle);

        this._status = makeElement('div', 'workbench-status');
        this._status.setAttribute('data-state', 'idle');
        this._status.textContent = options.status || '待命';
        this._status.setAttribute('role', 'status');
        this._status.setAttribute('aria-live', 'polite');
        this._status.setAttribute('aria-label', this._status.textContent);
        this._status.title = this._status.textContent;
        this._metrics = makeElement('div', 'workbench-metrics');
        this._actions = makeElement('div', 'workbench-header-actions');
        this._header.appendChild(identity);
        this._header.appendChild(this._status);
        this._header.appendChild(this._metrics);
        this._header.appendChild(this._actions);

        this._body = makeElement('main', 'workbench-body');
        var left = this._createSlot('L', options.leftLabel || 'SOURCE');
        this._rail = makeElement('div', 'workbench-flow-rail');
        this._rail.innerHTML = '<span class="workbench-flow-arrow">›</span>';
        var flowLabel = options.flowLabel == null ? '' : String(options.flowLabel);
        if (flowLabel) {
            var flowLabelNode = makeElement('span', 'workbench-flow-label');
            flowLabelNode.textContent = flowLabel;
            this._rail.appendChild(flowLabelNode);
        }
        var right = this._createSlot('R', options.rightLabel || 'TARGET');
        this._body.appendChild(left.frame);
        this._body.appendChild(this._rail);
        this._body.appendChild(right.frame);

        this._modalLayer = makeElement('div', 'workbench-modal-layer');
        this._modalLayer.style.display = 'none';
        this._root.appendChild(this._header);
        this._root.appendChild(this._body);
        this._root.appendChild(this._modalLayer);

        this._hosts = {
            L: new WorkbenchViewHost('L', this, left.host),
            R: new WorkbenchViewHost('R', this, right.host)
        };
        this._slotFrames = { L: left.frame, R: right.frame };
        this._activeModal = null;
        this._modalReturnFocus = null;
        this._activeSlot = null;
        var self = this;
        left.frame.addEventListener('pointerdown', function() { self.focusSlot('L'); });
        right.frame.addEventListener('pointerdown', function() { self.focusSlot('R'); });
        left.frame.addEventListener('focusin', function() { self.focusSlot('L'); });
        right.frame.addEventListener('focusin', function() { self.focusSlot('R'); });
        this.focusSlot('L');
    }

    DualPaneShell.prototype._createSlot = function(slotId, label) {
        var frame = makeElement('section', 'workbench-slot');
        frame.setAttribute('data-slot', slotId);
        frame.setAttribute('tabindex', '0');
        frame.setAttribute('aria-label', '工作台栏位 ' + slotId + ' ' + label);
        var marker = makeElement('div', 'workbench-slot-marker');
        marker.innerHTML = '<b>' + slotId + '</b><span></span>';
        marker.querySelector('span').textContent = label;
        var host = makeElement('div', 'workbench-view-host');
        frame.appendChild(marker);
        frame.appendChild(host);
        return { frame: frame, host: host };
    };

    DualPaneShell.prototype.getRoot = function() { return this._root; };
    DualPaneShell.prototype.getHost = function(slotId) { return this._hosts[slotId] || null; };
    DualPaneShell.prototype.getSlotFrame = function(slotId) { return this._slotFrames[slotId] || null; };

    DualPaneShell.prototype.setSlotLabel = function(slotId, label) {
        var frame = this._slotFrames[slotId];
        if (!frame) return false;
        var text = String(label || '');
        var marker = frame.querySelector('.workbench-slot-marker span');
        if (marker) marker.textContent = text;
        frame.setAttribute('aria-label', '工作台栏位 ' + slotId + ' ' + text);
        return true;
    };

    DualPaneShell.prototype.focusSlot = function(slotId) {
        if (!this._slotFrames[slotId] || this._activeSlot === slotId) return false;
        var previousId = this._activeSlot;
        var previousView = previousId && this._hosts[previousId] ? this._hosts[previousId].currentView : null;
        if (previousId) this._slotFrames[previousId].classList.remove('active');
        this._activeSlot = slotId;
        this._root.setAttribute('data-active-slot', slotId);
        this._slotFrames[slotId].classList.add('active');
        if (previousView && typeof previousView.onBlur === 'function') previousView.onBlur({ slotId: previousId, shell: this });
        var nextView = this._hosts[slotId] ? this._hosts[slotId].currentView : null;
        if (nextView && typeof nextView.onFocus === 'function') nextView.onFocus({ slotId: slotId, shell: this });
        return true;
    };

    DualPaneShell.prototype.getActiveSlot = function() { return this._activeSlot; };

    DualPaneShell.prototype.setTitle = function(title, subtitle) {
        this._title.textContent = title || '';
        this._subtitle.textContent = subtitle || '';
    };

    DualPaneShell.prototype.setStatus = function(text, state) {
        var label = text || '';
        this._status.textContent = label;
        this._status.setAttribute('data-state', state || 'idle');
        this._status.setAttribute('aria-label', label);
        this._status.title = label;
    };

    DualPaneShell.prototype.setMetric = function(key, label, value) {
        key = String(key || 'metric');
        var metric = this._metrics.querySelector('[data-metric="' + key.replace(/"/g, '') + '"]');
        if (!metric) {
            metric = makeElement('div', 'workbench-metric');
            metric.setAttribute('data-metric', key);
            metric.innerHTML = '<span></span><b></b>';
            this._metrics.appendChild(metric);
        }
        metric.querySelector('span').textContent = label || '';
        metric.querySelector('b').textContent = value == null ? '' : String(value);
        return metric.querySelector('b');
    };

    DualPaneShell.prototype.addHeaderAction = function(element) {
        if (element) this._actions.appendChild(element);
    };

    DualPaneShell.prototype.registerView = function(view) {
        var key = viewKey(view);
        if (!key) throw new Error('workbench view requires instanceKey');
        if (this._views[key] && this._views[key] !== view) throw new Error('duplicate workbench instanceKey: ' + key);
        this._views[key] = view;
        return view;
    };

    DualPaneShell.prototype.setDefault = function(slotId, view) {
        if (!this._hosts[slotId] || !this._hosts[slotId].canMount(view)) return false;
        this.registerView(view);
        this._defaults[slotId] = view;
        return true;
    };

    DualPaneShell.prototype.mountInitial = function(leftView, rightView) {
        if (!this._hosts.L.canMount(leftView) || !this._hosts.R.canMount(rightView)) return false;
        if (isBindingSingleton(leftView) && isBindingSingleton(rightView) && viewKey(leftView) === viewKey(rightView)) return false;
        this.registerView(leftView);
        this.registerView(rightView);
        this._hosts.L.mount(leftView);
        this._hosts.R.mount(rightView);
        this.focusSlot('L');
        return true;
    };

    DualPaneShell.prototype.moveView = function(slotId, view) {
        var target = this._hosts[slotId];
        var otherId = slotId === 'L' ? 'R' : 'L';
        var other = this._hosts[otherId];
        if (!target || !target.canMount(view)) return false;
        this.registerView(view);

        var conflicts = isBindingSingleton(view)
            && other.currentView
            && viewKey(other.currentView) === viewKey(view);
        if (!conflicts) {
            var mounted = target.mount(view);
            if (mounted) this.focusSlot(slotId);
            return mounted;
        }

        var oldTarget = target.currentView;
        var oldOther = other.currentView;
        var fallback = oldTarget && other.canMount(oldTarget) ? oldTarget : this._defaults[otherId];
        if (!fallback || !other.canMount(fallback)) return false;
        if (isBindingSingleton(fallback) && viewKey(fallback) === viewKey(view)) return false;

        target._detach();
        other._detach();
        try {
            target._attach(view);
            other._attach(fallback);
            this.focusSlot(slotId);
            return true;
        } catch (error) {
            target._detach();
            other._detach();
            if (oldTarget) target._attach(oldTarget);
            if (oldOther) other._attach(oldOther);
            return false;
        }
    };

    DualPaneShell.prototype.openModal = function(spec) {
        spec = spec || {};
        this.closeModal();
        this._modalReturnFocus = document.activeElement;
        var backdrop = makeElement('div', 'workbench-modal-backdrop');
        var dialog = makeElement('section', 'workbench-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('data-modal-kind', spec.kind || 'notice');
        var kicker = makeElement('div', 'workbench-modal-kicker');
        kicker.textContent = spec.kicker == null ? '' : String(spec.kicker);
        var title = makeElement('h2', 'workbench-modal-title');
        title.textContent = spec.title || '';
        var message = makeElement('div', 'workbench-modal-message');
        message.textContent = spec.message || '';
        var detail = makeElement('div', 'workbench-modal-detail');
        detail.textContent = spec.detail || '';
        var actions = makeElement('div', 'workbench-modal-actions');
        var self = this;
        var list = spec.actions || [];
        for (var i = 0; i < list.length; i++) {
            (function(action) {
                var button = makeElement('button', 'workbench-modal-action' + (action.primary ? ' primary' : '') + (action.danger ? ' danger' : ''));
                button.type = 'button';
                button.textContent = action.label || action.id;
                button.setAttribute('data-action', action.id || 'action');
                if (action.audioCue) button.setAttribute('data-audio-cue', action.audioCue);
                button.addEventListener('click', function() {
                    if (action.close !== false) self.closeModal();
                    if (typeof action.onSelect === 'function') action.onSelect();
                });
                actions.appendChild(button);
            })(list[i]);
        }
        dialog.appendChild(kicker);
        dialog.appendChild(title);
        if (spec.message) dialog.appendChild(message);
        if (spec.detail) dialog.appendChild(detail);
        dialog.appendChild(actions);
        backdrop.appendChild(dialog);
        this._modalLayer.appendChild(backdrop);
        this._modalLayer.style.display = '';
        this._activeModal = { backdrop: backdrop, dialog: dialog, spec: spec };
        var focusTarget = dialog.querySelector('.workbench-modal-action.primary') || dialog.querySelector('.workbench-modal-action');
        if (focusTarget && focusTarget.focus) focusTarget.focus();
        return this._activeModal;
    };

    DualPaneShell.prototype.closeModal = function() {
        var returnFocus = this._modalReturnFocus;
        clearElement(this._modalLayer);
        this._modalLayer.style.display = 'none';
        this._activeModal = null;
        this._modalReturnFocus = null;
        if (returnFocus && document.documentElement.contains(returnFocus) && returnFocus.focus) returnFocus.focus();
    };

    DualPaneShell.prototype.hasModal = function() { return !!this._activeModal; };
    DualPaneShell.prototype.getModalKind = function() {
        return this._activeModal && this._activeModal.spec ? this._activeModal.spec.kind || 'notice' : null;
    };

    DualPaneShell.prototype.destroy = function() {
        this.closeModal();
        this._hosts.L.unmount();
        this._hosts.R.unmount();
        this._views = {};
    };

    function ViewChrome(options) {
        options = options || {};
        this.root = makeElement('div', 'workbench-view-chrome');
        var heading = makeElement('div', 'workbench-view-heading');
        this.kicker = makeElement('div', 'workbench-view-kicker');
        this.titleRow = makeElement('div', 'workbench-view-title-row');
        this.title = makeElement('div', 'workbench-view-title');
        this.breadcrumbHost = makeElement('div', 'workbench-view-breadcrumb-host');
        this.breadcrumbHost.hidden = true;
        this.meta = makeElement('div', 'workbench-view-meta');
        this.toolbar = makeElement('div', 'workbench-view-toolbar');
        this.kicker.textContent = options.kicker || '';
        this.title.textContent = options.title || '';
        this.meta.textContent = options.meta || '';
        heading.appendChild(this.kicker);
        this.titleRow.appendChild(this.title);
        this.titleRow.appendChild(this.breadcrumbHost);
        heading.appendChild(this.titleRow);
        this.root.appendChild(heading);
        this.root.appendChild(this.meta);
        this.root.appendChild(this.toolbar);
    }

    ViewChrome.prototype.setTitle = function(title, kicker) {
        this.title.textContent = title || '';
        if (kicker != null) this.kicker.textContent = kicker;
    };
    ViewChrome.prototype.setMeta = function(meta) { this.meta.textContent = meta || ''; };
    ViewChrome.prototype.setToolbar = function(node) {
        clearElement(this.toolbar);
        if (node) this.toolbar.appendChild(node);
    };

    function GridRenderer(options) {
        options = options || {};
        this.options = options;
        this.root = makeElement('div', 'workbench-grid-renderer' + (options.className ? ' ' + options.className : ''));
        this.root.setAttribute('data-grid-renderer', '1');
        this._items = [];
        this._selectedKey = null;
    }

    GridRenderer.prototype.render = function(items) {
        this._items = (items || []).slice();
        clearElement(this.root);
        if (!this._items.length) {
            var empty = makeElement('div', 'workbench-grid-empty');
            empty.textContent = this.options.emptyText || '暂无项目';
            this.root.appendChild(empty);
            return;
        }
        var fragment = document.createDocumentFragment();
        for (var i = 0; i < this._items.length; i++) {
            var item = this._items[i];
            var node = this.options.renderItem ? this.options.renderItem(item, i) : makeElement('div');
            if (!node || node.nodeType !== 1) throw new Error('GridRenderer.renderItem must return an Element');
            node.setAttribute('data-workbench-item', String(i));
            node.__workbenchItem = item;
            node.__workbenchIndex = i;
            var key = this.options.keyOf ? String(this.options.keyOf(item, i)) : String(i);
            node.setAttribute('data-workbench-key', key);
            if (this._selectedKey != null && key === this._selectedKey) node.classList.add('workbench-source-selected');
            if (typeof this.options.bindItem === 'function') this.options.bindItem(node, item, i);
            fragment.appendChild(node);
        }
        this.root.appendChild(fragment);
    };

    GridRenderer.prototype.findItemNode = function(target) {
        var node = target && target.closest ? target.closest('[data-workbench-item]') : null;
        return node && this.root.contains(node) ? node : null;
    };

    GridRenderer.prototype.itemFromTarget = function(target) {
        var node = this.findItemNode(target);
        return node ? { item: node.__workbenchItem, index: node.__workbenchIndex, node: node } : null;
    };

    GridRenderer.prototype.itemAtPoint = function(clientX, clientY) {
        var target = document.elementFromPoint(clientX, clientY);
        return this.itemFromTarget(target);
    };

    GridRenderer.prototype.setSelectedKey = function(key) {
        this._selectedKey = key == null ? null : String(key);
        var nodes = this.root.querySelectorAll('[data-workbench-key]');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].classList.toggle('workbench-source-selected', this._selectedKey != null && nodes[i].getAttribute('data-workbench-key') === this._selectedKey);
        }
    };

    GridRenderer.prototype.destroy = function() {
        clearElement(this.root);
        this._items = [];
        this._selectedKey = null;
    };

    function ContainerViewAdapter(options) {
        options = options || {};
        this.instanceKey = options.instanceKey || '';
        this.instancePolicy = options.instancePolicy || 'singletonByBinding';
        this.itemModel = options.itemModel || 'owned';
        this.getItems = options.getItems || function() { return []; };
        this.renderItem = options.renderItem || function() { return makeElement('div'); };
        this.bindItem = options.bindItem || null;
        this.keyOf = options.keyOf || null;
        this.exportOfferHandler = options.exportOffer || null;
        this.probeAcceptHandler = options.probeAccept || null;
    }

    ContainerViewAdapter.prototype.items = function() { return this.getItems() || []; };
    ContainerViewAdapter.prototype.exportOffer = function(item, hit) {
        return this.exportOfferHandler ? this.exportOfferHandler(item, hit) : null;
    };
    ContainerViewAdapter.prototype.probeAccept = function(offer, hit) {
        return this.probeAcceptHandler ? this.probeAcceptHandler(offer, hit) : { accepted: false, reason: 'unsupported' };
    };

    function GridContainerView(options) {
        options = options || {};
        this.adapter = options.adapter;
        if (!this.adapter) throw new Error('GridContainerView requires adapter');
        this.instanceKey = options.instanceKey || this.adapter.instanceKey;
        this.instancePolicy = options.instancePolicy || this.adapter.instancePolicy;
        this.allowedSlots = options.allowedSlots || null;
        this.viewKind = options.viewKind || 'grid-container';
        this.root = makeElement('div', 'workbench-view workbench-grid-container' + (options.className ? ' ' + options.className : ''));
        this.root.setAttribute('data-item-model', this.adapter.itemModel);
        this.chrome = new ViewChrome({ kicker: options.kicker, title: options.title, meta: options.meta });
        this.renderer = new GridRenderer({
            className: options.gridClassName || '',
            emptyText: options.emptyText,
            renderItem: this.adapter.renderItem,
            bindItem: this.adapter.bindItem,
            keyOf: this.adapter.keyOf
        });
        this.root.appendChild(this.chrome.root);
        this.root.appendChild(this.renderer.root);
        this._mounted = false;
    }

    GridContainerView.prototype.mount = function(container) {
        container.appendChild(this.root);
        this._mounted = true;
    };
    GridContainerView.prototype.unmount = function() {
        if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
        this._mounted = false;
    };
    GridContainerView.prototype.render = function() {
        this.renderer.render(this.adapter.items());
    };
    GridContainerView.prototype.exportOffer = function(item, hit) { return this.adapter.exportOffer(item, hit); };
    GridContainerView.prototype.probeAccept = function(offer, hit) { return this.adapter.probeAccept(offer, hit); };

    function InteractionBroker(options) {
        options = options || {};
        this._onIntent = options.onIntent || function() {};
        this._onReject = options.onReject || function() {};
        this._onSelectionChange = options.onSelectionChange || function() {};
        this._selected = null;
    }

    InteractionBroker.prototype.select = function(view, item, node) {
        if (this._selected && this._selected.node) this._selected.node.classList.remove('workbench-source-selected');
        this._selected = view && item ? { view: view, item: item, node: node || null } : null;
        if (this._selected && this._selected.node) this._selected.node.classList.add('workbench-source-selected');
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

    function PointerDragController(options) {
        options = options || {};
        this._sourceElement = options.sourceElement;
        this._getSource = options.getSource;
        this._resolveTarget = options.resolveTarget;
        this._renderGhost = options.renderGhost || null;
        this._onDragStart = options.onDragStart || function() {};
        this._onDragEnd = options.onDragEnd || function() {};
        this._broker = options.broker;
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
        if (event.target && event.target.closest && event.target.closest('button,input,textarea,select')) return;
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
            if (gesture.captureNode && gesture.captureNode.releasePointerCapture)
                gesture.captureNode.releasePointerCapture(gesture.pointerId);
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

    function escapeHtml(s) {
        return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    /**
     * Shared item card primitive. Every catalog card uses the same semantic
     * shell (icon/body/name/meta/price/overlays); legacy skin class names stay
     * attached as compatibility tokens while panel CSS migrates gradually.
     */
    function ItemCard() {}

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
            if (locked && options.lockTitle) node.title = options.lockTitle;
        }

        var icon = makeElement(skin === 'kshop' ? 'div' : 'span', 'item-card-icon '
            + (skin === 'kshop' ? 'kshop-card-icon-frame' : 'npcshop-card-icon'));
        icon.innerHTML = options.iconHtml || '';
        node.appendChild(icon);

        var body = makeElement(skin === 'kshop' ? 'div' : 'span', 'item-card-body '
            + (skin === 'kshop' ? 'kshop-card-info' : 'npcshop-card-copy'));
        var name = makeElement(skin === 'kshop' ? 'div' : 'b', 'item-card-name'
            + (skin === 'kshop' ? ' kshop-card-name' : ''));
        name.textContent = options.name || '';
        body.appendChild(name);

        var meta;
        if (locked && skin === 'kshop') {
            meta = makeElement('div', 'item-card-meta item-card-lock kshop-lock');
            meta.textContent = options.lockReason || '';
            meta.title = options.lockReason || '';
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

        return node;
    };

    /**
     * Shared item grid primitive. Wraps GridContainerView/ContainerViewAdapter
     * and adds layoutMode support (full/compact) by toggling the
     * `item-grid-compact` class on the grid root. Panels can persist the mode
     * per panel id through localStorage.
     */
    function ItemGrid(options) {
        options = options || {};
        this.layoutMode = options.layoutMode || 'full';
        this._gridClassName = options.gridClassName || '';

        var adapter = new ContainerViewAdapter({
            instanceKey: options.instanceKey,
            instancePolicy: options.instancePolicy,
            itemModel: options.itemModel || 'owned',
            getItems: options.getItems || function() { return []; },
            keyOf: options.keyOf || null,
            renderItem: options.renderItem || function() { return makeElement('div'); },
            bindItem: options.bindItem || null,
            exportOffer: options.exportOffer || null,
            probeAccept: options.probeAccept || null
        });
        this.adapter = adapter;

        this.view = new GridContainerView({
            adapter: adapter,
            title: options.title,
            kicker: options.kicker,
            meta: options.meta,
            className: options.className,
            gridClassName: this._effectiveGridClassName(),
            emptyText: options.emptyText,
            allowedSlots: options.allowedSlots
        });
        this.view.viewKind = options.viewKind || this.view.viewKind;
        if (options.toolbar) this.view.chrome.setToolbar(options.toolbar);

        this.renderer = this.view.renderer;
        this.root = this.view.root;
        this.chrome = this.view.chrome;
        this.view.itemGrid = this;
        if (options.densityController && typeof options.densityController.register === 'function') {
            options.densityController.register(this);
        }
    }

    ItemGrid.prototype._effectiveGridClassName = function() {
        return this._gridClassName + (this.layoutMode === 'compact' ? ' item-grid-compact' : '');
    };

    ItemGrid.prototype.setLayoutMode = function(mode) {
        if (mode !== 'full' && mode !== 'compact') return false;
        if (this.layoutMode === mode) return false;
        this.layoutMode = mode;
        this.renderer.root.classList.toggle('item-grid-compact', mode === 'compact');
        return true;
    };

    ItemGrid.prototype.render = function() {
        this.view.render();
    };

    ItemGrid.getLayoutMode = function(panelId) {
        try {
            var v = window.localStorage.getItem('cf7.itemgrid.mode.' + panelId);
            if (v === 'compact' || v === 'full') return v;
        } catch (e) {}
        return 'full';
    };

    ItemGrid.setLayoutMode = function(panelId, mode) {
        try { window.localStorage.setItem('cf7.itemgrid.mode.' + panelId, mode); } catch (e) {}
    };

    ItemGrid.createToggle = function(panelId, currentMode, callback) {
        currentMode = currentMode === 'compact' ? 'compact' : 'full';
        var group = makeElement('div', 'item-grid-mode-switch item-grid-mode-toggle');
        group.setAttribute('role', 'group');
        group.setAttribute('aria-label', '物品格布局');

        var label = makeElement('span', 'item-grid-mode-label');
        label.textContent = '布局';
        group.appendChild(label);

        var buttons = {};
        function updateSelection(mode) {
            currentMode = mode;
            group.setAttribute('data-layout-mode', mode);
            for (var key in buttons) {
                var active = key === mode;
                buttons[key].classList.toggle('active', active);
                buttons[key].setAttribute('aria-pressed', active ? 'true' : 'false');
            }
        }

        function addOption(mode, text, title) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'workbench-mode-btn item-grid-mode-option';
            button.setAttribute('data-layout-mode', mode);
            button.textContent = text;
            button.title = title;
            button.addEventListener('click', function() {
                if (mode === currentMode) return;
                ItemGrid.setLayoutMode(panelId, mode);
                updateSelection(mode);
                if (typeof callback === 'function') callback(mode);
            });
            buttons[mode] = button;
            group.appendChild(button);
        }

        addOption('full', '完整', '显示名称、价格与物品状态');
        addOption('compact', '紧凑', '使用完整图标瓦片，一屏查看更多物品');
        updateSelection(currentMode);
        return group;
    };

    /**
     * One density state for every grid owned by a panel. Targets may be an
     * ItemGrid, GridRenderer, view, or raw grid element. Registering a target
     * immediately applies the current mode, so late-created subviews stay in
     * sync without panel-specific applyLayoutMode loops.
     */
    function GridDensityController(options) {
        options = options || {};
        this.panelId = String(options.panelId || 'default');
        this.compactClass = String(options.compactClass || 'item-grid-compact');
        this.mode = options.mode === 'compact' || options.mode === 'full'
            ? options.mode : ItemGrid.getLayoutMode(this.panelId);
        this._targets = [];
        this._listeners = [];
    }

    GridDensityController.prototype._elementOf = function(target) {
        if (!target) return null;
        if (target instanceof ItemGrid) return target.renderer && target.renderer.root;
        if (target.renderer && target.renderer.root) return target.renderer.root;
        if (target.root && target.root.classList) return target.root;
        return target.classList ? target : null;
    };

    GridDensityController.prototype.register = function(target) {
        var element = this._elementOf(target);
        if (!element) return false;
        for (var i = 0; i < this._targets.length; i++) if (this._targets[i] === target) return true;
        this._targets.push(target);
        if (target instanceof ItemGrid) target.setLayoutMode(this.mode);
        else element.classList.toggle(this.compactClass, this.mode === 'compact');
        return true;
    };

    GridDensityController.prototype.unregister = function(target) {
        for (var i = this._targets.length - 1; i >= 0; i--) {
            if (this._targets[i] === target) this._targets.splice(i, 1);
        }
    };

    GridDensityController.prototype.setMode = function(mode) {
        if (mode !== 'full' && mode !== 'compact') return false;
        var changed = this.mode !== mode;
        this.mode = mode;
        ItemGrid.setLayoutMode(this.panelId, mode);
        for (var i = 0; i < this._targets.length; i++) {
            var target = this._targets[i];
            var element = this._elementOf(target);
            if (!element) continue;
            if (target instanceof ItemGrid) target.setLayoutMode(mode);
            else element.classList.toggle(this.compactClass, mode === 'compact');
        }
        if (changed) {
            for (i = 0; i < this._listeners.length; i++) this._listeners[i](mode);
        }
        return changed;
    };

    GridDensityController.prototype.createToggle = function(callback) {
        var self = this;
        return ItemGrid.createToggle(this.panelId, this.mode, function(mode) {
            self.setMode(mode);
            if (typeof callback === 'function') callback(mode);
        });
    };

    GridDensityController.prototype.subscribe = function(listener) {
        if (typeof listener !== 'function') return function() {};
        var self = this;
        this._listeners.push(listener);
        return function() {
            var index = self._listeners.indexOf(listener);
            if (index >= 0) self._listeners.splice(index, 1);
        };
    };

    GridDensityController.prototype.destroy = function() {
        this._targets = [];
        this._listeners = [];
    };

    return {
        contractStatus: function() {
            return {
                shell: 'gate-a1-accepted',
                viewHost: 'gate-a1-accepted',
                grid: 'gate-a1-accepted',
                pointerGesture: 'gate-a1-accepted',
                interactionBroker: 'gate-a2-accepted',
                ownedTransfer: 'gate-a2-accepted',
                warehouseWindow: 'gate-a3-candidate'
            };
        },
        DualPaneShell: DualPaneShell,
        WorkbenchViewHost: WorkbenchViewHost,
        ViewChrome: ViewChrome,
        GridRenderer: GridRenderer,
        ContainerViewAdapter: ContainerViewAdapter,
        GridContainerView: GridContainerView,
        InteractionBroker: InteractionBroker,
        PointerDragController: PointerDragController,
        ItemCard: ItemCard,
        ItemGrid: ItemGrid,
        GridDensityController: GridDensityController
    };
});
