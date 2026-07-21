/**
 * Workbench Gate A1 primitives.
 *
 * This module owns layout, view lifecycle, grid rendering and pointer gesture matching only.
 * Domain coordinators are injected by consumers through neutral OperationIntent callbacks.
 */
(function(root, factory) {
    'use strict';
    var primitives = root && root.WorkbenchPrimitives;
    var focus = root && (root.WorkbenchFocus || root.CF7 && root.CF7.WorkbenchFocus);
    if (!primitives && typeof module !== 'undefined' && module.exports) {
        primitives = require('./workbench-primitives.js');
    }
    if (!focus && typeof module !== 'undefined' && module.exports) {
        focus = require('./workbench-focus.js');
    }
    if (!primitives) {
        throw new Error('workbench.js requires workbench-primitives.js to load first');
    }
    if (!focus || typeof focus.FocusScope !== 'function') {
        throw new Error('workbench.js requires workbench-focus.js to load first');
    }
    var api = factory(primitives, focus);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.Workbench = api;
})(typeof window !== 'undefined' ? window : globalThis, function(WorkbenchPrimitives, WorkbenchFocus) {
    'use strict';
    var primitiveNames = ['EntityTile', 'ItemCard', 'InteractionBroker', 'PointerDragController'];
    for (var primitiveIndex = 0; primitiveIndex < primitiveNames.length; primitiveIndex++) {
        if (typeof WorkbenchPrimitives[primitiveNames[primitiveIndex]] !== 'function') {
            throw new Error('workbench-primitives.js missing ' + primitiveNames[primitiveIndex]);
        }
    }
    var EntityTile = WorkbenchPrimitives.EntityTile;
    var ItemCard = WorkbenchPrimitives.ItemCard;
    var InteractionBroker = WorkbenchPrimitives.InteractionBroker;
    var PointerDragController = WorkbenchPrimitives.PointerDragController;
    var FocusScope = WorkbenchFocus.FocusScope;
    var ENTITY_FOCUS_SELECTOR = 'button,a[href],input,select,textarea,[tabindex],[contenteditable="true"]';

    function makeElement(tag, className) {
        var element = document.createElement(tag || 'div');
        if (className) element.className = className;
        return element;
    }

    function releaseElementBindings(element) {
        if (!element) return;
        var nodes = [element].concat(element.querySelectorAll
            ? Array.prototype.slice.call(element.querySelectorAll('*')) : []);
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (node.__panelTooltipBinding && typeof node.__panelTooltipBinding.destroy === 'function') node.__panelTooltipBinding.destroy();
            if (node.__workbenchEntityTileBinding
                    && typeof node.__workbenchEntityTileBinding.destroy === 'function') node.__workbenchEntityTileBinding.destroy();
        }
    }

    function clearElement(element) {
        if (!element) return;
        // Re-rendering a grid is also a lifecycle boundary. Explicitly release
        // shared tile/tooltip bindings before detaching nodes so pending async
        // callbacks cannot retain an obsolete entity tree until timeout.
        releaseElementBindings(element);
        while (element && element.firstChild) element.removeChild(element.firstChild);
    }

    function includes(list, value) {
        if (!list) return false;
        for (var i = 0; i < list.length; i++) if (list[i] === value) return true;
        return false;
    }

    /**
     * 工作台状态机统一枚举。
     * 旧代码中的 'busy' 视为 'loading' 的遗留同义词，仍被接受但建议逐步迁移。
     */
    var WorkbenchState = {
        IDLE: 'idle',
        LOADING: 'loading',
        READY: 'ready',
        PENDING: 'pending',
        WARNING: 'warning',
        ERROR: 'error',
        DISCONNECTED: 'disconnected',
        // 遗留同义词
        BUSY: 'busy'
    };
    var _validStates = [
        WorkbenchState.IDLE, WorkbenchState.LOADING, WorkbenchState.READY,
        WorkbenchState.PENDING, WorkbenchState.WARNING, WorkbenchState.ERROR,
        WorkbenchState.DISCONNECTED, WorkbenchState.BUSY
    ];
    function normalizeState(state) {
        if (!state) return WorkbenchState.IDLE;
        if (includes(_validStates, state)) return state;
        return WorkbenchState.IDLE;
    }

    function viewKey(view) {
        return view && view.instanceKey ? String(view.instanceKey) : '';
    }

    function isBindingSingleton(view) {
        return !!view && view.instancePolicy === 'singletonByBinding' && !!viewKey(view);
    }

    var _modalIdSequence = 0;

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
        this._status.setAttribute('data-state', WorkbenchState.IDLE);
        this._status.textContent = options.status || '待命';
        this._status.setAttribute('role', 'status');
        this._status.setAttribute('aria-live', 'polite');
        this._status.setAttribute('aria-label', this._status.textContent);
        this._metrics = makeElement('div', 'workbench-metrics');
        this._actions = makeElement('div', 'workbench-header-actions');
        this._header.appendChild(identity);
        this._header.appendChild(this._status);
        this._header.appendChild(this._metrics);
        this._header.appendChild(this._actions);

        this._body = makeElement('main', 'workbench-body');
        var left = this._createSlot('L', options.leftLabel || 'SOURCE');
        this._rail = makeElement('div', 'workbench-flow-rail');
        this._rail.setAttribute('data-state', 'idle');
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
        this._activeSlot = null;
        this._destroyed = false;
        this._destroying = false;
        this._modalGeneration = 0;
        this._slotListeners = [];
        var self = this;
        this._slotListeners = [
            [left.frame, 'pointerdown', function() { self.focusSlot('L'); }],
            [right.frame, 'pointerdown', function() { self.focusSlot('R'); }],
            [left.frame, 'focusin', function() { self.focusSlot('L'); }],
            [right.frame, 'focusin', function() { self.focusSlot('R'); }]
        ];
        for (var listenerIndex = 0; listenerIndex < this._slotListeners.length; listenerIndex++) {
            var listener = this._slotListeners[listenerIndex];
            listener[0].addEventListener(listener[1], listener[2]);
        }
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
        if (this._destroyed || !this._slotFrames[slotId] || this._activeSlot === slotId) return false;
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
        var normalized = normalizeState(state);
        this._status.textContent = label;
        this._status.setAttribute('data-state', normalized);
        this._status.setAttribute('aria-label', label);
        if (normalized === WorkbenchState.LOADING || normalized === WorkbenchState.PENDING
                || normalized === WorkbenchState.BUSY) this.setFlowState('pending');
        else if (this._rail.getAttribute('data-state') === 'pending') this.setFlowState('idle');
    };

    DualPaneShell.prototype.setFlowState = function(state) {
        state = state === 'accept' || state === 'reject' || state === 'pending' ? state : 'idle';
        this._rail.setAttribute('data-state', state);
        return state;
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
        if (this._destroyed || this._destroying) return null;
        spec = spec || {};
        var generation = ++this._modalGeneration;
        var returnFocus = this._activeModal ? this._activeModal.opener : document.activeElement;
        this._closeModal('replace', false);
        if (this._destroyed || this._destroying || generation !== this._modalGeneration) {
            return this._activeModal;
        }
        var modalId = 'workbench-modal-' + (++_modalIdSequence);
        var backdrop = makeElement('div', 'workbench-modal-backdrop');
        var dialog = makeElement('section', 'workbench-modal');
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('data-modal-kind', spec.kind || 'notice');
        dialog.setAttribute('tabindex', '-1');
        var kicker = makeElement('div', 'workbench-modal-kicker');
        kicker.textContent = spec.kicker == null ? '' : String(spec.kicker);
        var title = makeElement('h2', 'workbench-modal-title');
        title.id = modalId + '-title';
        title.textContent = spec.title || '';
        var message = makeElement('div', 'workbench-modal-message');
        message.id = modalId + '-message';
        message.textContent = spec.message || '';
        var detail = makeElement('div', 'workbench-modal-detail');
        detail.id = modalId + '-detail';
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
                button.disabled = !!action.disabled;
                button.addEventListener('click', function() {
                    if (action.close !== false) self.closeModal('action:' + (action.id || 'action'));
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
        dialog.setAttribute('aria-labelledby', spec.labelledBy || spec.ariaLabelledBy || title.id);
        var describedBy = [];
        if (spec.describedBy || spec.ariaDescribedBy) {
            describedBy.push(String(spec.describedBy || spec.ariaDescribedBy));
        }
        if (spec.message) describedBy.push(message.id);
        if (spec.detail) describedBy.push(detail.id);
        if (describedBy.length) dialog.setAttribute('aria-describedby', describedBy.join(' '));
        backdrop.appendChild(dialog);
        this._modalLayer.appendChild(backdrop);
        this._modalLayer.style.display = '';
        var activeModal = {
            backdrop: backdrop,
            dialog: dialog,
            spec: spec,
            opener: returnFocus,
            generation: generation,
            focusScope: null,
            backdropHandler: null,
            closed: false
        };
        this._activeModal = activeModal;
        activeModal.backdropHandler = function(event) {
            if (event.target !== backdrop || spec.closeOnBackdrop === false) return;
            self.closeModal('backdrop');
        };
        backdrop.addEventListener('click', activeModal.backdropHandler);

        var focusTarget = null;
        if (spec.initialFocus && spec.initialFocus.nodeType === 1) focusTarget = spec.initialFocus;
        else if (typeof spec.initialFocus === 'string') focusTarget = dialog.querySelector(spec.initialFocus);
        focusTarget = focusTarget || dialog.querySelector('.workbench-modal-action.primary')
            || dialog.querySelector('.workbench-modal-action') || dialog;
        activeModal.focusScope = new FocusScope({
            root: dialog,
            document: document,
            restoreFocus: false,
            onEscape: function() {
                if (spec.closeOnEscape === false) return false;
                self.closeModal('escape');
                return false;
            }
        });
        try {
            activeModal.focusScope.activate({
                opener: returnFocus,
                initialFocus: focusTarget,
                underlay:Array.prototype.filter.call(this._root.children,
                    function(node) { return node !== self._modalLayer; })
            });
        } catch (error) {
            if (this._activeModal === activeModal) this._closeModal('open-error', false);
            throw error;
        }
        return this._activeModal;
    };

    DualPaneShell.prototype._closeModal = function(reason, restoreFocus) {
        var activeModal = this._activeModal;
        if (!activeModal || activeModal.closed) return false;
        activeModal.closed = true;
        if (this._activeModal === activeModal) this._activeModal = null;
        var returnFocus = activeModal.opener;
        var firstError = null;
        if (activeModal.backdrop && activeModal.backdropHandler) {
            activeModal.backdrop.removeEventListener('click', activeModal.backdropHandler);
        }
        if (activeModal.focusScope) {
            try { activeModal.focusScope.deactivate(reason || 'close', {restoreFocus:false}); }
            catch (focusError) { firstError = focusError; }
            try { activeModal.focusScope.destroy(); }
            catch (destroyError) { if (!firstError) firstError = destroyError; }
        }
        if (activeModal.backdrop && activeModal.backdrop.parentNode === this._modalLayer) {
            try {
                clearElement(activeModal.backdrop);
                this._modalLayer.removeChild(activeModal.backdrop);
            } catch (removeError) { if (!firstError) firstError = removeError; }
        }
        if (!this._modalLayer.firstChild) this._modalLayer.style.display = 'none';
        if (restoreFocus !== false && returnFocus && document.documentElement.contains(returnFocus) && returnFocus.focus) {
            try { returnFocus.focus(); } catch (returnError) { if (!firstError) firstError = returnError; }
        }
        try {
            if (typeof activeModal.spec.onClose === 'function') activeModal.spec.onClose(reason || 'close');
        } catch (closeError) { if (!firstError) firstError = closeError; }
        if (firstError) throw firstError;
        return true;
    };

    DualPaneShell.prototype.closeModal = function(reason) {
        if (this._destroyed || this._destroying) return false;
        this._modalGeneration++;
        return this._closeModal(reason || 'close', true);
    };

    DualPaneShell.prototype.hasModal = function() { return !!this._activeModal; };
    DualPaneShell.prototype.getModalKind = function() {
        return this._activeModal && this._activeModal.spec ? this._activeModal.spec.kind || 'notice' : null;
    };

    DualPaneShell.prototype.destroy = function() {
        if (this._destroyed || this._destroying) return false;
        this._destroying = true;
        this._destroyed = true;
        this._modalGeneration++;
        var firstError = null;
        try { this._closeModal('destroy', false); }
        catch (modalError) { firstError = modalError; }
        for (var listenerIndex = 0; listenerIndex < this._slotListeners.length; listenerIndex++) {
            var listener = this._slotListeners[listenerIndex];
            try { listener[0].removeEventListener(listener[1], listener[2]); }
            catch (listenerError) { if (!firstError) firstError = listenerError; }
        }
        this._slotListeners = [];
        try { this._hosts.L.unmount(); } catch (leftError) { if (!firstError) firstError = leftError; }
        try { this._hosts.R.unmount(); } catch (rightError) { if (!firstError) firstError = rightError; }
        clearElement(this._hosts.L.root);
        clearElement(this._hosts.R.root);
        this._views = {};
        this._destroying = false;
        if (firstError) throw firstError;
        return true;
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
        this.root.setAttribute('role', options.role || 'listbox');
        if (options.multiselectable) this.root.setAttribute('aria-multiselectable', 'true');
        this._items = [];
        this._selectedKey = null;
    }

    GridRenderer.prototype.render = function(items, renderOptions) {
        renderOptions = renderOptions || {};
        var preserveScroll = renderOptions.preserveScroll !== false,
            previousScrollTop = preserveScroll ? this.root.scrollTop : 0,
            previousScrollLeft = preserveScroll ? this.root.scrollLeft : 0;
        var activeItem = null;
        if (preserveScroll && typeof document !== 'undefined' && document.activeElement
                && this.root.contains(document.activeElement)) activeItem = this.findItemNode(document.activeElement);
        var activeKey = activeItem ? activeItem.getAttribute('data-workbench-key') : null, activeFocusIndex = -1;
        if (activeItem && document.activeElement) {
            var activeFocusables = [activeItem].concat(Array.prototype.slice.call(activeItem.querySelectorAll(ENTITY_FOCUS_SELECTOR)));
            activeFocusIndex = activeFocusables.indexOf(document.activeElement);
        }
        this._items = (items || []).slice();
        if (!this._items.length) {
            clearElement(this.root);
            var empty = makeElement('div', 'workbench-grid-empty');
            empty.textContent = this.options.emptyText || '暂无项目';
            this.root.appendChild(empty);
        } else {
            var existingByKey = Object.create(null);
            var existingChildren = Array.prototype.slice.call(this.root.children);
            for (var existingIndex = 0; existingIndex < existingChildren.length; existingIndex++) {
                var existingKey = existingChildren[existingIndex].getAttribute('data-workbench-key');
                if (existingKey != null && !Object.prototype.hasOwnProperty.call(existingByKey, existingKey))
                    existingByKey[existingKey] = existingChildren[existingIndex];
            }
            var desiredNodes = [];
            for (var i = 0; i < this._items.length; i++) {
                var item = this._items[i];
                var key = this.options.keyOf ? String(this.options.keyOf(item, i)) : String(i);
                var node = existingByKey[key];
                var reuse = !!node && renderOptions.forceItemRender !== true && node.__workbenchItem === item;
                if (!reuse) {
                    node = this.options.renderItem ? this.options.renderItem(item, i) : makeElement('div');
                    if (!node || node.nodeType !== 1) throw new Error('GridRenderer.renderItem must return an Element');
                }
                node.setAttribute('data-workbench-item', String(i));
                node.__workbenchItem = item;
                node.__workbenchIndex = i;
                node.setAttribute('data-workbench-key', key);
                if (this._selectedKey != null && key === this._selectedKey) {
                    node.classList.add('workbench-source-selected');
                    EntityTile.setSelected(node, true);
                }
                if (!reuse && typeof this.options.bindItem === 'function') this.options.bindItem(node, item, i);
                desiredNodes.push(node);
                delete existingByKey[key];
            }
            for (var desiredIndex = 0; desiredIndex < desiredNodes.length; desiredIndex++) {
                var currentNode = this.root.children[desiredIndex] || null;
                if (currentNode !== desiredNodes[desiredIndex]) this.root.insertBefore(desiredNodes[desiredIndex], currentNode);
            }
            while (this.root.children.length > desiredNodes.length) {
                var staleNode = this.root.lastChild;
                releaseElementBindings(staleNode); this.root.removeChild(staleNode);
            }
        }
        this.root.scrollTop = previousScrollTop;
        this.root.scrollLeft = previousScrollLeft;
        if (activeKey != null) {
            var renderedNodes = this.root.querySelectorAll('[data-workbench-key]');
            for (var renderedIndex = 0; renderedIndex < renderedNodes.length; renderedIndex++) {
                if (renderedNodes[renderedIndex].getAttribute('data-workbench-key') !== activeKey) continue;
                var focusTarget = renderedNodes[renderedIndex];
                if (activeFocusIndex > 0) {
                    var nextFocusables = [focusTarget].concat(Array.prototype.slice.call(focusTarget.querySelectorAll(ENTITY_FOCUS_SELECTOR)));
                    if (nextFocusables[activeFocusIndex]) focusTarget = nextFocusables[activeFocusIndex];
                }
                if (typeof focusTarget.focus === 'function') focusTarget.focus();
                break;
            }
        }
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
            var selected = this._selectedKey != null && nodes[i].getAttribute('data-workbench-key') === this._selectedKey;
            nodes[i].classList.toggle('workbench-source-selected', selected);
            EntityTile.setSelected(nodes[i], selected);
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
            button.setAttribute('aria-label', title);
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
        EntityTile: EntityTile,
        ItemCard: ItemCard,
        ItemGrid: ItemGrid,
        GridDensityController: GridDensityController,
        WorkbenchState: WorkbenchState
    };
});
