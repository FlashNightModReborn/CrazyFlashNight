/** Fixed B7 preparation projection and one-level menu presentation. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchPreparationMenu = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var menuSequence = 0;
    var PROGRESSION_REASON = '完成基地整备后开放';
    var DEFAULT_LOCK_REASON = '构筑操作完成前不能切换整备目标。';
    var ROUTES = [
        {identity:'equipment', label:'装备', destinationKind:'current'},
        {identity:'battlebox', label:'战备箱', destinationKind:'local-view'},
        {identity:'tuning', label:'装备调制', destinationKind:'local-view'},
        {identity:'skills', label:'技能', destinationKind:'post-close'},
        {identity:'materials', label:'材料', destinationKind:'post-close'},
        {identity:'intelligence', label:'情报', destinationKind:'post-close'}
    ].map(function(route) { return Object.freeze(route); });
    Object.freeze(ROUTES);

    function noop() {}

    function normalizeQuestProgress(value) {
        if (typeof value === 'number') {
            return Number.isFinite(value) && Math.floor(value) === value
                ? value
                : 0;
        }
        if (typeof value !== 'string'
                || !/^[+-]?\d+$/.test(value.trim())) return 0;
        var parsed = Number(value.trim());
        return Number.isSafeInteger(parsed) ? parsed : 0;
    }

    function availability(visible, disabled, reason) {
        return {
            visible:!!visible,
            disabled:!!disabled,
            reason:reason == null ? '' : String(reason)
        };
    }

    function projectAvailability(questProgress, locked, lockReason) {
        var progress = normalizeQuestProgress(questProgress);
        var blockedByProgression = progress <= 13;
        var reason = locked
            ? String(lockReason || DEFAULT_LOCK_REASON)
            : '';
        return {
            equipment:availability(true, true, '当前'),
            battlebox:availability(
                true,
                blockedByProgression || !!locked,
                blockedByProgression ? PROGRESSION_REASON : reason),
            tuning:availability(
                true,
                blockedByProgression || !!locked,
                blockedByProgression ? PROGRESSION_REASON : reason),
            skills:availability(true, !!locked, reason),
            materials:availability(true, !!locked, reason),
            intelligence:availability(true, !!locked, reason)
        };
    }

    function PreparationMenuController(options) {
        options = options || {};
        if (!options.document || !options.host) {
            throw new Error('PreparationMenuController requires document and host');
        }
        this._document = options.document;
        this._host = options.host;
        this._uiData = options.uiData || null;
        this._onSelect = typeof options.onSelect === 'function'
            ? options.onSelect
            : noop;
        this._onChange = typeof options.onChange === 'function'
            ? options.onChange
            : noop;
        this._listeners = [];
        this._items = {};
        this._open = false;
        this._outsideListening = false;
        this._destroyed = false;
        this._suppressed = false;
        this._questProgress = this._uiData
            && typeof this._uiData.get === 'function'
            ? this._uiData.get('q')
            : undefined;
        this._locked = false;
        this._lockReason = '';
        this._availability = projectAvailability(this._questProgress, false, '');
        this._create();
        this._subscribe();
    }

    PreparationMenuController.prototype._listen =
        function(node, type, handler) {
            node.addEventListener(type, handler);
            this._listeners.push(function() {
                node.removeEventListener(type, handler);
            });
        };

    PreparationMenuController.prototype._create = function() {
        var self = this;
        var id = 'inventory-preparation-menu-' + (++menuSequence);
        this.wrapper = this._document.createElement('div');
        this.wrapper.className = 'inventory-preparation-menu';
        this.trigger = this._document.createElement('button');
        this.trigger.type = 'button';
        this.trigger.className = 'workbench-mode-btn inventory-preparation-trigger';
        this.trigger.textContent = '整备 ▾';
        this.trigger.setAttribute('data-header-action', 'preparation-menu');
        this.trigger.setAttribute('aria-haspopup', 'menu');
        this.trigger.setAttribute('aria-expanded', 'false');
        this.trigger.setAttribute('aria-controls', id);
        this.menu = this._document.createElement('div');
        this.menu.id = id;
        this.menu.className = 'inventory-preparation-popover';
        this.menu.setAttribute('role', 'menu');
        this.menu.setAttribute('aria-label', '整备目标');
        this.menu.hidden = true;
        this.wrapper.appendChild(this.trigger);
        this.wrapper.appendChild(this.menu);
        this._host.appendChild(this.wrapper);
        this._listen(this.trigger, 'click', function() {
            if (self._open) self.close(true);
            else self.open(false);
        });
        this._listen(this.trigger, 'keydown', function(event) {
            var key = event && event.key;
            if (key !== 'Enter' && key !== ' ' && key !== 'Spacebar'
                    && key !== 'ArrowDown') return;
            event.preventDefault();
            if (key === 'ArrowDown') {
                self.open(true);
            } else if (self._open) {
                self.close(true);
            } else {
                self.open(true);
            }
        });
        for (var i = 0; i < ROUTES.length; i++) {
            this._createItem(ROUTES[i]);
        }
    };

    PreparationMenuController.prototype._createItem = function(route) {
        var self = this;
        var item = this._document.createElement('button');
        var reason = this._document.createElement('span');
        item.type = 'button';
        item.className = 'inventory-preparation-item';
        item.setAttribute('role', 'menuitem');
        item.setAttribute('data-preparation-route', route.identity);
        item.tabIndex = -1;
        var label = this._document.createElement('span');
        label.className = 'inventory-preparation-label';
        label.textContent = route.label;
        reason.className = 'inventory-preparation-reason';
        reason.id = this.menu.id + '-' + route.identity + '-reason';
        item.appendChild(label);
        item.appendChild(reason);
        this.menu.appendChild(item);
        this._items[route.identity] = {
            node:item,
            label:label,
            reason:reason,
            route:route
        };
        this._listen(item, 'click', function(event) {
            self._activate(route.identity, event && event.currentTarget || item);
        });
        this._listen(item, 'keydown', function(event) {
            self._handleMenuKey(event, route.identity);
        });
    };

    PreparationMenuController.prototype._subscribe = function() {
        if (!this._uiData || typeof this._uiData.on !== 'function') return;
        var self = this;
        this._qHandler = function(value) {
            self._questProgress = value;
            self._refreshAvailability();
            self._onChange(self.getAvailability());
        };
        this._uiData.on('q', this._qHandler);
    };

    PreparationMenuController.prototype._refreshAvailability = function() {
        this._availability = projectAvailability(
            this._questProgress,
            this._locked,
            this._lockReason);
        return this._availability;
    };

    PreparationMenuController.prototype.getAvailability = function() {
        var result = {};
        for (var i = 0; i < ROUTES.length; i++) {
            var key = ROUTES[i].identity;
            result[key] = Object.assign({}, this._availability[key]);
        }
        return result;
    };

    PreparationMenuController.prototype.updateLock = function(locked, reason) {
        this._locked = !!locked;
        this._lockReason = this._locked ? String(reason || '') : '';
        this._refreshAvailability();
        return this.getAvailability();
    };

    PreparationMenuController.prototype.applyProjection = function(items) {
        if (!items || Object.keys(items).length !== ROUTES.length) {
            throw new Error('Preparation menu projection rejected');
        }
        for (var i = 0; i < ROUTES.length; i++) {
            var route = ROUTES[i];
            var state = items[route.identity];
            var item = this._items[route.identity];
            if (!state || state.destinationKind !== route.destinationKind
                    || typeof state.visible !== 'boolean'
                    || typeof state.disabled !== 'boolean'
                    || typeof state.reason !== 'string'
                    || typeof state.current !== 'boolean') {
                throw new Error('Preparation menu item projection rejected');
            }
            item.node.hidden = !state.visible;
            item.node.setAttribute(
                'aria-disabled',
                state.disabled ? 'true' : 'false');
            if (state.current) item.node.setAttribute('aria-current', 'page');
            else item.node.removeAttribute('aria-current');
            item.reason.textContent = state.reason;
            item.reason.hidden = !state.reason;
            if (state.reason) {
                item.node.setAttribute('aria-describedby', item.reason.id);
                item.node.setAttribute('title', state.reason);
            } else {
                item.node.removeAttribute('aria-describedby');
                item.node.removeAttribute('title');
            }
        }
        return items;
    };

    PreparationMenuController.prototype._visibleItems = function() {
        var result = [];
        for (var i = 0; i < ROUTES.length; i++) {
            var item = this._items[ROUTES[i].identity].node;
            if (!item.hidden) result.push(item);
        }
        return result;
    };

    PreparationMenuController.prototype._focusInitial = function() {
        var current = this._items.equipment
            && this._items.equipment.node;
        var target = current && !current.hidden ? current : null;
        var visible = this._visibleItems();
        if (!target) {
            for (var i = 0; i < visible.length; i++) {
                if (visible[i].getAttribute('aria-disabled') !== 'true') {
                    target = visible[i];
                    break;
                }
            }
        }
        target = target || visible[0] || null;
        if (target) {
            target.tabIndex = 0;
            target.focus();
        }
        return target;
    };

    PreparationMenuController.prototype._listenOutside = function() {
        if (this._outsideListening) return;
        var self = this;
        this._outsidePointer = function(event) {
            if (!self.wrapper.contains(event.target)) self.close(false);
        };
        this._outsideFocus = function(event) {
            if (!self.wrapper.contains(event.target)) self.close(false);
        };
        this._document.addEventListener('pointerdown', this._outsidePointer);
        this._document.addEventListener('focusin', this._outsideFocus);
        this._outsideListening = true;
    };

    PreparationMenuController.prototype._unlistenOutside = function() {
        if (!this._outsideListening) return;
        this._document.removeEventListener('pointerdown', this._outsidePointer);
        this._document.removeEventListener('focusin', this._outsideFocus);
        this._outsidePointer = null;
        this._outsideFocus = null;
        this._outsideListening = false;
    };

    PreparationMenuController.prototype.open = function(focusMenu) {
        if (this._destroyed || this._suppressed) return false;
        if (!this._open) {
            this._open = true;
            this.menu.hidden = false;
            this.trigger.setAttribute('aria-expanded', 'true');
            this._listenOutside();
        }
        if (focusMenu) this._focusInitial();
        return true;
    };

    PreparationMenuController.prototype.close = function(restoreFocus) {
        if (!this._open) return false;
        this._open = false;
        this.menu.hidden = true;
        this.trigger.setAttribute('aria-expanded', 'false');
        this._unlistenOutside();
        var visible = this._visibleItems();
        for (var i = 0; i < visible.length; i++) visible[i].tabIndex = -1;
        if (restoreFocus && !this._suppressed) this.trigger.focus();
        return true;
    };

    PreparationMenuController.prototype._activate = function(identity, opener) {
        var item = this._items[identity];
        if (!item || item.node.hidden
                || item.node.getAttribute('aria-disabled') === 'true') return false;
        this.close(false);
        return this._onSelect(identity, opener) !== false;
    };

    PreparationMenuController.prototype._handleMenuKey =
        function(event, identity) {
            var key = event && event.key;
            if (key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                this.close(true);
                return;
            }
            if (key === 'Tab') {
                this.close(false);
                return;
            }
            if (key === 'Enter' || key === ' ' || key === 'Spacebar') {
                event.preventDefault();
                this._activate(identity, event.currentTarget);
                return;
            }
            if (key !== 'ArrowDown' && key !== 'ArrowUp'
                    && key !== 'Home' && key !== 'End') return;
            event.preventDefault();
            var visible = this._visibleItems();
            if (!visible.length) return;
            var current = this._items[identity].node;
            var index = visible.indexOf(current);
            if (key === 'Home') index = 0;
            else if (key === 'End') index = visible.length - 1;
            else if (key === 'ArrowDown') index = (index + 1) % visible.length;
            else index = (index - 1 + visible.length) % visible.length;
            for (var i = 0; i < visible.length; i++) visible[i].tabIndex = -1;
            visible[index].tabIndex = 0;
            visible[index].focus();
        };

    PreparationMenuController.prototype.setSuppressed = function(value) {
        this._suppressed = !!value;
        if (this._suppressed) this.close(false);
        this.wrapper.hidden = this._suppressed;
        if (this._suppressed) this.wrapper.setAttribute('inert', '');
        else this.wrapper.removeAttribute('inert');
        return this._suppressed;
    };

    PreparationMenuController.prototype.consumeEscape = function() {
        if (!this._open) return false;
        this.close(true);
        return true;
    };

    PreparationMenuController.prototype.focusTrigger = function() {
        if (this._destroyed || this._suppressed || this.trigger.hidden) return false;
        this.trigger.focus();
        return true;
    };

    PreparationMenuController.prototype.isOpen = function() {
        return this._open;
    };

    PreparationMenuController.prototype.destroy = function() {
        if (this._destroyed) return false;
        this.close(false);
        this._destroyed = true;
        if (this._uiData && this._qHandler
                && typeof this._uiData.off === 'function') {
            this._uiData.off('q', this._qHandler);
        }
        this._qHandler = null;
        for (var i = this._listeners.length - 1; i >= 0; i--) {
            this._listeners[i]();
        }
        this._listeners = [];
        if (this.wrapper.parentNode) {
            this.wrapper.parentNode.removeChild(this.wrapper);
        }
        return true;
    };

    return {
        PROGRESSION_REASON:PROGRESSION_REASON,
        ROUTES:ROUTES,
        normalizeQuestProgress:normalizeQuestProgress,
        projectAvailability:projectAvailability,
        PreparationMenuController:PreparationMenuController
    };
});
