/** Read-only material catalog/detail composition for the crafting workbench. */
var CraftingMaterials = (function() {
    'use strict';

    // 语义音效命令式入口（契约 §8）：选中类手势在 bindCard 内播音，避免快照自动选中误响
    function cue(name) {
        var A = (typeof window !== 'undefined') ? window.BootstrapAudio : null;
        if (A && typeof A.cue === 'function') A.cue(name);
    }

    function create(options) {
        options = options || {};
        var state = {
            items:[],
            selectedName:'',
            detail:null,
            loading:true,
            detailLoading:false,
            detailRetryAvailable:false,
            detailRetryFocusName:'',
            useAction:null,
            shopNavigation:null,
            catalogError:'',
            detailError:'',
            query:'',
            filter:'all',
            filterPath:[],
            sort:'archive',
            focusedName:'',
            protocolVersion:0,
            snapshotId:'',
            taxonomy:null,
            navigationAccess:{shop:false, crafting:false},
            layoutMode:options.densityController
                && options.densityController.mode === 'full' ? 'full' : 'compact'
        };
        var nameCollator = typeof Intl !== 'undefined' && Intl.Collator
            ? new Intl.Collator('zh-CN', {numeric:true, sensitivity:'base'}) : null;
        var resultAnnouncementTimer = null;
        var detailRenderEpoch = 0;
        var typeLabels = null;

        var catalogRoot = document.createElement('div');
        catalogRoot.className = 'workbench-view crafting-material-catalog-view item-filter-catalog';
        var catalogChrome = new Workbench.ViewChrome({
            title:'材料目录', kicker:'收集品', meta:'同步中'
        });
        var toolbar = document.createElement('div');
        toolbar.className = 'crafting-material-toolbar';
        var navigatorHost = document.createElement('div');
        navigatorHost.className = 'crafting-material-navigator';
        navigatorHost.hidden = true;
        var filterNavigator = new ItemFilter.FilterNavigator({
            tree:ItemFilter.buildMany([]), path:[], presentation:'drilldown',
            allLabel:'全部材料', ariaLabel:'材料分类', visualStyle:'catalog',
            autoDescendSingle:false,
            breadcrumbHost:catalogChrome.breadcrumbHost,
            onChange:function(path) {
                if (shopNavigationPending()) {
                    filterNavigator.setPath(state.filterPath, true);
                    return;
                }
                state.filterPath = path.slice();
                applyCatalogConstraint();
            }
        });
        navigatorHost.appendChild(filterNavigator.root);
        toolbar.appendChild(navigatorHost);
        var searchRow = document.createElement('div');
        searchRow.className = 'crafting-material-search-row';
        var search = document.createElement('input');
        search.type = 'search';
        search.className = 'crafting-material-search';
        search.placeholder = '搜索材料';
        search.setAttribute('aria-label', '搜索材料');
        searchRow.appendChild(search);
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
            var countNode = document.createElement('small');
            countNode.hidden = true;
            button.appendChild(countNode);
            button.setAttribute('data-material-filter', filter.id);
            button.addEventListener('click', function() {
                if (shopNavigationPending()) return;
                state.filter = filter.id;
                renderFilters();
                applyCatalogConstraint();
            });
            filters.appendChild(button);
        });
        searchRow.appendChild(filters);
        var sortDropdown = new WorkbenchComponents.Dropdown({
            value:'archive',
            labelPrefix:'排序：',
            ariaLabel:'材料排序',
            className:'workbench-dropdown crafting-material-sort',
            choices:[
                {value:'archive', label:'档案顺序'},
                {value:'owned', label:'持有数'},
                {value:'name', label:'名称'},
                {value:'purpose', label:'用途数'}
            ],
            onChange:function(value) {
                if (shopNavigationPending()) {
                    sortDropdown.update({value:state.sort});
                    return;
                }
                state.sort = value;
                renderCatalog({preserveScroll:false});
                scheduleResultAnnouncement();
            }
        });
        sortDropdown.root.hidden = true;
        sortDropdown.update({disabled:true});
        sortDropdown.mount(searchRow);
        toolbar.appendChild(searchRow);
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
                var anchorName = state.selectedName || state.focusedName;
                if (!anchorName) return;
                var anchor = renderer.root.querySelector('[data-material-name="'
                    + (typeof CSS !== 'undefined' && CSS.escape
                        ? CSS.escape(anchorName) : anchorName.replace(/["\\]/g, '')) + '"]');
                if (anchor) anchor.scrollIntoView({block:'nearest', inline:'nearest'});
            });
        }
        var catalogEmpty = document.createElement('div');
        catalogEmpty.className = 'crafting-material-catalog-empty';
        catalogEmpty.hidden = true;
        var resultStatus = document.createElement('p');
        resultStatus.className = 'crafting-material-result-status';
        resultStatus.setAttribute('role', 'status');
        resultStatus.setAttribute('aria-live', 'polite');
        resultStatus.setAttribute('aria-atomic', 'true');
        var legacyWarning = document.createElement('p');
        legacyWarning.className = 'crafting-material-legacy-warning';
        legacyWarning.setAttribute('role', 'status');
        legacyWarning.setAttribute('data-material-compat', 'legacy_limited');
        legacyWarning.textContent = '旧版兼容视图：分类、档案顺序与来源档位可能不完整。';
        legacyWarning.hidden = true;
        catalogRoot.appendChild(catalogChrome.root);
        catalogRoot.appendChild(legacyWarning);
        catalogRoot.appendChild(renderer.root);
        catalogRoot.appendChild(catalogEmpty);
        catalogRoot.appendChild(resultStatus);

        var detailRoot = document.createElement('div');
        detailRoot.className = 'workbench-view crafting-material-detail-view';
        var detailChrome = new Workbench.ViewChrome({
            title:'材料档案', kicker:'来源与用途', meta:'请选择材料'
        });
        var anchorNav = document.createElement('nav');
        anchorNav.className = 'crafting-material-anchor-nav';
        anchorNav.setAttribute('aria-label', '详情小节导航');
        anchorNav.hidden = true;
        detailChrome.setToolbar(anchorNav);
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
            if (shopNavigationPending()) {
                search.value = state.query;
                return;
            }
            state.query = String(search.value || '').toLowerCase();
            applyCatalogConstraint();
        });

        catalogRoot.addEventListener('keydown', onCatalogKeyDown);

        function entryMap(entries) {
            var result = Object.create(null);
            (entries || []).forEach(function(entry) { result[entry.id] = entry; });
            return result;
        }

        function segmentFrom(entry) {
            return {id:entry.id, label:entry.label, order:entry.order};
        }

        function taxonomyPaths(item) {
            var taxonomy = state.taxonomy;
            if (!taxonomy) return [];
            var roots = entryMap(taxonomy.roots), types = entryMap(taxonomy.types);
            var recipePurposes = entryMap(taxonomy.recipePurposes);
            var directPurposes = entryMap(taxonomy.directPurposes);
            var paths = [], typeRoot = segmentFrom(roots.type), type = segmentFrom(types[item.typeId]);
            if (item.typeId === 'equipment_mod') {
                taxonomy.modAxes.forEach(function(axis) {
                    var values = entryMap(axis.values);
                    paths.push([typeRoot, type, segmentFrom(axis),
                        segmentFrom(values[item.modFacetIds[axis.id]])]);
                });
            } else {
                paths.push([typeRoot, type]);
            }
            var purposeRoot = segmentFrom(roots.purpose);
            (item.recipePurposeIds || []).forEach(function(id) {
                paths.push([purposeRoot, {id:'recipe', label:'合成配方', order:0},
                    segmentFrom(recipePurposes[id])]);
            });
            (item.directPurposeIds || []).forEach(function(id) {
                paths.push([purposeRoot, {id:'direct', label:'直接系统用途', order:1},
                    segmentFrom(directPurposes[id])]);
            });
            if (!(item.recipePurposeIds || []).length && !(item.directPurposeIds || []).length) {
                paths.push([purposeRoot, segmentFrom(taxonomy.fallback)]);
            }
            return paths;
        }

        function purposeCount(item) {
            return state.protocolVersion === 2
                ? Number(item.structuredPurposeCount || 0) : Number(item.useCount || 0);
        }

        function consumeEscape(target) {
            if (shopNavigationPending()) return false;
            if (sortDropdown.consumeEscape()) return true;
            if (target === search && state.query) {
                search.value = '';
                state.query = '';
                applyCatalogConstraint();
                search.focus();
                return true;
            }
            var inNavigator = !!target && (filterNavigator.root.contains(target)
                || catalogChrome.breadcrumbHost.contains(target));
            if (inNavigator && state.filterPath.length && filterNavigator.back()) {
                return true;
            }
            return false;
        }

        function onCatalogKeyDown(event) {
            if (!event || event.defaultPrevented || event.key !== 'Escape') return;
            if (consumeEscape(event.target)) {
                event.preventDefault();
                event.stopPropagation();
            }
        }

        function visibleItems() {
            var visible = state.items.filter(function(item) {
                if (state.filter === 'owned' && Number(item.owned || 0) <= 0) return false;
                if (state.filter === 'used' && purposeCount(item) <= 0) return false;
                if (state.protocolVersion === 2 && state.filterPath.length
                        && !ItemFilter.matchesAnyPath(item, state.filterPath, taxonomyPaths)) return false;
                if (!state.query) return true;
                return String(item.displayName || '').toLowerCase().indexOf(state.query) >= 0;
            });
            if (state.protocolVersion !== 2) return visible;
            return visible.sort(materialComparator);
        }

        function archiveCompare(left, right) {
            return Number(left.archiveOrder) - Number(right.archiveOrder);
        }

        function materialComparator(left, right) {
            var compared = 0;
            if (state.sort === 'owned') compared = Number(right.owned) - Number(left.owned);
            else if (state.sort === 'purpose') compared = purposeCount(right) - purposeCount(left);
            else if (state.sort === 'name') compared = nameCollator
                ? nameCollator.compare(left.displayName, right.displayName)
                : String(left.displayName).localeCompare(String(right.displayName), 'zh-CN');
            return compared || archiveCompare(left, right);
        }

        function renderFilters() {
            var navigationBusy = shopNavigationPending();
            var buttons = filters.querySelectorAll('[data-material-filter]');
            var counts = {all:state.items.length, owned:0, used:0};
            for (var index = 0; index < state.items.length; index++) {
                if (Number(state.items[index].owned || 0) > 0) counts.owned++;
                if (purposeCount(state.items[index]) > 0) counts.used++;
            }
            var hideCounts = state.loading || !!state.catalogError;
            for (var i = 0; i < buttons.length; i++) {
                var active = buttons[i].getAttribute('data-material-filter') === state.filter;
                buttons[i].classList.toggle('active', active);
                buttons[i].setAttribute('aria-pressed', active ? 'true' : 'false');
                buttons[i].disabled = state.loading || !!state.catalogError || navigationBusy;
                var countNode = buttons[i].querySelector('small');
                if (countNode) {
                    countNode.hidden = hideCounts;
                    if (!hideCounts) {
                        countNode.textContent = numberLabel(
                            counts[buttons[i].getAttribute('data-material-filter')] || 0);
                    }
                }
            }
            search.disabled = state.loading || !!state.catalogError || navigationBusy;
            filterNavigator.setDisabled(state.loading || !!state.catalogError || navigationBusy);
            sortDropdown.update({disabled:state.protocolVersion !== 2 || state.loading
                || !!state.catalogError || navigationBusy, value:state.sort});
        }

        function renderCard(item) {
            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'crafting-material-card crafting-material-tile';
            card.setAttribute('role', 'option');
            card.setAttribute('tabindex', '-1');
            card.setAttribute('data-material-name', item.name);
            card.setAttribute('aria-label', (item.displayName || '未命名材料')
                + '，持有 ' + numberLabel(item.owned || 0)
                + '，来源 ' + numberLabel(item.sourceCount || 0)
                + '，用途 ' + numberLabel(purposeCount(item)));
            if (Number(item.owned || 0) <= 0) card.classList.add('is-unowned');
            var icon = document.createElement('span');
            icon.className = 'crafting-material-card-icon';
            icon.innerHTML = options.iconHtml(item.icon, 'kshop-icon');
            var copy = document.createElement('span');
            copy.className = 'crafting-material-card-copy';
            var name = document.createElement('b');
            name.textContent = item.displayName || '未命名材料';
            var owned = document.createElement('small');
            owned.textContent = '持有 ' + numberLabel(item.owned || 0);
            var meta = document.createElement('span');
            meta.className = 'crafting-material-card-meta';
            var metaParts = [];
            var typeEntry = typeLabels && typeLabels[item.typeId];
            if (typeEntry && typeEntry.label) metaParts.push(typeEntry.label);
            metaParts.push('来源 ' + numberLabel(item.sourceCount || 0));
            metaParts.push('用途 ' + numberLabel(purposeCount(item)));
            meta.textContent = metaParts.join(' · ');
            var badge = document.createElement('span');
            badge.className = 'crafting-material-card-owned';
            badge.textContent = Number(item.owned || 0) > 0 ? numberLabel(Number(item.owned)) : '';
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
                if (shopNavigationPending()) return;
                state.focusedName = item.name;
                syncRovingFocus(item.name);
                select(item.name);
                cue('select');
            });
            card.addEventListener('keydown', function(event) {
                if (shopNavigationPending()) return;
                var key = event && event.key;
                if (key === 'Enter' || key === ' ') {
                    event.preventDefault();
                    state.focusedName = item.name;
                    select(item.name);
                    cue('select');
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
            if (typeof options.bindTooltip === 'function') {
                card.setAttribute('data-material-tooltip', 'catalog');
                options.bindTooltip(card, item);
            }
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
            catalogChrome.setMeta(state.loading ? '同步中' : state.catalogError
                ? '读取失败' : '显示 ' + visible.length + ' / ' + state.items.length);
            renderer.setSelectedKey(state.selectedName || null);
            if (state.loading) renderCatalogEmpty('loading', '正在同步材料目录…', '请稍候。');
            else if (state.catalogError) renderCatalogEmpty(
                'error', state.catalogError, '重新同步以获取有效材料数据。');
            else if (!state.items.length) renderCatalogEmpty(
                'empty', '当前材料目录没有有效材料数据。', '重新同步以确认数据源。');
            else if (!visible.length) renderCatalogEmpty(
                'filtered-empty', '当前条件没有匹配的材料。', '清除搜索、快捷筛选与分类路径。');
            else {
                catalogEmpty.hidden = true;
                renderer.root.hidden = false;
                renderer.render(visible, renderOptions);
                syncRovingFocus();
            }
        }

        function renderCatalogEmpty(kind, statement, nextStep) {
            renderer.render([]);
            renderer.root.hidden = true;
            Workbench.clearElement(catalogEmpty);
            catalogEmpty.hidden = false;
            catalogEmpty.setAttribute('data-empty-kind', kind);
            var statementNode = document.createElement('p');
            statementNode.className = 'crafting-material-empty-statement';
            statementNode.textContent = statement;
            var nextNode = document.createElement('p');
            nextNode.className = 'crafting-material-empty-next';
            nextNode.textContent = nextStep;
            catalogEmpty.appendChild(statementNode);
            catalogEmpty.appendChild(nextNode);
            if (kind === 'filtered-empty') {
                appendCatalogEmptyAction('清除筛选', clearCatalogConstraints);
            } else if (kind === 'empty' || kind === 'error') {
                appendCatalogEmptyAction('重新同步', function() {
                    if (typeof options.onRetry === 'function') options.onRetry();
                });
            }
            state.focusedName = '';
        }

        function appendCatalogEmptyAction(label, action) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'workbench-mode-btn crafting-material-empty-action';
            button.textContent = label;
            button.addEventListener('click', action);
            catalogEmpty.appendChild(button);
        }

        function clearCatalogConstraints() {
            if (shopNavigationPending()) return false;
            search.value = '';
            state.query = '';
            state.filter = 'all';
            state.filterPath = [];
            filterNavigator.setPath([], true);
            renderFilters();
            renderCatalog({preserveScroll:false});
            scheduleResultAnnouncement();
            var first = renderer.root.querySelector('.crafting-material-card');
            if (first) {
                state.focusedName = first.getAttribute('data-material-name') || '';
                syncRovingFocus(state.focusedName);
                first.focus();
            } else search.focus();
        }

        function scheduleResultAnnouncement() {
            if (resultAnnouncementTimer !== null) clearTimeout(resultAnnouncementTimer);
            resultStatus.textContent = '';
            resultAnnouncementTimer = setTimeout(function() {
                resultAnnouncementTimer = null;
                if (state.loading || state.catalogError) {
                    resultStatus.textContent = '';
                    return;
                }
                resultStatus.textContent = '显示 ' + visibleItems().length
                    + ' 种材料，共 ' + state.items.length + ' 种。';
            }, 180);
        }

        function applyCatalogConstraint() {
            if (shopNavigationPending()) return false;
            var visible = visibleItems();
            var selectedVisible = state.selectedName && visible.some(function(item) {
                return item.name === state.selectedName;
            });
            if (state.selectedName && !selectedVisible) {
                var previousSelection = state.selectedName;
                state.selectedName = '';
                state.detail = null;
                state.detailLoading = false;
                clearUseAction();
                if (typeof options.onSelectionChange === 'function') {
                    options.onSelectionChange('', previousSelection);
                }
                renderDetail();
            }
            if (state.focusedName && !visible.some(function(item) {
                return item.name === state.focusedName;
            })) state.focusedName = '';
            renderCatalog({preserveScroll:false});
            scheduleResultAnnouncement();
        }

        function syncAnchorNav() {
            Workbench.clearElement(anchorNav);
            var entries = [];
            [detailBody.querySelector('.crafting-material-sources'),
                detailBody.querySelector('.crafting-material-uses')].forEach(function(host) {
                if (!host) return;
                var heading = host.querySelector('h3');
                if (!heading) return;
                entries.push({host:host, label:heading.textContent,
                    count:heading.getAttribute('data-count')});
            });
            anchorNav.hidden = entries.length === 0;
            entries.forEach(function(entry) {
                var chip = document.createElement('button');
                chip.type = 'button';
                chip.className = 'crafting-material-anchor';
                chip.setAttribute('aria-label', '跳到' + entry.label);
                chip.textContent = entry.label;
                if (entry.count) {
                    var countNode = document.createElement('small');
                    countNode.textContent = entry.count;
                    chip.appendChild(countNode);
                }
                chip.addEventListener('click', function() {
                    entry.host.scrollIntoView({block:'start'});
                });
                anchorNav.appendChild(chip);
            });
        }

        function appendEmpty(text) {
            anchorNav.hidden = true;
            Workbench.clearElement(anchorNav);
            var empty = document.createElement('div');
            empty.className = 'crafting-detail-empty';
            empty.textContent = text;
            detailBody.appendChild(empty);
            return empty;
        }

        function appendDetailRetry(host) {
            if (!state.detailRetryAvailable || !state.selectedName) return null;
            var catalogItem = selectedCatalogItem();
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'workbench-mode-btn crafting-material-detail-retry';
            button.setAttribute('data-material-detail-retry', state.selectedName);
            button.setAttribute('aria-label', '重新读取'
                + (catalogItem && catalogItem.displayName || '当前材料') + '的材料详情');
            button.textContent = '重新读取当前材料';
            button.addEventListener('click', function() {
                var name = String(state.selectedName || '');
                if (shopNavigationPending() || !name || state.detailLoading || !state.detailError
                        || typeof options.onSelect !== 'function') return;
                state.detailRetryFocusName = name;
                state.detailRetryAvailable = false;
                state.detailError = '';
                state.detailLoading = true;
                renderDetail();
                if (options.onSelect(name) === false && state.detailLoading) {
                    setDetailError('材料详情请求未发送，请重试。', true);
                }
            });
            (host || detailBody).appendChild(button);
            return button;
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

        function useKey(use) {
            if (!use) return '';
            return String(use.recipeOrigin === 'craft_source' ? 'craft_source' : 'use') + '\u0000'
                + String(use.recipeOrigin === 'craft_source' ? use.sourceKey || '' : '') + '\u0000'
                + String(use.category || '') + '\u0000'
                + String(Number(use.recipeIndex)) + '\u0000'
                + String(use.productName || '');
        }

        function findCurrentUse(category, recipeIndex, productName) {
            var uses = state.detail && state.detail.uses || [];
            var matches = uses.filter(function(use) {
                return String(use.category || '') === String(category || '')
                    && Number(use.recipeIndex) === Number(recipeIndex)
                    && String(use.productName || '') === String(productName || '');
            });
            return matches.length === 1 ? matches[0] : null;
        }

        function isCurrentUse(category, recipeIndex, productName) {
            return state.protocolVersion === 2 && !!state.selectedName
                && !!findCurrentUse(category, recipeIndex, productName);
        }

        function findCurrentCraftSource(sourceKey, category, recipeIndex, productName) {
            var sources = state.detail && state.detail.sources || [];
            var matches = sources.filter(function(source) {
                return source && source.kind === 'craft'
                    && String(source.sourceKey || '') === String(sourceKey || '')
                    && String(source.category || '') === String(category || '')
                    && Number(source.recipeIndex) === Number(recipeIndex)
                    && String(source.productName || '') === String(productName || '');
            });
            if (matches.length !== 1 || !state.detail || !state.detail.material
                    || String(state.detail.material.name || '') !== String(matches[0].productName || '')
                    || String(state.selectedName || '') !== String(matches[0].productName || '')) return null;
            return {
                category:String(matches[0].category || ''),
                recipeIndex:Number(matches[0].recipeIndex),
                productName:String(matches[0].productName || ''),
                sourceKey:String(matches[0].sourceKey || ''),
                displayName:String(state.detail.material.displayName || matches[0].productName || ''),
                itemKind:'',
                recipeOrigin:'craft_source'
            };
        }

        function findCurrentRecipeTarget(category, recipeIndex, productName, recipeOrigin, sourceKey) {
            if (recipeOrigin === 'craft_source') {
                return findCurrentCraftSource(sourceKey, category, recipeIndex, productName);
            }
            if (recipeOrigin && recipeOrigin !== 'use') return null;
            return findCurrentUse(category, recipeIndex, productName);
        }

        function isCurrentRecipeTarget(category, recipeIndex, productName, recipeOrigin, sourceKey) {
            return state.protocolVersion === 2 && !!state.selectedName
                && !!findCurrentRecipeTarget(category, recipeIndex, productName, recipeOrigin, sourceKey);
        }

        function craftingNavigationAllowed() {
            return state.protocolVersion === 2 && state.navigationAccess.crafting === true;
        }

        function shopNavigationAllowed() {
            return state.protocolVersion === 2 && state.navigationAccess.shop === true;
        }

        function actionLabel(kind, status) {
            var equipment = kind === 'inspect';
            if (!equipment && !craftingNavigationAllowed()) return '需摩托车';
            if (status === 'pending') return equipment ? '核验装备…' : '正在打开…';
            if (status === 'error') return equipment ? '重试查看装备' : '重试前往合成';
            return equipment ? '查看装备' : '前往合成';
        }

        function syncUseActionControls() {
            var pending = !!state.useAction && state.useAction.status === 'pending';
            var navigationBusy = shopNavigationPending();
            var buttons = detailBody.querySelectorAll('[data-material-use-action]');
            Array.prototype.forEach.call(buttons, function(button) {
                var matches = !!state.useAction
                    && button.__materialUseKey === state.useAction.key
                    && button.getAttribute('data-material-use-action') === state.useAction.kind;
                var recipeLocked = button.getAttribute('data-material-use-action') === 'recipe'
                    && !craftingNavigationAllowed();
                button.disabled = pending || navigationBusy || recipeLocked;
                button.textContent = actionLabel(
                    button.getAttribute('data-material-use-action'),
                    matches ? state.useAction.status : 'idle');
                button.setAttribute('aria-busy', matches && pending ? 'true' : 'false');
                if (recipeLocked) {
                    button.title = '需要摩托车或越野车，才能从材料档案前往合成。';
                } else {
                    button.removeAttribute('title');
                }
            });
            var statuses = detailBody.querySelectorAll('.crafting-material-use-action-status');
            Array.prototype.forEach.call(statuses, function(status) {
                var matches = !!state.useAction && status.__materialUseKey === state.useAction.key;
                status.textContent = matches ? state.useAction.message : '';
                status.hidden = !matches || !state.useAction.message;
                status.setAttribute('data-action-state', matches ? state.useAction.status : 'idle');
            });
        }

        function setUseActionPending(use, kind) {
            kind = kind === 'inspect' ? 'inspect' : 'recipe';
            var current = kind === 'inspect'
                ? findCurrentUse(use && use.category, use && use.recipeIndex, use && use.productName)
                : findCurrentRecipeTarget(use && use.category, use && use.recipeIndex,
                    use && use.productName, use && use.recipeOrigin, use && use.sourceKey);
            if (state.protocolVersion !== 2 || !current
                    || kind === 'inspect' && current.itemKind !== 'equipment'
                    || kind === 'recipe' && !craftingNavigationAllowed()) return false;
            state.useAction = {
                key:useKey(current), kind:kind, status:'pending',
                message:kind === 'inspect' ? '正在核验最新装备数据…' : '正在打开合成…'
            };
            syncUseActionControls();
            return true;
        }

        function setUseActionError(use, kind, message) {
            kind = kind === 'inspect' ? 'inspect' : 'recipe';
            var current = kind === 'inspect'
                ? findCurrentUse(use && use.category, use && use.recipeIndex, use && use.productName)
                : findCurrentRecipeTarget(use && use.category, use && use.recipeIndex,
                    use && use.productName, use && use.recipeOrigin, use && use.sourceKey);
            if (state.protocolVersion !== 2 || !current) return false;
            state.useAction = {
                key:useKey(current), kind:kind, status:'error',
                message:String(message || '暂时无法打开合成；请重试。')
            };
            syncUseActionControls();
            return true;
        }

        function completeUseAction(use, kind) {
            kind = kind === 'inspect' ? 'inspect' : 'recipe';
            if (!state.useAction || state.useAction.key !== useKey(use)
                    || state.useAction.kind !== kind) return false;
            state.useAction = null;
            syncUseActionControls();
            return true;
        }

        function clearUseAction() {
            if (!state.useAction) return false;
            state.useAction = null;
            syncUseActionControls();
            return true;
        }

        function isUseActionTrigger(node, use, kind) {
            return !!node && node.nodeType === 1 && node.isConnected !== false
                && detailBody.contains(node)
                && node.getAttribute('data-material-use-action') === kind
                && node.__materialUseKey === useKey(use);
        }

        function appendUseAction(actions, use, kind) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'workbench-mode-btn crafting-material-use-action';
            button.setAttribute('data-material-use-action', kind);
            button.__materialUseKey = useKey(use);
            button.textContent = actionLabel(kind, 'idle');
            button.setAttribute('aria-label', kind === 'recipe' && !craftingNavigationAllowed()
                ? '需要摩托车或越野车，才能前往合成：'
                    + (use.displayName || '未命名用途')
                : (kind === 'inspect' ? '查看装备 ' : '前往合成 ')
                    + (use.displayName || '未命名用途'));
            button.addEventListener('click', function(event) {
                event.preventDefault();
                event.stopPropagation();
                if (shopNavigationPending()
                        || state.useAction && state.useAction.status === 'pending') return;
                var callback = kind === 'inspect' ? options.onInspectUse : options.onOpenRecipe;
                if (typeof callback !== 'function' || callback(use, button) === false) {
                    if (!state.useAction || state.useAction.status === 'pending') {
                        setUseActionError(use, kind, '暂时无法打开合成；请重试。');
                    }
                }
            });
            actions.appendChild(button);
            return button;
        }

        function sourceTitle(source) {
            if (source.kind === 'enemy') return '敌人 · ' + (source.displayName || '未知敌人');
            if (source.kind === 'stage') return '关卡 · ' + (source.stageName || '未知');
            if (source.kind === 'shop') return '商店 · ' + (source.shopId || source.npc || '未知');
            if (source.kind === 'kshop') return 'K 点商城 · ' + (source.category || '商品');
            if (source.kind === 'quest') return '任务 · ' + (source.title || '未知任务');
            return '合成 · ' + (source.category || '未知分类');
        }

        function legacySourceMeta(source) {
            var parts = [];
            if (source.kind === 'enemy' || source.kind === 'stage') {
                parts.push('旧版来源记录；概率与档位不可核验');
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

        function numberLabel(value) {
            return Number(value).toLocaleString('zh-CN', {maximumFractionDigits:6});
        }

        function heroStatsText() {
            var item = selectedCatalogItem();
            if (!item) return '';
            var parts = [];
            var typeEntry = typeLabels && typeLabels[item.typeId];
            if (typeEntry && typeEntry.label) parts.push(typeEntry.label);
            parts.push('来源 ' + numberLabel(item.sourceCount || 0));
            parts.push('用途 ' + numberLabel(purposeCount(item)));
            return parts.join(' · ');
        }

        function quantityLabel(variant) {
            return variant.quantityMin === variant.quantityMax
                ? '数量 ' + numberLabel(variant.quantityMin)
                : '数量 ' + numberLabel(variant.quantityMin) + '–' + numberLabel(variant.quantityMax);
        }

        function reverseLevelLabel(variant) {
            var min = variant.minReverseLevel, max = variant.maxReverseLevel;
            if (min === null && max === null) return '';
            if (min !== null && max !== null) return min === max
                ? '逆向等级 ' + min : '逆向等级 ' + min + '–' + max;
            return min !== null ? '逆向等级 ≥ ' + min : '逆向等级 ≤ ' + max;
        }

        function variantLabel(source, variant) {
            var parts = [];
            if (source.kind === 'enemy') {
                if (variant.chanceInputState === 'explicit') {
                    parts.push('基础掉落 ' + numberLabel(variant.nominalChancePercent) + '%');
                } else if (variant.chanceInputState === 'absent_defaulted') {
                    parts.push('默认必得');
                } else {
                    parts.push('配置异常，按必得处理');
                }
                var level = reverseLevelLabel(variant);
                if (level) parts.push(level);
            } else {
                parts.push('关卡基准 '
                    + numberLabel(variant.defaultBranchChancePercent) + '%');
            }
            parts.push(quantityLabel(variant));
            return parts.join(' · ');
        }

        function v2SourceMeta(source) {
            var parts = [];
            if (source.kind === 'craft') {
                if (source.price > 0) parts.push(numberLabel(source.price) + ' 金币');
                if (source.kpoints > 0) parts.push(numberLabel(source.kpoints) + ' K 点');
            } else if (source.kind === 'shop') {
                parts.push('参考单价 ' + numberLabel(source.unitPriceAtSnapshot) + ' 金币');
                if (source.locked) parts.push('当前未解锁');
                if (source.requiredInfo) parts.push(source.requiredInfo);
            } else if (source.kind === 'kshop') {
                parts.push(numberLabel(source.priceK) + ' K 点');
            } else if (source.kind === 'quest') {
                parts.push((source.rewardSet === 'challenge' ? '挑战奖励 ' : '任务奖励 ')
                    + numberLabel(source.quantity) + ' 个');
            }
            return parts.join(' · ');
        }

        function sourceGuideText(sources) {
            var hasDrops = sources.some(function(source) {
                return source.kind === 'enemy' || source.kind === 'stage';
            });
            var hasShop = sources.some(function(source) { return source.kind === 'shop'; });
            var parts = [];
            if (hasDrops) parts.push('掉落率仅供参考');
            if (hasShop) parts.push('价格和库存以商店内为准');
            return parts.join('；') + (parts.length ? '。' : '');
        }

        function shopNavigationPending() {
            return !!state.shopNavigation && state.shopNavigation.status === 'pending';
        }

        function currentShopSource(sourceKey) {
            var sources = state.detail && state.detail.sources || [];
            var matches = sources.filter(function(source) {
                return source && source.kind === 'shop'
                    && String(source.sourceKey || '') === String(sourceKey || '');
            });
            return matches.length === 1 ? matches[0] : null;
        }

        function shopSourceNavigable(source) {
            return state.protocolVersion === 2 && !!source
                && source.kind === 'shop'
                && source.shopAccessMode === 'full'
                && source.shopAccessReason === 'indexed_live_match';
        }

        function syncShopNavigationControls() {
            var navigation = state.shopNavigation;
            var pending = shopNavigationPending();
            catalogRoot.setAttribute('aria-busy', pending ? 'true' : 'false');
            detailRoot.setAttribute('aria-busy', pending ? 'true' : 'false');
            renderFilters();
            var cards = renderer.root.querySelectorAll('.crafting-material-card');
            Array.prototype.forEach.call(cards, function(card) { card.disabled = pending; });
            var retry = detailBody.querySelector('.crafting-material-detail-retry');
            if (retry) retry.disabled = pending;
            syncUseActionControls();
            var buttons = detailBody.querySelectorAll('[data-material-shop-action]');
            Array.prototype.forEach.call(buttons, function(button) {
                var matches = !!navigation && button.getAttribute('data-material-shop-action')
                    === navigation.sourceKey;
                var accessLocked = !shopNavigationAllowed();
                button.disabled = pending || accessLocked;
                button.setAttribute('aria-busy', matches && pending ? 'true' : 'false');
                button.textContent = accessLocked ? '需自行车'
                    : matches && pending ? '正在打开…'
                    : matches && navigation.status === 'error' ? '重试前往商店' : '前往商店';
                if (accessLocked) {
                    button.title = '建成自行车、摩托车或越野车后，可从材料档案前往商店。';
                } else {
                    button.removeAttribute('title');
                }
            });
            var statuses = detailBody.querySelectorAll('.crafting-material-shop-navigation-status');
            Array.prototype.forEach.call(statuses, function(status) {
                var matches = !!navigation && status.getAttribute('data-material-shop-status')
                    === navigation.sourceKey;
                status.textContent = matches ? navigation.message : '';
                status.hidden = !matches || !navigation.message;
                status.setAttribute('data-navigation-state', matches ? navigation.status : 'idle');
            });
        }

        function setShopNavigationPending(sourceKey) {
            var source = currentShopSource(sourceKey);
            if (shopNavigationPending() || !shopSourceNavigable(source)
                    || !shopNavigationAllowed()) return false;
            state.shopNavigation = {sourceKey:String(sourceKey), status:'pending',
                message:'正在验证最新商店访问权限…'};
            syncShopNavigationControls();
            return true;
        }

        function setShopNavigationError(sourceKey, message) {
            if (!state.shopNavigation || state.shopNavigation.status !== 'pending'
                    || state.shopNavigation.sourceKey !== String(sourceKey)
                    || !currentShopSource(sourceKey)) return false;
            state.shopNavigation = {sourceKey:String(sourceKey), status:'error',
                message:String(message || '暂时无法前往商店；请重试。')};
            syncShopNavigationControls();
            return true;
        }

        function clearShopNavigation() {
            var changed = !!state.shopNavigation;
            state.shopNavigation = null;
            if (changed) syncShopNavigationControls();
            return changed;
        }

        function isShopNavigationTrigger(node, sourceKey) {
            return !!node && node.nodeType === 1 && node.isConnected !== false
                && detailBody.contains(node)
                && node.getAttribute('data-material-shop-action') === String(sourceKey || '');
        }

        function invalidateSourcePortraits(root) {
            if (!root || !root.querySelectorAll) return;
            var portraits = root.querySelectorAll('.crafting-material-source-portrait');
            Array.prototype.forEach.call(portraits, function(container) {
                container.removeAttribute('data-material-portrait-epoch');
                container.removeAttribute('data-portrait-request');
                container.removeAttribute('data-shop-portrait-request');
                var img = container.querySelector('img');
                if (!img) return;
                img.onload = null;
                img.onerror = null;
                img.removeAttribute('src');
            });
        }

        function mountSourcePortrait(row, content, source, renderEpoch) {
            if (state.protocolVersion !== 2
                    || (source.kind !== 'enemy' && source.kind !== 'shop')) return;
            var container = document.createElement('span');
            container.className = 'crafting-material-source-portrait';
            container.setAttribute('aria-hidden', 'true');
            container.setAttribute('data-material-portrait-epoch', String(renderEpoch));
            container.setAttribute('data-material-portrait-state', 'placeholder');
            var img = document.createElement('img');
            img.alt = '';
            img.setAttribute('alt', '');
            img.setAttribute('aria-hidden', 'true');
            img.draggable = false;
            container.appendChild(img);
            row.classList.add('has-source-portrait');
            row.insertBefore(container, content);

            var mountResult = null;
            try {
                if (source.kind === 'enemy' && typeof EnemyPortraits !== 'undefined'
                        && EnemyPortraits && typeof EnemyPortraits.mount === 'function') {
                    mountResult = EnemyPortraits.mount(container, img, {
                        consumer:'crafting',
                        portraitRef:source.enemyType,
                        legacyUrl:EnemyPortraits.fallbackUrl()
                    });
                } else if (source.kind === 'shop' && typeof ShopPortraits !== 'undefined'
                        && ShopPortraits && typeof ShopPortraits.mount === 'function') {
                    mountResult = ShopPortraits.mount(container, img, source.shopId);
                }
            } catch (ignore) {
                mountResult = null;
            }
            if (!mountResult || typeof mountResult.then !== 'function') return;
            mountResult.then(function() {
                if (detailRenderEpoch === renderEpoch
                        && container.getAttribute('data-material-portrait-epoch') === String(renderEpoch)
                        && container.isConnected !== false) return;
                container.removeAttribute('data-portrait-request');
                container.removeAttribute('data-shop-portrait-request');
                img.onload = null;
                img.onerror = null;
                img.removeAttribute('src');
            }).catch(function() {
                // Portraits are decoration. Resolver or decode failures retain
                // the fixed placeholder and never alter source disclosure.
            });
        }

        function appendSourceCard(sourceList, source, renderEpoch, sourceGuideId) {
            var row = document.createElement('article');
            row.className = 'crafting-material-source-card';
            row.setAttribute('data-material-source-kind', source.kind);
            if (source.sourceKey) row.setAttribute('data-material-source-key', source.sourceKey);
            if (source.kind === 'enemy') row.setAttribute('data-enemy-type', source.enemyType);
            if (source.kind === 'shop') row.setAttribute('data-shop-id', source.shopId);
            if (source.sourceOrder != null) {
                row.setAttribute('data-source-order', String(source.sourceOrder));
            }
            var content = document.createElement('div');
            content.className = 'crafting-material-source-content';
            var title = document.createElement('h4');
            title.textContent = sourceTitle(source);
            content.appendChild(title);
            if (state.protocolVersion === 2
                    && (source.kind === 'enemy' || source.kind === 'stage')) {
                var list = document.createElement('ul');
                list.className = 'crafting-material-source-variants';
                source.variants.slice().sort(function(left, right) {
                    return left.occurrenceIndex - right.occurrenceIndex;
                }).forEach(function(variant) {
                    var entry = document.createElement('li');
                    entry.setAttribute('data-occurrence-index', String(variant.occurrenceIndex));
                    entry.textContent = variantLabel(source, variant);
                    list.appendChild(entry);
                });
                content.appendChild(list);
            } else {
                var meta = document.createElement('small');
                if (source.kind === 'shop') {
                    meta.id = 'crafting-material-shop-meta-' + renderEpoch + '-'
                        + String(source.sourceOrder);
                }
                meta.textContent = state.protocolVersion === 2
                    ? (v2SourceMeta(source) || '已记录')
                    : (legacySourceMeta(source) || '已记录');
                content.appendChild(meta);
            }
            if (state.protocolVersion === 2 && source.kind === 'shop') {
                var navigation = document.createElement('div');
                navigation.className = 'crafting-material-shop-navigation';
                if (shopSourceNavigable(source)) {
                    var button = document.createElement('button');
                    button.type = 'button';
                    button.className = 'workbench-mode-btn crafting-material-shop-action';
                    button.setAttribute('data-material-shop-action', source.sourceKey);
                    button.setAttribute('aria-label', shopNavigationAllowed()
                        ? '前往商店：' + source.shopId + '，定位‘'
                            + (state.detail.material.displayName || '当前材料') + '’'
                        : '需要自行车、摩托车或越野车，才能前往商店：'
                            + source.shopId);
                    button.setAttribute('aria-describedby',
                        'crafting-material-shop-meta-' + renderEpoch + '-'
                            + String(source.sourceOrder)
                            + (sourceGuideId ? ' ' + sourceGuideId : ''));
                    button.textContent = '前往商店';
                    button.addEventListener('click', function(event) {
                        event.preventDefault();
                        event.stopPropagation();
                        if (shopNavigationPending() || typeof options.onOpenShop !== 'function') return;
                        options.onOpenShop(source, button);
                    });
                    navigation.appendChild(button);
                    var status = document.createElement('small');
                    status.className = 'crafting-material-shop-navigation-status';
                    status.setAttribute('data-material-shop-status', source.sourceKey);
                    status.setAttribute('role', 'status');
                    status.setAttribute('aria-live', 'polite');
                    status.hidden = true;
                    navigation.appendChild(status);
                } else {
                    var unavailable = document.createElement('span');
                    unavailable.className = 'crafting-material-shop-unavailable';
                    unavailable.textContent = '暂不能从档案前往';
                    navigation.appendChild(unavailable);
                }
                content.appendChild(navigation);
            } else if (state.protocolVersion === 2 && source.kind === 'craft') {
                var craftTarget = findCurrentCraftSource(
                    source.sourceKey, source.category, source.recipeIndex, source.productName);
                if (craftTarget) {
                    var craftNavigation = document.createElement('div');
                    craftNavigation.className = 'crafting-material-craft-navigation';
                    var craftButton = appendUseAction(craftNavigation, craftTarget, 'recipe');
                    craftButton.classList.add('crafting-material-craft-action');
                    var craftStatus = document.createElement('small');
                    craftStatus.className = 'crafting-material-use-action-status';
                    craftStatus.setAttribute('role', 'status');
                    craftStatus.setAttribute('aria-live', 'polite');
                    craftStatus.hidden = true;
                    craftStatus.__materialUseKey = useKey(craftTarget);
                    craftNavigation.appendChild(craftStatus);
                    content.appendChild(craftNavigation);
                }
            }
            sourceList.appendChild(row);
            row.appendChild(content);
            mountSourcePortrait(row, content, source, renderEpoch);
        }

        function ingredientLabel(ingredient) {
            var name = ingredient.displayName || ingredient.name || '未命名材料';
            var required = Number(ingredient.required || 0);
            return ingredient.isQuantity === false
                ? name + ' · 强化 ≥ +' + required
                : name + ' ×' + required;
        }

        function appendIngredientPreview(row, use) {
            if (!Array.isArray(use.ingredients) || !use.ingredients.length) return null;
            var preview = document.createElement('div');
            preview.className = 'crafting-material-use-ingredients';
            var list = document.createElement('ul');
            list.className = 'crafting-material-ingredient-grid';
            var labels = [];
            use.ingredients.forEach(function(ingredient) {
                var item = document.createElement('li');
                var label = ingredientLabel(ingredient);
                var current = String(ingredient.name || '') === String(state.selectedName || '');
                labels.push(label);
                item.className = 'crafting-material-tile crafting-material-ingredient-tile';
                item.setAttribute('aria-label', (current ? '当前材料，' : '') + label);
                var icon = document.createElement('span');
                icon.className = 'crafting-material-card-icon';
                var iconUrl = options.staticIconUrl(ingredient.icon);
                if (iconUrl) {
                    var image = document.createElement('img');
                    image.className = 'kshop-icon';
                    image.src = iconUrl;
                    image.alt = '';
                    image.setAttribute('data-static-icon-name', ingredient.icon);
                    image.onerror = function() { this.style.display = 'none'; };
                    icon.appendChild(image);
                } else {
                    icon.innerHTML = options.iconHtml('', 'kshop-icon');
                }
                icon.setAttribute('aria-hidden', 'true');
                var badge = document.createElement('span');
                badge.className = 'crafting-material-card-owned';
                badge.textContent = ingredient.isQuantity === false
                    ? '≥+' + Number(ingredient.required || 0)
                    : '×' + Number(ingredient.required || 0);
                item.appendChild(icon);
                item.appendChild(badge);
                if (current) {
                    item.classList.add('is-current');
                    item.setAttribute('aria-current', 'true');
                }
                if (typeof options.bindTooltip === 'function') {
                    options.bindTooltip(item, ingredient);
                }
                list.appendChild(item);
            });
            preview.setAttribute('aria-label', '所需材料：' + labels.join('，'));
            preview.appendChild(list);
            row.appendChild(preview);
            return preview;
        }

        function infrastructureLevelLabel(level) {
            return 'Lv.' + Number(level.levelIndex) + ' → Lv.' + Number(level.targetLevel);
        }

        function appendInfrastructureMaterialTile(list, material, level) {
            var item = document.createElement('li');
            var displayName = material.displayName || material.name || '当前材料';
            item.className = 'crafting-material-tile crafting-material-ingredient-tile'
                + ' crafting-material-infrastructure-tile is-current';
            item.setAttribute('aria-current', 'true');
            item.setAttribute('aria-label', '当前材料，' + displayName + ' ×' + Number(level.required));
            var icon = document.createElement('span');
            icon.className = 'crafting-material-card-icon';
            var iconUrl = options.staticIconUrl(material.icon);
            if (iconUrl) {
                var image = document.createElement('img');
                image.className = 'kshop-icon';
                image.src = iconUrl;
                image.alt = '';
                image.setAttribute('data-static-icon-name', material.icon);
                image.onerror = function() { this.style.display = 'none'; };
                icon.appendChild(image);
            } else {
                icon.innerHTML = options.iconHtml('', 'kshop-icon');
            }
            icon.setAttribute('aria-hidden', 'true');
            var badge = document.createElement('span');
            badge.className = 'crafting-material-card-owned';
            badge.textContent = '×' + Number(level.required);
            item.appendChild(icon);
            item.appendChild(badge);
            if (typeof options.bindTooltip === 'function') options.bindTooltip(item, material);
            list.appendChild(item);
        }

        function appendInfrastructureUses(host, material, projects) {
            var group = document.createElement('div');
            group.className = 'crafting-material-infrastructure';
            group.setAttribute('role', 'group');
            group.setAttribute('aria-label', '基建升级逐级需求');
            var guide = document.createElement('p');
            guide.className = 'crafting-material-infrastructure-guide';
            var guideTitle = document.createElement('b');
            guideTitle.textContent = '基建升级';
            var guideCopy = document.createElement('span');
            guideCopy.textContent = '各级缺口按当前库存独立计算。';
            guide.appendChild(guideTitle);
            guide.appendChild(guideCopy);
            group.appendChild(guide);
            var projectList = document.createElement('div');
            projectList.className = 'crafting-material-infrastructure-list';
            projects.forEach(function(project) {
                var card = document.createElement('article');
                card.className = 'crafting-material-infrastructure-card';
                card.setAttribute('data-project-order', String(project.projectOrder));
                card.setAttribute('aria-label', project.infrastructureName + '，当前等级 '
                    + Number(project.currentLevel) + '，最高等级 ' + Number(project.maximumLevel));
                var header = document.createElement('header');
                var title = document.createElement('h4');
                title.textContent = project.infrastructureName;
                var progress = document.createElement('small');
                progress.textContent = Number(project.currentLevel) >= Number(project.maximumLevel)
                    ? '已满级 · Lv.' + Number(project.maximumLevel)
                    : '当前 Lv.' + Number(project.currentLevel) + ' / ' + Number(project.maximumLevel);
                header.appendChild(title);
                header.appendChild(progress);
                card.appendChild(header);
                var levels = document.createElement('ol');
                levels.className = 'crafting-material-infrastructure-levels';
                project.levels.forEach(function(level) {
                    var row = document.createElement('li');
                    var completed = level.status === 'completed';
                    var missing = Number(level.missing || 0);
                    row.className = 'crafting-material-infrastructure-level';
                    row.setAttribute('data-level-index', String(level.levelIndex));
                    row.setAttribute('data-target-level', String(level.targetLevel));
                    row.setAttribute('data-infrastructure-status', level.status);
                    row.setAttribute('data-material-gap', completed ? 'completed' : (missing > 0 ? 'missing' : 'ready'));
                    var levelName = document.createElement('span');
                    levelName.className = 'crafting-material-infrastructure-level-name';
                    levelName.textContent = infrastructureLevelLabel(level);
                    var requirement = document.createElement('div');
                    requirement.className = 'crafting-material-infrastructure-requirement';
                    var materialList = document.createElement('ul');
                    materialList.className = 'crafting-material-ingredient-grid';
                    appendInfrastructureMaterialTile(materialList, material, level);
                    requirement.appendChild(materialList);
                    var status = document.createElement('strong');
                    status.className = 'crafting-material-infrastructure-status';
                    status.textContent = completed ? '已完成' : (missing > 0 ? '缺 ' + missing : '材料已足');
                    var accessibleStatus = completed ? '已完成'
                        : ('当前持有 ' + Number(level.owned) + '，'
                            + (missing > 0 ? '还缺 ' + missing : '材料已足够'));
                    row.setAttribute('aria-label', project.infrastructureName + '，'
                        + infrastructureLevelLabel(level) + '，'
                        + (completed ? '已完成升级' : (level.status === 'current' ? '当前升级' : '后续升级')) + '，'
                        + (material.displayName || material.name || '当前材料') + '需要 '
                        + Number(level.required) + '，' + accessibleStatus);
                    row.appendChild(levelName);
                    row.appendChild(requirement);
                    row.appendChild(status);
                    levels.appendChild(row);
                });
                card.appendChild(levels);
                projectList.appendChild(card);
            });
            group.appendChild(projectList);
            host.appendChild(group);
        }

        function renderDetail() {
            detailRenderEpoch++;
            invalidateSourcePortraits(detailBody);
            var renderEpoch = detailRenderEpoch;
            Workbench.clearElement(detailBody);
            if (state.catalogError) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta('目录不可用');
                appendEmpty('材料目录暂不可用；重新同步后再查看档案。');
                return;
            }
            if (state.loading) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta('同步中');
                appendEmpty('正在同步材料目录…');
                return;
            }
            if (state.detailError) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta('详情读取失败');
                appendDetailRetry(appendEmpty(state.detailError));
                return;
            }
            if (!state.selectedName) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta(state.loading ? '同步中' : '请选择材料');
                appendEmpty(state.loading ? '正在同步材料目录…' : '从左侧选择一种材料');
                return;
            }
            if (state.detailLoading || !state.detail) {
                detailChrome.setTitle('材料档案', '来源与用途');
                detailChrome.setMeta('正在读取…');
                appendEmpty('正在读取来源与用途…');
                return;
            }
            var material = state.detail.material || {};
            detailChrome.setTitle('材料档案', '来源与用途');
            detailChrome.setMeta('当前持有 ' + numberLabel(material.owned || 0));

            var hero = document.createElement('section');
            hero.className = 'crafting-material-hero';
            var icon = document.createElement('span');
            icon.className = 'crafting-material-hero-icon';
            icon.innerHTML = options.iconHtml(material.icon, 'kshop-icon');
            var copy = document.createElement('div');
            var title = document.createElement('h2');
            title.textContent = material.displayName || '未命名材料';
            copy.appendChild(title);
            var ownedText = state.protocolVersion === 2
                ? heroStatsText() : '持有 ' + numberLabel(material.owned || 0);
            if (ownedText) {
                var owned = document.createElement('strong');
                owned.textContent = ownedText;
                copy.appendChild(owned);
            }
            if (material.description) {
                var description = document.createElement('p');
                // 描述是 AS2 htmlText（可含 <font color> 等标记）：与 tooltip 同走
                // convertAS2Html 白名单清洗，不能用 textContent 原样输出标签。
                if (typeof PanelTooltip !== 'undefined'
                        && typeof PanelTooltip.convertAS2Html === 'function') {
                    description.innerHTML = PanelTooltip.convertAS2Html(material.description);
                } else {
                    description.textContent = material.description;
                }
                copy.appendChild(description);
            }
            hero.appendChild(icon);
            hero.appendChild(copy);
            detailBody.appendChild(hero);

            var summarySection = appendSection('档案摘要', 'crafting-material-summary');
            if (material.sourceSummary) {
                var summary = document.createElement('p');
                summary.className = 'crafting-material-source-summary';
                summary.textContent = material.sourceSummary;
                summarySection.appendChild(summary);
            } else {
                var noSummary = document.createElement('p');
                noSummary.className = 'crafting-material-empty-copy';
                noSummary.textContent = '当前档案暂无摘要。';
                summarySection.appendChild(noSummary);
            }
            var sourceSection = appendSection(state.protocolVersion === 2
                ? '已发现来源' : '从哪里获得', 'crafting-material-sources');
            var sources = (state.detail.sources || []).slice();
            if (state.protocolVersion === 2) sources.sort(function(left, right) {
                return left.sourceOrder - right.sourceOrder;
            });
            if (sources.length) {
                sourceSection.querySelector('h3').setAttribute('data-count', numberLabel(sources.length));
                var sourceGuide = state.protocolVersion === 2 ? sourceGuideText(sources) : '';
                var sourceGuideId = '';
                if (sourceGuide) {
                    var guide = document.createElement('p');
                    guide.className = 'crafting-material-source-guide';
                    guide.id = 'crafting-material-source-guide-' + renderEpoch;
                    guide.textContent = sourceGuide;
                    sourceGuideId = guide.id;
                    sourceSection.appendChild(guide);
                }
                var sourceList = document.createElement('div');
                sourceList.className = 'crafting-material-source-list';
                sources.forEach(function(source) {
                    appendSourceCard(sourceList, source, renderEpoch, sourceGuideId);
                });
                sourceSection.appendChild(sourceList);
            } else {
                var noSource = document.createElement('p');
                noSource.className = 'crafting-material-empty-copy';
                noSource.textContent = state.protocolVersion === 2
                    ? '尚未发现可核验的结构化来源。'
                    : '旧版兼容视图中暂无来源记录。';
                sourceSection.appendChild(noSource);
            }

            var useSection = appendSection('会用在哪里', 'crafting-material-uses');
            var directPurposes = state.protocolVersion === 2
                ? (state.detail.directPurposes || []) : [];
            if (state.protocolVersion === 2) {
                directPurposes.forEach(function(purpose) {
                    var infrastructurePurpose = purpose.id === 'system:infrastructure_upgrade';
                    var infrastructureUses = infrastructurePurpose ? state.detail.infrastructureUses : null;
                    if (infrastructurePurpose && infrastructureUses.length) {
                        appendInfrastructureUses(useSection, material, infrastructureUses);
                        return;
                    }
                    var purposeRow = document.createElement('article');
                    purposeRow.className = 'crafting-material-direct-purpose-row';
                    var purposeName = document.createElement('b');
                    purposeName.textContent = purpose.label;
                    var purposeMeta = document.createElement('small');
                    purposeMeta.textContent = infrastructurePurpose
                        ? '尚未发现相关项目' : '直接系统用途';
                    purposeRow.appendChild(purposeName);
                    purposeRow.appendChild(purposeMeta);
                    useSection.appendChild(purposeRow);
                });
            }
            var uses = state.detail.uses || [];
            var useRowCount = uses.length
                + (state.protocolVersion === 2 ? directPurposes.length : 0);
            if (useRowCount) {
                useSection.querySelector('h3').setAttribute('data-count', numberLabel(useRowCount));
            }
            if (!uses.length) {
                var noUse = document.createElement('p');
                noUse.className = 'crafting-material-empty-copy';
                var hasCraftSource = sources.some(function(source) {
                    return source && source.kind === 'craft';
                });
                noUse.textContent = hasCraftSource
                    ? '没有配方将它作为材料；可从上方合成来源前往制作。'
                    : '当前合成目录中暂无配方用途。';
                if (hasCraftSource || !directPurposes.length) useSection.appendChild(noUse);
            } else {
                uses.forEach(function(use) {
                    var row = document.createElement('article');
                    row.className = 'crafting-material-use-row';
                    var header = document.createElement('div');
                    header.className = 'crafting-material-use-product';
                    var icon = document.createElement('span');
                    icon.className = 'crafting-material-card-icon crafting-material-use-icon';
                    icon.innerHTML = options.iconHtml(use.icon, 'kshop-icon');
                    var copy = document.createElement('span');
                    copy.className = 'crafting-material-use-copy';
                    var name = document.createElement('b');
                    name.textContent = use.displayName || '未命名用途';
                    var meta = document.createElement('small');
                    meta.textContent = use.category || '合成配方';
                    copy.appendChild(name);
                    copy.appendChild(meta);
                    header.appendChild(icon);
                    header.appendChild(copy);
                    if (typeof options.bindTooltip === 'function') {
                        var tooltipItem = state.protocolVersion === 2 ? {
                            name:use.productName,
                            displayName:use.displayName,
                            icon:use.icon,
                            itemKind:use.itemKind
                        } : use;
                        if (state.protocolVersion === 2) {
                            copy.setAttribute('data-material-use-tooltip', '1');
                            options.bindTooltip(copy, tooltipItem);
                        } else {
                            row.setAttribute('tabindex', '0');
                            row.setAttribute('aria-label', (use.displayName || '未命名用途')
                                + '，' + (use.category || '合成配方')
                                + (Number(use.required || 0) > 0 ? '，每份需要 ' + Number(use.required) : ''));
                            options.bindTooltip(row, tooltipItem);
                        }
                    }
                    if (state.protocolVersion === 2) {
                        var actions = document.createElement('span');
                        actions.className = 'crafting-material-use-actions';
                        appendUseAction(actions, use, 'recipe');
                        if (use.itemKind === 'equipment') appendUseAction(actions, use, 'inspect');
                        row.appendChild(header);
                        appendIngredientPreview(row, use);
                        row.appendChild(actions);
                        var actionStatus = document.createElement('small');
                        actionStatus.className = 'crafting-material-use-action-status';
                        actionStatus.setAttribute('role', 'status');
                        actionStatus.setAttribute('aria-live', 'polite');
                        actionStatus.hidden = true;
                        actionStatus.__materialUseKey = useKey(use);
                        row.appendChild(actionStatus);
                    } else {
                        row.classList.add('is-legacy-use');
                        row.appendChild(header);
                    }
                    useSection.appendChild(row);
                });
                syncUseActionControls();
            }
            syncShopNavigationControls();
            syncAnchorNav();
        }

        function select(name) {
            name = String(name || '');
            if (!name || shopNavigationPending()) return false;
            var changed = state.selectedName !== name;
            var previousSelection = state.selectedName;
            state.selectedName = name;
            if (changed) {
                clearUseAction();
                if (typeof options.onSelectionChange === 'function') {
                    options.onSelectionChange(name, previousSelection);
                }
            }
            state.detailError = '';
            state.shopNavigation = null;
            state.detailRetryAvailable = false;
            state.detailRetryFocusName = '';
            state.detailLoading = true;
            if (changed) state.detail = null;
            renderCatalog({preserveScroll:true});
            renderDetail();
            if (typeof options.onSelect === 'function') options.onSelect(name);
            return true;
        }

        function sameStringArray(left, right) {
            return Array.isArray(left) && Array.isArray(right)
                && left.length === right.length && left.every(function(value, index) {
                    return value === right[index];
                });
        }

        function selectedCatalogItem() {
            for (var index = 0; index < state.items.length; index++) {
                if (state.items[index].name === state.selectedName) return state.items[index];
            }
            return null;
        }

        function validInfrastructureUses(response, hasInfrastructurePurpose) {
            var ownsUses = Object.prototype.hasOwnProperty.call(response, 'infrastructureUses');
            return hasInfrastructurePurpose
                ? ownsUses && Array.isArray(response.infrastructureUses)
                : !ownsUses;
        }

        function detailMatchesCatalog(response) {
            if (state.protocolVersion !== 2) return true;
            var item = selectedCatalogItem();
            if (!item || response.snapshotId !== state.snapshotId
                    || response.material.displayName !== item.displayName
                    || response.material.icon !== item.icon
                    || response.material.owned !== item.owned
                    || response.sourceCount !== item.sourceCount
                    || response.dropVariantCount !== item.dropVariantCount
                    || response.useCount !== item.useCount
                    || response.structuredPurposeCount !== item.structuredPurposeCount
                    || item.hasSourceSummary !== (response.material.sourceSummary.length > 0)) return false;
            var recipeRegistry = entryMap(state.taxonomy.recipePurposes);
            var recipeIds = [];
            (response.uses || []).forEach(function(use) {
                var id = 'recipe:' + use.category;
                if (recipeIds.indexOf(id) < 0) recipeIds.push(id);
            });
            if (recipeIds.some(function(id) { return !recipeRegistry[id]; })) return false;
            recipeIds.sort(function(left, right) {
                return recipeRegistry[left].order - recipeRegistry[right].order;
            });
            var directRegistry = entryMap(state.taxonomy.directPurposes);
            var directIds = (response.directPurposes || []).map(function(purpose) {
                var canonical = directRegistry[purpose.id];
                if (!canonical || canonical.label !== purpose.label
                        || canonical.order !== purpose.order) return '';
                return purpose.id;
            });
            return directIds.indexOf('') < 0
                && validInfrastructureUses(response,
                    directIds.indexOf('system:infrastructure_upgrade') >= 0)
                && sameStringArray(recipeIds, item.recipePurposeIds)
                && sameStringArray(directIds, item.directPurposeIds);
        }

        function setSnapshot(response, preferredName) {
            var firstSnapshot = state.protocolVersion === 0;
            var previousSelection = String(state.selectedName || '');
            state.protocolVersion = response && response.v === 2 ? 2 : 1;
            state.snapshotId = state.protocolVersion === 2 ? String(response.snapshotId || '') : '';
            state.taxonomy = state.protocolVersion === 2 ? response.taxonomy : null;
            state.navigationAccess = state.protocolVersion === 2
                ? {shop:response.navigationAccess.shop === true,
                    crafting:response.navigationAccess.crafting === true}
                : {shop:false, crafting:false};
            state.items = response && Array.isArray(response.materials) ? response.materials.slice() : [];
            if (state.protocolVersion === 2) {
                state.items.sort(function(left, right) { return left.archiveOrder - right.archiveOrder; });
                typeLabels = entryMap(state.taxonomy.types);
                var tree = ItemFilter.buildMany(state.items, taxonomyPaths, function(item) {
                    return item.name;
                });
                filterNavigator.setModel(tree, state.filterPath);
                state.filterPath = filterNavigator.path.slice();
                navigatorHost.hidden = false;
                filterNavigator.root.hidden = false;
                sortDropdown.root.hidden = false;
                sortDropdown.update({disabled:false, value:state.sort});
                legacyWarning.hidden = true;
                catalogRoot.setAttribute('data-material-session', 'v2');
            } else {
                state.filterPath = [];
                typeLabels = null;
                filterNavigator.setModel(ItemFilter.buildMany([]), []);
                filterNavigator.root.hidden = true;
                navigatorHost.hidden = true;
                sortDropdown.update({disabled:true, value:'archive'});
                sortDropdown.root.hidden = true;
                state.sort = 'archive';
                if (catalogChrome.breadcrumbHost) catalogChrome.breadcrumbHost.hidden = true;
                legacyWarning.hidden = false;
                catalogRoot.setAttribute('data-material-session', 'legacy_limited');
            }
            state.loading = false;
            state.catalogError = '';
            state.detailError = '';
            state.useAction = null;
            state.shopNavigation = null;
            var preferred = String(preferredName || previousSelection || '');
            var visible = visibleItems();
            var found = visible.some(function(item) { return item.name === preferred; });
            var next = found ? preferred
                : (firstSnapshot && visible[0] ? String(visible[0].name) : '');
            state.selectedName = '';
            if (!next) {
                state.detail = null;
                state.detailLoading = false;
            }
            renderFilters();
            renderCatalog({preserveScroll:false});
            scheduleResultAnnouncement();
            if (next) select(next);
            else renderDetail();
            var active = catalogRoot.ownerDocument && catalogRoot.ownerDocument.activeElement;
            if (firstSnapshot && state.protocolVersion === 2 && visible.length
                    && (!active || active === catalogRoot.ownerDocument.body
                        || active === catalogRoot.ownerDocument.documentElement)) {
                filterNavigator.focusPath([]);
            }
        }

        function setDetail(response) {
            if (!response || !response.material
                    || response.v !== state.protocolVersion
                    || String(response.material.name) !== state.selectedName
                    || !detailMatchesCatalog(response)) return false;
            state.detail = response;
            state.detailLoading = false;
            state.detailError = '';
            state.detailRetryAvailable = false;
            state.detailRetryFocusName = '';
            state.shopNavigation = null;
            renderDetail();
            return true;
        }

        function setCatalogLoading() {
            state.loading = true;
            state.catalogError = '';
            state.detailError = '';
            state.items = [];
            state.detail = null;
            state.detailLoading = false;
            state.detailRetryAvailable = false;
            state.detailRetryFocusName = '';
            state.useAction = null;
            state.shopNavigation = null;
            state.focusedName = '';
            typeLabels = null;
            navigatorHost.hidden = true;
            filterNavigator.root.hidden = true;
            if (catalogChrome.breadcrumbHost) catalogChrome.breadcrumbHost.hidden = true;
            legacyWarning.hidden = true;
            sortDropdown.update({disabled:true});
            sortDropdown.root.hidden = true;
            renderFilters();
            renderCatalog({preserveScroll:false});
            renderDetail();
            if (resultAnnouncementTimer !== null) clearTimeout(resultAnnouncementTimer);
            resultAnnouncementTimer = null;
            resultStatus.textContent = '';
        }

        function setCatalogError(message) {
            state.loading = false;
            state.detailLoading = false;
            state.catalogError = String(message || '材料目录读取失败。');
            state.detailError = '';
            state.items = [];
            typeLabels = null;
            state.detail = null;
            state.detailRetryAvailable = false;
            state.detailRetryFocusName = '';
            state.useAction = null;
            state.shopNavigation = null;
            navigatorHost.hidden = true;
            filterNavigator.root.hidden = true;
            if (catalogChrome.breadcrumbHost) catalogChrome.breadcrumbHost.hidden = true;
            legacyWarning.hidden = true;
            sortDropdown.update({disabled:true});
            sortDropdown.root.hidden = true;
            renderFilters();
            renderCatalog({preserveScroll:false});
            renderDetail();
            resultStatus.textContent = '';
        }

        function setDetailError(message, retryable) {
            state.detailLoading = false;
            state.detail = null;
            state.detailError = String(message || '材料详情读取失败。');
            state.detailRetryAvailable = retryable !== false && !!state.selectedName;
            if (!state.detailRetryAvailable) state.detailRetryFocusName = '';
            renderDetail();
            if (state.detailRetryAvailable
                    && state.detailRetryFocusName === state.selectedName) {
                var retry = detailBody.querySelector('.crafting-material-detail-retry');
                state.detailRetryFocusName = '';
                if (retry && typeof retry.focus === 'function') retry.focus();
            }
        }

        renderFilters();
        renderCatalog();
        renderDetail();

        return {
            catalogView:catalogView,
            detailView:detailView,
            setSnapshot:setSnapshot,
            setDetail:setDetail,
            setCatalogLoading:setCatalogLoading,
            setCatalogError:setCatalogError,
            setDetailError:setDetailError,
            setError:setCatalogError,
            select:select,
            consumeEscape:consumeEscape,
            getSelectedName:function() { return state.selectedName; },
            isCurrentUse:isCurrentUse,
            isCurrentRecipeTarget:isCurrentRecipeTarget,
            canOpenCrafting:craftingNavigationAllowed,
            canOpenShop:shopNavigationAllowed,
            setUseActionPending:setUseActionPending,
            setUseActionError:setUseActionError,
            completeUseAction:completeUseAction,
            clearUseAction:clearUseAction,
            isUseActionTrigger:isUseActionTrigger,
            setShopNavigationPending:setShopNavigationPending,
            setShopNavigationError:setShopNavigationError,
            clearShopNavigation:clearShopNavigation,
            isShopNavigationTrigger:isShopNavigationTrigger,
            isShopNavigationPending:shopNavigationPending,
            debugState:function() {
                return {
                    count:state.items.length,
                    selectedName:state.selectedName,
                    focusedName:state.focusedName,
                    detailLoading:state.detailLoading,
                    query:state.query,
                    filter:state.filter,
                    filterPath:state.filterPath.slice(),
                    sort:state.sort,
                    visibleCount:visibleItems().length,
                    catalogError:state.catalogError,
                    detailError:state.detailError,
                    useAction:state.useAction ? {
                        key:state.useAction.key, kind:state.useAction.kind,
                        status:state.useAction.status, message:state.useAction.message
                    } : null,
                    shopNavigation:state.shopNavigation ? {
                        sourceKey:state.shopNavigation.sourceKey,
                        status:state.shopNavigation.status,
                        message:state.shopNavigation.message
                    } : null,
                    navigationAccess:{shop:state.navigationAccess.shop,
                        crafting:state.navigationAccess.crafting},
                    protocolVersion:state.protocolVersion,
                    snapshotId:state.snapshotId,
                    legacyLimited:state.protocolVersion === 1,
                    layoutMode:state.layoutMode
                };
            },
            destroy:function() {
                detailRenderEpoch++;
                invalidateSourcePortraits(detailBody);
                densityUnsubscribe();
                if (options.densityController) options.densityController.unregister(renderer);
                catalogRoot.removeEventListener('keydown', onCatalogKeyDown);
                if (resultAnnouncementTimer !== null) clearTimeout(resultAnnouncementTimer);
                resultAnnouncementTimer = null;
                sortDropdown.destroy();
                filterNavigator.destroy();
                state.items = [];
                state.detail = null;
                state.useAction = null;
                state.shopNavigation = null;
                Workbench.clearElement(catalogRoot);
                Workbench.clearElement(detailRoot);
            }
        };
    }

    return {create:create};
})();
