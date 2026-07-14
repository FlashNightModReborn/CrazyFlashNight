/**
 * Inventory UI components.
 *
 * Owns window pagination math, page-menu/keyboard behavior and inventory view
 * controls (display sort / category filter / authority sort intent). Authority,
 * leases and writes remain in InventoryRuntime.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryUI = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function integerOr(value, fallback) {
        value = Number(value);
        return isFinite(value) && Math.floor(value) === value ? value : fallback;
    }

    function derivePageState(snapshot, request, defaults) {
        defaults = defaults || {};
        var defaultOffset = Math.max(0, integerOr(defaults.offset, 0));
        var defaultLimit = Math.max(1, integerOr(defaults.limit, 50));
        var defaultCapacity = Math.max(0, integerOr(defaults.capacity, defaultLimit));
        var offset = snapshot ? integerOr(snapshot.offset, defaultOffset)
            : request ? integerOr(request.offset, defaultOffset) : defaultOffset;
        var limit = request ? integerOr(request.limit, defaultLimit) : defaultLimit;
        var physicalCapacity = snapshot ? integerOr(snapshot.capacity, defaultCapacity) : defaultCapacity;
        var accessibleCapacity = snapshot && snapshot.accessibleCapacity != null
            ? integerOr(snapshot.accessibleCapacity, physicalCapacity) : physicalCapacity;
        var capacity = snapshot && snapshot.viewCapacity != null
            ? integerOr(snapshot.viewCapacity, accessibleCapacity) : accessibleCapacity;
        var filterKey = snapshot && snapshot.filterKey != null
            ? String(snapshot.filterKey) : request && request.filterKey != null
                ? String(request.filterKey) : 'all';
        var filterSpec = snapshot && snapshot.filterSpec != null
            ? snapshot.filterSpec : request && request.filterSpec != null ? request.filterSpec : null;
        offset = Math.max(0, offset);
        limit = Math.max(1, limit);
        capacity = Math.max(0, capacity);
        var pageCount = Math.max(1, Math.ceil(capacity / limit));
        var page = Math.max(1, Math.min(pageCount, Math.floor(offset / limit) + 1));
        return {
            offset: offset,
            limit: limit,
            capacity: capacity,
            accessibleCapacity: Math.max(0, accessibleCapacity),
            physicalCapacity: Math.max(capacity, physicalCapacity),
            filterKey: filterKey,
            filterSpec: filterSpec,
            filtered: filterKey !== 'all' || !!(filterSpec && String(filterSpec.major || 'all') !== 'all'),
            page: page,
            pageCount: pageCount,
            rangeStart: capacity > 0 ? Math.min(capacity, offset + 1) : 0,
            rangeEnd: Math.min(capacity, offset + limit)
        };
    }

    function pageFromShortcut(event, state) {
        if (!event || !state) return null;
        if (event.key === 'PageUp') return state.page - 1;
        if (event.key === 'PageDown') return state.page + 1;
        if (event.ctrlKey && event.key === 'Home') return 1;
        if (event.ctrlKey && event.key === 'End') return state.pageCount;
        return null;
    }

    function appendSelectOption(select, value, label) {
        var option = document.createElement('option');
        option.value = value;
        option.textContent = label;
        select.appendChild(option);
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    function escapeAttr(value) {
        return escapeHtml(value).replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function compactQuantity(value) {
        var quantity = Math.max(0, Math.floor(Number(value) || 0));
        if (quantity < 10000) return String(quantity);
        var unitValue = quantity >= 100000000 ? 100000000 : 10000;
        var unitLabel = unitValue === 100000000 ? '亿' : '万';
        var scaled = quantity / unitValue;
        var compact = scaled < 10 ? Math.floor(scaled * 10) / 10 : Math.floor(scaled);
        return String(compact).replace(/\.0$/, '') + unitLabel;
    }

    function exactQuantity(value) {
        return String(Math.max(0, Math.floor(Number(value) || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function normalizeModGrade(value) {
        var grade = String(value || 'unknown');
        return grade === 'low' || grade === 'medium' || grade === 'high' || grade === 'special'
            ? grade : 'unknown';
    }

    function normalizeModSymbol(value) {
        var symbol = String(value || 'diamond-outline');
        var legacy = {triangle:'triangle-solid',square:'square-outline',circle:'circle-outline',diamond:'diamond-outline',star:'star-solid'};
        if (legacy[symbol]) symbol = legacy[symbol];
        return /^(triangle|square|circle|diamond|star)-(solid|outline)$/.test(symbol)
            ? symbol : 'diamond-outline';
    }

    function normalizeModGradeColor(value, grade) {
        var canonical = {low:'#006600',medium:'#996600',high:'#0099FF',special:'#FFFF00',unknown:'#58636E'};
        var color = String(value || '').toUpperCase();
        return color === canonical[grade] ? color : canonical[grade];
    }

    function renderTierMarker(item) {
        if (!item.tierSlotAvailable && !item.tierSlotUsed) return '';
        var state = item.tierSlotUsed ? 'used' : 'empty';
        var label = state === 'used' ? '装备已升阶' : '装备可升阶但尚未升阶';
        return '<span class="inventory-tier-marker ' + state + '" aria-label="' + label + '"></span>';
    }

    function renderEquipmentSlotRail(item) {
        var html = '<span class="inventory-equip-slots" aria-label="三个插件槽状态">';
        var capacity = Math.max(0, Math.floor(Number(item.modSlotCapacity) || 0));
        var used = Math.max(0, Math.floor(Number(item.modSlotUsed) || 0));
        var modSlots = item.modSlots instanceof Array ? item.modSlots : [];
        for (var index = 0; index < 3; index++) {
            var available = index < capacity;
            var mod = index < modSlots.length ? modSlots[index] : null;
            if (available && index < used) {
                mod = mod || {name:'未知插件',grade:'unknown',gradeLabel:'未知档级',roleLabel:'结构与功能',symbol:'diamond-outline'};
                var grade = normalizeModGrade(mod.grade);
                var symbol = normalizeModSymbol(mod.symbol);
                var color = normalizeModGradeColor(mod.gradeColor, grade);
                var label = '插件槽 ' + (index + 1) + '：' + String(mod.name || '未知插件')
                    + '，' + String(mod.gradeLabel || '未知档级') + '，' + String(mod.roleLabel || '结构与功能');
                html += '<span class="inventory-equip-slot mod used grade-' + grade
                    + '" style="--mod-grade-color:' + color + '" aria-label="' + escapeAttr(label) + '">'
                    + '<span class="inventory-mod-glyph symbol-' + symbol + '" aria-hidden="true"></span></span>';
            } else {
                var state = available ? 'empty' : 'unavailable';
                html += '<span class="inventory-equip-slot mod ' + state + '" aria-label="插件槽 '
                    + (index + 1) + '：' + (available ? '空闲' : '不存在') + '"></span>';
            }
        }
        return html + '</span>';
    }

    /** Shared owned-slot presentation used by shop inventory and standalone workbenches. */
    function renderOwnedSlot(containerId, slot, options) {
        options = options || {};
        var node = document.createElement('article');
        node.className = 'item-card item-card-owned inventory-slot-card ' + (slot.occupied ? 'occupied' : 'empty');
        node.setAttribute('data-container-id', containerId);
        node.setAttribute('data-physical-slot', slot.physicalSlot);
        if (!slot.occupied) {
            node.setAttribute('aria-label', containerId + '空槽 ' + (Number(slot.physicalSlot) + 1));
            return node;
        }
        var item = slot.item || {};
        var isEquipment = item.itemKind === 'equipment';
        var badge = '';
        if (isEquipment && Number(item.enhancementLevel) > 1) {
            badge = '<span class="inventory-slot-value level" title="强化等级 ' + Number(item.enhancementLevel)
                + '" aria-label="强化等级 ' + Number(item.enhancementLevel) + '">' + Number(item.enhancementLevel) + '</span>';
        } else if (!isEquipment && Number(item.quantity) > 1) {
            badge = '<span class="inventory-slot-value quantity" title="数量 ' + exactQuantity(item.quantity)
                + '" aria-label="数量 ' + exactQuantity(item.quantity) + '">' + compactQuantity(item.quantity) + '</span>';
        }
        node.classList.add(isEquipment ? 'equipment' : 'stack');
        if (isEquipment && item.isMaxEnhancement) node.classList.add('max-enhancement');
        node.setAttribute('aria-label', containerId + '槽位 ' + (Number(slot.physicalSlot) + 1) + '，'
            + String(item.displayName || item.name || '未知物品'));
        var icon = typeof options.iconHtml === 'function'
            ? options.iconHtml(item.icon || item.name, 'inventory-owned-icon') : '';
        node.innerHTML = '<span class="item-card-icon inventory-slot-icon-frame"><span class="inventory-slot-icon">'
            + icon + '</span>' + (isEquipment ? renderTierMarker(item) : '') + badge + '</span>'
            + '<span class="item-card-body inventory-slot-copy"><b>' + escapeHtml(item.displayName || item.name || '未知物品') + '</b>'
            + (isEquipment ? renderEquipmentSlotRail(item) : '') + '</span>'
            + (options.allowDiscard ? '<button class="inventory-discard-btn" type="button" title="丢弃整槽" data-audio-cue="cancel">×</button>' : '');
        return node;
    }

    function InventoryWindowPager(options) {
        options = options || {};
        this.containerId = String(options.containerId || '');
        this.containerLabel = String(options.containerLabel || this.containerId || '库存');
        this.columns = Math.max(1, integerOr(options.columns, 6));
        this.defaults = {
            offset: Math.max(0, integerOr(options.defaultOffset, 0)),
            limit: Math.max(1, integerOr(options.defaultLimit, 50)),
            capacity: Math.max(0, integerOr(options.defaultCapacity, 0))
        };
        this.getSnapshot = options.getSnapshot || function() { return null; };
        this.getRequest = options.getRequest || function() { return null; };
        this.onBeforeChange = options.onBeforeChange || function() {};
        this.onRequest = options.onRequest || function(offset, limit, callback) {
            if (callback) callback({success: false, error: 'not_connected'});
            return false;
        };
        this.onResult = options.onResult || function() {};
        this.shortcutEnabled = options.shortcutEnabled || function() { return true; };
        this._disabled = false;
        this._attached = false;
        this._createDOM();
        this.refresh();
    }

    InventoryWindowPager.prototype._createDOM = function() {
        var self = this;
        this.root = document.createElement('div');
        this.root.className = 'inventory-warehouse-pager';

        this.prevButton = document.createElement('button');
        this.prevButton.type = 'button';
        this.prevButton.className = 'inventory-toolbar-btn inventory-page-prev';
        this.prevButton.textContent = '‹';
        this.prevButton.setAttribute('aria-label', '上一页' + this.containerLabel);
        this.prevButton.addEventListener('click', function() { self.requestRelative(-1); });

        this.pageLabel = document.createElement('button');
        this.pageLabel.type = 'button';
        this.pageLabel.className = 'inventory-toolbar-btn inventory-page-label inventory-page-jump';
        this.pageLabel.textContent = '1 / 1';
        this.pageLabel.setAttribute('aria-label', '选择' + this.containerLabel + '页码');
        this.pageLabel.setAttribute('aria-haspopup', 'menu');
        this.pageLabel.setAttribute('aria-expanded', 'false');
        this.pageLabel.addEventListener('click', function() { self.toggleMenu(); });

        this.nextButton = document.createElement('button');
        this.nextButton.type = 'button';
        this.nextButton.className = 'inventory-toolbar-btn inventory-page-next';
        this.nextButton.textContent = '›';
        this.nextButton.setAttribute('aria-label', '下一页' + this.containerLabel);
        this.nextButton.addEventListener('click', function() { self.requestRelative(1); });

        this.pageRange = document.createElement('span');
        this.pageRange.className = 'inventory-page-range';
        this.pageRange.setAttribute('aria-hidden', 'true');

        this.menu = document.createElement('div');
        this.menu.className = 'inventory-page-menu';
        this.menu.hidden = true;
        this.menu.setAttribute('role', 'menu');
        this.menu.setAttribute('aria-label', this.containerLabel + '页码快速跳转');
        this.pageGrid = document.createElement('div');
        this.pageGrid.className = 'inventory-page-grid';
        this.menu.appendChild(this.pageGrid);
        this.menu.addEventListener('keydown', function(event) { self._onMenuKeyDown(event); });

        this.root.appendChild(this.prevButton);
        this.root.appendChild(this.pageLabel);
        this.root.appendChild(this.nextButton);
        this.root.appendChild(this.pageRange);
        this.root.appendChild(this.menu);

        this._outsideHandler = function(event) {
            if (!self.menu.hidden && !self.root.contains(event.target)) self.setMenuOpen(false, false);
        };
        this._shortcutHandler = function(event) {
            if (!self.shortcutEnabled(event)) return;
            var page = pageFromShortcut(event, self.getState());
            if (page == null) return;
            event.preventDefault();
            event.stopPropagation();
            self.requestPage(page);
        };
    };

    InventoryWindowPager.prototype.getState = function() {
        return derivePageState(this.getSnapshot(), this.getRequest(), this.defaults);
    };

    InventoryWindowPager.prototype.refresh = function() {
        var state = this.getState();
        this.pageLabel.textContent = state.page + ' / ' + state.pageCount;
        var rangeName = state.filtered ? '匹配项' : '槽位';
        this.pageLabel.setAttribute('aria-label', '第 ' + state.page + ' 页，共 ' + state.pageCount
            + ' 页；' + rangeName + ' ' + state.rangeStart + ' 至 ' + state.rangeEnd + '，点击快速跳转');
        this.pageRange.textContent = state.rangeStart + '–' + state.rangeEnd + ' / ' + state.capacity;
        this.prevButton.setAttribute('data-boundary', state.page <= 1 ? 'start' : '');
        this.nextButton.setAttribute('data-boundary', state.page >= state.pageCount ? 'end' : '');
        this._renderMenu(state);
        this._applyDisabled(state);
        return state;
    };

    InventoryWindowPager.prototype._renderMenu = function(state) {
        var self = this;
        this.pageGrid.innerHTML = '';
        var fragment = document.createDocumentFragment();
        for (var page = 1; page <= state.pageCount; page++) {
            var start = (page - 1) * state.limit + 1;
            var end = Math.min(state.capacity, page * state.limit);
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'inventory-page-option';
            button.textContent = page < 10 ? '0' + page : String(page);
            button.setAttribute('role', 'menuitemradio');
            button.setAttribute('data-page', String(page));
            button.setAttribute('aria-checked', page === state.page ? 'true' : 'false');
            var rangeName = state.filtered ? '匹配项' : '槽位';
            button.setAttribute('aria-label', '第 ' + page + ' 页，' + rangeName + ' ' + start + ' 至 ' + end);
            button.title = '第 ' + page + ' 页 · ' + rangeName + ' ' + start + '–' + end;
            if (page === state.page) {
                button.classList.add('current');
                button.setAttribute('aria-current', 'page');
            }
            button.addEventListener('click', function(event) {
                self.requestPage(Number(event.currentTarget.getAttribute('data-page')));
            });
            fragment.appendChild(button);
        }
        this.pageGrid.appendChild(fragment);
    };

    InventoryWindowPager.prototype._applyDisabled = function(state) {
        this.prevButton.disabled = this._disabled || state.page <= 1;
        this.nextButton.disabled = this._disabled || state.page >= state.pageCount;
        this.pageLabel.disabled = this._disabled;
        if (this._disabled) this.setMenuOpen(false, false);
    };

    InventoryWindowPager.prototype.setDisabled = function(disabled) {
        this._disabled = !!disabled;
        this._applyDisabled(this.getState());
    };

    InventoryWindowPager.prototype.setMenuOpen = function(open, returnFocus) {
        var nextOpen = !!open && !this.pageLabel.disabled;
        this.menu.hidden = !nextOpen;
        this.pageLabel.setAttribute('aria-expanded', nextOpen ? 'true' : 'false');
        if (nextOpen) {
            var current = this.menu.querySelector('.inventory-page-option.current');
            if (current) current.focus();
        } else if (returnFocus) {
            this.pageLabel.focus();
        }
    };

    InventoryWindowPager.prototype.toggleMenu = function() {
        this.setMenuOpen(this.menu.hidden, false);
    };

    InventoryWindowPager.prototype._onMenuKeyDown = function(event) {
        if (this.menu.hidden) return;
        if (event.key === 'Escape') {
            event.preventDefault();
            event.stopPropagation();
            this.setMenuOpen(false, true);
            return;
        }
        var options = Array.prototype.slice.call(this.menu.querySelectorAll('.inventory-page-option'));
        if (!options.length) return;
        var index = options.indexOf(document.activeElement);
        var nextIndex = index < 0 ? 0 : index;
        if (event.key === 'ArrowRight') nextIndex = Math.min(options.length - 1, nextIndex + 1);
        else if (event.key === 'ArrowLeft') nextIndex = Math.max(0, nextIndex - 1);
        else if (event.key === 'ArrowDown') nextIndex = Math.min(options.length - 1, nextIndex + this.columns);
        else if (event.key === 'ArrowUp') nextIndex = Math.max(0, nextIndex - this.columns);
        else if (event.key === 'Home') nextIndex = 0;
        else if (event.key === 'End') nextIndex = options.length - 1;
        else return;
        event.preventDefault();
        options[nextIndex].focus();
    };

    InventoryWindowPager.prototype.requestRelative = function(direction) {
        var state = this.getState();
        return this.requestPage(state.page + Number(direction));
    };

    InventoryWindowPager.prototype.requestPage = function(page) {
        if (this._disabled) return false;
        var state = this.getState();
        page = Math.max(1, Math.min(state.pageCount, Math.floor(Number(page) || 1)));
        this.setMenuOpen(false, false);
        if (page === state.page) return false;
        this.onBeforeChange(state, page);
        var self = this;
        var offset = (page - 1) * state.limit;
        var started = this.onRequest(offset, state.limit, function(result) {
            self.refresh();
            self.onResult(result || {success: false, error: 'invalid_response'}, page);
        });
        if (!started) this.refresh();
        return !!started;
    };

    InventoryWindowPager.prototype.attach = function() {
        if (this._attached || typeof document === 'undefined') return;
        document.addEventListener('pointerdown', this._outsideHandler);
        document.addEventListener('keydown', this._shortcutHandler);
        this._attached = true;
    };

    InventoryWindowPager.prototype.detach = function() {
        if (!this._attached || typeof document === 'undefined') return;
        document.removeEventListener('pointerdown', this._outsideHandler);
        document.removeEventListener('keydown', this._shortcutHandler);
        this.setMenuOpen(false, false);
        this._attached = false;
    };

    function filterSpecFromPath(path) {
        path = Array.isArray(path) ? path : [];
        if (path[0] === 'set') {
            var setSpec = {branch:'set'};
            if (path.length > 1) setSpec.setId = String(path[1]);
            return setSpec;
        }
        var offset = path[0] === 'category' ? 1 : 0;
        var spec = {major:path.length > offset ? String(path[offset]) : 'all'};
        if (offset) spec.branch = 'category';
        if (path.length > offset + 1) spec.use = String(path[offset + 1]);
        if (path.length > offset + 2) spec.subtype = String(path[offset + 2]);
        return spec;
    }

    function filterPathFromSpec(spec, filterKey, branched) {
        if (!spec || typeof spec !== 'object') {
            filterKey = String(filterKey || 'all');
            return filterKey === 'all' ? [] : (branched ? ['category', filterKey] : [filterKey]);
        }
        if (spec.branch === 'set') return spec.setId ? ['set', String(spec.setId)] : ['set'];
        var path = String(spec.major || 'all') === 'all' ? [] : [String(spec.major)];
        if (spec.use) path.push(String(spec.use));
        if (spec.subtype) path.push(String(spec.subtype));
        if (branched && (path.length || spec.branch === 'category')) path.unshift('category');
        return path;
    }

    function InventoryFilterControl(options) {
        options = options || {};
        var self = this;
        this.options = options;
        this.presentation = options.presentation === 'popover' ? 'popover' : 'inline';
        this.root = document.createElement('div');
        this.root.className = 'inventory-toolbar-field filter inventory-filter-control';
        if (this.presentation === 'popover') this.root.classList.add('popover');
        if (options.label) {
            var label = document.createElement('span');
            label.className = 'inventory-toolbar-label';
            label.textContent = String(options.label);
            this.root.appendChild(label);
        }
        this.select = document.createElement('select');
        this.select.className = 'inventory-category-filter';
        this.select.setAttribute('aria-label', options.ariaLabel || '库存分类筛选');
        var values = options.options || [];
        for (var i = 0; i < values.length; i++) appendSelectOption(this.select, values[i].value, values[i].label);
        this.select.addEventListener('change', function() {
            if (options.onLegacyChange) options.onLegacyChange(self.select.value);
        });
        this.root.appendChild(this.select);
        this.trigger = null;
        if (this.presentation === 'popover') {
            this.trigger = document.createElement('button');
            this.trigger.type = 'button';
            this.trigger.className = 'inventory-filter-tree-trigger';
            this.trigger.hidden = true;
            this.trigger.setAttribute('aria-haspopup', 'true');
            this.trigger.setAttribute('aria-expanded', 'false');
            this.trigger.addEventListener('click', function() {
                if (self.disabled) return;
                var open = !self.root.classList.contains('open');
                self.root.classList.toggle('open', open);
                self.trigger.setAttribute('aria-expanded', open ? 'true' : 'false');
                if (open && self.navigator) {
                    var active = self.navigator.root.querySelector('.active');
                    if (active) active.focus();
                }
            });
            this.root.insertBefore(this.trigger, this.select);
            this.root.addEventListener('focusout', function() {
                setTimeout(function() {
                    if (!self.root.contains(document.activeElement)) self.closePopover();
                }, 0);
            });
            this.root.addEventListener('keydown', function(event) {
                if (event.key === 'Escape' && self.root.classList.contains('open')) {
                    event.preventDefault(); event.stopPropagation(); self.closePopover(); self.trigger.focus();
                }
            });
        }
        this.navigator = null;
        this.disabled = false;
        this.pendingSpec = null;
    }

    InventoryFilterControl.prototype.setSnapshot = function(snapshot) {
        if (!snapshot || !Array.isArray(snapshot.filterFacets) || typeof ItemFilter === 'undefined') {
            this.root.classList.remove('tree');
            this.closePopover();
            if (this.trigger) this.trigger.hidden = true;
            this.select.hidden = false;
            this.select.value = String(snapshot && snapshot.filterKey || this.select.value || 'all');
            if (this.navigator) {
                this.navigator.root.hidden = true;
                this.navigator.setPath([], true);
            }
            return false;
        }
        var self = this;
        if (!this.navigator) {
            this.navigator = new ItemFilter.FilterNavigator({
                className:'inventory-filter-navigator item-filter-navigator',
                ariaLabel:this.options.ariaLabel || '库存分类筛选',
                presentation:this.options.navigatorPresentation || 'drilldown',
                breadcrumbHost:this.options.breadcrumbHost,
                onChange:function(path, node) {
                    self.pendingSpec = filterSpecFromPath(path);
                    if (!node || !(node.children || []).length) self.closePopover();
                    if (self.options.onSpecChange) self.options.onSpecChange(self.pendingSpec, path);
                }
            });
            this.root.appendChild(this.navigator.root);
        }
        var categoryTree = ItemFilter.fromFacets(snapshot.filterFacets, Number(snapshot.filterItemCount) || 0);
        var branched = (Array.isArray(snapshot.setFacets) && snapshot.setFacets.length > 0)
            || (snapshot.filterSpec && snapshot.filterSpec.branch === 'set')
            || (this.pendingSpec && this.pendingSpec.branch === 'set');
        var tree = branched ? ItemFilter.branchTree([
            {id:'category', label:'类别', tree:categoryTree},
            {id:'set', label:'套装', tree:ItemFilter.fromFacets(snapshot.setFacets, Number(snapshot.setFilterItemCount) || 0)}
        ], Number(snapshot.filterItemCount) || 0) : categoryTree;
        var authoritativePath = filterPathFromSpec(snapshot.filterSpec, snapshot.filterKey, branched);
        var pendingPath = this.pendingSpec ? filterPathFromSpec(this.pendingSpec, 'all', branched) : null;
        if (pendingPath && pendingPath.join('/') === authoritativePath.join('/')) this.pendingSpec = null;
        var path = this.pendingSpec ? pendingPath : authoritativePath;
        this.navigator.root.hidden = false;
        this.navigator.setModel(tree, path);
        this.navigator.setDisabled(this.disabled);
        this.select.hidden = true;
        if (this.trigger) {
            this.trigger.hidden = false;
            var labels = [], cursor = tree;
            for (var i = 0; i < path.length; i++) {
                cursor = ItemFilter.nodeAt(cursor, [path[i]]);
                if (!cursor) break;
                labels.push(cursor.label);
            }
            this.trigger.textContent = (labels.length ? labels.join(' / ') : '全部') + '  ' + Number(tree.count || 0);
            this.trigger.title = labels.length ? labels.join(' / ') : '全部分类';
        }
        this.root.classList.add('tree');
        return true;
    };

    InventoryFilterControl.prototype.closePopover = function() {
        this.root.classList.remove('open');
        if (this.trigger) this.trigger.setAttribute('aria-expanded', 'false');
    };

    InventoryFilterControl.prototype.getFilterKey = function() { return this.select.value || 'all'; };
    InventoryFilterControl.prototype.setFilterKey = function(filterKey) { this.select.value = String(filterKey || 'all'); };
    InventoryFilterControl.prototype.setBreadcrumbHost = function(host) {
        this.options.breadcrumbHost = host || null;
        if (this.navigator) this.navigator.setBreadcrumbHost(this.options.breadcrumbHost);
    };
    InventoryFilterControl.prototype.setDisabled = function(disabled) {
        this.disabled = !!disabled;
        this.select.disabled = this.disabled;
        if (this.trigger) this.trigger.disabled = this.disabled;
        if (this.disabled) this.closePopover();
        if (this.navigator) this.navigator.setDisabled(this.disabled);
    };
    InventoryFilterControl.prototype.rejectPending = function(snapshot) {
        this.pendingSpec = null;
        this.setSnapshot(snapshot);
    };

    function AuthoritySortControl(options) {
        options = options || {};
        var self = this;
        this.root = document.createElement('label');
        this.root.className = 'inventory-toolbar-field authority';
        if (options.label) this.root.appendChild(document.createTextNode(String(options.label)));
        this.select = document.createElement('select');
        this.select.className = 'inventory-authority-sort';
        this.select.setAttribute('aria-label', options.ariaLabel || '库存整理方式');
        var values = options.options || [];
        for (var i = 0; i < values.length; i++) appendSelectOption(this.select, values[i].value, values[i].label);
        this.root.appendChild(this.select);
        this.button = document.createElement('button');
        this.button.type = 'button';
        this.button.className = 'inventory-toolbar-btn inventory-sort-commit';
        this.button.textContent = options.commitLabel || '整理';
        this.button.addEventListener('click', function() {
            if (options.onCommit) options.onCommit(self.select.value, self.getLabel());
        });
    }

    AuthoritySortControl.prototype.getLabel = function() {
        var option = this.select.options[this.select.selectedIndex];
        return option ? option.textContent : this.select.value;
    };
    AuthoritySortControl.prototype.setDisabled = function(disabled) {
        this.select.disabled = !!disabled;
        this.button.disabled = !!disabled;
    };

    /**
     * Shared owned-item view shell. It only composes Workbench primitives and
     * presentation callbacks; leases, writes and domain policies remain with
     * the caller's coordinator.
     */
    function OwnedInventoryViewShell(options) {
        options = options || {};
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required');
        this.containerId = String(options.containerId || options.viewId || 'owned');
        this.grid = new Workbench.ItemGrid({
            instanceKey:options.instanceKey || 'inventory:' + this.containerId,
            instancePolicy:options.instancePolicy,
            itemModel:'owned',
            getItems:options.getItems,
            keyOf:options.keyOf,
            renderItem:options.renderItem,
            bindItem:options.bindItem,
            exportOffer:options.exportOffer,
            probeAccept:options.probeAccept,
            title:options.title,
            kicker:options.kicker,
            meta:options.meta || '同步中',
            className:options.className || 'inventory-owned-view',
            gridClassName:options.gridClassName || 'inventory-owned-grid',
            emptyText:options.emptyText || '正在同步库存…',
            allowedSlots:options.allowedSlots || ['L','R'],
            layoutMode:options.layoutMode || 'full',
            densityController:options.densityController
        });
        this.view = this.grid.view;
        this.view.containerId = this.containerId;
        this.view.ownedInventoryShell = this;
        this.controls = null;
        this.pager = null;
    }

    OwnedInventoryViewShell.prototype.setToolbar = function(toolbar, controls, pager) {
        this.controls = controls || null;
        this.pager = pager || null;
        if (this.controls && typeof this.controls.setBreadcrumbHost === 'function') {
            this.controls.setBreadcrumbHost(this.view.chrome.breadcrumbHost);
        }
        this.view.chrome.setToolbar(toolbar);
    };

    OwnedInventoryViewShell.prototype.syncSnapshot = function(snapshot, options) {
        options = options || {};
        if (this.controls && typeof this.controls.setSnapshot === 'function') this.controls.setSnapshot(snapshot);
        var slots = snapshot && snapshot.slots ? snapshot.slots : [];
        if (options.emptyText != null) this.view.renderer.options.emptyText = String(options.emptyText);
        this.view.renderer.render(slots);
        if (options.meta != null) this.view.chrome.setMeta(String(options.meta));
        if (this.pager) this.pager.refresh();
    };

    OwnedInventoryViewShell.prototype.setDisabled = function(disabled) {
        if (this.controls) this.controls.setDisabled(disabled);
        if (this.pager) this.pager.setDisabled(disabled);
    };

    function InventorySortControls(options) {
        options = options || {};
        var self = this;
        this.root = document.createElement('div');
        this.root.className = 'inventory-sort-controls';

        var filterOptions = options.filterOptions || [];
        this.filterGroup = null;
        this.filterSelect = null;
        if (filterOptions.length) {
            var filterLabel = Object.prototype.hasOwnProperty.call(options, 'filterLabel')
                ? String(options.filterLabel || '') : '分类';
            this.filterControl = new InventoryFilterControl({options:filterOptions, label:filterLabel,
                ariaLabel:options.filterAriaLabel, onLegacyChange:options.onFilterChange,
                onSpecChange:options.onFilterSpecChange});
            this.filterGroup = this.filterControl.root;
            this.filterSelect = this.filterControl.select;
            this.root.appendChild(this.filterGroup);
        }

        var authorityOptions = options.authorityOptions || [];
        this.authorityGroup = null;
        this.authoritySelect = null;
        this.commitButton = null;
        if (authorityOptions.length && typeof options.onAuthorityCommit === 'function') {
            var authorityLabel = Object.prototype.hasOwnProperty.call(options, 'authorityLabel')
                ? String(options.authorityLabel || '') : '整理';
            this.authorityControl = new AuthoritySortControl({options:authorityOptions, label:authorityLabel,
                ariaLabel:options.authorityAriaLabel, commitLabel:options.commitLabel,
                onCommit:options.onAuthorityCommit});
            this.authorityGroup = this.authorityControl.root;
            this.authoritySelect = this.authorityControl.select;
            this.commitButton = this.authorityControl.button;
            this.root.appendChild(this.authorityGroup);
            this.root.appendChild(this.commitButton);
        }
    }

    InventorySortControls.prototype.getFilterKey = function() { return this.filterSelect ? this.filterSelect.value : 'all'; };
    InventorySortControls.prototype.getAuthorityMethod = function() { return this.authoritySelect ? this.authoritySelect.value : null; };
    InventorySortControls.prototype.getAuthorityLabel = function() {
        if (!this.authoritySelect) return '';
        var option = this.authoritySelect.options[this.authoritySelect.selectedIndex];
        return option ? option.textContent : this.authoritySelect.value;
    };
    InventorySortControls.prototype.setFilterKey = function(filterKey) {
        if (this.filterControl) this.filterControl.setFilterKey(filterKey);
    };
    InventorySortControls.prototype.setBreadcrumbHost = function(host) {
        if (this.filterControl) this.filterControl.setBreadcrumbHost(host);
    };
    InventorySortControls.prototype.setSnapshot = function(snapshot) {
        return this.filterControl ? this.filterControl.setSnapshot(snapshot) : false;
    };
    InventorySortControls.prototype.rejectFilterChange = function(snapshot) {
        if (this.filterControl) this.filterControl.rejectPending(snapshot);
    };
    InventorySortControls.prototype.setDisabled = function(disabled) {
        if (this.filterControl) this.filterControl.setDisabled(disabled);
        if (this.authoritySelect) this.authoritySelect.disabled = !!disabled;
        if (this.commitButton) this.commitButton.disabled = !!disabled;
    };
    InventorySortControls.prototype.setAuthorityDisabled = function(disabled) {
        if (this.authoritySelect) this.authoritySelect.disabled = !!disabled;
        if (this.commitButton) this.commitButton.disabled = !!disabled;
    };

    function categoryFilterOptions() {
        return [
            {value:'all', label:'全部'},
            {value:'weapon', label:'武器'},
            {value:'armor', label:'防具'},
            {value:'consumable', label:'消耗品'},
            {value:'material', label:'材料'},
            {value:'other', label:'其他'}
        ];
    }

    function authoritySortOptions() {
        return [
            {value:'byType', label:'类型'}, {value:'byUse', label:'用途'},
            {value:'byPrice', label:'总价'}, {value:'byLevel', label:'等级'},
            {value:'byID', label:'ID'}, {value:'byName', label:'名称'},
            {value:'byValue', label:'数量'}, {value:'byTime', label:'时间'}
        ];
    }

    return {
        derivePageState: derivePageState,
        pageFromShortcut: pageFromShortcut,
        renderOwnedSlot: renderOwnedSlot,
        categoryFilterOptions: categoryFilterOptions,
        authoritySortOptions: authoritySortOptions,
        InventoryWindowPager: InventoryWindowPager,
        InventoryFilterControl: InventoryFilterControl,
        AuthoritySortControl: AuthoritySortControl,
        OwnedInventoryViewShell: OwnedInventoryViewShell,
        InventorySortControls: InventorySortControls,
        filterSpecFromPath: filterSpecFromPath,
        filterPathFromSpec: filterPathFromSpec
    };
});
