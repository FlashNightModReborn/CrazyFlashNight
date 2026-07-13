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

    function segment(id, label) { return {id:text(id), label:text(label == null ? id : label)}; }

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
                var part = segment(raw && raw.id != null ? raw.id : raw, raw && raw.label != null ? raw.label : raw);
                if (!part.id) continue;
                var child = findChild(node, part.id);
                if (!child) {
                    child = {id:part.id, label:part.label, path:node.path.concat([part.id]), count:0, children:[]};
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
        this._keyHandler = this._onKeyDown.bind(this);
        this.root.addEventListener('keydown', this._keyHandler);
        this.render();
    }

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
            row.appendChild(this._button('‹ ' + (parentPath.length ? parent.label : this.allLabel), null, parentPath, false, true));
        }
        var allText = contextPath.length ? this.allLabel + context.label : this.allLabel;
        row.appendChild(this._button(allText, context.count, contextPath, this.path.length === contextPath.length));
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
    };

    return {
        majors:MAJORS,
        majorDefinition:majorDefinition,
        catalogPath:catalogPath,
        build:build,
        fromFacets:fromFacets,
        manualSections:manualSections,
        branchTree:branchTree,
        nodeAt:nodeAt,
        validPath:validPath,
        expandSingleChildren:expandSingleChildren,
        matchesPath:matchesPath,
        FilterNavigator:FilterNavigator
    };
});
