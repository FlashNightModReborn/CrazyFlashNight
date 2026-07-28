/**
 * Shared composition primitives for dual-pane workbench panels.
 *
 * The primitives deliberately own presentation/lifecycle state only. Domain
 * request multiplexing and authoritative writes stay in each panel runtime.
 */
(function(root, factory) {
    'use strict';
    var lifecycle = typeof module !== 'undefined' && module.exports
        ? require('./workbench-lifecycle.js')
        : root && (root.WorkbenchLifecycle || root.CF7 && root.CF7.WorkbenchLifecycle);
    var focus = typeof module !== 'undefined' && module.exports
        ? require('./workbench-focus.js')
        : root && (root.WorkbenchFocus || root.CF7 && root.CF7.WorkbenchFocus);
    var api = factory(lifecycle, focus);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.WorkbenchComponents = api;
        root.WorkbenchComponents = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(WorkbenchLifecycle, WorkbenchFocus) {
    'use strict';

    function FallbackDisposableStack() {
        this._entries = [];
        this._disposed = false;
    }
    FallbackDisposableStack.prototype.defer = function(dispose) {
        if (this._disposed) { dispose(); return dispose; }
        this._entries.push(dispose); return dispose;
    };
    FallbackDisposableStack.prototype.dispose = function() {
        if (this._disposed) return false;
        this._disposed = true;
        for (var i = this._entries.length - 1; i >= 0; i--) this._entries[i]();
        this._entries = [];
        return true;
    };
    FallbackDisposableStack.prototype.size = function() { return this._entries.length; };

    // Production loads workbench-lifecycle.js before this module. The fallback
    // keeps isolated DOM-free consumers usable without inventing a second API.
    var DisposableStack = WorkbenchLifecycle && WorkbenchLifecycle.DisposableStack
        ? WorkbenchLifecycle.DisposableStack : FallbackDisposableStack;
    if (!WorkbenchFocus || typeof WorkbenchFocus.FocusScope !== 'function') {
        throw new Error('workbench-components.js requires workbench-focus.js');
    }
    var FocusScope = WorkbenchFocus.FocusScope;
    var secondaryOpenSequence = 0;
    var quantityControlSequence = 0;

    function resolveDocument(options, node) {
        return options.document || (node && node.ownerDocument)
            || (typeof document !== 'undefined' ? document : null);
    }

    function removeNode(node) {
        if (node && node.parentNode) node.parentNode.removeChild(node);
    }

    function listen(target, type, handler) {
        if (!target || typeof target.addEventListener !== 'function') return function() {};
        target.addEventListener(type, handler);
        var active = true;
        return function() {
            if (!active) return;
            active = false;
            target.removeEventListener(type, handler);
        };
    }

    function setClass(node, name, enabled) {
        if (!node || !node.classList || !name) return;
        node.classList.toggle(name, !!enabled);
    }

    function copyAttributes(node, attributes) {
        attributes = attributes || {};
        for (var key in attributes) {
            if (!Object.prototype.hasOwnProperty.call(attributes, key)) continue;
            if (attributes[key] == null || attributes[key] === false) node.removeAttribute(key);
            else node.setAttribute(key, String(attributes[key]));
        }
    }

    function secondaryOwner(node) {
        return node && node.__cf7WorkbenchSecondaryPage || null;
    }

    function enclosingSecondaryOwner(node) {
        var current = node;
        while (current) {
            var owner = secondaryOwner(current);
            if (owner) return owner;
            current = current.parentNode;
        }
        return null;
    }

    function HelpAction(options) {
        options = options || {};
        if (!options.shell || typeof options.shell.addHeaderAction !== 'function'
                || typeof options.shell.openModal !== 'function') {
            throw new Error('HelpAction requires a workbench shell');
        }
        this.shell = options.shell;
        this.spec = null;
        this._destroyed = false;
        this.button = resolveDocument(options).createElement('button');
        this.button.type = 'button';
        this.button.className = 'workbench-mode-btn workbench-help-btn';
        this.button.textContent = '?';
        this.button.setAttribute('data-workbench-help', '');
        this.button.setAttribute('data-audio-cue', 'select');
        var self = this;
        this._unbind = listen(this.button, 'click', function() {
            var current = self.spec;
            if (!current || self._destroyed) return;
            if (typeof current.onOpen === 'function') {
                current.onOpen(self.button, self.shell);
                return;
            }
            var modalSpec = {};
            for (var key in current) modalSpec[key] = current[key];
            if (!modalSpec.kind) modalSpec.kind = 'workbench-help';
            if (!modalSpec.actions) modalSpec.actions = [
                {id:'close', label:'知道了', primary:true, audioCue:'confirm'}
            ];
            self.shell.openModal(modalSpec);
        });
        this.shell.addHeaderAction(this.button);
        this.update(options.spec || null);
    }
    HelpAction.prototype.update = function(spec) {
        if (this._destroyed) return false;
        this.spec = spec || null;
        this.button.hidden = !this.spec;
        this.button.disabled = !!(this.spec && this.spec.disabled);
        this.button.textContent = this.spec && this.spec.buttonLabel
            ? String(this.spec.buttonLabel) : '?';
        this.button.setAttribute('aria-label', this.spec && this.spec.ariaLabel
            ? String(this.spec.ariaLabel) : '查看工作台帮助');
        return true;
    };
    HelpAction.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._unbind();
        removeNode(this.button);
        this.spec = null;
        this.shell = null;
        return true;
    };

    function syncSecondaryAccessibility(host) {
        if (!host || !host.children) return;
        var top = null;
        for (var i = 0; i < host.children.length; i++) {
            var owner = secondaryOwner(host.children[i]);
            if (!owner || owner._host !== host || !owner._active) continue;
            if (!top || owner._stackOrder > top._stackOrder) top = owner;
        }
        for (var j = 0; j < host.children.length; j++) {
            var page = secondaryOwner(host.children[j]);
            if (!page || page._host !== host) continue;
            page.root.setAttribute('aria-hidden', page === top ? 'false' : 'true');
        }
    }

    function secondaryUnderlay(page) {
        var host = page._host || page.root.parentNode;
        if (!host || !host.children) return [];
        var result = [];
        for (var i = 0; i < host.children.length; i++) {
            var child = host.children[i];
            if (child === page.root) continue;
            // The shell-level modal portal must stay interactive while a secondary
            // page is active.  Modal focus ownership suppresses the page itself
            // when a dialog opens; suppressing the portal here would render the
            // dialog but leave every real pointer/keyboard action inert.
            if (child.classList && child.classList.contains('workbench-modal-layer')) continue;
            if (child.classList && child.classList.contains('workbench-secondary-page')) {
                var owner = secondaryOwner(child);
                var active = owner ? owner._active : child.getAttribute && child.getAttribute('aria-hidden') === 'false';
                if (active) result.push(child);
                continue;
            }
            result.push(child);
        }
        return result;
    }

    function secondaryRestoreTarget(page) {
        var target = page._focusScope && page._focusScope._opener;
        var visited = [];
        while (target && target.closest) {
            var root = target.closest('.workbench-secondary-page');
            var owner = secondaryOwner(root);
            if (!owner || owner._active || visited.indexOf(owner) >= 0) break;
            visited.push(owner);
            target = owner._returnFocus;
        }
        return target || null;
    }

    function SecondaryPage(options) {
        options = options || {};
        this._options = options;
        this._document = resolveDocument(options, options.root);
        if (!options.root && !this._document) throw new Error('SecondaryPage requires a document or root');
        this.root = options.root || this._document.createElement(options.tagName || 'section');
        this._ownsRoot = !options.root;
        this._host = null;
        this._active = false;
        this._destroyed = false;
        this._destroying = false;
        this._closing = false;
        this._generation = 0;
        this._stackOrder = 0;
        this._returnFocus = null;
        this._lifetime = new DisposableStack();
        this._activeClass = options.activeClass || 'active';
        this._backCallback = null;
        if (this.root.classList) {
            this.root.classList.add('workbench-secondary-page');
            if (options.className) {
                String(options.className).split(/\s+/).forEach(function(name) {
                    if (name) this.root.classList.add(name);
                }, this);
            }
        }
        if (options.role) this.root.setAttribute('role', options.role);
        if (options.role === 'dialog') this.root.setAttribute('aria-modal', 'true');
        if (options.ariaLabel) this.root.setAttribute('aria-label', options.ariaLabel);
        this.root.setAttribute('aria-hidden', 'true');
        this.root.__cf7WorkbenchSecondaryPage = this;
        var self = this;
        this._focusScope = new FocusScope({
            root:this.root,
            document:this._document,
            restoreFocus:options.restoreFocus !== false,
            onEscape:function(event) { return self._requestClose('escape', event); },
            onAncestorDeactivate:function(reason) {
                if (self._active) self.close(reason, {restoreFocus:false});
            }
        });
        if (options.closeTarget) this.bindClose(options.closeTarget);
    }

    SecondaryPage.prototype.mount = function(host) {
        if (this._destroyed || this._destroying || !host) return false;
        if (this._host === host && this.root.parentNode === host) return true;
        removeNode(this.root);
        host.appendChild(this.root);
        this._host = host;
        if (typeof this._options.onMount === 'function') this._options.onMount(this.root, host);
        return true;
    };

    SecondaryPage.prototype.bindClose = function(target, callback) {
        if (this._destroyed || this._destroying) return false;
        if (typeof target === 'string') target = this.root.querySelector(target);
        if (!target) return false;
        if (typeof callback === 'function') this._backCallback = callback;
        var self = this;
        this._lifetime.defer(listen(target, 'click', function(event) {
            if (event && event.preventDefault) event.preventDefault();
            self._requestClose('back', event, callback);
        }));
        return true;
    };

    SecondaryPage.prototype._requestClose = function(reason, event, callback) {
        if (!this._active || this._destroyed) return false;
        if (reason === 'escape' && this._options.closeOnEscape === false) return false;
        callback = callback || (reason === 'escape' && this._options.onEscape)
            || this._backCallback || this._options.onBack;
        var generation = this._generation;
        var result = typeof callback === 'function' ? callback(event, reason, this) : undefined;
        if (result !== false && this._active && generation === this._generation) this.close(reason || 'close');
        // FocusScope must not perform a second close after the domain callback.
        return false;
    };

    SecondaryPage.prototype.open = function(context) {
        if (this._destroyed || this._destroying || this._closing) return false;
        if (!this._host && this._options.host) this.mount(this._options.host);
        if (!this._host && !this.root.parentNode) return false;
        if (this._active) return true;
        context = context || {};
        var generation = ++this._generation;
        this._stackOrder = ++secondaryOpenSequence;
        this._returnFocus = context.opener || this._document && this._document.activeElement || null;
        this._initialFocus = context.initialFocus || this._options.initialFocus || null;
        this._active = true;
        setClass(this.root, this._activeClass, true);
        this.root.setAttribute('aria-hidden', 'false');
        try {
            if (typeof this._options.onOpen === 'function') this._options.onOpen(context, this.root);
            if (!this._active || this._destroyed || this._destroying || generation !== this._generation) return false;
            this._focusScope.activate({
                opener:context.opener,
                initialFocus:context.initialFocus != null ? context.initialFocus : this._options.initialFocus,
                underlay:context.underlay != null ? context.underlay
                    : this._options.underlay != null ? this._options.underlay : secondaryUnderlay(this)
            });
            syncSecondaryAccessibility(this._host || this.root.parentNode);
        } catch (error) {
            if (generation === this._generation) {
                this._generation++;
                this._active = false;
                setClass(this.root, this._activeClass, false);
                this.root.setAttribute('aria-hidden', 'true');
                try { this._focusScope.deactivate('open-error', {restoreFocus:false}); } catch (_) {}
                syncSecondaryAccessibility(this._host || this.root.parentNode);
            }
            throw error;
        }
        return this._active && generation === this._generation && this._focusScope.isActive();
    };

    SecondaryPage.prototype.close = function(reason, context) {
        if (this._destroyed || this._closing || !this._active) return false;
        context = context || {};
        this._closing = true;
        this._generation++;
        this._active = false;
        setClass(this.root, this._activeClass, false);
        this.root.setAttribute('aria-hidden', 'true');
        var firstError = null;
        var focusContext = {restoreFocus:context.restoreFocus};
        focusContext.restoreFocusTarget = secondaryRestoreTarget(this);
        try { this._focusScope.deactivate(reason || 'close', focusContext); }
        catch (focusError) { firstError = focusError; }
        syncSecondaryAccessibility(this._host || this.root.parentNode);
        try {
            if (typeof this._options.onClose === 'function') this._options.onClose(reason || 'close', this.root);
        } catch (closeError) { if (!firstError) firstError = closeError; }
        this._closing = false;
        if (firstError) throw firstError;
        return true;
    };

    SecondaryPage.prototype.update = function(state) {
        if (this._destroyed) return false;
        state = state || {};
        if (state.ariaLabel != null) this.root.setAttribute('aria-label', String(state.ariaLabel));
        if (state.disabled != null) this.root.setAttribute('aria-disabled', state.disabled ? 'true' : 'false');
        if (state.active === true) return this.open(state.context);
        if (state.active === false) return this.close(state.reason || 'update');
        return true;
    };

    SecondaryPage.prototype.isActive = function() { return this._active; };
    SecondaryPage.prototype.destroy = function() {
        if (this._destroyed || this._destroying) return false;
        this._destroying = true;
        var firstError = null;
        try { this.close('destroy', {restoreFocus:false}); }
        catch (closeError) { firstError = closeError; }
        this._destroyed = true;
        this._generation++;
        try { this._focusScope.destroy(); } catch (focusError) { if (!firstError) firstError = focusError; }
        try { this._lifetime.dispose(); } catch (lifetimeError) { if (!firstError) firstError = lifetimeError; }
        try { if (this._ownsRoot || this._options.removeOnDestroy) removeNode(this.root); }
        catch (removeError) { if (!firstError) firstError = removeError; }
        var host = this._host;
        if (this.root.__cf7WorkbenchSecondaryPage === this) {
            try { delete this.root.__cf7WorkbenchSecondaryPage; }
            catch (_) { this.root.__cf7WorkbenchSecondaryPage = null; }
        }
        this._host = null;
        this._returnFocus = null;
        this._initialFocus = null;
        syncSecondaryAccessibility(host);
        this._destroying = false;
        if (firstError) throw firstError;
        return true;
    };

    function ChoiceGroup(options) {
        options = options || {};
        this._options = options;
        this._document = resolveDocument(options, options.root);
        if (!this._document) throw new Error('ChoiceGroup requires a document or root');
        this.root = options.root || this._document.createElement(options.tagName || 'div');
        this._ownsRoot = !options.root;
        this._host = null;
        this._destroyed = false;
        this._disabled = !!options.disabled;
        this._value = options.value == null ? '' : String(options.value);
        this._choices = [];
        this._buttons = {};
        this._choiceLifetime = new DisposableStack();
        this.root.setAttribute('role', options.role || 'group');
        if (this.root.classList) this.root.classList.add('workbench-choice-group');
        if (options.ariaLabel) this.root.setAttribute('aria-label', options.ariaLabel);
        if (options.className && this.root.classList) {
            String(options.className).split(/\s+/).forEach(function(name) { if (name) this.root.classList.add(name); }, this);
        }
        this.setChoices(options.choices || []);
    }

    ChoiceGroup.prototype.setChoices = function(choices) {
        if (this._destroyed) return false;
        this._choiceLifetime.dispose();
        this._choiceLifetime = new DisposableStack();
        while (this.root.firstChild) this.root.removeChild(this.root.firstChild);
        this._choices = choices.slice ? choices.slice() : [];
        this._buttons = {};
        var self = this;
        this._choices.forEach(function(choice) {
            var value = String(choice.value == null ? choice.id : choice.value);
            var button = self._document.createElement('button');
            button.type = 'button';
            button.textContent = choice.label == null ? value : String(choice.label);
            button.className = choice.className || self._options.buttonClassName || 'workbench-mode-btn';
            if (button.classList) button.classList.add('workbench-choice-option');
            button.setAttribute('data-choice', value);
            if (choice.dataAttribute) button.setAttribute(choice.dataAttribute, value);
            if (choice.title) button.title = String(choice.title);
            if (choice.ariaLabel) button.setAttribute('aria-label', String(choice.ariaLabel));
            copyAttributes(button, choice.attributes);
            self._choiceLifetime.defer(listen(button, 'click', function(event) {
                if (button.disabled) return;
                if (typeof self._options.beforeChange === 'function'
                        && self._options.beforeChange(value, choice, event) === false) return;
                self.setValue(value, {event:event, choice:choice});
            }));
            self._buttons[value] = button;
            self.root.appendChild(button);
        });
        if (!this._buttons[this._value] && this._choices.length) {
            this._value = String(this._choices[0].value == null ? this._choices[0].id : this._choices[0].value);
        }
        this._render();
        return true;
    };

    ChoiceGroup.prototype._render = function() {
        for (var value in this._buttons) {
            var button = this._buttons[value];
            var choice = null;
            for (var i = 0; i < this._choices.length; i++) {
                var candidate = String(this._choices[i].value == null ? this._choices[i].id : this._choices[i].value);
                if (candidate === value) { choice = this._choices[i]; break; }
            }
            var selected = value === this._value;
            button.disabled = this._disabled || !!(choice && choice.disabled);
            button.setAttribute('aria-pressed', selected ? 'true' : 'false');
            setClass(button, this._options.selectedClass || 'active', selected);
        }
        this.root.setAttribute('aria-disabled', this._disabled ? 'true' : 'false');
    };

    ChoiceGroup.prototype.mount = function(host) {
        if (this._destroyed || !host) return false;
        if (this._host === host && this.root.parentNode === host) return true;
        removeNode(this.root); host.appendChild(this.root); this._host = host; return true;
    };
    ChoiceGroup.prototype.setValue = function(value, meta) {
        if (this._destroyed) return false;
        value = String(value);
        if (!this._buttons[value] || this._buttons[value].disabled) return false;
        var changed = value !== this._value;
        this._value = value;
        this._render();
        if (changed && !(meta && meta.silent) && typeof this._options.onChange === 'function') {
            this._options.onChange(value, meta && meta.choice, meta && meta.event);
        }
        return true;
    };
    ChoiceGroup.prototype.update = function(state) {
        if (this._destroyed) return false;
        state = state || {};
        if (state.choices) this.setChoices(state.choices);
        if (state.disabled != null) this._disabled = !!state.disabled;
        if (state.value != null) this._value = String(state.value);
        this._render();
        return true;
    };
    ChoiceGroup.prototype.getValue = function() { return this._value; };
    ChoiceGroup.prototype.getButton = function(value) { return this._buttons[String(value)] || null; };
    ChoiceGroup.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._choiceLifetime.dispose();
        if (this._ownsRoot || this._options.removeOnDestroy) removeNode(this.root);
        this._host = null; return true;
    };

    function CommitBar(options) {
        options = options || {};
        this._options = options;
        this._document = resolveDocument(options, options.root || options.primaryButton);
        if (!this._document) throw new Error('CommitBar requires a document or root');
        this.root = options.root || this._document.createElement(options.tagName || 'footer');
        this._ownsRoot = !options.root;
        this.statusNode = options.statusNode || this._document.createElement('span');
        this.primaryButton = options.primaryButton || this._document.createElement('button');
        this._destroyed = false;
        this._host = null;
        this._stateClass = '';
        this._lifetime = new DisposableStack();
        if (this.root.classList) this.root.classList.add('workbench-commit-bar');
        if (this.statusNode.classList) this.statusNode.classList.add('workbench-commit-status');
        if (this.primaryButton.classList) this.primaryButton.classList.add('workbench-commit-primary');
        if (!options.statusNode) {
            this.statusNode.setAttribute('data-commit-status', '');
            this.root.appendChild(this.statusNode);
        }
        if (!options.primaryButton) {
            this.primaryButton.type = 'button';
            this.primaryButton.setAttribute('data-commit-primary', '');
            this.root.appendChild(this.primaryButton);
        }
        if (options.className && this.root.classList) {
            String(options.className).split(/\s+/).forEach(function(name) { if (name) this.root.classList.add(name); }, this);
        }
        var self = this;
        this._lifetime.defer(listen(this.primaryButton, 'click', function(event) {
            if (self.primaryButton.disabled) return;
            if (typeof self._options.onCommit === 'function') self._options.onCommit(event);
        }));
        this.update({label:options.label || '', status:options.status || '', disabled:options.disabled,
            canCommit:options.canCommit, busy:options.busy, state:options.state});
    }

    CommitBar.prototype.mount = function(host) {
        if (this._destroyed || !host) return false;
        if (this._host === host && this.root.parentNode === host) return true;
        removeNode(this.root); host.appendChild(this.root); this._host = host; return true;
    };
    CommitBar.prototype.update = function(state) {
        if (this._destroyed) return false;
        state = state || {};
        if (state.label != null) this.primaryButton.textContent = String(state.label);
        if (state.status != null) this.statusNode.textContent = String(state.status);
        var blocked = !!state.busy || state.disabled === true || state.canCommit === false;
        this.primaryButton.disabled = blocked;
        this.primaryButton.setAttribute('aria-busy', state.busy ? 'true' : 'false');
        setClass(this.root, 'busy', !!state.busy);
        if (this._stateClass && this.root.classList) this.root.classList.remove(this._stateClass);
        this._stateClass = state.state ? 'is-' + String(state.state) : '';
        if (this._stateClass && this.root.classList) this.root.classList.add(this._stateClass);
        setClass(this.statusNode, 'error', state.state === 'error' || state.state === 'blocked');
        setClass(this.statusNode, 'ok', state.state === 'ready' || state.state === 'success');
        if (state.state) this.statusNode.setAttribute('data-state', String(state.state));
        else this.statusNode.removeAttribute('data-state');
        return true;
    };
    CommitBar.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._lifetime.dispose();
        if (this._ownsRoot || this._options.removeOnDestroy) removeNode(this.root);
        this._host = null; return true;
    };

    function defaultOwnedKey(item) {
        if (!item) return '';
        if (item.physicalSlot != null) return String(item.physicalSlot);
        if (item.collectionKey != null) return String(item.collectionKey);
        if (item.slot != null) return String(item.slot);
        return '';
    }

    function OwnedInventoryPane(options) {
        options = options || {};
        this._options = options;
        this.view = options.view || null;
        this.root = options.root || (this.view && this.view.root) || null;
        this._shell = options.shell || (this.view && this.view.ownedInventoryShell) || null;
        this._keyOf = options.keyOf || defaultOwnedKey;
        this._snapshot = null;
        this._selection = {};
        this._disabled = !!options.disabled;
        this._mounted = false;
        this._destroyed = false;
        this._queue = [];
        this._inflight = null;
        this._transferSeq = 0;
        this._epoch = 1;
        this._completed = 0;
        this._accepted = 0;
        if (this.root && this.root.classList) this.root.classList.add('workbench-owned-pane');
        if (this.view) this.view.ownedInventoryPane = this;
    }

    OwnedInventoryPane.prototype.mount = function(host) {
        if (this._destroyed || !host) return false;
        if (this._mounted && this.root && this.root.parentNode === host) return true;
        if (this.view && typeof this.view.mount === 'function') this.view.mount(host);
        else if (this.root) { removeNode(this.root); host.appendChild(this.root); }
        else return false;
        this._mounted = true;
        return true;
    };

    OwnedInventoryPane.prototype.update = function(snapshot, presentation) {
        if (this._destroyed) return false;
        if (arguments.length === 0 && typeof this._options.getSnapshot === 'function') {
            snapshot = this._options.getSnapshot();
        }
        this._snapshot = snapshot || null;
        this._reconcileSelection();
        if (typeof this._options.syncSnapshot === 'function') {
            this._options.syncSnapshot(this._snapshot, presentation || {}, this);
        } else if (this._shell && typeof this._shell.syncSnapshot === 'function') {
            this._shell.syncSnapshot(this._snapshot, presentation || {});
        } else if (this.view && typeof this.view.render === 'function') {
            this.view.render();
        }
        if (typeof this._options.onUpdate === 'function') this._options.onUpdate(this._snapshot, presentation || {}, this);
        return true;
    };

    OwnedInventoryPane.prototype._reconcileSelection = function() {
        if (!this._snapshot) return;
        var items = this._snapshot.slots || this._snapshot.items;
        if (!Array.isArray(items)) return;
        var present = {};
        for (var i = 0; i < items.length; i++) present[String(this._keyOf(items[i]))] = true;
        var changed = false;
        for (var key in this._selection) {
            if (!present[key]) { delete this._selection[key]; changed = true; }
        }
        if (changed) this._emitSelection();
    };

    OwnedInventoryPane.prototype.setSelected = function(item, selected) {
        if (this._destroyed || !item) return false;
        var key = String(this._keyOf(item));
        if (!key) return false;
        var had = Object.prototype.hasOwnProperty.call(this._selection, key);
        if (selected === false) delete this._selection[key];
        else this._selection[key] = item;
        if (had === (selected !== false)) return true;
        this._emitSelection();
        return true;
    };
    OwnedInventoryPane.prototype.toggleSelection = function(item) {
        var key = item ? String(this._keyOf(item)) : '';
        if (!key) return false;
        return this.setSelected(item, !Object.prototype.hasOwnProperty.call(this._selection, key));
    };
    OwnedInventoryPane.prototype.clearSelection = function() {
        if (this._destroyed) return false;
        if (!Object.keys(this._selection).length) return true;
        this._selection = {}; this._emitSelection(); return true;
    };
    OwnedInventoryPane.prototype._emitSelection = function() {
        if (typeof this._options.onSelectionChange === 'function') {
            this._options.onSelectionChange(this.selectedItems(), this);
        }
    };
    OwnedInventoryPane.prototype.isSelected = function(item) {
        var key = item ? String(this._keyOf(item)) : '';
        return !!key && Object.prototype.hasOwnProperty.call(this._selection, key);
    };
    OwnedInventoryPane.prototype.selectedItems = function() {
        var result = [];
        for (var key in this._selection) result.push(this._selection[key]);
        return result;
    };

    OwnedInventoryPane.prototype.setDisabled = function(disabled) {
        this._disabled = !!disabled;
        if (this.root) this.root.setAttribute('aria-disabled', this._disabled ? 'true' : 'false');
        this._emitTransferState();
    };

    OwnedInventoryPane.prototype.quickTransfer = function(source, target, meta) {
        if (this._destroyed || this._disabled || !source || typeof this._options.onQuickTransfer !== 'function') return false;
        meta = meta || {};
        var key = meta.key || String(this._keyOf(source)) + '>' + String(target && this._keyOf(target) || target || 'auto');
        if (this._inflight && this._inflight.key === key) return false;
        for (var i = 0; i < this._queue.length; i++) if (this._queue[i].key === key) return false;
        this._queue.push({id:++this._transferSeq, key:key, source:source, target:target || null, meta:meta});
        this._emitTransferState();
        this._drainTransfers();
        return true;
    };

    OwnedInventoryPane.prototype._drainTransfers = function() {
        if (this._destroyed || this._inflight || !this._queue.length) return;
        var self = this;
        var entry = this._queue.shift();
        var epoch = this._epoch;
        var settled = false;
        this._inflight = entry;
        this._emitTransferState();
        function done(result) {
            if (settled) return;
            settled = true;
            if (self._destroyed || epoch !== self._epoch || self._inflight !== entry) return;
            self._inflight = null;
            self._completed++;
            if (result && result.success) self._accepted++;
            if (result && result.snapshot) self.update(result.snapshot, result.presentation || {});
            if (typeof self._options.onQuickTransferResult === 'function') {
                self._options.onQuickTransferResult(result || {success:false}, entry, self);
            }
            self._emitTransferState();
            self._drainTransfers();
        }
        var returned;
        try {
            returned = this._options.onQuickTransfer({source:entry.source, target:entry.target,
                meta:entry.meta, key:entry.key, id:entry.id}, done);
        } catch (error) {
            done({success:false, error:error});
            return;
        }
        if (returned === false) done({success:false, error:'rejected'});
        else if (returned && typeof returned.then === 'function') {
            returned.then(done, function(error) { done({success:false, error:error}); });
        }
    };

    OwnedInventoryPane.prototype.cancelQuickTransfers = function() {
        if (this._destroyed) return false;
        this._epoch++;
        this._queue = [];
        this._inflight = null;
        this._emitTransferState();
        return true;
    };
    OwnedInventoryPane.prototype._emitTransferState = function() {
        if (this.root) {
            var state = this._inflight ? 'busy' : this._queue.length ? 'pending' : 'idle';
            this.root.setAttribute('data-transfer-state', state);
            setClass(this.root, 'busy', state === 'busy');
        }
        if (typeof this._options.onQuickTransferState === 'function') {
            this._options.onQuickTransferState(this.debugState().quickTransfer, this);
        }
    };
    OwnedInventoryPane.prototype.debugState = function() {
        return {
            disabled:this._disabled,
            selected:Object.keys(this._selection),
            snapshot:!!this._snapshot,
            quickTransfer:{pending:this._queue.length, inFlight:this._inflight ? this._inflight.key : null,
                completed:this._completed, accepted:this._accepted}
        };
    };
    OwnedInventoryPane.prototype.destroy = function() {
        if (this._destroyed) return false;
        this.cancelQuickTransfers();
        this._destroyed = true;
        this._selection = {};
        if (this.view && this.view.ownedInventoryPane === this) this.view.ownedInventoryPane = null;
        if (this._options.ownsView && this._shell && typeof this._shell.destroy === 'function') this._shell.destroy();
        else if (this._options.ownsView && this.view && typeof this.view.unmount === 'function') this.view.unmount();
        this._mounted = false;
        return true;
    };

    function QuantityControl(options) {
        options = options || {};
        this._options = options;
        this._document = resolveDocument(options, options.root);
        if (!this._document) throw new Error('QuantityControl requires a document or root');
        this._lifetime = new DisposableStack();
        this._destroyed = false;
        this._min = 1;
        this._max = 1;
        this._presetMax = 1;
        this._sliderMax = 1;
        this._sliderScale = 'linear';
        this._sliderSteps = 1000;
        this._value = 1;
        this._disabled = false;
        this._numberDraft = null;
        this._rangeDraft = null;
        this._pendingFocusRestore = null;
        this._pendingFocusFallback = null;
        this._changeFocusOrigin = null;
        this._feedbackId = 'workbench-quantity-feedback-' + (++quantityControlSequence);
        this.root = options.root || this._document.createElement('span');
        this.root.className = options.className || 'workbench-quantity-control';
        this.root.setAttribute('role', 'group');
        this.root.setAttribute('aria-label', options.ariaLabel || '数量');

        this.minusButton = this._button('−', '减少 1');
        this.numberInput = this._document.createElement('input');
        this.numberInput.type = 'number';
        this.numberInput.className = 'workbench-quantity-number';
        this.numberInput.setAttribute('inputmode', 'numeric');
        this.numberInput.setAttribute('aria-label', options.inputAriaLabel || '输入数量');
        this.numberInput.setAttribute('aria-describedby', this._feedbackId);
        this.plusButton = this._button('+', '增加 1');
        this.plusFiveButton = this._button('+5', '增加 5');
        this.plusFiveButton.classList.add('wide');
        this.maxButton = this._button(options.maxLabel || '最大', '使用当前可直接结算上限');
        this.maxButton.classList.add('wide');
        this.rangeInput = this._document.createElement('input');
        this.rangeInput.type = 'range';
        this.rangeInput.className = 'workbench-quantity-range';
        this.rangeInput.setAttribute('aria-label', options.rangeAriaLabel || '拖动选择数量');
        this.rangeInput.setAttribute('aria-keyshortcuts',
            'ArrowLeft ArrowRight ArrowUp ArrowDown PageUp PageDown Home End');
        this.rangeShell = this._document.createElement('span');
        this.rangeShell.className = 'workbench-quantity-range-shell';
        this.rangeTrack = this._document.createElement('span');
        this.rangeTrack.className = 'workbench-quantity-track';
        this.rangeMarker = this._document.createElement('span');
        this.rangeMarker.className = 'workbench-quantity-effective-marker';
        this.rangeMarker.setAttribute('aria-hidden', 'true');
        this.rangeTrack.appendChild(this.rangeInput);
        this.rangeTrack.appendChild(this.rangeMarker);
        this.rangeScale = this._document.createElement('span');
        this.rangeScale.className = 'workbench-quantity-scale';
        this.rangeScale.setAttribute('aria-hidden', 'true');
        this.rangeMinLabel = this._document.createElement('span');
        this.rangeMidLabel = this._document.createElement('span');
        this.rangeMaxLabel = this._document.createElement('span');
        this.rangeScale.appendChild(this.rangeMinLabel);
        this.rangeScale.appendChild(this.rangeMidLabel);
        this.rangeScale.appendChild(this.rangeMaxLabel);
        this.rangeShell.appendChild(this.rangeTrack);
        this.rangeShell.appendChild(this.rangeScale);
        this.feedback = this._document.createElement('span');
        this.feedback.className = 'workbench-quantity-feedback';
        this.feedback.setAttribute('id', this._feedbackId);
        this.feedback.setAttribute('role', 'status');
        this.feedback.setAttribute('aria-live', 'polite');
        this.feedback.setAttribute('aria-atomic', 'true');
        this.feedback.hidden = true;

        this.root.appendChild(this.minusButton);
        this.root.appendChild(this.numberInput);
        this.root.appendChild(this.plusButton);
        this.root.appendChild(this.plusFiveButton);
        this.root.appendChild(this.maxButton);
        this.root.appendChild(this.rangeShell);
        this.root.appendChild(this.feedback);

        var self = this;
        this._lifetime.defer(listen(this.minusButton, 'click', function(event) {
            if (self.minusButton.disabled) return;
            self.setValue(self._value - 1, {notify:true, reason:'decrement', event:event});
        }));
        this._lifetime.defer(listen(this.plusButton, 'click', function(event) {
            if (self.plusButton.disabled) return;
            self.setValue(self._value + 1, {notify:true, reason:'increment', event:event});
        }));
        this._lifetime.defer(listen(this.plusFiveButton, 'click', function(event) {
            if (self.plusFiveButton.disabled) return;
            self.setValue(self._value + 5, {notify:true, reason:'increment_five', event:event});
        }));
        this._lifetime.defer(listen(this.maxButton, 'click', function(event) {
            if (self.maxButton.disabled) return;
            self.setValue(self._presetMax, {notify:true, reason:'maximum', event:event});
        }));
        this._lifetime.defer(listen(this.numberInput, 'input', function() {
            self._syncNumberDraft(self.numberInput.value);
        }));
        this._lifetime.defer(listen(this.numberInput, 'change', function(event) {
            self._commitNumberDraft(event);
        }));
        this._lifetime.defer(listen(this.numberInput, 'keydown', function(event) {
            if (!event) return;
            if (event.key === 'Enter') {
                if (event.preventDefault) event.preventDefault();
                self._commitNumberDraft(event);
            } else if (event.key === 'Escape') {
                if (event.preventDefault) event.preventDefault();
                if (event.stopPropagation) event.stopPropagation();
                if (event.stopImmediatePropagation) event.stopImmediatePropagation();
                self._numberDraft = null;
                self._setValidation(null);
                self._render();
            }
        }));
        this._lifetime.defer(listen(this.rangeInput, 'input', function() {
            self._syncSliderDraft(self.rangeInput.value);
        }));
        this._lifetime.defer(listen(this.rangeInput, 'change', function(event) {
            var next = self._rangeDraft == null
                ? self._sliderToQuantity(self.rangeInput.value) : self._rangeDraft;
            self._rangeDraft = null;
            self.setValue(next, {notify:true, reason:'range', event:event});
        }));
        this._lifetime.defer(listen(this.rangeInput, 'keydown', function(event) {
            self._handleRangeKeydown(event);
        }));
        this.update(options);
    }

    QuantityControl.prototype._button = function(label, ariaLabel) {
        var button = this._document.createElement('button');
        button.type = 'button';
        button.textContent = label;
        button.setAttribute('aria-label', ariaLabel);
        return button;
    };
    QuantityControl.prototype._clamp = function(value) {
        value = Math.floor(Number(value));
        if (!isFinite(value)) value = this._min;
        return Math.max(this._min, Math.min(this._max, value));
    };
    QuantityControl.prototype._sliderUpper = function() {
        return Math.max(this._min, this._sliderMax);
    };
    QuantityControl.prototype._sliderQuantity = function(value) {
        value = this._clamp(value);
        return Math.max(this._min, Math.min(this._sliderUpper(), value));
    };
    QuantityControl.prototype._quantityToSlider = function(value) {
        var quantity = this._sliderQuantity(value);
        if (this._sliderScale !== 'log') return quantity;
        var span = this._sliderUpper() - this._min;
        if (span <= 0) return 0;
        var ratio = Math.log(quantity - this._min + 1) / Math.log(span + 1);
        return Math.max(0, Math.min(this._sliderSteps, Math.round(ratio * this._sliderSteps)));
    };
    QuantityControl.prototype._sliderToQuantity = function(value) {
        if (this._sliderUpper() <= this._min) return this._min;
        if (this._sliderScale !== 'log') return this._sliderQuantity(value);
        var position = Math.max(0, Math.min(this._sliderSteps, Number(value) || 0));
        var span = this._sliderUpper() - this._min;
        var quantity = this._min + Math.round(
            Math.exp(position / this._sliderSteps * Math.log(span + 1)) - 1);
        return this._sliderQuantity(quantity);
    };
    QuantityControl.prototype._physicalProgress = function(value) {
        var position = this._quantityToSlider(value);
        if (this._sliderScale === 'log') return position / this._sliderSteps;
        return (position - this._min) / Math.max(1, this._sliderUpper() - this._min);
    };
    QuantityControl.prototype._syncSliderAria = function(quantity) {
        quantity = this._sliderQuantity(quantity);
        this.rangeInput.setAttribute('aria-valuemin', String(this._min));
        this.rangeInput.setAttribute('aria-valuemax', String(this._sliderUpper()));
        this.rangeInput.setAttribute('aria-valuenow', String(quantity));
        this.rangeInput.setAttribute('aria-valuetext',
            this._presetMax >= this._min && this._presetMax < this._sliderUpper()
                ? quantity + '；当前可直接结算 ' + this._presetMax
                : String(quantity));
        var progress = Math.max(0, Math.min(1, this._physicalProgress(quantity)));
        if (this.rangeInput.style && this.rangeInput.style.setProperty) {
            this.rangeInput.style.setProperty('--quantity-progress',
                Math.round(progress * 10000) / 100 + '%');
        }
    };
    QuantityControl.prototype._syncSliderDraft = function(value) {
        var quantity = this._sliderToQuantity(value);
        this._rangeDraft = quantity;
        this._numberDraft = null;
        this._setValidation(null);
        this.numberInput.value = String(quantity);
        this._syncSliderAria(quantity);
        return quantity;
    };
    QuantityControl.prototype._validationResult = function(value) {
        var draft = String(value == null ? '' : value).trim();
        var bounds = this._formatSliderLabel(this._min) + '–' + this._formatSliderLabel(this._max);
        if (!draft) return {valid:false, message:'请输入 ' + bounds + ' 的整数'};
        if (!/^\d+$/.test(draft)) return {valid:false, message:'数量只能填写整数'};
        var numeric = Number(draft);
        if (!isFinite(numeric) || numeric < this._min || numeric > this._max) {
            return {valid:false, message:'数量须在 ' + bounds + ' 之间'};
        }
        return {valid:true, value:numeric, message:''};
    };
    QuantityControl.prototype._setValidation = function(result) {
        var invalid = !!(result && !result.valid);
        this.numberInput.setAttribute('aria-invalid', invalid ? 'true' : 'false');
        this.root.classList.toggle('has-invalid-quantity', invalid);
        this.feedback.textContent = invalid ? result.message : '';
        this.feedback.hidden = !invalid;
    };
    QuantityControl.prototype._syncNumberDraft = function(value) {
        this._numberDraft = String(value == null ? '' : value);
        this._rangeDraft = null;
        this.numberInput.setAttribute('data-workbench-escape-owner', 'field');
        var result = this._validationResult(this._numberDraft);
        this._setValidation(result);
        if (!result.valid) {
            this.rangeInput.value = String(this._quantityToSlider(this._value));
            this._syncSliderAria(this._value);
            return null;
        }
        this.rangeInput.value = String(this._quantityToSlider(result.value));
        this._syncSliderAria(result.value);
        return result.value;
    };
    QuantityControl.prototype._commitNumberDraft = function(event) {
        var result = this._validationResult(this.numberInput.value);
        this._numberDraft = String(this.numberInput.value == null ? '' : this.numberInput.value);
        this._setValidation(result);
        if (!result.valid) return false;
        this._numberDraft = null;
        return this.setValue(result.value, {notify:true, reason:'number', event:event});
    };
    QuantityControl.prototype._magnitudeNodes = function() {
        var nodes = [this._min, this._sliderUpper()];
        if (this._presetMax >= this._min && this._presetMax <= this._sliderUpper()) {
            nodes.push(this._presetMax);
        }
        var multiplier = 1;
        while (multiplier <= this._sliderUpper() && multiplier <= 1000000000) {
            nodes.push(multiplier, multiplier * 2, multiplier * 5);
            multiplier *= 10;
        }
        var unique = {};
        var result = [];
        for (var i = 0; i < nodes.length; i++) {
            var value = Math.floor(Number(nodes[i]));
            if (!isFinite(value) || value < this._min || value > this._sliderUpper() || unique[value]) continue;
            unique[value] = true;
            result.push(value);
        }
        result.sort(function(a, b) { return a - b; });
        return result;
    };
    QuantityControl.prototype._pageQuantity = function(current, direction) {
        var nodes = this._magnitudeNodes();
        if (direction > 0) {
            for (var i = 0; i < nodes.length; i++) if (nodes[i] > current) return nodes[i];
            return this._sliderUpper();
        }
        for (var j = nodes.length - 1; j >= 0; j--) if (nodes[j] < current) return nodes[j];
        return this._min;
    };
    QuantityControl.prototype._handleRangeKeydown = function(event) {
        if (!event || this.rangeInput.disabled) return false;
        var current = Number(this.rangeInput.getAttribute('aria-valuenow'));
        if (!isFinite(current)) current = this._value;
        var next = current;
        var handled = true;
        if (event.key === 'ArrowLeft' || event.key === 'ArrowDown') next -= event.shiftKey ? 5 : 1;
        else if (event.key === 'ArrowRight' || event.key === 'ArrowUp') next += event.shiftKey ? 5 : 1;
        else if (event.key === 'Home') next = this._min;
        else if (event.key === 'End') next = this._sliderUpper();
        else if (event.key === 'PageDown') next = this._pageQuantity(current, -1);
        else if (event.key === 'PageUp') next = this._pageQuantity(current, 1);
        else handled = false;
        if (!handled) return false;
        if (event.preventDefault) event.preventDefault();
        this.setValue(next, {notify:true, reason:'range_keyboard', event:event});
        return true;
    };
    QuantityControl.prototype._formatSliderLabel = function(value) {
        return Math.max(0, Math.floor(Number(value) || 0)).toLocaleString('zh-CN');
    };
    QuantityControl.prototype._render = function() {
        this.numberInput.min = String(this._min);
        this.numberInput.max = String(this._max);
        this.numberInput.step = '1';
        if (this._numberDraft != null) {
            this.numberInput.setAttribute('data-workbench-escape-owner', 'field');
        } else {
            this.numberInput.removeAttribute('data-workbench-escape-owner');
        }
        var sliderUpper = this._sliderUpper();
        this._sliderScale = this._options.sliderScale === 'linear'
            || this._options.sliderScale === 'log'
            ? this._options.sliderScale
            : sliderUpper > Number(this._options.linearSliderThreshold || 200)
                ? 'log' : 'linear';
        this.rangeInput.min = this._sliderScale === 'log' ? '0' : String(this._min);
        this.rangeInput.max = this._sliderScale === 'log'
            ? String(this._sliderSteps) : String(sliderUpper);
        this.rangeInput.step = '1';
        if (this._numberDraft == null) this.numberInput.value = String(this._value);
        var sliderQuantity = this._numberDraft == null
            ? (this._rangeDraft == null ? this._value : this._rangeDraft)
            : this._validationResult(this._numberDraft).valid
                ? Number(this._numberDraft) : this._value;
        this.rangeInput.value = String(this._quantityToSlider(sliderQuantity));
        this.rangeMinLabel.textContent = this._formatSliderLabel(this._min);
        this.rangeMidLabel.textContent = this._presetMax >= this._min && this._presetMax < sliderUpper
            ? '可用 ' + this._formatSliderLabel(this._presetMax)
            : this._formatSliderLabel(this._sliderToQuantity(this._sliderScale === 'log'
                ? this._sliderSteps / 2 : (this._min + sliderUpper) / 2));
        this.rangeMaxLabel.textContent = this._formatSliderLabel(sliderUpper);
        this.maxButton.textContent = this._options.maxLabel || '最大';
        this.maxButton.setAttribute('aria-label', (this._options.maxAriaLabel || '设为当前可直接结算上限')
            + (this._presetMax >= this._min ? ' ' + this._presetMax : '（当前为 0）'));
        this.rangeInput.title = '拖动范围 ' + this._formatSliderLabel(this._min)
            + '–' + this._formatSliderLabel(sliderUpper)
            + (this._sliderScale === 'log' ? '（对数刻度；方向键按实际数量增减）' : '');
        var markerVisible = this._presetMax >= this._min && this._presetMax < sliderUpper;
        this.rangeMarker.hidden = !markerVisible;
        this.rangeMarker.title = markerVisible
            ? '当前可直接结算 ' + this._formatSliderLabel(this._presetMax) : '';
        if (markerVisible && this.rangeTrack.style && this.rangeTrack.style.setProperty) {
            this.rangeTrack.style.setProperty('--quantity-effective-position',
                Math.round(this._physicalProgress(this._presetMax) * 10000) / 100 + '%');
        }
        this._syncSliderAria(sliderQuantity);
        var disabled = this._disabled || this._max <= 0;
        this.numberInput.disabled = disabled;
        this.rangeInput.disabled = disabled || sliderUpper <= this._min;
        this.minusButton.disabled = disabled || this._value <= this._min;
        this.plusButton.disabled = disabled || this._value >= this._max;
        this.plusFiveButton.disabled = disabled || this._value >= this._max;
        this.maxButton.disabled = disabled || this._presetMax < this._min || this._value === this._presetMax;
        this.plusFiveButton.hidden = this._options.showPlusFive === false;
        this.maxButton.hidden = this._options.showMax === false;
        this.rangeInput.hidden = this._options.showRange === false || sliderUpper <= this._min;
        this.rangeShell.hidden = this.rangeInput.hidden;
        this.root.setAttribute('aria-disabled', disabled ? 'true' : 'false');
        this.root.setAttribute('data-value', String(this._value));
        this.root.setAttribute('data-max', String(this._max));
        this.root.setAttribute('data-preset-max', String(this._presetMax));
        this.root.setAttribute('data-slider-max', String(this._sliderMax));
        this.root.setAttribute('data-slider-scale', this._sliderScale);
        this.root.setAttribute('data-value-outside-preset',
            this._presetMax >= this._min && this._value > this._presetMax ? 'true' : 'false');
    };
    QuantityControl.prototype.setValue = function(value, meta) {
        if (this._destroyed || this._disabled) return false;
        var next = this._clamp(value);
        var changed = next !== this._value;
        this._value = next;
        this._numberDraft = null;
        this._rangeDraft = null;
        this._setValidation(null);
        this._render();
        if ((changed || meta && meta.forceNotify) && meta && meta.notify
                && typeof this._options.onChange === 'function') {
            var focusOrigin = this._document.activeElement;
            if (focusOrigin && this.root.contains(focusOrigin)) this._changeFocusOrigin = focusOrigin;
            try {
                this._options.onChange(next, meta.reason || 'set', meta.event);
            } finally {
                if (this._changeFocusOrigin === focusOrigin) this._changeFocusOrigin = null;
            }
        }
        return changed;
    };
    QuantityControl.prototype.update = function(state) {
        if (this._destroyed) return false;
        state = state || {};
        if (state.onChange) this._options.onChange = state.onChange;
        if (state.showPlusFive != null) this._options.showPlusFive = state.showPlusFive;
        if (state.showMax != null) this._options.showMax = state.showMax;
        if (state.showRange != null) this._options.showRange = state.showRange;
        if (state.sliderScale != null) this._options.sliderScale = state.sliderScale;
        if (state.maxLabel != null) this._options.maxLabel = state.maxLabel;
        if (state.maxAriaLabel != null) this._options.maxAriaLabel = state.maxAriaLabel;
        if (state.linearSliderThreshold != null) {
            this._options.linearSliderThreshold = state.linearSliderThreshold;
        }
        this._min = Math.max(0, Math.floor(Number(state.min == null ? this._min : state.min) || 0));
        this._max = Math.max(this._min, Math.floor(Number(state.max == null ? this._max : state.max) || 0));
        var presetMax = Math.floor(Number(state.presetMax == null ? this._max : state.presetMax));
        if (!isFinite(presetMax)) presetMax = this._max;
        this._presetMax = Math.max(0, Math.min(this._max, presetMax));
        var sliderMax = Object.prototype.hasOwnProperty.call(state, 'sliderMax')
            ? Math.floor(Number(state.sliderMax)) : this._max;
        this._sliderMax = isFinite(sliderMax) ? Math.max(0, Math.min(this._max, sliderMax)) : this._max;
        this._value = this._clamp(state.value == null ? this._value : state.value);
        var nextDisabled = !!state.disabled;
        var activeElement = this._document.activeElement;
        var restoreOrigin = activeElement && this.root.contains(activeElement)
            ? activeElement : this._changeFocusOrigin && this.root.contains(this._changeFocusOrigin)
                ? this._changeFocusOrigin : null;
        if (!this._disabled && nextDisabled && restoreOrigin) {
            this._pendingFocusRestore = restoreOrigin;
            this._pendingFocusFallback = null;
            this._changeFocusOrigin = null;
        }
        this._disabled = nextDisabled;
        if (this._numberDraft != null && this._document.activeElement !== this.numberInput) {
            this._numberDraft = null;
            this._setValidation(null);
        }
        this._render();
        if (this._disabled && this._pendingFocusRestore) {
            this._pendingFocusFallback = this._document.activeElement;
        }
        if (!this._disabled && this._pendingFocusRestore) {
            var restoreTarget = this._pendingFocusRestore;
            var fallbackFocus = this._pendingFocusFallback;
            this._pendingFocusRestore = null;
            this._pendingFocusFallback = null;
            var currentFocus = this._document.activeElement;
            var secondary = enclosingSecondaryOwner(this.root);
            var neutralFocus = !currentFocus
                || currentFocus === restoreTarget
                || currentFocus === this._document.body
                || currentFocus === this._document.documentElement
                || currentFocus === fallbackFocus
                || secondary && currentFocus === secondary._initialFocus;
            if (neutralFocus && restoreTarget.parentNode && !restoreTarget.disabled
                    && typeof restoreTarget.focus === 'function') {
                restoreTarget.focus();
            }
        }
        return true;
    };
    QuantityControl.prototype.getValue = function() { return this._value; };
    QuantityControl.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._lifetime.dispose();
        if (this._options.removeOnDestroy) removeNode(this.root);
        return true;
    };

    return {
        SecondaryPage: SecondaryPage,
        ChoiceGroup: ChoiceGroup,
        CommitBar: CommitBar,
        HelpAction: HelpAction,
        OwnedInventoryPane: OwnedInventoryPane,
        QuantityControl: QuantityControl
    };
});
