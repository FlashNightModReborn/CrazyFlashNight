/** Read-only material catalog/detail composition for the crafting workbench. */
var CraftingMaterials = (function() {
    'use strict';

    function create(options) {
        options = options || {};
        var state = {
            items:[],
            selectedName:'',
            detail:null,
            loading:true,
            detailLoading:false,
            error:'',
            query:'',
            filter:'all',
            focusedName:'',
            layoutMode:options.densityController
                && options.densityController.mode === 'full' ? 'full' : 'compact'
        };

        var catalogRoot = document.createElement('div');
        catalogRoot.className = 'workbench-view crafting-material-catalog-view item-filter-catalog';
        var catalogChrome = new Workbench.ViewChrome({
            title:'材料目录', kicker:'收集品', meta:'同步中'
        });
        var toolbar = document.createElement('div');
        toolbar.className = 'crafting-material-toolbar';
        var search = document.createElement('input');
        search.type = 'search';
        search.className = 'crafting-material-search';
        search.placeholder = '搜索材料';
        search.setAttribute('aria-label', '搜索材料');
        toolbar.appendChild(search);
        var filters = document.createElement('div');
        filters.className = 'crafting-material-filters';
        filters.setAttribute('role', 'group');
        filters.setAttribute('aria-label', '材料筛选');
        [
            {id:'all', label:'全部'},
            {id:'owned', label:'已持有'},
            {id:'used', label:'有用途'}
        ].forEach(function(filter) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'item-filter-option';
            button.textContent = filter.label;
            button.setAttribute('data-material-filter', filter.id);
            button.addEventListener('click', function() {
                state.filter = filter.id;
                renderFilters();
                applyCatalogConstraint();
            });
            filters.appendChild(button);
        });
        toolbar.appendChild(filters);
        catalogChrome.setToolbar(toolbar);
        var renderer = new Workbench.GridRenderer({
            className:'crafting-material-grid workbench-catalog-grid',
            emptyText:'没有符合当前条件的材料',
            keyOf:function(item) { return item.name; },
            renderItem:renderCard,
            bindItem:bindCard
        });
        renderer.root.setAttribute('aria-label', '材料目录');
        var densityUnsubscribe = function() {};
        if (options.densityController) {
            options.densityController.register(renderer);
            densityUnsubscribe = options.densityController.subscribe(function(mode) {
                state.layoutMode = mode;
                syncRovingFocus();
            });
        }
        catalogRoot.appendChild(catalogChrome.root);
        catalogRoot.appendChild(renderer.root);

        var detailRoot = document.createElement('div');
        detailRoot.className = 'workbench-view crafting-material-detail-view';
        var detailChrome = new Workbench.ViewChrome({
            title:'材料档案', kicker:'来源与用途', meta:'请选择材料'
        });
        var detailBody = document.createElement('div');
        detailBody.className = 'crafting-material-detail-body';
        detailRoot.appendChild(detailChrome.root);
        detailRoot.appendChild(detailBody);

        var catalogView = {
            instanceKey:'crafting:materials:catalog',
            instancePolicy:'singletonByBinding',
            allowedSlots:['L'],
            viewKind:'catalog',
            root:catalogRoot,
            chrome:catalogChrome,
            mount:function(container) { container.appendChild(catalogRoot); },
            unmount:function() { if (catalogRoot.parentNode) catalogRoot.parentNode.removeChild(catalogRoot); },
            render:renderCatalog
        };
        var detailView = {
            instanceKey:'crafting:materials:detail',
            instancePolicy:'singletonByBinding',
            allowedSlots:['R'],
            viewKind:'detail',
            root:detailRoot,
            chrome:detailChrome,
            mount:function(container) { container.appendChild(detailRoot); },
            unmount:function() { if (detailRoot.parentNode) detailRoot.parentNode.removeChild(detailRoot); },
            render:renderDetail
        };

        search.addEventListener('input', function() {
            state.query = String(search.value || '').toLowerCase();
            applyCatalogConstraint();
        });

        function visibleItems() {
            return state.items.filter(function(item) {
                if (state.filter === 'owned' && Number(item.owned || 0) <= 0) return false;
                if (state.filter === 'used' && Number(item.useCount || 0) <= 0) return false;
                if (!state.query) return true;
                return String(item.displayName || '').toLowerCase().indexOf(state.query) >= 0;
            });
        }

        function renderFilters() {
            var buttons = filters.querySelectorAll('[data-material-filter]');
            for (var i = 0; i < buttons.length; i++) {
                var active = buttons[i].getAttribute('data-material-filter') === state.filter;
                buttons[i].classList.toggle('active', active);
                buttons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
            }
        }

        function renderCard(item) {
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'crafting-material-card';
            card.setAttribute('role', 'option');
            card.setAttribute('tabindex', '-1');
            card.setAttribute('data-material-name', item.name);
            card.setAttribute('aria-label', (item.displayName || '未命名材料')
                + '，持有 ' + Number(item.owned || 0)
                + '，来源 ' + Number(item.sourceCount || 0)
                + '，用途 ' + Number(item.useCount || 0));
            var icon = document.createElement('span');
            icon.className = 'crafting-material-card-icon';
            icon.innerHTML = options.iconHtml(item.icon, 'kshop-icon');
            var copy = document.createElement('span');
            copy.className = 'crafting-material-card-copy';
            var name = document.createElement('b');
            name.textContent = item.displayName || '未命名材料';
            var owned = document.createElement('small');
            owned.textContent = '持有 ' + Number(item.owned || 0);
            var meta = document.createElement('span');
            meta.className = 'crafting-material-card-meta';
            meta.textContent = '来源 ' + Number(item.sourceCount || 0)
                + ' · 用途 ' + Number(item.useCount || 0);
            var badge = document.createElement('span');
            badge.className = 'crafting-material-card-owned';
            badge.textContent = Number(item.owned || 0) > 0 ? String(Number(item.owned)) : '';
            badge.hidden = Number(item.owned || 0) <= 0;
            copy.appendChild(name);
            copy.appendChild(owned);
            copy.appendChild(meta);
            card.appendChild(icon);
            card.appendChild(copy);
            card.appendChild(badge);
            return card;
        }

        function bindCard(card, item) {
            card.addEventListener('click', function() {
                state.focusedName = item.name;
                syncRovingFocus(item.name);
                select(item.name);
            });
            card.addEventListener('keydown', function(event) {
                var key = event && event.key;
                if (key === 'Enter' || key === ' ') {
                    event.preventDefault();
                    state.focusedName = item.name;
                    select(item.name);
                    return;
                }
                var nodes = Array.prototype.slice.call(
                    renderer.root.querySelectorAll('.crafting-material-card'));
                var current = nodes.indexOf(card);
                if (current < 0 || !nodes.length) return;
                var next = current;
                var columns = state.layoutMode === 'compact' ? 7 : 2;
                if (key === 'ArrowLeft') next = current % columns > 0 ? current - 1 : current;
                else if (key === 'ArrowRight') next = current % columns < columns - 1
                    && current + 1 < nodes.length ? current + 1 : current;
                else if (key === 'ArrowUp') next = current - columns;
                else if (key === 'ArrowDown') next = current + columns;
                else if (key === 'Home') next = 0;
                else if (key === 'End') next = nodes.length - 1;
                else if (key === 'PageUp' || key === 'PageDown') {
                    var rowHeight = Math.max(1, card.getBoundingClientRect().height + 5);
                    var visibleRows = Math.max(1, Math.floor(renderer.root.clientHeight / rowHeight));
                    next = current + (key === 'PageDown' ? 1 : -1) * visibleRows * columns;
                } else return;
                event.preventDefault();
                next = Math.max(0, Math.min(nodes.length - 1, next));
                state.focusedName = nodes[next].getAttribute('data-material-name') || '';
                syncRovingFocus(state.focusedName);
                nodes[next].focus();
                nodes[next].scrollIntoView({block:'nearest', inline:'nearest'});
            });
            if (typeof options.bindTooltip === 'function') options.bindTooltip(card, item);
        }

        function syncRovingFocus(preferredName) {
            var nodes = renderer.root.querySelectorAll('.crafting-material-card');
            if (!nodes.length) {
                state.focusedName = '';
                return;
            }
            var targetName = String(preferredName || state.focusedName || state.selectedName || '');
            var found = false;
            for (var i = 0; i < nodes.length; i++) {
                var matches = !found && nodes[i].getAttribute('data-material-name') === targetName;
                nodes[i].setAttribute('tabindex', matches ? '0' : '-1');
                if (matches) found = true;
            }
            if (!found) {
                nodes[0].setAttribute('tabindex', '0');
                state.focusedName = nodes[0].getAttribute('data-material-name') || '';
            } else {
                state.focusedName = targetName;
            }
        }

        function renderCatalog(renderOptions) {
            var visible = visibleItems();
            catalogChrome.setMeta(state.loading
                ? '同步中'
                : '显示 ' + visible.length + ' / ' + state.items.length);
            renderer.setSelectedKey(state.selectedName || null);
            renderer.render(visible, renderOptions);
            syncRovingFocus();
        }

        function applyCatalogConstraint() {
            var visible = visibleItems();
            var selectedVisible = state.selectedName && visible.some(function(item) {
                return item.name === state.selectedName;
            });
            if (state.selectedName && !selectedVisible) {
                state.selectedName = '';
                state.detail = null;
                state.detailLoading = false;
                renderDetail();
            }
            if (state.focusedName && !visible.some(function(item) {
                return item.name === state.focusedName;
            })) state.focusedName = '';
            renderCatalog({preserveScroll:false});
        }

        function appendEmpty(text) {
            var empty = document.createElement('div');
            empty.className = 'crafting-detail-empty';
            empty.textContent = text;
            detailBody.appendChild(empty);
        }

        function appendSection(title, className) {
            var section = document.createElement('section');
            section.className = className;
            var heading = document.createElement('h3');
            heading.textContent = title;
            section.appendChild(heading);
            detailBody.appendChild(section);
            return section;
        }

        function sourceTitle(source) {
            if (source.kind === 'enemy') return '敌人 · ' + (source.displayName || '未知敌人');
            if (source.kind === 'stage') return '关卡 · ' + (source.stageName || '未知');
            if (source.kind === 'shop') return '商店 · ' + (source.npc || '未知');
            if (source.kind === 'kshop') return 'K 点商城 · ' + (source.category || '商品');
            if (source.kind === 'quest') return '任务 · ' + (source.title || '未知任务');
            return '合成 · ' + (source.category || '未知分类');
        }

        function sourceMeta(source) {
            var parts = [];
            if (Number(source.probability || 0) > 0) {
                var probability = Number(source.probability);
                parts.push('概率 ' + (probability <= 1 ? Math.round(probability * 10000) / 100 : probability) + '%');
            }
            if (Number(source.quantityMax || 0) > 0) parts.push('最多 ' + Number(source.quantityMax) + ' 个');
            var minLevel = Number(source.minLevel || 0);
            var maxLevel = Number(source.maxLevel || 0);
            if (minLevel > 0 && maxLevel > 0 && maxLevel < 999) {
                parts.push(minLevel === maxLevel ? '逆向等级 ' + minLevel
                    : '逆向等级 ' + minLevel + '–' + maxLevel);
            } else if (minLevel > 0) {
                parts.push('逆向等级 ≥ ' + minLevel);
            } else if (maxLevel > 0 && maxLevel < 999) {
                parts.push('逆向等级 ≤ ' + maxLevel);
            }
            if (source.kind === 'quest' && Number(source.quantity || 0) > 0) {
                parts.push('奖励 ' + Number(source.quantity) + ' 个');
            }
            if (Number(source.price || 0) > 0) parts.push(Number(source.price).toLocaleString() + ' 金币');
            if (Number(source.kpoints || source.priceK || 0) > 0) {
                parts.push(Number(source.kpoints || source.priceK).toLocaleString() + ' K 点');
            }
            if (source.requirement) parts.push(source.requirement);
            return parts.join(' · ');
        }

        function renderDetail() {
            Workbench.clearElement(detailBody);
            if (state.error) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta('读取失败');
                appendEmpty(state.error);
                return;
            }
            if (!state.selectedName) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta(state.loading ? '同步中' : '请选择材料');
                appendEmpty(state.loading ? '正在同步材料目录…' : '从左侧选择一种材料');
                return;
            }
            if (state.detailLoading || !state.detail) { appendEmpty('正在读取来源与用途…'); return; }
            var material = state.detail.material || {};
            detailChrome.setTitle(material.displayName || '材料档案', '来源与用途');
            detailChrome.setMeta('当前持有 ' + Number(material.owned || 0));

            var hero = document.createElement('section');
            hero.className = 'crafting-material-hero';
            var icon = document.createElement('span');
            icon.className = 'crafting-material-hero-icon';
            icon.innerHTML = options.iconHtml(material.icon, 'kshop-icon');
            var copy = document.createElement('div');
            var title = document.createElement('h2');
            title.textContent = material.displayName || '未命名材料';
            var owned = document.createElement('strong');
            owned.textContent = '持有 ' + Number(material.owned || 0);
            copy.appendChild(title);
            copy.appendChild(owned);
            if (material.description) {
                var description = document.createElement('p');
                description.textContent = material.description;
                copy.appendChild(description);
            }
            hero.appendChild(icon);
            hero.appendChild(copy);
            detailBody.appendChild(hero);

            var sourceSection = appendSection('从哪里获得', 'crafting-material-sources');
            if (material.sourceSummary) {
                var summary = document.createElement('p');
                summary.className = 'crafting-material-source-summary';
                summary.textContent = material.sourceSummary;
                sourceSection.appendChild(summary);
            }
            var sources = state.detail.sources || [];
            if (sources.length) {
                var sourceList = document.createElement('div');
                sourceList.className = 'crafting-material-source-list';
                sources.forEach(function(source) {
                    var row = document.createElement('article');
                    var title = document.createElement('b');
                    title.textContent = sourceTitle(source);
                    var meta = document.createElement('small');
                    meta.textContent = sourceMeta(source) || '已记录';
                    row.appendChild(title);
                    row.appendChild(meta);
                    sourceList.appendChild(row);
                });
                sourceSection.appendChild(sourceList);
            } else if (!material.sourceSummary) {
                var noSource = document.createElement('p');
                noSource.className = 'crafting-material-empty-copy';
                noSource.textContent = '当前来源索引中暂无记录。';
                sourceSection.appendChild(noSource);
            }

            var useSection = appendSection('会用在哪里', 'crafting-material-uses');
            var uses = state.detail.uses || [];
            if (!uses.length) {
                var noUse = document.createElement('p');
                noUse.className = 'crafting-material-empty-copy';
                noUse.textContent = '当前合成索引中暂无用途。';
                useSection.appendChild(noUse);
            } else {
                uses.forEach(function(use) {
                    var row = document.createElement('article');
                    row.className = 'crafting-material-use-row';
                    var icon = document.createElement('span');
                    icon.innerHTML = options.iconHtml(use.icon, 'kshop-icon');
                    var copy = document.createElement('span');
                    var name = document.createElement('b');
                    name.textContent = use.displayName || '未命名用途';
                    var meta = document.createElement('small');
                    meta.textContent = (use.category || '合成配方')
                        + (Number(use.required || 0) > 0 ? ' · 每份需要 ' + Number(use.required) : '');
                    copy.appendChild(name);
                    copy.appendChild(meta);
                    row.appendChild(icon);
                    row.appendChild(copy);
                    if (typeof options.bindTooltip === 'function') {
                        row.setAttribute('tabindex', '0');
                        row.setAttribute('aria-label', (use.displayName || '未命名用途')
                            + '，' + (use.category || '合成配方')
                            + (Number(use.required || 0) > 0 ? '，每份需要 ' + Number(use.required) : ''));
                        options.bindTooltip(row, use);
                    }
                    useSection.appendChild(row);
                });
            }
        }

        function select(name) {
            name = String(name || '');
            if (!name) return false;
            var changed = state.selectedName !== name;
            state.selectedName = name;
            state.error = '';
            state.detailLoading = true;
            if (changed) state.detail = null;
            renderCatalog({preserveScroll:true});
            renderDetail();
            if (typeof options.onSelect === 'function') options.onSelect(name);
            return true;
        }

        function setSnapshot(response, preferredName) {
            state.items = response && Array.isArray(response.materials) ? response.materials.slice() : [];
            state.loading = false;
            state.error = '';
            var preferred = String(preferredName || state.selectedName || '');
            var found = state.items.some(function(item) { return item.name === preferred; });
            var next = found ? preferred : (state.items[0] ? String(state.items[0].name) : '');
            state.selectedName = '';
            renderFilters();
            renderCatalog({preserveScroll:false});
            if (next) select(next);
            else renderDetail();
        }

        function setDetail(response) {
            if (!response || !response.material
                    || String(response.material.name) !== state.selectedName) return false;
            state.detail = response;
            state.detailLoading = false;
            state.error = '';
            renderDetail();
            return true;
        }

        function setError(message) {
            state.loading = false;
            state.detailLoading = false;
            state.error = String(message || '材料数据读取失败。');
            renderCatalog();
            renderDetail();
        }

        renderFilters();
        renderCatalog();
        renderDetail();

        return {
            catalogView:catalogView,
            detailView:detailView,
            setSnapshot:setSnapshot,
            setDetail:setDetail,
            setError:setError,
            select:select,
            getSelectedName:function() { return state.selectedName; },
            debugState:function() {
                return {
                    count:state.items.length,
                    selectedName:state.selectedName,
                    focusedName:state.focusedName,
                    detailLoading:state.detailLoading,
                    query:state.query,
                    filter:state.filter,
                    layoutMode:state.layoutMode
                };
            },
            destroy:function() {
                densityUnsubscribe();
                if (options.densityController) options.densityController.unregister(renderer);
                state.items = [];
                state.detail = null;
                Workbench.clearElement(catalogRoot);
                Workbench.clearElement(detailRoot);
            }
        };
    }

    return {create:create};
})();
