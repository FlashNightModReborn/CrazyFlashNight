/** Shared focus scope for workbench dialogs and secondary pages. */
(function(root, factory) {
    'use strict';
    var lifecycle = typeof module !== 'undefined' && module.exports
        ? require('./workbench-lifecycle.js')
        : root && (root.WorkbenchLifecycle || root.CF7 && root.CF7.WorkbenchLifecycle);
    var api = factory(lifecycle);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.WorkbenchFocus = api;
        root.WorkbenchFocus = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function(WorkbenchLifecycle) {
    'use strict';

    if (!WorkbenchLifecycle || !WorkbenchLifecycle.DisposableStack) {
        throw new Error('workbench-focus.js requires workbench-lifecycle.js');
    }

    var DisposableStack = WorkbenchLifecycle.DisposableStack;
    var activeScopes = [];
    var suppressedNodes = [];
    var FOCUSABLE_SELECTOR = [
        'button:not([disabled])', 'a[href]', 'input:not([disabled])',
        'select:not([disabled])', 'textarea:not([disabled])',
        '[tabindex]:not([tabindex="-1"])', '[contenteditable="true"]'
    ].join(',');

    function asArray(value) {
        if (!value) return [];
        if (Array.isArray(value)) return value.slice();
        if (typeof value.length === 'number' && !value.nodeType && typeof value !== 'string') {
            return Array.prototype.slice.call(value);
        }
        return [value];
    }

    function resolveValue(value, scope) {
        if (typeof value === 'function') value = value(scope);
        if (typeof value === 'string') return scope.root.querySelector(value);
        return value || null;
    }

    function isSuppressedInTree(node) {
        for (var current = node; current; current = current.parentNode) {
            if (current.hidden || current.inert === true) return true;
            if (current.getAttribute && (current.getAttribute('aria-hidden') === 'true'
                    || current.hasAttribute && current.hasAttribute('inert'))) return true;
        }
        return false;
    }

    function canFocus(node) {
        if (!node || typeof node.focus !== 'function' || node.disabled || node.hidden) return false;
        if (node.getAttribute && (node.getAttribute('aria-hidden') === 'true'
                || node.getAttribute('aria-disabled') === 'true')) return false;
        return !isSuppressedInTree(node);
    }

    function focusables(root) {
        if (!root || typeof root.querySelectorAll !== 'function') return [];
        return Array.prototype.filter.call(root.querySelectorAll(FOCUSABLE_SELECTOR), canFocus);
    }

    function focusNode(node) {
        if (!canFocus(node)) return false;
        try { node.focus({preventScroll:true}); }
        catch (_) { node.focus(); }
        return true;
    }

    function suppressionRecord(node) {
        for (var i = 0; i < suppressedNodes.length; i++) {
            if (suppressedNodes[i].node === node) return suppressedNodes[i];
        }
        return null;
    }

    function suppress(nodes, root) {
        var tokens = [];
        var seen = [];
        asArray(nodes).forEach(function(node) {
            if (!node || node === root || node.contains && node.contains(root)) return;
            if (seen.indexOf(node) >= 0) return;
            seen.push(node);
            var hasAttribute = typeof node.hasAttribute === 'function';
            var record = suppressionRecord(node);
            if (!record) {
                record = {
                    node:node,
                    depth:0,
                    hadAriaHidden:hasAttribute && node.hasAttribute('aria-hidden'),
                    ariaHidden:node.getAttribute ? node.getAttribute('aria-hidden') : null,
                    hadInert:hasAttribute && node.hasAttribute('inert'),
                    inertValue:'inert' in node ? !!node.inert : null
                };
                suppressedNodes.push(record);
            }
            record.depth++;
            tokens.push(record);
            if ('inert' in node) node.inert = true;
            if (node.setAttribute) {
                node.setAttribute('inert', '');
                node.setAttribute('aria-hidden', 'true');
            }
        });
        return tokens;
    }

    function restore(tokens) {
        for (var i = tokens.length - 1; i >= 0; i--) {
            var record = tokens[i];
            if (!record.node) continue;
            record.depth--;
            if (record.depth > 0) continue;
            if ('inert' in record.node && record.inertValue != null) record.node.inert = record.inertValue;
            if (record.node.removeAttribute && !record.hadInert) record.node.removeAttribute('inert');
            if (record.node.setAttribute && record.hadAriaHidden) {
                record.node.setAttribute('aria-hidden', record.ariaHidden == null ? '' : record.ariaHidden);
            } else if (record.node.removeAttribute) record.node.removeAttribute('aria-hidden');
            var recordIndex = suppressedNodes.indexOf(record);
            if (recordIndex >= 0) suppressedNodes.splice(recordIndex, 1);
        }
    }

    function removeActive(scope) {
        var index = activeScopes.indexOf(scope);
        if (index >= 0) activeScopes.splice(index, 1);
    }

    function FocusScope(options) {
        options = options || {};
        if (!options.root) throw new Error('FocusScope requires a root');
        this.root = options.root;
        this._options = options;
        this._document = options.document || this.root.ownerDocument
            || (typeof document !== 'undefined' ? document : null);
        if (!this._document) throw new Error('FocusScope requires a document');
        this._session = null;
        this._opener = null;
        this._active = false;
        this._destroyed = false;
    }

    FocusScope.prototype._isTop = function() {
        return activeScopes.length > 0 && activeScopes[activeScopes.length - 1] === this;
    };

    FocusScope.prototype._focusInitial = function(context) {
        var target = resolveValue(context && context.initialFocus != null
            ? context.initialFocus : this._options.initialFocus, this);
        if (!canFocus(target)) {
            var candidates = focusables(this.root);
            target = candidates.length ? candidates[0] : this.root;
        }
        if (target === this.root && this.root.getAttribute && this.root.getAttribute('tabindex') == null) {
            this.root.setAttribute('tabindex', '-1');
            var root = this.root;
            this._session.defer(function() { root.removeAttribute('tabindex'); });
        }
        focusNode(target);
    };

    FocusScope.prototype._handleKeyDown = function(event) {
        if (!this._isTop()) return;
        if (event.key === 'Escape' || event.key === 'Esc') {
            event.preventDefault();
            if (event.stopPropagation) event.stopPropagation();
            var result = typeof this._options.onEscape === 'function'
                ? this._options.onEscape(event, this) : undefined;
            if (result !== false && this._active) this.deactivate('escape');
            return;
        }
        if (event.key !== 'Tab') return;
        var candidates = focusables(this.root);
        if (!candidates.length) {
            event.preventDefault();
            focusNode(this.root);
            return;
        }
        var current = this._document.activeElement;
        var index = candidates.indexOf(current);
        if (event.shiftKey && index <= 0) {
            event.preventDefault(); focusNode(candidates[candidates.length - 1]);
        } else if (!event.shiftKey && (index < 0 || index === candidates.length - 1)) {
            event.preventDefault(); focusNode(candidates[0]);
        }
    };

    FocusScope.prototype.activate = function(context) {
        if (this._destroyed) return false;
        if (this._active) return true;
        context = context || {};
        this._active = true;
        this._opener = context.opener || this._document.activeElement || null;
        this._session = new DisposableStack({onError:this._options.onError});
        var self = this;
        try {
            var underlay = resolveValue(context.underlay != null ? context.underlay : this._options.underlay, this);
            var records = suppress(underlay, this.root);
            this._session.defer(function() { restore(records); });
            activeScopes.push(this);
            this._session.defer(function() { removeActive(self); });
            this._session.listen(this._document, 'keydown', function(event) { self._handleKeyDown(event); }, true);
            this._session.listen(this._document, 'focusin', function(event) {
                if (!self._isTop() || !self.root.contains || self.root.contains(event.target)) return;
                self._focusInitial({});
            }, true);
            this._focusInitial(context);
        } catch (error) {
            this._active = false;
            this._session.dispose();
            this._session = null;
            this._opener = null;
            throw error;
        }
        return true;
    };

    FocusScope.prototype.deactivate = function(reason, context) {
        if (!this._active) return false;
        context = context || {};
        var firstError = null;
        for (var i = activeScopes.length - 1; i >= 0; i--) {
            var child = activeScopes[i];
            if (child === this) break;
            if (!this.root.contains || !this.root.contains(child.root)) continue;
            try {
                if (typeof child._options.onAncestorDeactivate === 'function') {
                    child._options.onAncestorDeactivate('ancestor-' + (reason || 'close'), child);
                }
            } catch (error) { if (!firstError) firstError = error; }
            try {
                if (child._active) child.deactivate('ancestor-' + (reason || 'close'), {restoreFocus:false});
            } catch (childError) { if (!firstError) firstError = childError; }
        }
        this._active = false;
        var session = this._session;
        this._session = null;
        if (session) session.dispose();
        var opener = Object.prototype.hasOwnProperty.call(context, 'restoreFocusTarget')
            ? context.restoreFocusTarget : this._opener;
        this._opener = null;
        if (context.restoreFocus !== false && this._options.restoreFocus !== false
                && opener && opener !== this.root) focusNode(opener);
        if (firstError) throw firstError;
        return true;
    };

    FocusScope.prototype.destroy = function() {
        if (this._destroyed) return false;
        this.deactivate('destroy');
        this._destroyed = true;
        return true;
    };
    FocusScope.prototype.isActive = function() { return this._active; };

    function RovingGridFocus(options) {
        options = options || {};
        if (!options.root) throw new Error('RovingGridFocus requires a root');
        this.root = options.root;
        this._options = options;
        this._document = options.document || this.root.ownerDocument
            || (typeof document !== 'undefined' ? document : null);
        if (!this._document) throw new Error('RovingGridFocus requires a document');
        this._items = [];
        this._records = [];
        this._activeKey = options.activeKey == null ? '' : String(options.activeKey);
        this._destroyed = false;
        this._lifetime = new DisposableStack({onError:options.onError});
        var self = this;
        this._lifetime.listen(this.root, 'keydown', function(event) { self._handleKeyDown(event); });
        this._lifetime.listen(this.root, 'focusin', function(event) { self._handleFocusIn(event); });
        this.refresh({preferredKey:this._activeKey});
    }

    RovingGridFocus.prototype._keyFor = function(node, index) {
        var key = typeof this._options.getKey === 'function'
            ? this._options.getKey(node, index, this)
            : node && node.getAttribute
                ? node.getAttribute(this._options.keyAttribute || 'data-roving-key') : null;
        return key == null || key === '' ? '' : String(key);
    };

    RovingGridFocus.prototype._eligible = function(node, index) {
        if (!node || typeof node.setAttribute !== 'function') return false;
        if (typeof this._options.isEligible === 'function') {
            return this._options.isEligible(node, index, this) !== false;
        }
        return !node.disabled && !node.hidden && !isSuppressedInTree(node)
            && (!node.getAttribute || node.getAttribute('aria-hidden') !== 'true');
    };

    RovingGridFocus.prototype._readItems = function() {
        var source = typeof this._options.items === 'function'
            ? this._options.items(this.root, this)
            : this._options.items;
        if (!source && this.root.querySelectorAll) {
            source = this.root.querySelectorAll(this._options.itemSelector || '[data-roving-key]');
        }
        var self = this;
        return asArray(source).filter(function(node, index) {
            return self._eligible(node, index) && !!self._keyFor(node, index);
        });
    };

    RovingGridFocus.prototype._record = function(node) {
        for (var i = 0; i < this._records.length; i++) {
            if (this._records[i].node === node) return this._records[i];
        }
        var record = {
            node:node,
            hadTabindex:node.hasAttribute && node.hasAttribute('tabindex'),
            tabindex:node.getAttribute ? node.getAttribute('tabindex') : null
        };
        this._records.push(record);
        return record;
    };

    RovingGridFocus.prototype._restoreRecord = function(record) {
        if (!record || !record.node) return;
        if (record.hadTabindex) record.node.setAttribute('tabindex', record.tabindex);
        else if (record.node.removeAttribute) record.node.removeAttribute('tabindex');
    };

    RovingGridFocus.prototype._pruneRecords = function() {
        for (var i = this._records.length - 1; i >= 0; i--) {
            if (this._items.indexOf(this._records[i].node) >= 0) continue;
            this._restoreRecord(this._records[i]);
            this._records.splice(i, 1);
        }
    };

    RovingGridFocus.prototype._nodeFor = function(target) {
        if (typeof target === 'number') return this._items[target] || null;
        if (target && typeof target !== 'string') {
            return this._items.indexOf(target) >= 0 ? target : null;
        }
        var key = target == null ? '' : String(target);
        for (var i = 0; i < this._items.length; i++) {
            if (this._keyFor(this._items[i], i) === key) return this._items[i];
        }
        return null;
    };

    RovingGridFocus.prototype._itemForTarget = function(target) {
        for (var node = target; node && node !== this.root; node = node.parentNode) {
            if (this._items.indexOf(node) >= 0) return node;
        }
        return this._items.indexOf(this.root) >= 0 ? this.root : null;
    };

    RovingGridFocus.prototype._applyTabStops = function(activeNode) {
        for (var i = 0; i < this._items.length; i++) {
            var node = this._items[i];
            this._record(node);
            node.setAttribute('tabindex', node === activeNode ? '0' : '-1');
        }
    };

    RovingGridFocus.prototype.refresh = function(options) {
        if (this._destroyed) return false;
        if (typeof options === 'string') options = {preferredKey:options};
        options = options || {};
        this._items = this._readItems();
        this._pruneRecords();
        if (!this._items.length) {
            this._activeKey = '';
            return false;
        }
        var activeNode = this._nodeFor(this._activeKey);
        if (!activeNode && options.preferredKey != null) activeNode = this._nodeFor(String(options.preferredKey));
        if (!activeNode) activeNode = this._itemForTarget(this._document.activeElement);
        if (!activeNode) activeNode = this._items[0];
        this._activeKey = this._keyFor(activeNode, this._items.indexOf(activeNode));
        this._applyTabStops(activeNode);
        if (options.focus === true) focusNode(activeNode);
        return true;
    };

    RovingGridFocus.prototype.setActive = function(target, options) {
        if (this._destroyed) return false;
        options = options || {};
        var node = this._nodeFor(target);
        if (!node) return false;
        var previous = this._activeKey;
        this._activeKey = this._keyFor(node, this._items.indexOf(node));
        this._applyTabStops(node);
        if (options.focus !== false) focusNode(node);
        if ((previous !== this._activeKey || options.notifySame)
                && typeof this._options.onActiveChange === 'function') {
            this._options.onActiveChange(this._activeKey, node, options.reason || 'programmatic', this);
        }
        return true;
    };

    RovingGridFocus.prototype._handleFocusIn = function(event) {
        if (this._destroyed) return;
        var node = this._itemForTarget(event && event.target);
        if (node) this.setActive(node, {focus:false, reason:'focus'});
    };

    RovingGridFocus.prototype._explicitNeighbor = function(node, direction) {
        var index = this._items.indexOf(node);
        var key = this._keyFor(node, index);
        var target = null;
        if (typeof this._options.getNeighbor === 'function') {
            target = this._options.getNeighbor({
                key:key, node:node, index:index, direction:direction,
                items:this._items.slice(), controller:this
            });
        } else if (this._options.neighbors) {
            var entry = this._options.neighbors[key];
            target = entry && entry[direction];
        } else return undefined;
        return target == null || target === '' ? null : this._nodeFor(target);
    };

    RovingGridFocus.prototype._columnNeighbor = function(node, direction) {
        var index = this._items.indexOf(node);
        if (index < 0) return null;
        var columns = typeof this._options.columns === 'function'
            ? this._options.columns(this) : this._options.columns;
        columns = Math.max(1, Math.floor(Number(columns) || 1));
        var rowStart = Math.floor(index / columns) * columns;
        var rowEnd = Math.min(this._items.length - 1, rowStart + columns - 1);
        if (direction === 'left') return index > rowStart ? this._items[index - 1] : node;
        if (direction === 'right') return index < rowEnd ? this._items[index + 1] : node;
        if (direction === 'up') return index >= columns ? this._items[index - columns] : node;
        if (direction === 'down') return index + columns < this._items.length ? this._items[index + columns] : node;
        return node;
    };

    RovingGridFocus.prototype._handleKeyDown = function(event) {
        if (this._destroyed || !event || event.altKey || event.ctrlKey || event.metaKey) return;
        var directions = {ArrowLeft:'left', ArrowRight:'right', ArrowUp:'up', ArrowDown:'down'};
        var node = this._itemForTarget(event.target);
        if (!node) return;
        var target = null;
        if (directions[event.key]) {
            target = this._explicitNeighbor(node, directions[event.key]);
            if (target === undefined) target = this._columnNeighbor(node, directions[event.key]);
        } else if (event.key === 'Home') target = this._items[0];
        else if (event.key === 'End') target = this._items[this._items.length - 1];
        else return;
        if (event.preventDefault) event.preventDefault();
        if (target) this.setActive(target, {reason:'keyboard'});
    };

    RovingGridFocus.prototype.getActiveKey = function() { return this._activeKey; };
    RovingGridFocus.prototype.getActiveNode = function() { return this._nodeFor(this._activeKey); };
    RovingGridFocus.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._lifetime.dispose();
        for (var i = this._records.length - 1; i >= 0; i--) {
            this._restoreRecord(this._records[i]);
        }
        this._items = [];
        this._records = [];
        return true;
    };

    return {
        FocusScope:FocusScope,
        RovingGridFocus:RovingGridFocus,
        focusables:focusables,
        debugActiveCount:function() { return activeScopes.length; }
    };
});
