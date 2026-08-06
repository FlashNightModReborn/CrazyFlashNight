/**
 * Shared item taxonomy and progressive filter navigation.
 *
 * The model is data-source neutral: catalogs may build counts locally while
 * inventory snapshots hydrate the same tree from AS2-authoritative facets.
 * Paths contain bounded domain values, never executable predicates.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.ItemFilter = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var MAJORS = [
        {id:'weapon', label:'武器', aliases:['武器']},
        {id:'armor', label:'防具', aliases:['防具']},
        {id:'consumable', label:'消耗品', aliases:['消耗品']},
        {id:'material', label:'材料', aliases:['材料']},
        {id:'collection', label:'收集品', aliases:['收集品']},
        {id:'other', label:'其他', aliases:[]}
    ];

    var CHILD_ORDER = {
        weapon:['刀','手枪','长枪','其他'],
        armor:['头部装备','颈部装备','上装装备','手部装备','下装装备','脚部装备','其他'],
        consumable:['药剂','弹夹','手雷','材料','货币','其他'],
        collection:['材料','情报','其他'],
        'weapon/刀':['刀剑','直剑','长刀','重斩','狂野','短兵','短柄','镰刀','长枪','长柄','长棍','双刀','迅捷','棍棒','疾影','其他'],
        'weapon/*':['手枪','大威力手枪','冲锋枪','压制冲锋枪','突击步枪','战斗步枪','霰弹枪','狙击步枪','反器材武器','机枪','压制机枪','发射器','弓弩','近战','压制近战','特殊','其他']
    };

    function text(value) { return value == null ? '' : String(value); }

    function majorDefinition(value) {
        value = text(value);
        for (var i = 0; i < MAJORS.length - 1; i++) {
            for (var j = 0; j < MAJORS[i].aliases.length; j++) {
                if (MAJORS[i].aliases[j] === value || MAJORS[i].id === value) return MAJORS[i];
            }
        }
        return MAJORS[MAJORS.length - 1];
    }

    function segment(id, label, order) {
        order = Number(order);
        return {id:text(id), label:text(label == null ? id : label), order:isFinite(order) ? order : 0};
    }

    function catalogPath(item, options) {
        item = item || {};
        options = options || {};
        var major = majorDefinition(item.majorType != null ? item.majorType : item.type);
        var path = [segment(major.id, major.label)];
        if (major.id === 'other') return path;
        var secondary = text(item.use || item.subType || item.subtype || '') || '其他';
        path.push(segment(secondary, secondary));
        if (major.id === 'weapon' && options.weaponSubtype !== false) {
            var subtype = text(item.weaponType || item.actionType || '');
            if (subtype) path.push(segment(subtype, subtype));
        }
        return path;
    }

    function setPath(item) {
        item = item || {};
        var id = text(item.setId || '');
        var name = text(item.setName || '');
        return id && name ? [segment(id, name, item.setOrder)] : [];
    }

    function buildSetTree(items) {
        items = Array.isArray(items) ? items : [];
        return build(items.filter(function(item) { return setPath(item).length > 0; }), setPath);
    }

    function clonePath(path) {
        var result = [];
        for (var i = 0; i < (path || []).length; i++) result.push(text(path[i] && path[i].id != null ? path[i].id : path[i]));
        return result;
    }

    function createRoot(count) {
        return {id:'', label:'', path:[], count:Number(count) || 0, children:[]};
    }

    function findChild(node, id) {
        for (var i = 0; i < node.children.length; i++) if (node.children[i].id === id) return node.children[i];
        return null;
    }

    function build(items, classifier) {
        items = Array.isArray(items) ? items : [];
        classifier = typeof classifier === 'function' ? classifier : catalogPath;
        var root = createRoot(items.length);
        for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
            var rawPath = classifier(items[itemIndex]) || [];
            var node = root;
            for (var depth = 0; depth < rawPath.length; depth++) {
                var raw = rawPath[depth];
                var part = segment(raw && raw.id != null ? raw.id : raw, raw && raw.label != null ? raw.label : raw,
                    raw && raw.order != null ? raw.order : 0);
                if (!part.id) continue;
                var child = findChild(node, part.id);
                if (!child) {
                    child = {id:part.id, label:part.label, order:part.order, path:node.path.concat([part.id]), count:0, children:[]};
                    node.children.push(child);
                }
                child.count++;
                node = child;
            }
        }
        sortTree(root);
        return root;
    }

    function fromFacets(facets, total) {
        var root = createRoot(total);
        facets = Array.isArray(facets) ? facets : [];
        for (var i = 0; i < facets.length; i++) insertFacet(root, facets[i], []);
        sortTree(root);
        return root;
    }

    function insertFacet(parent, source, parentPath) {
        if (!source || source.id == null) return;
        var id = text(source.id);
        if (!id) return;
        var node = {
            id:id,
            label:text(source.label || id),
            order:isFinite(Number(source.order)) ? Number(source.order) : 0,
            path:parentPath.concat([id]),
            count:Math.max(0, Math.floor(Number(source.count) || 0)),
            children:[]
        };
        parent.children.push(node);
        var children = Array.isArray(source.children) ? source.children : [];
        for (var i = 0; i < children.length; i++) insertFacet(node, children[i], node.path);
    }

    function manualSections(sections, total) {
        var root = createRoot(total);
        sections = Array.isArray(sections) ? sections : [];
        for (var i = 0; i < sections.length; i++) {
            var source = sections[i] || {};
            var id = text(source.id);
            if (!id) continue;
            root.children.push({
                id:id,
                label:text(source.label || id),
                path:[id],
                count:Array.isArray(source.entries) ? source.entries.length : Math.max(0, Number(source.count) || 0),
                children:[]
            });
        }
        return root;
    }

    function cloneBranchNode(source, parentPath) {
        var node = {
            id:text(source.id),
            label:text(source.label || source.id),
            order:isFinite(Number(source.order)) ? Number(source.order) : 0,
            path:parentPath.concat([text(source.id)]),
            count:Math.max(0, Math.floor(Number(source.count) || 0)),
            children:[]
        };
        var children = Array.isArray(source.children) ? source.children : [];
        for (var i = 0; i < children.length; i++) node.children.push(cloneBranchNode(children[i], node.path));
        return node;
    }

    function branchTree(branches, total) {
        var root = createRoot(total);
        branches = Array.isArray(branches) ? branches : [];
        for (var i = 0; i < branches.length; i++) {
            var branch = branches[i] || {}, id = text(branch.id), tree = branch.tree;
            if (!id || !tree) continue;
            var node = {
                id:id,
                label:text(branch.label || id),
                path:[id],
                count:Math.max(0, Math.floor(Number(tree.count) || 0)),
                children:[]
            };
            var children = Array.isArray(tree.children) ? tree.children : [];
            for (var childIndex = 0; childIndex < children.length; childIndex++) {
                node.children.push(cloneBranchNode(children[childIndex], node.path));
            }
            root.children.push(node);
        }
        return root;
    }

    function orderFor(parentPath) {
        var key = clonePath(parentPath).join('/');
        if (!key) {
            var ids = [];
            for (var i = 0; i < MAJORS.length; i++) ids.push(MAJORS[i].id);
            return ids;
        }
        return CHILD_ORDER[key] || (key.indexOf('weapon/') === 0 ? CHILD_ORDER['weapon/*'] : []) || [];
    }

    function sortTree(node) {
        var order = orderFor(node.path);
        node.children.sort(function(a, b) {
            var ai = order.indexOf(a.id), bi = order.indexOf(b.id);
            if (ai < 0) ai = 1000;
            if (bi < 0) bi = 1000;
            if (ai !== bi) return ai - bi;
            var ao = isFinite(Number(a.order)) ? Number(a.order) : 0;
            var bo = isFinite(Number(b.order)) ? Number(b.order) : 0;
            if (ao !== bo) return ao - bo;
            return a.label.localeCompare(b.label, 'zh-CN');
        });
        for (var i = 0; i < node.children.length; i++) sortTree(node.children[i]);
    }

    function nodeAt(tree, path) {
        var node = tree;
        path = clonePath(path);
        for (var i = 0; node && i < path.length; i++) node = findChild(node, path[i]);
        return node || null;
    }

    /**
     * Adds zero-count presentation nodes only for the currently selected authority path.
     * This keeps the breadcrumb visible when a write removes the final matching item;
     * it never changes the authority counts or performs client-side filtering.
     */
    function ensurePath(tree, path, labelForId) {
        if (!tree || !Array.isArray(tree.children)) return null;
        path = clonePath(path);
        var node = tree;
        for (var index = 0; index < path.length; index++) {
            var id = path[index];
            var child = findChild(node, id);
            if (!child) {
                var label = typeof labelForId === 'function'
                    ? labelForId(id, index, path.slice()) : id;
                child = {id:id, label:text(label || id), order:0,
                    path:node.path.concat([id]), count:0, children:[]};
                node.children.push(child);
                sortTree(node);
            }
            node = child;
        }
        return node;
    }

    function validPath(tree, path) {
        var result = [], node = tree;
        path = clonePath(path);
        for (var i = 0; node && i < path.length; i++) {
            var next = findChild(node, path[i]);
            if (!next) break;
            result.push(next.id);
            node = next;
        }
        return result;
    }

    function expandSingleChildren(tree, path) {
        var result = validPath(tree, path);
        var node = nodeAt(tree, result);
        while (result.length && node && node.children.length === 1) {
            node = node.children[0];
            result.push(node.id);
        }
        return result;
    }

    function matchesPath(item, path, classifier) {
        path = clonePath(path);
        if (!path.length) return true;
        var itemPath = clonePath((classifier || catalogPath)(item));
        for (var i = 0; i < path.length; i++) if (itemPath[i] !== path[i]) return false;
        return true;
    }

    function FilterNavigator(options) {
        options = options || {};
        this.root = document.createElement('div');
        this.root.className = options.className || 'item-filter-navigator';
        this.visualStyle = options.visualStyle === 'catalog' ? 'catalog' : 'compact';
        if (this.visualStyle === 'catalog') this.root.classList.add('item-filter-catalog');
        this.root.setAttribute('role', 'navigation');
        this.root.setAttribute('aria-label', options.ariaLabel || '物品分类');
        this.tree = options.tree || createRoot(0);
        this.path = validPath(this.tree, options.path || []);
        this.autoDescendSingle = options.autoDescendSingle !== false;
        this.presentation = options.presentation === 'drilldown' ? 'drilldown' : 'stacked';
        if (this.presentation === 'drilldown') this.root.classList.add('item-filter-drilldown');
        this.allLabel = options.allLabel || '全部';
        this.onChange = typeof options.onChange === 'function' ? options.onChange : function() {};
        this.disabled = false;
        this.breadcrumbHost = null;
        this.breadcrumbRoot = null;
        this._breadcrumbObserver = null;
        this._breadcrumbView = null;
        this._breadcrumbFrame = 0;
        this._breadcrumbResizeHandler = this.refreshBreadcrumbLayout.bind(this);
        this._keyHandler = this._onKeyDown.bind(this);
        this.root.addEventListener('keydown', this._keyHandler);
        if (options.breadcrumbHost) this.setBreadcrumbHost(options.breadcrumbHost);
        this.render();
    }

    FilterNavigator.prototype.setBreadcrumbHost = function(host) {
        if (host === this.breadcrumbHost) return;
        if (this._breadcrumbObserver) this._breadcrumbObserver.disconnect();
        if (this._breadcrumbView && this._breadcrumbFrame) this._breadcrumbView.cancelAnimationFrame(this._breadcrumbFrame);
        if (this._breadcrumbView && !this._breadcrumbObserver) {
            this._breadcrumbView.removeEventListener('resize', this._breadcrumbResizeHandler);
        }
        if (this.breadcrumbRoot && this.breadcrumbRoot.parentNode) this.breadcrumbRoot.parentNode.removeChild(this.breadcrumbRoot);
        if (this.breadcrumbHost) this.breadcrumbHost.hidden = true;
        this.breadcrumbHost = host && host.nodeType === 1 ? host : null;
        this.breadcrumbRoot = null;
        this._breadcrumbObserver = null;
        this._breadcrumbView = this.breadcrumbHost && this.breadcrumbHost.ownerDocument
            ? this.breadcrumbHost.ownerDocument.defaultView : null;
        this._breadcrumbFrame = 0;
        if (this.breadcrumbHost) {
            this.breadcrumbRoot = document.createElement('nav');
            this.breadcrumbRoot.className = 'item-filter-breadcrumbs';
            this.breadcrumbRoot.setAttribute('aria-label', '当前筛选路径');
            this.breadcrumbHost.appendChild(this.breadcrumbRoot);
            if (this._breadcrumbView && this._breadcrumbView.ResizeObserver) {
                this._breadcrumbObserver = new this._breadcrumbView.ResizeObserver(this._breadcrumbResizeHandler);
                this._breadcrumbObserver.observe(this.breadcrumbHost);
            } else if (this._breadcrumbView) {
                this._breadcrumbView.addEventListener('resize', this._breadcrumbResizeHandler);
            }
        }
        this._renderBreadcrumb();
    };

    FilterNavigator.prototype._queueBreadcrumbLayout = function() {
        var self = this;
        this.refreshBreadcrumbLayout();
        if (!this._breadcrumbView || !this._breadcrumbView.requestAnimationFrame) return;
        if (this._breadcrumbFrame) this._breadcrumbView.cancelAnimationFrame(this._breadcrumbFrame);
        this._breadcrumbFrame = this._breadcrumbView.requestAnimationFrame(function() {
            self._breadcrumbFrame = 0;
            self.refreshBreadcrumbLayout();
        });
    };

    FilterNavigator.prototype.refreshBreadcrumbLayout = function() {
        var root = this.breadcrumbRoot;
        if (!root || root.hidden) return;
        root.classList.remove('is-collapsed');
        if (root.querySelector('.item-filter-breadcrumb-middle')
                && root.clientWidth > 0 && root.scrollWidth > root.clientWidth + 1) {
            root.classList.add('is-collapsed');
        }
    };

    FilterNavigator.prototype._renderBreadcrumb = function() {
        var root = this.breadcrumbRoot;
        if (!root || !this.breadcrumbHost) return;
        while (root.firstChild) root.removeChild(root.firstChild);
        root.classList.remove('is-collapsed');
        if (!this.path.length) {
            root.hidden = true;
            this.breadcrumbHost.hidden = true;
            return;
        }
        var crumbs = [{label:this.allLabel, path:[]}];
        var cursor = this.tree;
        for (var i = 0; cursor && i < this.path.length; i++) {
            cursor = findChild(cursor, this.path[i]);
            if (!cursor) break;
            crumbs.push({label:cursor.label, path:cursor.path.slice()});
        }
        var self = this;
        var hasMiddle = crumbs.length > 3;
        for (var index = 0; index < crumbs.length; index++) {
            if (index === 1 && hasMiddle) {
                var ellipsis = document.createElement('span');
                ellipsis.className = 'item-filter-breadcrumb-segment item-filter-breadcrumb-ellipsis';
                ellipsis.setAttribute('aria-hidden', 'true');
                ellipsis.setAttribute(
                    'title',
                    crumbs.slice(1, crumbs.length - 2)
                        .map(function(entry) { return entry.label; })
                        .join(' › ')
                );
                ellipsis.innerHTML = '<span class="item-filter-breadcrumb-separator">›</span><span>…</span>';
                root.appendChild(ellipsis);
            }
            var crumb = crumbs[index];
            var segmentNode = document.createElement('span');
            segmentNode.className = 'item-filter-breadcrumb-segment';
            if (index > 0 && index < crumbs.length - 2) segmentNode.classList.add('item-filter-breadcrumb-middle');
            if (index >= crumbs.length - 2) segmentNode.classList.add('item-filter-breadcrumb-tail');
            if (index > 0) {
                var separator = document.createElement('span');
                separator.className = 'item-filter-breadcrumb-separator';
                separator.setAttribute('aria-hidden', 'true');
                separator.textContent = '›';
                segmentNode.appendChild(separator);
            }
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'item-filter-breadcrumb';
            button.textContent = crumb.label;
            var fullLabel = crumbs.slice(0, index + 1)
                .map(function(entry) { return entry.label; }).join(' › ');
            button.setAttribute('aria-label', fullLabel);
            button.setAttribute('title', fullLabel);
            button.setAttribute('data-filter-breadcrumb-path', crumb.path.join('/'));
            if (index === crumbs.length - 1) button.setAttribute('aria-current', 'page');
            button.disabled = this.disabled;
            (function(path) {
                button.addEventListener('click', function() { self.setPath(path, false); });
            })(crumb.path.slice());
            segmentNode.appendChild(button);
            root.appendChild(segmentNode);
        }
        root.hidden = false;
        this.breadcrumbHost.hidden = false;
        root.setAttribute('aria-label', crumbs.map(function(entry) { return entry.label; }).join(' › '));
        this._queueBreadcrumbLayout();
    };

    FilterNavigator.prototype.setModel = function(tree, path) {
        this.tree = tree || createRoot(0);
        this.path = validPath(this.tree, path == null ? this.path : path);
        this.render();
    };

    FilterNavigator.prototype.setPath = function(path, silent) {
        var next = validPath(this.tree, path);
        this.path = next;
        this.render();
        if (!silent) this.onChange(next.slice(), nodeAt(this.tree, next));
    };

    FilterNavigator.prototype.select = function(path) {
        var next = this.autoDescendSingle ? expandSingleChildren(this.tree, path) : validPath(this.tree, path);
        this.setPath(next, false);
    };

    FilterNavigator.prototype.setDisabled = function(disabled) {
        this.disabled = !!disabled;
        var buttons = this.root.querySelectorAll('button');
        for (var i = 0; i < buttons.length; i++) buttons[i].disabled = this.disabled;
        if (this.breadcrumbRoot) {
            buttons = this.breadcrumbRoot.querySelectorAll('button');
            for (i = 0; i < buttons.length; i++) buttons[i].disabled = this.disabled;
        }
    };

    FilterNavigator.prototype._button = function(label, count, path, active, exactPath) {
        var self = this;
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'item-filter-option';
        button.classList.toggle('active', !!active);
        button.setAttribute('aria-pressed', active ? 'true' : 'false');
        button.setAttribute('data-filter-path', clonePath(path).join('/'));
        var labelNode = document.createElement('span');
        labelNode.textContent = label;
        button.appendChild(labelNode);
        if (count != null) {
            var badge = document.createElement('small');
            badge.textContent = String(count);
            button.appendChild(badge);
        }
        button.disabled = this.disabled;
        button.addEventListener('click', function() {
            if (exactPath) self.setPath(path, false);
            else self.select(path);
        });
        return button;
    };

    FilterNavigator.prototype.render = function() {
        while (this.root.firstChild) this.root.removeChild(this.root.firstChild);
        this._renderBreadcrumb();
        if (this.presentation === 'drilldown') {
            this._renderDrilldown();
            return;
        }
        var parent = this.tree;
        var depth = 0;
        while (parent) {
            var children = parent.children || [];
            if (!children.length) break;
            // A selected single-child level is implicit. Skip its redundant
            // row, but continue walking so grandchildren remain visible.
            // Previously this branch broke the loop and hid weapon subtypes in
            // production shops where every weapon shared one `use` value.
            if (depth > 0 && children.length === 1
                    && this.path.length > depth && this.path[depth] === children[0].id) {
                parent = children[0];
                depth++;
                continue;
            }
            var row = document.createElement('div');
            row.className = 'item-filter-row';
            row.setAttribute('data-filter-depth', String(depth));
            var parentPath = parent.path || [];
            var allText = depth === 0 ? this.allLabel : this.allLabel + parent.label;
            row.appendChild(this._button(allText, parent.count, parentPath, this.path.length === depth));
            for (var i = 0; i < children.length; i++) {
                row.appendChild(this._button(children[i].label, children[i].count, children[i].path,
                    this.path.length > depth && this.path[depth] === children[i].id));
            }
            this.root.appendChild(row);
            if (this.path.length <= depth) break;
            parent = nodeAt(this.tree, this.path.slice(0, depth + 1));
            depth++;
        }
    };

    FilterNavigator.prototype._renderDrilldown = function() {
        var contextPath = this.path.slice();
        var context = nodeAt(this.tree, contextPath) || this.tree;
        if (!(context.children || []).length && contextPath.length) {
            contextPath.pop();
            context = nodeAt(this.tree, contextPath) || this.tree;
        }
        var row = document.createElement('div');
        row.className = 'item-filter-row item-filter-current-row';
        row.setAttribute('data-filter-depth', String(contextPath.length));
        if (contextPath.length) {
            var parentPath = contextPath.slice(0, -1);
            var parent = nodeAt(this.tree, parentPath) || this.tree;
            var parentButton = this._button(
                '‹ ' + (parentPath.length ? parent.label : this.allLabel),
                null, parentPath, false, true);
            parentButton.classList.add('item-filter-parent-option');
            row.appendChild(parentButton);
        }
        var allText = contextPath.length ? this.allLabel + context.label : this.allLabel;
        var contextButton = this._button(
            allText, context.count, contextPath, this.path.length === contextPath.length);
        contextButton.classList.add('item-filter-context-option');
        row.appendChild(contextButton);
        var children = context.children || [];
        for (var i = 0; i < children.length; i++) {
            row.appendChild(this._button(children[i].label, children[i].count, children[i].path,
                this.path.length > contextPath.length && this.path[contextPath.length] === children[i].id));
        }
        this.root.appendChild(row);
    };

    FilterNavigator.prototype._onKeyDown = function(event) {
        if (event.key === 'Escape' && this.path.length) {
            event.preventDefault();
            this.select(this.path.slice(0, -1));
            return;
        }
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight' && event.key !== 'Home' && event.key !== 'End') return;
        var buttons = Array.prototype.slice.call(this.root.querySelectorAll('button:not(:disabled)'));
        var index = buttons.indexOf(document.activeElement);
        if (index < 0 || !buttons.length) return;
        event.preventDefault();
        if (event.key === 'Home') index = 0;
        else if (event.key === 'End') index = buttons.length - 1;
        else index = (index + (event.key === 'ArrowRight' ? 1 : -1) + buttons.length) % buttons.length;
        buttons[index].focus();
    };

    FilterNavigator.prototype.destroy = function() {
        this.root.removeEventListener('keydown', this._keyHandler);
        this.setBreadcrumbHost(null);
    };

    return {
        majors:MAJORS,
        majorDefinition:majorDefinition,
        catalogPath:catalogPath,
        setPath:setPath,
        buildSetTree:buildSetTree,
        build:build,
        fromFacets:fromFacets,
        manualSections:manualSections,
        branchTree:branchTree,
        nodeAt:nodeAt,
        ensurePath:ensurePath,
        validPath:validPath,
        expandSingleChildren:expandSingleChildren,
        matchesPath:matchesPath,
        FilterNavigator:FilterNavigator
    };
});
