/** Skill panel — manage loadout/passives/order and trainer preview/commit flows. */
var SkillsPanel = (function() {
    'use strict';

    var _scaleEl = null, _scaleHandle = null, _shell = null;
    var _leftRoot = null, _rightRoot = null, _list = null, _search = null;
    var _searchToggle = null, _searchControls = null, _searchClose = null, _searchExpanded = false;
    var _filterNavigators = {}, _filterBoard = null, _filterResetButton = null;
    var _filterPaths = {manage:emptyFilterPaths(), trainer:emptyFilterPaths()};
    var _refreshButton = null, _diagnosticButton = null, _switchButton = null, _helpButton = null, _closeButton = null, _returnFocus = null;
    var _snapshot = null, _view = 'manage', _initData = null, _selectedKey = '';
    var _desiredLevel = 1, _preview = null, _schemaError = '', _lastDiagnostic = null;
    var _previewTimer = null, _previewIntent = 0, _previewLoading = false, _previewError = '', _previewReceivedAt = 0;
    var _trainerExpired = false;
    var _pendingFocusKey = '';
    var _density = null, _densityToggle = null, _confirmationToggle = null;
    var _drag = null, _dragBroker = null, _dragSourceView = null, _dragSlotSourceView = null;
    var _dragTargetView = null, _dragSlotTargetView = null, _dragOrderTargetView = null;
    var _switchWaitTimer = null, _switchPending = false;
    var _config = (typeof window !== 'undefined' && window.__SKILLS_CONFIG__) || {};
    var LOADOUT_CONFIRMATION_KEY = 'cf7.skills.loadoutConfirmationMode';
    var _loadoutConfirmationMode = readLoadoutConfirmationMode();

    var _coordinator = new SkillRuntime.SkillCoordinator({
        send: function(message) { return Bridge.send(message); },
        timeoutMs: _config.requestTimeoutMs,
        sessionNonce: _config.sessionNonce,
        onState: onCoordinatorState,
        onSnapshot: onAuthoritativeSnapshot,
        onError: onCoordinatorError,
        validateSnapshot: function(snapshot) { return validateSnapshot(snapshot, _view); }
    });

    Panels.register('skills', {
        create: createDOM,
        onOpen: onOpen,
        onRebind: onRebind,
        onClose: cleanup,
        onRequestClose: requestClose,
        onForceClose: function() { cleanup(); toast('连接已断开，技能面板已关闭。'); }
    });

    function createDOM() {
        _scaleEl = document.createElement('div');
        _scaleEl.className = 'panel-scale-shell skills-scale-shell';
        _scaleEl.addEventListener('keydown', onPanelKeyDown);
        return _scaleEl;
    }

    function onOpen(el, initData) {
        _returnFocus = document.activeElement && !el.contains(document.activeElement) ? document.activeElement : null;
        beginOpen(initData || {});
    }

    function onRebind(el, initData) {
        var result = _coordinator.queueRebind(initData || {}, beginOpen);
        if (result === 'queued') {
            toast('上一个操作仍在确认，页面会稍后自动切换。');
            refreshStateControls();
        }
    }

    function beginOpen(initData) {
        cleanupView(false);
        _initData = initData || {};
        _view = _initData.view === 'trainer' ? 'trainer' : 'manage';
        _snapshot = null;
        _selectedKey = typeof _initData.focusSkillKey === 'string' ? _initData.focusSkillKey : '';
        _desiredLevel = 1; _preview = null; _schemaError = ''; _lastDiagnostic = null; _searchExpanded = false;
        _previewLoading = false; _previewError = ''; _previewReceivedAt = 0; _trainerExpired = false; _pendingFocusKey = '';
        var opened = _coordinator.open(_initData);
        buildDOM();
        if (!opened) {
            _schemaError = '面板实例无效，无法建立技能会话。';
            renderAll();
            return;
        }
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_scaleEl, 1024, 576) : null;
        if (_coordinator.getState() === 'needs_reconcile') _coordinator.retryReconcile();
        else if (_coordinator.getState() === 'idle') requestSnapshot();
        refreshStateControls();
    }

    function buildDOM() {
        while (_scaleEl.firstChild) _scaleEl.removeChild(_scaleEl.firstChild);
        if (_shell) _shell.destroy();
        _shell = new Workbench.DualPaneShell({
            title: _view === 'trainer' ? '技能研习' : '我的技能',
            subtitle: _view === 'trainer' ? '选择技能，查看说明后研习' : '技能库与快捷技能带',
            status: '读取中',
            leftLabel: _view === 'trainer' ? '教师目录' : '技能库',
            rightLabel: _view === 'trainer' ? '研习操作' : '快捷技能带',
            flowLabel: _view === 'trainer' ? '研习' : ''
        });
        var root = _shell.getRoot();
        root.classList.add('skills-panel');
        root.setAttribute('data-skill-view', _view);
        root.setAttribute('data-workbench-skin', 'skills');
        _scaleEl.appendChild(root);

        _density = new Workbench.GridDensityController({panelId:'skills', compactClass:'skills-density-compact'});
        _density.register(root);
        _densityToggle = _density.createToggle();
        _densityToggle.classList.add('skills-density-toggle');
        _densityToggle.setAttribute('aria-label', '技能库布局');
        _densityToggle.setAttribute('aria-label', '只切换技能库的完整卡片或紧凑瓦片；快捷技能带保持固定');
        var densityLabel = _densityToggle.querySelector('.item-grid-mode-label');
        if (densityLabel) densityLabel.textContent = '技能库';
        var fullDensity = _densityToggle.querySelector('[data-layout-mode="full"]');
        var compactDensity = _densityToggle.querySelector('[data-layout-mode="compact"]');
        if (fullDensity) fullDensity.setAttribute('aria-label', '技能库显示名称、等级与状态');
        if (compactDensity) compactDensity.setAttribute('aria-label', '技能库使用方块图标瓦片，一屏查看更多技能');
        _shell.addHeaderAction(_densityToggle);
        if (_view === 'manage') {
            _confirmationToggle = createLoadoutConfirmationToggle();
            _shell.addHeaderAction(_confirmationToggle);
        }
        if (_view === 'trainer') {
            _switchButton = button('管理技能', 'workbench-mode-btn skills-switch-manage-btn', requestManageView);
            _switchButton.setAttribute('aria-label', '保留当前选择并打开技能管理');
            _shell.addHeaderAction(_switchButton);
        } else if (_initData && _initData.canReturnTrainer === true) {
            _switchButton = button('返回研习', 'workbench-mode-btn skills-switch-trainer-btn', requestTrainerView);
            _switchButton.setAttribute('aria-label', '仅本次教师入口有效；返回后需要重新取得学习预览');
            _shell.addHeaderAction(_switchButton);
        }
        _helpButton = button('?', 'workbench-mode-btn skills-help-btn', openHelp);
        _helpButton.setAttribute('aria-label', '查看技能操作帮助');
        _helpButton.setAttribute('aria-label', '查看操作帮助');
        _shell.addHeaderAction(_helpButton);
        _refreshButton = button('刷新', 'workbench-mode-btn skills-refresh-btn', function() {
            if (_coordinator.getState() === 'needs_reconcile') _coordinator.retryReconcile();
            else requestSnapshot();
        });
        _refreshButton.hidden = true;
        _shell.addHeaderAction(_refreshButton);
        _diagnosticButton = button('复制诊断信息', 'workbench-mode-btn skills-diagnostic-btn skills-header-diagnostic', function() {
            copyDiagnostic(_schemaError ? 'skill_data_error' : _coordinator.getState());
        });
        _diagnosticButton.hidden = true;
        _shell.addHeaderAction(_diagnosticButton);
        _closeButton = button('×', 'workbench-close-btn', requestClose);
        _closeButton.setAttribute('aria-label', '关闭技能面板');
        _shell.addHeaderAction(_closeButton);

        var leftView = createLeftView();
        var rightView = createRightView();
        _shell.setDefault('L', leftView); _shell.setDefault('R', rightView);
        _shell.mountInitial(leftView, rightView);
        renderAll();
    }

    function createLeftView() {
        _leftRoot = document.createElement('div');
        _leftRoot.className = 'workbench-view skills-library-view';
        var header = document.createElement('div'); header.className = 'skills-library-header';
        var titleRow = document.createElement('div'); titleRow.className = 'skills-library-title-row';
        var title = document.createElement('div'); title.className = 'skills-section-title';
        title.textContent = _view === 'trainer' ? '当前教师可研习技能' : '已学技能库';
        titleRow.appendChild(title);
        _filterResetButton = button('清除筛选', 'skills-filter-reset', clearSkillFilters);
        _filterResetButton.hidden = true;
        titleRow.appendChild(_filterResetButton);
        _searchToggle = button('搜索', 'skills-search-toggle', function() { setSearchExpanded(!_searchExpanded); });
        _searchToggle.setAttribute('aria-expanded', 'false');
        _searchToggle.setAttribute('aria-controls', 'skills-search-controls');
        _searchToggle.setAttribute('aria-label', '展开技能名称搜索（快捷键 /）');
        titleRow.appendChild(_searchToggle); header.appendChild(titleRow);
        var controls = document.createElement('div'); controls.className = 'skills-library-controls'; controls.id = 'skills-search-controls';
        controls.hidden = true; _searchControls = controls;
        _search = document.createElement('input'); _search.type = 'search';
        _search.placeholder = '搜索技能'; _search.setAttribute('aria-label', '搜索技能');
        _search.setAttribute('data-browser-native', '1');
        _search.addEventListener('input', renderList);
        _search.addEventListener('keydown', function(event) {
            if (event.key !== 'Escape') return;
            event.preventDefault(); event.stopPropagation(); setSearchExpanded(false);
            if (_searchToggle) _searchToggle.focus();
        });
        _searchClose = button('收起', 'skills-search-close', function() { setSearchExpanded(false); });
        controls.appendChild(_search); controls.appendChild(_searchClose); header.appendChild(controls);
        _filterBoard = document.createElement('div');
        _filterBoard.className = 'skills-filter-board';
        skillFilterDefinitions().forEach(function(definition) {
            var group = document.createElement('div');
            group.className = 'skills-filter-group';
            if (definition.collapsed) group.classList.add('collapsible', 'collapsed');
            group.setAttribute('data-skill-filter', definition.id);
            group.setAttribute('role', 'group');
            group.setAttribute('aria-label', definition.label + '筛选');
            var label = document.createElement('span');
            label.className = 'skills-filter-label';
            label.textContent = definition.label;
            if (definition.collapsed) {
                label.setAttribute('tabindex', '0');
                label.setAttribute('role', 'button');
                label.setAttribute('aria-expanded', 'false');
                label.setAttribute('aria-label', '点击展开“' + definition.label + '”筛选');
            }
            group.appendChild(label);
            var value = document.createElement('span');
            value.className = 'skills-filter-value';
            value.setAttribute('aria-hidden', 'true');
            group.appendChild(value);
            var navigator = new ItemFilter.FilterNavigator({
                tree:ItemFilter.build([], definition.classifier), path:filterPathsForView()[definition.id],
                presentation:'drilldown', allLabel:'不限', ariaLabel:definition.label + '筛选',
                visualStyle:'catalog', autoDescendSingle:false,
                onChange:function(path) {
                    filterPathsForView()[definition.id] = path.slice();
                    refreshFilterReset(); refreshFilterValue(definition.id); renderList();
                }
            });
            navigator.root.classList.add('skills-filter-navigator');
            _filterNavigators[definition.id] = navigator;
            group.appendChild(navigator.root);
            if (definition.collapsed) {
                label.addEventListener('click', function() { toggleSkillFilterCollapsed(definition.id); });
                label.addEventListener('keydown', function(event) {
                    if (event.key === 'Enter' || event.key === ' ') {
                        event.preventDefault();
                        toggleSkillFilterCollapsed(definition.id);
                    }
                });
            }
            _filterBoard.appendChild(group);
        });
        header.appendChild(_filterBoard);
        _list = document.createElement('div'); _list.className = 'skills-library-list';
        _list.setAttribute('role', 'listbox');
        _leftRoot.appendChild(header); _leftRoot.appendChild(_list);
        installPointerDrag();
        return simpleView('skills:library', 'catalog', ['L'], _leftRoot, renderList);
    }

    function createRightView() {
        _rightRoot = document.createElement('div');
        _rightRoot.className = 'workbench-view skills-action-view';
        if (_view === 'trainer') _rightRoot.classList.add('skills-trainer-view');
        return simpleView('skills:actions', 'detail', ['R'], _rightRoot, renderDetail);
    }

    function simpleView(key, kind, slots, root, renderer) {
        return {
            instanceKey: key, instancePolicy: 'singletonByBinding', viewKind: kind, allowedSlots: slots,
            mount: function(container) { container.appendChild(root); },
            unmount: function() { if (root.parentNode) root.parentNode.removeChild(root); },
            render: renderer
        };
    }

    function renderAll() {
        renderMetrics(); refreshFilterModel(); renderList(); renderDetail(); refreshStateControls();
    }

    function renderMetrics() {
        var player = _snapshot && _snapshot.player || {};
        if (!_shell) return;
        if (_view !== 'trainer') return;
        _shell.setMetric('level', '等级', safeNumber(player.level));
        _shell.setMetric('sp', '技能点', safeNumber(player.skillPoints));
    }

    function renderList() {
        if (!_list) return;
        var focusKey = focusKeyOf(document.activeElement);
        while (_list.firstChild) _list.removeChild(_list.firstChild);
        if (_schemaError) { _list.appendChild(empty('技能数据暂时无法读取，请重试。', 'error')); return; }
        var entries = visibleEntries();
        if (!entries.length) {
            _list.appendChild(empty(_snapshot ? '没有符合条件的技能' : '正在读取技能状态…'));
            return;
        }
        entries.forEach(function(entry) {
            var row = document.createElement('div'); row.className = 'skills-library-row'; row.tabIndex = 0;
            row.setAttribute('role', 'option'); row.setAttribute('data-skill-key', entry.skillKey);
            row.setAttribute('data-focus-key', 'skill:' + entry.skillKey);
            row.setAttribute('aria-selected', entry.skillKey === _selectedKey ? 'true' : 'false');
            if (entry.skillKey === _selectedKey) row.classList.add('selected');
            if (entry.writeBlocked || entry.stateHealth !== 'ok') row.classList.add('corrupt');
            var icon = iconNode(entry.iconKey, 'skills-row-icon');
            var copy = document.createElement('span'); copy.className = 'skills-row-copy';
            var name = document.createElement('b'); name.textContent = entry.skillKey;
            var meta = document.createElement('span');
            meta.textContent = entry.currentLevel != null
                ? '当前 Lv.' + safeNumber(entry.currentLevel) + ' / ' + safeNumber(entry.maxLevel)
                : 'Lv.' + safeNumber(entry.level) + ' / ' + safeNumber(entry.maxLevel);
            var type = document.createElement('small'); type.textContent = entry.type || '未知类型';
            copy.appendChild(name); copy.appendChild(meta); copy.appendChild(type);
            var badge = document.createElement('span'); badge.className = 'skills-row-badge';
            badge.textContent = healthLabel(entry);
            var tileLevel = document.createElement('span'); tileLevel.className = 'skills-tile-level';
            tileLevel.textContent = 'Lv.' + safeNumber(entry.currentLevel != null ? entry.currentLevel : entry.level);
            var tileState = document.createElement('span'); tileState.className = 'skills-tile-state';
            tileState.textContent = compactStateLabel(entry);
            row.appendChild(icon); row.appendChild(copy); row.appendChild(badge); row.appendChild(tileLevel); row.appendChild(tileState);
            row.setAttribute('aria-label', skillAriaLabel(entry));
            bindSkillTooltip(row, entry);
            row.addEventListener('click', function() {
                if (_drag && _drag.consumeClick()) return;
                selectSkill(entry.skillKey);
            });
            row.addEventListener('keydown', function(event) {
                if (_view === 'manage' && event.altKey && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
                    event.preventDefault();
                    reorderTo(entry, adjacentVisibleEntry(entry, event.key === 'ArrowDown' ? 1 : -1));
                } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
                    event.preventDefault(); focusSibling(row, event.key === 'ArrowDown' ? 1 : -1);
                } else if (event.key === 'Enter' || event.key === ' ') {
                    event.preventDefault(); selectSkill(entry.skillKey);
                }
            });
            _list.appendChild(row);
        });
        restoreFocusKey(focusKey);
    }

    function visibleEntries() {
        var entries = sourceEntries().slice();
        var query = _search ? String(_search.value || '').toLowerCase() : '';
        var filterPaths = filterPathsForView();
        return entries.filter(function(entry) {
            if (query && String(entry.skillKey || '').toLowerCase().indexOf(query) < 0
                    && String(entry.type || '').toLowerCase().indexOf(query) < 0) return false;
            return matchesSkillFilter(entry, filterPaths);
        }).sort(function(a, b) {
            var ai = a.orderIndex != null ? Number(a.orderIndex) : sourceEntries().indexOf(a);
            var bi = b.orderIndex != null ? Number(b.orderIndex) : sourceEntries().indexOf(b);
            return ai - bi;
        });
    }

    function setSearchExpanded(expanded) {
        _searchExpanded = !!expanded;
        if (_searchControls) _searchControls.hidden = !_searchExpanded;
        if (_searchToggle) {
            _searchToggle.setAttribute('aria-expanded', _searchExpanded ? 'true' : 'false');
            _searchToggle.textContent = _searchExpanded ? '收起搜索' : '搜索';
        }
        if (_searchExpanded) {
            if (_search) setTimeout(function() { if (_search) { _search.focus(); _search.select(); } }, 0);
            return;
        }
        if (_search && _search.value) {
            _search.value = '';
            renderList();
        }
    }

    function onPanelKeyDown(event) {
        if (!event || event.defaultPrevented || event.key !== '/' || event.ctrlKey || event.metaKey || event.altKey) return;
        var target = event.target;
        var tag = target && target.tagName ? String(target.tagName).toLowerCase() : '';
        if (tag === 'input' || tag === 'textarea' || tag === 'select' || (_shell && _shell.hasModal())) return;
        event.preventDefault();
        setSearchExpanded(true);
    }

    function sourceEntries() {
        if (!_snapshot) return [];
        if (_view === 'trainer') return _snapshot.trainer && Array.isArray(_snapshot.trainer.entries)
            ? _snapshot.trainer.entries : [];
        return Array.isArray(_snapshot.learned) ? _snapshot.learned : [];
    }

    function refreshFilterModel() {
        var entries = sourceEntries(), paths = filterPathsForView();
        skillFilterDefinitions().forEach(function(definition) {
            var navigator = _filterNavigators[definition.id];
            if (!navigator) return;
            navigator.setModel(ItemFilter.build(entries, definition.classifier), paths[definition.id]);
            paths[definition.id] = navigator.path.slice();
            refreshFilterValue(definition.id);
        });
        refreshFilterReset();
    }

    function emptyFilterPaths() { return {form:[], status:[], school:[]}; }
    function filterPathsForView() {
        var paths = _filterPaths[_view];
        if (!paths || Array.isArray(paths)) paths = _filterPaths[_view] = emptyFilterPaths();
        return paths;
    }
    function skillFilterDefinitions() {
        return [
            {id:'form', label:'形态', classifier:skillFormPath},
            {id:'status', label:_view === 'trainer' ? '学习' : '配置', classifier:skillStatusPath},
            {id:'school', label:'流派', classifier:skillSchoolPath, collapsed:true}
        ];
    }
    function clearSkillFilters() {
        var paths = filterPathsForView();
        skillFilterDefinitions().forEach(function(definition) {
            paths[definition.id] = [];
            if (_filterNavigators[definition.id]) _filterNavigators[definition.id].setPath([], true);
            refreshFilterValue(definition.id);
        });
        refreshFilterReset(); renderList();
    }
    function refreshFilterReset() {
        if (!_filterResetButton) return;
        var paths = filterPathsForView();
        _filterResetButton.hidden = !(paths.form.length || paths.status.length || paths.school.length);
    }
    function toggleSkillFilterCollapsed(id) {
        var group = _filterBoard && _filterBoard.querySelector('.skills-filter-group[data-skill-filter="' + id + '"]');
        if (!group || !group.classList.contains('collapsible')) return;
        var collapsed = group.classList.toggle('collapsed');
        var label = group.querySelector('.skills-filter-label');
        if (label) {
            label.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
            label.setAttribute('aria-label', (collapsed ? '点击展开' : '点击收起') + '“' + skillFilterLabel(id) + '”筛选');
        }
    }
    function refreshFilterValue(id) {
        var group = _filterBoard && _filterBoard.querySelector('.skills-filter-group[data-skill-filter="' + id + '"]');
        if (!group) return;
        var value = group.querySelector('.skills-filter-value');
        if (!value) return;
        var navigator = _filterNavigators[id];
        var label = '';
        if (navigator && navigator.path && navigator.path.length) {
            var node = ItemFilter.nodeAt(navigator.tree, navigator.path);
            label = node && node.label ? node.label : navigator.path[navigator.path.length - 1];
        }
        value.textContent = label;
        var labelEl = group.querySelector('.skills-filter-label');
        if (labelEl) {
            var base = skillFilterLabel(id) + '筛选';
            labelEl.setAttribute('aria-label', label ? base + '，当前：' + label : base);
        }
    }
    function skillFilterLabel(id) {
        var definitions = skillFilterDefinitions();
        for (var i = 0; i < definitions.length; i++) if (definitions[i].id === id) return definitions[i].label;
        return id;
    }

    function facet(id, label, order) { return [{id:id, label:label, order:order}]; }
    function skillFormPath(entry) {
        if (entry.passive && !entry.equippable) return facet('passive', '纯被动', 20);
        if (entry.passive && entry.equippable) return facet('hybrid', '主动 / 被动', 30);
        if (entry.equippable) return facet('equippable', '主动可装备', 10);
        return facet('unsupported', '不可配置', 90);
    }
    function skillStatusPath(entry) {
        if (entry.writeBlocked || entry.stateHealth !== 'ok') return facet('blocked', '异常', 90);
        if (_view === 'trainer') {
            var current = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 0);
            if (current <= 0) return facet('unlearned', '未学习', 10);
            if (max > 0 && current >= max) return facet('maxed', '已满级', 30);
            return facet('learned', '已学习', 20);
        }
        if (entry.passive && !entry.equippable)
            return facet(entry.enabled ? 'passive_on' : 'passive_off', entry.enabled ? '被动启用' : '被动停用', entry.enabled ? 30 : 40);
        return entry.equippedSlots && entry.equippedSlots.length
            ? facet('equipped', '已装备', 10) : facet('unequipped', '未装备', 20);
    }
    function skillSchoolPath(entry) {
        var type = String(entry.type || '');
        var schools = [
            ['武术','武术',10],['剑术','剑术',20],['枪术','枪术',30],['内功','内功',40],['神功','神功',50],
            ['科技','科技',60],['超能力','超能力',70],['投技','投技',80],['龙吼','龙吼',90]
        ];
        var selected = null, selectedIndex = 9999;
        for (var i = 0; i < schools.length; i++) {
            var index = type.indexOf(schools[i][0]);
            if (index >= 0 && index < selectedIndex) { selected = schools[i]; selectedIndex = index; }
        }
        return selected ? facet(selected[0], selected[1], selected[2]) : [];
    }
    function matchesSkillFilter(entry, paths) {
        paths = paths && !Array.isArray(paths) ? paths : emptyFilterPaths();
        return ItemFilter.matchesPath(entry, paths.form, skillFormPath)
            && ItemFilter.matchesPath(entry, paths.status, skillStatusPath)
            && ItemFilter.matchesPath(entry, paths.school, skillSchoolPath);
    }

    function selectSkill(skillKey) {
        _selectedKey = String(skillKey || ''); clearPreviewState();
        var entry = selectedEntry();
        if (_view === 'trainer' && entry) {
            var current = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 1);
            _desiredLevel = current <= 0 ? 1 : Math.min(max, current + 1);
        }
        renderList();
        if (_view === 'trainer' && entry) scheduleLearnPreview(entry, false);
        else renderDetail();
    }

    function selectedEntry() {
        var entries = sourceEntries();
        for (var i = 0; i < entries.length; i++) if (entries[i].skillKey === _selectedKey) return entries[i];
        return null;
    }

    function renderDetail() {
        if (!_rightRoot) return;
        var focusKey = _pendingFocusKey || focusKeyOf(document.activeElement);
        while (_rightRoot.firstChild) _rightRoot.removeChild(_rightRoot.firstChild);
        if (_trainerExpired) {
            _rightRoot.appendChild(renderTrainerExpired());
            restoreFocusKey(focusKey);
            return;
        }
        if (_schemaError) { _rightRoot.appendChild(empty('技能数据暂时无法读取，请重试。', 'error')); return; }
        var entry = selectedEntry();
        if (_view === 'trainer') {
            if (!entry) _rightRoot.appendChild(empty(_snapshot ? '从左侧选择研习目标' : '正在读取技能…'));
            else {
                _rightRoot.appendChild(renderTrainerSummary(entry));
                renderTrainerActions(entry);
            }
        } else {
            renderManageActions(entry);
            if (_snapshot) _rightRoot.appendChild(renderLoadout(false));
            else _rightRoot.appendChild(empty('正在读取技能…'));
        }
        restoreFocusKey(focusKey);
        if (_pendingFocusKey && _coordinator.getState() === 'idle') _pendingFocusKey = '';
    }

    function renderTrainerSummary(entry) {
        var summary = document.createElement('section'); summary.className = 'skills-trainer-summary';
        var icon = iconNode(entry.iconKey || entry.skillKey, 'skills-trainer-summary-icon');
        summary.appendChild(icon);
        var copy = document.createElement('div'); copy.className = 'skills-trainer-summary-copy';
        var kicker = document.createElement('span'); kicker.className = 'skills-trainer-kicker'; kicker.textContent = '研习目标';
        var title = document.createElement('h2'); title.textContent = entry.skillKey;
        var meta = document.createElement('div'); meta.className = 'skills-detail-meta';
        meta.textContent = (entry.type || '未知类型') + ' · 当前 Lv.' + safeNumber(entry.currentLevel) + '/' + safeNumber(entry.maxLevel)
            + ' · MP ' + safeNumber(entry.mp) + ' · CD ' + cooldownText(entry.cooldownMs);
        copy.appendChild(kicker); copy.appendChild(title); copy.appendChild(meta); summary.appendChild(copy);
        var description = document.createElement('div'); description.className = 'skills-trainer-description';
        var rawDescription = entry.description || '暂无技能说明。';
        if (typeof PanelTooltip !== 'undefined' && PanelTooltip && PanelTooltip.convertAS2Html)
            description.innerHTML = PanelTooltip.convertAS2Html(normalizeAS2Description(rawDescription));
        else description.textContent = rawDescription;
        summary.appendChild(description);
        if (entry.writeBlocked || entry.stateHealth !== 'ok') {
            var warning = document.createElement('div'); warning.className = 'skills-corrupt-warning';
            var warningText = document.createElement('span'); warningText.textContent = '技能数据异常，暂时无法研习。';
            var diagnostic = button('复制诊断信息', 'skills-inline-diagnostic skills-diagnostic-btn', function() {
                copyDiagnostic('skill_data_error', entry);
            });
            warning.appendChild(warningText); warning.appendChild(diagnostic); summary.appendChild(warning);
        }
        bindSkillTooltip(summary, entry);
        return summary;
    }

    function renderTrainerExpired() {
        var state = document.createElement('section'); state.className = 'skills-trainer-expired';
        var marker = document.createElement('div'); marker.className = 'skills-trainer-expired-mark'; marker.textContent = '!';
        var title = document.createElement('h2'); title.textContent = '教师连接已失效';
        var message = document.createElement('p');
        message.textContent = '本次研习权限已经结束。为避免误操作，页面已停止计算和研习；请返回游戏后重新与教师对话。';
        var hint = document.createElement('small'); hint.textContent = '已选择的技能和筛选仍保留在当前画面中，未扣除技能点。';
        var actions = document.createElement('div'); actions.className = 'skills-trainer-expired-actions';
        var diagnostic = button('复制诊断信息', 'skills-action-btn skills-close-allowed', function() {
            copyDiagnostic('trainer_session_expired', selectedEntry());
        });
        var close = button('返回游戏并重新对话', 'skills-action-btn primary skills-close-allowed', requestClose);
        close.setAttribute('data-focus-key', 'trainer:expired-close');
        actions.appendChild(diagnostic); actions.appendChild(close);
        state.appendChild(marker); state.appendChild(title); state.appendChild(message); state.appendChild(hint); state.appendChild(actions);
        return state;
    }

    function renderSelectionContext(entry, label) {
        var context = document.createElement('div'); context.className = 'skills-selection-context';
        var kicker = document.createElement('span'); kicker.textContent = label || '当前技能';
        var title = document.createElement('b'); title.textContent = entry.skillKey;
        var meta = document.createElement('small'); meta.className = 'skills-detail-meta';
        var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
        meta.textContent = (entry.type || '未知类型') + ' · Lv.' + safeNumber(level) + '/' + safeNumber(entry.maxLevel)
            + ' · MP ' + safeNumber(entry.mp) + ' · CD ' + cooldownText(entry.cooldownMs);
        context.appendChild(kicker); context.appendChild(title); context.appendChild(meta);
        if (entry.writeBlocked || entry.stateHealth !== 'ok') {
            var warning = document.createElement('div'); warning.className = 'skills-corrupt-warning';
            var warningText = document.createElement('span');
            warningText.textContent = '技能数据异常，暂时无法修改。';
            var diagnostic = button('复制诊断信息', 'skills-inline-diagnostic skills-diagnostic-btn', function(event) {
                event.stopPropagation(); copyDiagnostic('skill_data_error', entry);
            });
            warning.appendChild(warningText); warning.appendChild(diagnostic);
            context.appendChild(warning);
        }
        bindSkillTooltip(context, entry);
        return context;
    }

    function renderManageActions(entry) {
        var actions = document.createElement('section'); actions.className = 'skills-detail-actions';
        if (!entry) {
            var emptyContext = document.createElement('div'); emptyContext.className = 'skills-action-hint';
            emptyContext.textContent = '技能格可拖到快捷栏；快捷槽之间可直接拖动调整按键布局。';
            actions.appendChild(emptyContext); _rightRoot.appendChild(actions); return;
        }
        actions.appendChild(renderSelectionContext(entry, '已选择'));
        if (entry.passive && !entry.equippable) {
            var passive = button(entry.enabled ? '停用被动' : '启用被动', 'skills-action-btn primary', function() {
                writeCommand('setPassive', {skillKey:entry.skillKey, enabled:!entry.enabled,
                    expectedRevision:Number(_snapshot.revision)});
            });
            passive.disabled = writesDisabled(entry);
            passive.setAttribute('data-focus-key', 'action:passive'); actions.appendChild(passive);
        } else {
            var hint = document.createElement('div'); hint.className = 'skills-action-hint';
            hint.textContent = entry.equippable
                ? '拖到技能格可交换顺序；拖到快捷槽可装备，快捷槽之间可移动或交换。'
                : '可拖到其他技能格交换顺序；该技能不可装备到快捷栏。';
            actions.appendChild(hint);
        }
        _rightRoot.appendChild(actions);
    }

    function adjacentVisibleEntry(entry, delta) {
        var entries = visibleEntries();
        var index = entries.indexOf(entry), target = entries[index + delta];
        return target || null;
    }

    function reorderBlockReason(entry, role) {
        if (writesDisabled(entry)) return 'skill_locked';
        var easyMode = !!(_snapshot && _snapshot.player && _snapshot.player.easyMode);
        if (entry && entry.equippedSlots && entry.equippedSlots.length && (role === 'target' || !easyMode))
            return 'equipped_skill_locked';
        return '';
    }

    function reorderTo(entry, target) {
        if (!target) return;
        var reason = reorderBlockReason(entry, 'source') || reorderBlockReason(target, 'target');
        if (reason) { toast(dragRejectMessage(reason)); return; }
        writeCommand('reorder', {skillKey:entry.skillKey, targetIndex:Number(target.orderIndex),
            expectedRevision:Number(_snapshot.revision)});
    }

    function renderTrainerActions(entry) {
        var current = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 1);
        var section = document.createElement('section'); section.className = 'skills-trainer-actions';
        var matchingPreview = previewMatches(entry) ? _preview : null;
        var target = document.createElement('div'); target.className = 'skills-trainer-target';
        var targetHeading = document.createElement('div'); targetHeading.className = 'skills-trainer-section-heading';
        targetHeading.textContent = current >= max ? '技能等级' : '目标等级'; target.appendChild(targetHeading);
        var stepper = document.createElement('div'); stepper.className = 'skills-level-stepper';
        var rangeShell = null;
        var label = document.createElement('span');
        label.textContent = current >= max ? 'Lv.' + current + '（已满级）' : 'Lv.' + current + ' →'; stepper.appendChild(label);
        if (current >= max) {
            var full = document.createElement('output'); full.textContent = 'Lv.' + max; stepper.appendChild(full);
        } else if (current <= 0) {
            var fixed = document.createElement('output'); fixed.textContent = 'Lv.1（初学固定）'; stepper.appendChild(fixed);
            _desiredLevel = 1;
        } else {
            var minus = button('−', 'skills-level-btn', function() { setDesiredLevel(_desiredLevel - 1); });
            var value = document.createElement('input'); value.type = 'number'; value.className = 'skills-level-value';
            value.min = String(current + 1); value.max = String(max); value.step = '1'; value.value = String(_desiredLevel);
            value.inputMode = 'numeric'; value.setAttribute('aria-label', '目标等级');
            value.setAttribute('data-focus-key', 'trainer:level-value');
            value.disabled = writesDisabled(entry);
            var plus = button('+', 'skills-level-btn', function() { setDesiredLevel(_desiredLevel + 1); });
            minus.setAttribute('data-focus-key', 'trainer:level-minus');
            plus.setAttribute('data-focus-key', 'trainer:level-plus');
            minus.disabled = writesDisabled(entry) || _desiredLevel <= current + 1;
            plus.disabled = writesDisabled(entry) || _desiredLevel >= max;
            stepper.appendChild(minus); stepper.appendChild(value); stepper.appendChild(plus);
            rangeShell = document.createElement('div'); rangeShell.className = 'skills-level-range-shell';
            var range = document.createElement('input'); range.type = 'range'; range.className = 'skills-level-range';
            range.min = String(current + 1); range.max = String(max); range.step = '1'; range.value = String(_desiredLevel);
            range.setAttribute('aria-label', '选择目标等级'); range.setAttribute('aria-valuetext', '目标等级 ' + _desiredLevel);
            range.setAttribute('data-focus-key', 'trainer:level-range');
            range.disabled = writesDisabled(entry);
            range.addEventListener('input', function() { stageDesiredLevel(range.value, entry, target); });
            range.addEventListener('change', function() { setDesiredLevel(range.value, true); });
            value.addEventListener('input', function() {
                var typed = Number(value.value);
                if (isFinite(typed) && Math.floor(typed) === typed && typed >= current + 1 && typed <= max)
                    stageDesiredLevel(typed, entry, target);
            });
            value.addEventListener('change', function() { setDesiredLevel(value.value, true); });
            value.addEventListener('keydown', function(event) {
                if (event.key === 'Enter') { event.preventDefault(); setDesiredLevel(value.value, true); }
                else if (event.key === 'Escape') { event.preventDefault(); value.value = String(_desiredLevel); }
            });
            rangeShell.appendChild(range);
            var marks = document.createElement('div'); marks.className = 'skills-level-marks';
            targetMarkLevels(current + 1, max).forEach(function(level) {
                var mark = button(String(level), 'skills-level-mark', function() { setDesiredLevel(level, true); });
                var position = max === current + 1 ? 100 : (level - current - 1) * 100 / (max - current - 1);
                mark.style.setProperty('--skills-level-mark-position', position + '%');
                mark.setAttribute('data-level', String(level)); mark.setAttribute('tabindex', '-1');
                mark.setAttribute('aria-label', '目标等级 ' + level);
                mark.disabled = writesDisabled(entry);
                marks.appendChild(mark);
            });
            rangeShell.appendChild(marks);
        }
        target.appendChild(stepper);
        if (rangeShell) { target.appendChild(rangeShell); syncTargetSelector(target, entry); }
        if (current > 0 && current < max) {
            var presets = document.createElement('div'); presets.className = 'skills-target-presets';
            var toMax = button('升至满级', 'skills-target-preset', function() { setDesiredLevel(max, true); });
            toMax.setAttribute('data-focus-key', 'trainer:level-max');
            toMax.disabled = writesDisabled(entry) || _desiredLevel === max;
            presets.appendChild(toMax); target.appendChild(presets);
        }
        section.appendChild(target);

        var gate = document.createElement('div'); gate.className = 'skills-trainer-gate';
        if (matchingPreview && !matchingPreview.canCommit && matchingPreview.blockingError) gate.classList.add('blocked');
        gate.textContent = '解锁 Lv.' + safeNumber(entry.unlockLevel) + ' · 初学 ' + safeNumber(entry.unlockSP)
            + ' 点 · 升级 ' + safeNumber(entry.upgradeSP) + ' 点/级'; section.appendChild(gate);

        var result = document.createElement('div'); result.className = 'skills-preview-result skills-cost-card';
        var previousPreview = _preview && _preview.skillKey === entry.skillKey ? _preview : null;
        if (current >= max) {
            result.classList.add('ok');
            appendCostRow(result, '研习状态', '技能已达到最高等级');
        } else if (matchingPreview) {
            appendPreviewSummary(result, matchingPreview, entry, false);
            if (_previewLoading) {
                result.classList.add('updating');
                appendPreviewUpdateStatus(result, '正在刷新 Lv.' + _desiredLevel + ' 的权威消耗…', false);
            } else if (_previewError) {
                appendPreviewUpdateStatus(result, '消耗刷新失败：' + errorMessage(_previewError), true);
                appendPreviewRetry(result, entry);
            }
        } else if (previousPreview) {
            result.classList.add('stale'); appendPreviewSummary(result, previousPreview, entry, true);
            if (_previewLoading) appendPreviewUpdateStatus(result, '正在更新目标 Lv.' + _desiredLevel + ' 的消耗…', false);
            else if (_previewError) {
                appendPreviewUpdateStatus(result, 'Lv.' + _desiredLevel + ' 更新失败：' + errorMessage(_previewError), true);
                appendPreviewRetry(result, entry);
            }
        } else if (_previewLoading) {
            result.classList.add('loading');
            appendCostRow(result, '本次消耗', '正在计算 Lv.' + _desiredLevel + '…');
        } else if (_previewError) {
            result.classList.add('blocked');
            var error = document.createElement('div'); error.className = 'skills-preview-message';
            error.textContent = '暂时无法计算研习消耗：' + errorMessage(_previewError); result.appendChild(error);
            appendPreviewRetry(result, entry);
        } else {
            appendCostRow(result, '本次消耗', '准备计算…');
        }
        section.appendChild(result);

        var footer = document.createElement('div'); footer.className = 'skills-trainer-footer';
        var commitText = '正在准备研习…', commitEnabled = false;
        if (current >= max) commitText = '该技能已满级';
        else if (_previewLoading) commitText = '正在更新 Lv.' + safeNumber(_desiredLevel) + ' 的消耗…';
        else if (_previewError) commitText = '暂时无法研习';
        else if (matchingPreview && matchingPreview.canCommit && matchingPreview.learnToken) {
            commitText = '研习至 Lv.' + safeNumber(_desiredLevel) + ' · ' + safeNumber(matchingPreview.cost) + ' 点';
            commitEnabled = !writesDisabled(entry);
        } else if (matchingPreview) commitText = errorMessage(matchingPreview.blockingError);
        var commit = button(commitText, 'skills-action-btn primary skills-trainer-commit', function() { prepareLearnConfirmation(entry); });
        commit.disabled = !commitEnabled; commit.setAttribute('data-focus-key', 'trainer:commit'); footer.appendChild(commit);
        section.appendChild(footer); _rightRoot.appendChild(section);
    }

    function targetMarkLevels(min, max) {
        var levels = [], count = max - min + 1, level;
        if (count <= 12) {
            for (level = min; level <= max; level++) levels.push(level);
            return levels;
        }
        levels.push(min);
        for (level = Math.ceil(min / 5) * 5; level < max; level += 5) if (level !== min) levels.push(level);
        if (max !== min) levels.push(max);
        return levels;
    }

    function normalizedDesiredLevel(entry, level) {
        var current = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 1), numeric = Number(level);
        if (!isFinite(numeric)) numeric = current + 1;
        numeric = Math.round(numeric);
        return current <= 0 ? 1 : Math.max(current + 1, Math.min(max, numeric));
    }

    function syncTargetSelector(target, entry) {
        if (!target || !entry) return;
        var current = Number(entry.currentLevel || 0), max = Number(entry.maxLevel || 1), min = current + 1;
        var range = target.querySelector('.skills-level-range'), value = target.querySelector('.skills-level-value');
        if (value && document.activeElement !== value) value.value = String(_desiredLevel);
        if (range) {
            range.value = String(_desiredLevel);
            var progress = max <= min ? 100 : (_desiredLevel - min) * 100 / (max - min);
            range.style.setProperty('--skills-level-progress', progress + '%');
            range.setAttribute('aria-valuenow', String(_desiredLevel));
            range.setAttribute('aria-valuetext', '目标等级 ' + _desiredLevel);
        }
        var marks = target.querySelectorAll('.skills-level-mark');
        for (var i = 0; i < marks.length; i++) marks[i].classList.toggle('selected', Number(marks[i].getAttribute('data-level')) === _desiredLevel);
    }

    function stageDesiredLevel(level, entry, target) {
        if (!entry || writesDisabled(entry)) return;
        var normalized = normalizedDesiredLevel(entry, level);
        if (_previewTimer !== null) { clearTimeout(_previewTimer); _previewTimer = null; }
        _previewIntent++; _desiredLevel = normalized; _previewLoading = true; _previewError = '';
        syncTargetSelector(target, entry);
        var result = _rightRoot && _rightRoot.querySelector('.skills-cost-card');
        if (result) {
            result.classList.add('updating');
            if (_preview && _preview.skillKey === entry.skillKey) result.classList.add('stale');
            var status = result.querySelector('.skills-preview-update-status');
            if (!status) { status = document.createElement('div'); status.className = 'skills-preview-update-status'; result.appendChild(status); }
            status.textContent = '目标已选 Lv.' + normalized + '，松开或确认后更新消耗。';
        }
        var commit = _rightRoot && _rightRoot.querySelector('.skills-trainer-commit');
        if (commit) { commit.disabled = true; commit.textContent = '确认目标后计算 Lv.' + normalized; }
    }

    function setDesiredLevel(level, immediate) {
        var entry = selectedEntry(); if (!entry) return;
        if (writesDisabled(entry)) return;
        _desiredLevel = normalizedDesiredLevel(entry, level); _previewError = '';
        scheduleLearnPreview(entry, immediate === true);
    }

    function clearPreviewState() {
        _preview = null; _previewError = ''; _previewReceivedAt = 0;
    }

    function cancelPreviewWork() {
        if (_previewTimer !== null) { clearTimeout(_previewTimer); _previewTimer = null; }
        _previewIntent++;
        _previewLoading = false;
    }

    function scheduleLearnPreview(entry, immediate, callback) {
        if (_view !== 'trainer' || _trainerExpired || !entry || writesDisabled(entry)
                || Number(entry.currentLevel || 0) >= Number(entry.maxLevel || 1)) {
            _previewLoading = false; renderDetail(); return false;
        }
        if (_previewTimer !== null) clearTimeout(_previewTimer);
        var intent = ++_previewIntent;
        if (_preview && _preview.skillKey !== entry.skillKey) clearPreviewState();
        _previewError = ''; _previewLoading = true;
        renderDetail(); refreshStateControls();
        _previewTimer = setTimeout(function() {
            _previewTimer = null;
            requestLearnPreview(entry.skillKey, intent, callback);
        }, immediate ? 0 : previewDebounceMs());
        return true;
    }

    function requestLearnPreview(skillKey, intent, callback) {
        var entry = entryByKey(skillKey);
        if (!entry || intent !== _previewIntent || _trainerExpired) return;
        var requestedLevel = _desiredLevel;
        var callId = _coordinator.requestPreview({
            skillKey: entry.skillKey,
            desiredLevel: requestedLevel,
            trainerSession: String(_initData.trainerSession || ''),
            expectedRevision: Number(_snapshot.revision)
        }, function(response) {
            if (intent !== _previewIntent) return;
            _previewLoading = false;
            if (response.error === 'trainer_session_expired') return;
            if (response.success === true && response.skillKey === _selectedKey
                    && Number(response.desiredLevel) === _desiredLevel) {
                _preview = response; _previewError = ''; _previewReceivedAt = Date.now();
            } else {
                if (!_preview || _preview.skillKey !== _selectedKey) { _preview = null; _previewReceivedAt = 0; }
                _previewError = String(response.error || 'preview_failed');
                if (response.error === 'initial_level_must_be_one') _desiredLevel = 1;
            }
            renderDetail(); refreshStateControls();
            if (callback) callback(_preview);
        });
        if (!callId && intent === _previewIntent) {
            _previewLoading = false; _previewError = 'busy'; renderDetail(); refreshStateControls();
            if (callback) callback(null);
        }
    }

    function previewMatches(entry) {
        return !!(_preview && entry && _preview.skillKey === entry.skillKey && Number(_preview.desiredLevel) === _desiredLevel);
    }

    function previewDebounceMs() {
        var configured = Number(_config.previewDebounceMs);
        return isFinite(configured) && configured >= 0 ? configured : 140;
    }

    function previewTokenFreshMs() {
        var configured = Number(_config.previewTokenFreshMs);
        return isFinite(configured) && configured >= 50 && configured <= 29000 ? configured : 25000;
    }

    function hasFreshPreviewToken(entry) {
        return previewMatches(entry) && _preview.canCommit && _preview.learnToken && _previewReceivedAt > 0
            && Date.now() - _previewReceivedAt < previewTokenFreshMs();
    }

    function prepareLearnConfirmation(entry) {
        if (!entry || writesDisabled(entry) || _trainerExpired) return;
        if (hasFreshPreviewToken(entry)) { confirmLearn(entry); return; }
        scheduleLearnPreview(entry, true, function(preview) {
            var current = selectedEntry();
            if (preview && current && hasFreshPreviewToken(current)) confirmLearn(current);
        });
    }

    function appendCostRow(parent, label, value, strong) {
        var row = document.createElement('div'); row.className = 'skills-cost-row';
        var name = document.createElement('span'); name.textContent = label;
        var amount = document.createElement(strong ? 'strong' : 'b'); amount.textContent = value;
        row.appendChild(name); row.appendChild(amount); parent.appendChild(row);
    }

    function appendRequirement(parent, label, passed) {
        var item = document.createElement('span'); item.className = passed ? 'ok' : 'blocked';
        item.textContent = (passed ? '✓ ' : '× ') + label; parent.appendChild(item);
    }

    function appendPreviewSummary(parent, preview, entry, stale) {
        var skillPoints = Number(_snapshot && _snapshot.player && _snapshot.player.skillPoints || 0);
        var cost = Number(preview.cost || 0), remaining = skillPoints - cost;
        parent.classList.add(stale ? 'stale' : (preview.canCommit ? 'ok' : 'blocked'));
        appendCostRow(parent, stale ? '上次消耗 · Lv.' + safeNumber(preview.desiredLevel) : '本次消耗', safeNumber(cost) + ' 技能点', true);
        appendCostRow(parent, stale ? '上次研习后余额' : '研习后余额', remaining >= 0
            ? safeNumber(skillPoints) + ' → ' + safeNumber(remaining) : '还差 ' + safeNumber(-remaining) + ' 技能点');
        if (stale) return;
        var requirements = document.createElement('div'); requirements.className = 'skills-trainer-requirements';
        appendRequirement(requirements, '等级要求 Lv.' + safeNumber(entry.unlockLevel), Number(_snapshot.player.level) >= Number(entry.unlockLevel));
        appendRequirement(requirements, '教师可教', true);
        appendRequirement(requirements, '技能点充足', skillPoints >= cost);
        parent.appendChild(requirements);
        if (!preview.canCommit) {
            var blocked = document.createElement('div'); blocked.className = 'skills-preview-message';
            blocked.textContent = errorMessage(preview.blockingError); parent.appendChild(blocked);
        }
    }

    function appendPreviewUpdateStatus(parent, message, failed) {
        var status = document.createElement('div'); status.className = 'skills-preview-update-status' + (failed ? ' error' : '');
        status.textContent = message; parent.appendChild(status);
    }

    function appendPreviewRetry(parent, entry) {
        var retry = button('重新计算', 'skills-action-btn skills-preview-retry', function() { scheduleLearnPreview(entry, true); });
        retry.disabled = writesDisabled(entry); retry.setAttribute('data-focus-key', 'trainer:preview-retry'); parent.appendChild(retry);
    }

    function confirmLearn(entry) {
        if (!_preview || !_preview.learnToken) return;
        _shell.openModal({kind:'skills-learn-confirm', kicker:'教师研习', title:'确认学习 ' + entry.skillKey,
            message:'Lv.' + safeNumber(_preview.currentLevel) + ' → Lv.' + safeNumber(_preview.desiredLevel),
            detail:'将消耗 ' + safeNumber(_preview.cost) + ' 技能点。', actions:[
                {id:'cancel', label:'取消'},
                {id:'confirm', label:'确认研习', primary:true, onSelect:function() {
                    if (!hasFreshPreviewToken(entry)) {
                        scheduleLearnPreview(entry, true, function(preview) {
                            var current = selectedEntry();
                            if (preview && current && hasFreshPreviewToken(current)) confirmLearn(current);
                        });
                        return;
                    }
                    var token = _preview.learnToken;
                    clearPreviewState(); writeCommand('learnCommit', {expectedLearnToken:token});
                }}
            ]});
    }

    function renderLoadout(readOnly) {
        var section = document.createElement('section'); section.className = 'skills-loadout-section';
        var heading = document.createElement('div'); heading.className = 'skills-section-title';
        heading.textContent = readOnly ? '当前快捷栏' : '快捷技能'; section.appendChild(heading);
        var grid = document.createElement('div'); grid.className = 'skills-loadout-grid';
        var slots = _snapshot && _snapshot.loadout || [];
        slots.forEach(function(slot) {
            var card = document.createElement('div'); card.className = 'skills-slot';
            card.setAttribute('data-slot', String(slot.slot)); card.setAttribute('data-state-health', slot.stateHealth || 'invalid');
            if (!slot.skillKey) card.classList.add('empty');
            if (!readOnly && slot.skillKey && slot.stateHealth === 'ok' && !slot.writeBlocked) card.classList.add('movable');
            if (slot.skillKey && slot.skillKey === _selectedKey) card.classList.add('selected');
            if (slot.writeBlocked || slot.stateHealth === 'duplicate') card.classList.add('corrupt');
            var main = button('', 'skills-slot-main', function() { onSlotClick(slot, readOnly); });
            main.setAttribute('data-focus-key', 'slot:' + slot.slot);
            main.setAttribute('aria-label', '槽位 ' + slot.slot + ' · ' + (slot.keyLabel || '无按键') + ' · ' + (slot.skillKey || '空槽'))
                + (!readOnly && slot.skillKey && slot.stateHealth === 'ok' ? ' · 可拖动调整，Alt+←/→ 与相邻槽交换' : '');
            var number = document.createElement('span'); number.className = 'skills-slot-number'; number.textContent = String(slot.slot);
            var key = document.createElement('span'); key.className = 'skills-slot-key'; key.textContent = slot.keyLabel || '';
            var icon = iconNode(slot.iconKey, 'skills-slot-icon');
            var level = document.createElement('span'); level.className = 'skills-slot-level';
            level.textContent = slot.skillKey && Number(slot.level) > 0 ? 'Lv.' + String(slot.level) : '';
            var name = document.createElement('span'); name.className = 'skills-slot-name';
            name.textContent = slot.skillKey || '空槽';
            main.appendChild(number); main.appendChild(key); main.appendChild(icon); main.appendChild(level); main.appendChild(name);
            main.setAttribute('aria-label', '槽位 ' + slot.slot + '，按键 ' + (slot.keyLabel || '未设置') + '，' + (slot.skillKey || '空槽')
                + (!readOnly && slot.skillKey && slot.stateHealth === 'ok' ? '；可拖动调整，Alt 加左右方向键与相邻槽交换' : ''));
            main.disabled = !readOnly && (_coordinator.isWriteBlocked() || slot.writeBlocked);
            if (!readOnly) main.addEventListener('keydown', function(event) { onSlotKeyDown(event, slot); });
            card.appendChild(main);
            if (!readOnly && slot.skillKey) {
                var clear = button('×', 'skills-slot-clear', function(event) { event.stopPropagation(); proposeUnequip(slot); });
                clear.setAttribute('aria-label', '卸载槽位 ' + slot.slot + ' 的 ' + slot.skillKey);
                clear.disabled = _coordinator.isWriteBlocked() || slot.writeBlocked;
                card.appendChild(clear);
            }
            if (slot.skillKey) bindSkillTooltip(card, entryByKey(slot.skillKey), slot);
            grid.appendChild(card);
        });
        section.appendChild(grid); return section;
    }

    function onSlotClick(slot, readOnly) {
        if (_drag && _drag.consumeClick()) return;
        if (readOnly) {
            if (slot.skillKey) selectSkill(slot.skillKey);
            return;
        }
        var entry = selectedEntry();
        if (entry && entry.equippable && !entry.writeBlocked) proposeEquip(entry, slot);
        else if (slot.skillKey) selectSkill(slot.skillKey);
    }

    function onSlotKeyDown(event, slot) {
        if (!event.altKey || (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight')) return;
        event.preventDefault(); event.stopPropagation();
        var target = loadoutSlot(Number(slot.slot) + (event.key === 'ArrowLeft' ? -1 : 1));
        if (!target) return;
        // 焦点跟随被移动的技能，连续按 Alt+方向键可继续横向调整。
        moveQuickSlot(slot, target, 'slot:' + target.slot);
    }

    function moveQuickSlot(source, target, focusKey) {
        if (!source || !target || Number(source.slot) === Number(target.slot)
                || !source.skillKey || source.stateHealth !== 'ok' || source.writeBlocked
                || target.writeBlocked || (target.skillKey && target.stateHealth !== 'ok')
                || _coordinator.isWriteBlocked()) return;
        if (focusKey) _pendingFocusKey = focusKey;
        var callId = writeCommand('moveSlot', {sourceSlot:Number(source.slot), targetSlot:Number(target.slot),
            expectedRevision:Number(_snapshot.revision)});
        if (!callId && focusKey) _pendingFocusKey = '';
    }

    function proposeEquip(entry, slot) {
        if (writesDisabled(entry) || slot.writeBlocked) return;
        var payload = {skillKey:entry.skillKey, slot:Number(slot.slot), expectedRevision:Number(_snapshot.revision)};
        var replacingSkill = slot.skillKey && slot.skillKey !== entry.skillKey;
        if (_loadoutConfirmationMode === 'fast' || !replacingSkill) {
            writeCommand('equip', payload);
            return;
        }
        var replacing = slot.skillKey && slot.skillKey !== entry.skillKey ? '将替换「' + slot.skillKey + '」。' : '该槽当前为空。';
        _shell.openModal({kind:'skills-equip-confirm', kicker:'快捷栏配置', title:'装备到槽位 ' + slot.slot,
            message:'装备「' + entry.skillKey + '」', detail:replacing, actions:[
                {id:'cancel', label:'取消'},
                {id:'confirm', label:'确认装备', primary:true, onSelect:function() {
                    writeCommand('equip', payload);
                }}
            ]});
    }

    function proposeUnequip(slot) {
        if (!slot.skillKey || slot.writeBlocked || _coordinator.isWriteBlocked()) return;
        var payload = {slot:Number(slot.slot), expectedRevision:Number(_snapshot.revision)};
        if (_loadoutConfirmationMode === 'fast') {
            writeCommand('unequip', payload);
            return;
        }
        _shell.openModal({kind:'skills-unequip-confirm', kicker:'快捷栏配置', title:'卸载槽位 ' + slot.slot,
            message:'移除「' + slot.skillKey + '」', detail:slot.stateHealth === 'unknown'
                ? '该槽中的技能数据已失效，可以直接移除。' : '不会重置或缩短该槽的冷却。', actions:[
                {id:'cancel', label:'取消'},
                {id:'confirm', label:'确认卸载', primary:true, onSelect:function() {
                    writeCommand('unequip', payload);
                }}
            ]});
    }

    function readLoadoutConfirmationMode() {
        try {
            return window.localStorage.getItem(LOADOUT_CONFIRMATION_KEY) === 'fast' ? 'fast' : 'safe';
        } catch (error) { return 'safe'; }
    }

    function setLoadoutConfirmationMode(mode) {
        var previous = _loadoutConfirmationMode;
        _loadoutConfirmationMode = mode === 'fast' ? 'fast' : 'safe';
        try { window.localStorage.setItem(LOADOUT_CONFIRMATION_KEY, _loadoutConfirmationMode); } catch (error) {}
        refreshLoadoutConfirmationToggle();
        if (previous !== _loadoutConfirmationMode) {
            toast(_loadoutConfirmationMode === 'fast'
                ? '快捷栏已切换为快速操作：替换和卸载将直接执行。'
                : '快捷栏已切换为安全操作：替换和卸载前会确认。');
        }
        return _loadoutConfirmationMode;
    }

    function createLoadoutConfirmationToggle() {
        var group = document.createElement('div');
        group.className = 'item-grid-mode-switch skills-confirmation-toggle';
        group.setAttribute('role', 'group');
        group.setAttribute('aria-label', '快捷栏操作确认');
        group.setAttribute('aria-label', '安全模式会确认替换和卸载；快速模式直接执行。技能学习始终需要确认');
        var label = document.createElement('span'); label.className = 'item-grid-mode-label'; label.textContent = '快捷栏';
        group.appendChild(label);
        [{mode:'safe', label:'安全', title:'替换和卸载前确认；空槽仍直接装备'},
         {mode:'fast', label:'快速', title:'替换和卸载直接执行；技能学习仍需确认'}].forEach(function(option) {
            var choice = button(option.label, 'workbench-mode-btn item-grid-mode-option skills-confirmation-option', function() {
                setLoadoutConfirmationMode(option.mode);
            });
            choice.setAttribute('data-confirmation-mode', option.mode);
            choice.setAttribute('aria-label', '快捷栏确认：' + option.label + '模式');
            choice.setAttribute('aria-label', option.title);
            group.appendChild(choice);
        });
        refreshLoadoutConfirmationToggle(group);
        return group;
    }

    function refreshLoadoutConfirmationToggle(group) {
        group = group || _confirmationToggle;
        if (!group) return;
        group.setAttribute('data-current-confirmation-mode', _loadoutConfirmationMode);
        var choices = group.querySelectorAll('.skills-confirmation-option[data-confirmation-mode]');
        for (var i = 0; i < choices.length; i++) {
            var selected = choices[i].getAttribute('data-confirmation-mode') === _loadoutConfirmationMode;
            choices[i].setAttribute('aria-pressed', selected ? 'true' : 'false');
        }
    }

    function manageHelpDetail() {
        var mode = _loadoutConfirmationMode === 'fast' ? '快速' : '安全';
        var behavior = _loadoutConfirmationMode === 'fast'
            ? '装备、替换和卸载直接执行。技能学习仍须确认。'
            : '空槽直接装备；替换和卸载需要确认。';
        return '管理技能\n• 装备到已有槽位会替换原技能；是否确认由顶栏“快捷栏”的安全/快速选项决定。\n• 快捷槽可互相拖动：拖到空槽会移动，拖到已有技能会直接交换。\n• 聚焦快捷槽后按 Alt + ← / → 可与相邻槽交换。\n• 纯被动技能可以启用或停用。\n• 聚焦技能后按 Alt + ↑ / ↓ 也可交换相邻顺序。'
            + '\n\n查找与布局\n• 形态、配置和流派都可直接筛选，也可以组合使用。\n• 按 / 可以展开名称搜索。\n• 完整/紧凑只改变技能库；下方 12 格快捷技能保持固定。'
            + '\n\n快捷栏操作确认\n• 顶栏始终显示当前模式，可随时在“安全 / 快速”之间切换。\n• 当前：' + mode + '模式。' + behavior
            + '\n• 快捷槽之间的移动或交换无需确认；技能学习始终需要确认。'
            + (_initData && _initData.canReturnTrainer === true ? '\n• “返回研习”只在本次教师入口中可用。' : '');
    }

    function writeCommand(cmd, payload) {
        _preview = null;
        var callId = _coordinator.write(cmd, payload, function(response) {
            if (response.error === 'trainer_session_expired') return;
            if (response.success !== true) {
                toast(errorMessage(response.error));
                if (response.error === 'stale_state' || response.error === 'not_learned' || response.error === 'skill_not_found') requestSnapshot();
            } else toast(response.changed === false ? '状态未变化。' : successMessage(cmd));
            renderAll();
        });
        if (!callId) toast('当前暂时不能修改技能，请稍后重试。');
        renderAll();
        return callId;
    }

    function requestSnapshot() {
        if (_coordinator.getState() !== 'idle') return false;
        return !!_coordinator.requestSnapshot(function(response) {
            if (response.error === 'trainer_session_expired') return;
            if (response.success !== true) toast(errorMessage(response.error));
            refreshStateControls();
        });
    }

    function onAuthoritativeSnapshot(snapshot) {
        var validation = validateSnapshot(snapshot, _view);
        if (!validation.ok) {
            cancelPreviewWork(); _snapshot = null; _schemaError = validation.error; clearPreviewState();
            _lastDiagnostic = {source:'snapshot_validation', error:'invalid_snapshot', validationError:String(validation.error || '')};
            renderAll(); return;
        }
        cancelPreviewWork(); _snapshot = snapshot; _schemaError = ''; _trainerExpired = false; clearPreviewState(); _lastDiagnostic = null;
        var entries = sourceEntries();
        if (!entries.some(function(entry) { return entry.skillKey === _selectedKey; })) {
            _selectedKey = entries.length ? entries[0].skillKey : '';
            if (_view === 'trainer' && entries.length) {
                var current = Number(entries[0].currentLevel || 0);
                _desiredLevel = current <= 0 ? 1 : Math.min(Number(entries[0].maxLevel || 1), current + 1);
            }
        }
        renderAll();
        if (_view === 'trainer') {
            var selected = selectedEntry();
            if (selected) scheduleLearnPreview(selected, true);
        }
    }

    function validateSnapshot(snapshot, view) {
        if (!snapshot || snapshot.success !== true || Number(snapshot.v) !== 1) return {ok:false,error:'技能快照协议无效。'};
        if (snapshot.view !== view) return {ok:false,error:'技能快照视图与当前面板实例不一致。'};
        if (!Array.isArray(snapshot.learned) || !Array.isArray(snapshot.loadout) || snapshot.loadout.length !== 12)
            return {ok:false,error:'技能快照缺少完整 learned/loadout 结构。'};
        for (var i = 0; i < snapshot.learned.length; i++) if (!validEntry(snapshot.learned[i], false))
            return {ok:false,error:'已学技能条目结构无效。'};
        for (var slot = 0; slot < snapshot.loadout.length; slot++) {
            var item = snapshot.loadout[slot];
            if (!item || Number(item.slot) !== slot + 1 || typeof item.writeBlocked !== 'boolean')
                return {ok:false,error:'快捷栏必须是按 1..12 排列的完整槽对象。'};
        }
        if (view === 'trainer') {
            if (!snapshot.trainer || !Array.isArray(snapshot.trainer.entries))
                return {ok:false,error:'教师快照缺少完整 TrainerEntry 目录。'};
            if (String(snapshot.trainer.session || '') !== String(_initData && _initData.trainerSession || ''))
                return {ok:false,error:'教师快照 capability 与当前面板实例不一致。'};
            for (var j = 0; j < snapshot.trainer.entries.length; j++) if (!validEntry(snapshot.trainer.entries[j], true))
                return {ok:false,error:'教师目录拒绝纯 skillKey 或缺字段条目。'};
        } else if (snapshot.trainer !== null) return {ok:false,error:'管理快照不得携带教师 capability。'};
        return {ok:true};
    }

    function validEntry(entry, trainer) {
        if (!entry || typeof entry !== 'object' || Array.isArray(entry) || typeof entry.skillKey !== 'string'
                || typeof entry.type !== 'string' || typeof entry.description !== 'string'
                || typeof entry.stateHealth !== 'string' || typeof entry.writeBlocked !== 'boolean'
                || typeof entry.passive !== 'boolean' || typeof entry.equippable !== 'boolean') return false;
        return trainer ? typeof entry.currentLevel === 'number' && typeof entry.unlockSP === 'number'
            : typeof entry.level === 'number' && Array.isArray(entry.equippedSlots);
    }

    function onCoordinatorState() {
        if (_leftRoot && _rightRoot) renderAll();
        else refreshStateControls();
    }
    function onCoordinatorError(response, source) {
        if (handleTrainerExpired(response, source)) return;
        _lastDiagnostic = {
            source:String(source || 'unknown'), error:String(response && response.error || 'unknown'),
            callId:String(response && response.callId || ''), validationError:String(response && response.validationError || '')
        };
        if (response && response.error === 'malformed_response' && response.validationError) {
            _schemaError = response.validationError;
            renderAll();
        }
        if (source === 'write_unknown') toast('操作结果尚未确认，正在自动核对。');
        else if (source === 'reconcile' && response && response.error) toast('暂时无法确认操作结果，请重试。');
        refreshStateControls();
    }

    function handleTrainerExpired(response, source) {
        if (_view !== 'trainer' || !response || response.error !== 'trainer_session_expired') return false;
        cancelPreviewWork(); clearPreviewState();
        _trainerExpired = true;
        _lastDiagnostic = {source:String(source || 'unknown'), error:'trainer_session_expired',
            callId:String(response.callId || ''), validationError:''};
        toast('教师连接已失效，请返回游戏后重新与教师对话。');
        renderDetail(); refreshStateControls();
        return true;
    }

    function refreshStateControls() {
        if (!_shell) return;
        var state = _coordinator.getState();
        if (_switchPending) _shell.setStatus(_view === 'trainer' ? '正在切换到技能管理' : '正在返回技能研习', 'loading');
        else if (_trainerExpired) _shell.setStatus('教师连接已失效', 'error');
        else if (_schemaError) _shell.setStatus('技能数据异常', 'error');
        else if (state === 'write_pending') _shell.setStatus('正在保存', 'loading');
        else if (state === 'needs_reconcile') _shell.setStatus('结果待确认', 'error');
        else if (state === 'idle' && _snapshot) _shell.setStatus('', 'idle');
        else if (state === 'closed') _shell.setStatus('连接已断开', 'error');
        else _shell.setStatus('读取中', 'loading');
        if (_refreshButton) {
            _refreshButton.hidden = !(_schemaError || state === 'needs_reconcile');
            _refreshButton.textContent = state === 'needs_reconcile' ? '确认结果' : '重试';
            _refreshButton.disabled = state === 'write_pending' || state === 'closed';
        }
        if (_diagnosticButton) {
            _diagnosticButton.hidden = !(_schemaError || state === 'needs_reconcile');
            _diagnosticButton.disabled = false;
        }
        if (_switchButton) _switchButton.disabled = _trainerExpired || _switchPending || state !== 'idle';
        skillFilterDefinitions().forEach(function(definition) {
            if (_filterNavigators[definition.id]) _filterNavigators[definition.id].setDisabled(state === 'closed');
        });
        if (_rightRoot) {
            var controls = _rightRoot.querySelectorAll('button');
            for (var i = 0; i < controls.length; i++) {
                if (state !== 'idle' && !controls[i].classList.contains('skills-close-allowed')) controls[i].disabled = true;
            }
        }
    }

    function installPointerDrag() {
        _dragSourceView = {
            instanceKey:'skills:drag-source',
            exportOffer:function(entry) {
                return entry && !writesDisabled(entry)
                    ? {subjectKind:'skill', sourceRef:{skillKey:entry.skillKey, equippable:entry.equippable === true}} : null;
            }
        };
        _dragSlotSourceView = {
            instanceKey:'skills:quick-slot-source',
            exportOffer:function(slot) {
                return slot && slot.skillKey && slot.stateHealth === 'ok' && !slot.writeBlocked
                    ? {subjectKind:'quick_slot', sourceRef:{slot:Number(slot.slot), skillKey:String(slot.skillKey)}} : null;
            }
        };
        _dragTargetView = {
            instanceKey:'skills:loadout-target',
            probeAccept:function(offer, hit) {
                var slot = hit && hit.slot;
                if (!offer || offer.subjectKind !== 'skill') return {accepted:false, reason:'invalid_skill'};
                if (!offer.sourceRef || offer.sourceRef.equippable !== true) return {accepted:false, reason:'skill_not_equippable'};
                if (!slot || slot.writeBlocked || _coordinator.isWriteBlocked()) return {accepted:false, reason:'slot_locked'};
                return {accepted:true, operationId:'equip_skill', targetRef:{slot:Number(slot.slot)}};
            }
        };
        _dragSlotTargetView = {
            instanceKey:'skills:quick-slot-target',
            probeAccept:function(offer, hit) {
                var target = hit && hit.slot;
                var source = offer && offer.sourceRef ? loadoutSlot(Number(offer.sourceRef.slot)) : null;
                if (!offer || offer.subjectKind !== 'quick_slot' || !source || !source.skillKey)
                    return {accepted:false, reason:'invalid_skill'};
                if (!target || source.slot === target.slot || source.writeBlocked || target.writeBlocked
                        || source.stateHealth !== 'ok' || (target.skillKey && target.stateHealth !== 'ok')
                        || _coordinator.isWriteBlocked()) return {accepted:false, reason:'slot_locked'};
                return {accepted:true, operationId:'move_quick_slot',
                    targetRef:{sourceSlot:Number(source.slot), targetSlot:Number(target.slot)}};
            }
        };
        _dragOrderTargetView = {
            instanceKey:'skills:order-target',
            probeAccept:function(offer, hit) {
                var source = offer && offer.sourceRef ? entryByKey(offer.sourceRef.skillKey) : null;
                var target = hit && hit.entry;
                if (!source || !target || source.skillKey === target.skillKey) return {accepted:false, reason:'invalid_skill'};
                var reason = reorderBlockReason(source, 'source') || reorderBlockReason(target, 'target');
                if (reason) return {accepted:false, reason:reason};
                return {accepted:true, operationId:'reorder_skill',
                    targetRef:{skillKey:target.skillKey, targetIndex:Number(target.orderIndex)}};
            }
        };
        _dragBroker = new Workbench.InteractionBroker({
            onIntent:function(intent, context) {
                if (intent && intent.operationId === 'reorder_skill') {
                    reorderTo(context.sourceItem, entryByKey(intent.targetRef && intent.targetRef.skillKey));
                    return;
                }
                if (intent && intent.operationId === 'move_quick_slot') {
                    moveQuickSlot(loadoutSlot(Number(intent.targetRef.sourceSlot)), loadoutSlot(Number(intent.targetRef.targetSlot)));
                    return;
                }
                var slot = loadoutSlot(intent && intent.targetRef && Number(intent.targetRef.slot));
                if (slot) proposeEquip(context.sourceItem, slot);
            },
            onReject:function(result) {
                if (result && result.reason && result.reason !== 'invalid_skill') toast(dragRejectMessage(result.reason));
            }
        });
        _drag = new Workbench.PointerDragController({
            sourceElement:_scaleEl, broker:_dragBroker, allowInteractiveSource:true,
            threshold:6, timeoutMs:_config.dragTimeoutMs || 1400,
            getSource:function(target) {
                if (_view !== 'manage' || !_snapshot || _coordinator.isWriteBlocked()) return null;
                var row = target && target.closest ? target.closest('.skills-library-row[data-skill-key]') : null;
                if (row && _list.contains(row)) {
                    var entry = entryByKey(row.getAttribute('data-skill-key'));
                    if (!entry || writesDisabled(entry)) return null;
                    return {view:_dragSourceView, item:entry, node:row};
                }
                if (target && target.closest && target.closest('.skills-slot-clear')) return null;
                var node = target && target.closest ? target.closest('.skills-slot[data-slot]') : null;
                if (!node || !_scaleEl.contains(node)) return null;
                var slot = loadoutSlot(Number(node.getAttribute('data-slot')));
                if (!slot || !slot.skillKey || slot.stateHealth !== 'ok' || slot.writeBlocked) return null;
                return {view:_dragSlotSourceView, item:slot, node:node};
            },
            resolveTarget:function(clientX, clientY) {
                var target = document.elementFromPoint(clientX, clientY);
                var activeSlotNode = _scaleEl.querySelector('.skills-slot.dragging[data-slot]');
                if (activeSlotNode) {
                    var slotNode = target && target.closest ? target.closest('.skills-slot[data-slot]') : null;
                    if (!slotNode || !_scaleEl.contains(slotNode) || slotNode === activeSlotNode) return null;
                    var quickTarget = loadoutSlot(Number(slotNode.getAttribute('data-slot')));
                    return {view:_dragSlotTargetView, hit:{slot:quickTarget}, node:slotNode,
                        accepted:!!quickTarget && !quickTarget.writeBlocked
                            && (!quickTarget.skillKey || quickTarget.stateHealth === 'ok') && !_coordinator.isWriteBlocked()};
                }
                var node = target && target.closest ? target.closest('.skills-library-row[data-skill-key]') : null;
                if (node && _list.contains(node)) {
                    if (node.classList.contains('dragging')) return null;
                    var sourceNode = _list.querySelector('.skills-library-row.dragging[data-skill-key]');
                    var source = sourceNode ? entryByKey(sourceNode.getAttribute('data-skill-key')) : null;
                    var entry = entryByKey(node.getAttribute('data-skill-key'));
                    var reason = reorderBlockReason(source, 'source') || reorderBlockReason(entry, 'target');
                    return {view:_dragOrderTargetView, hit:{entry:entry}, node:node,
                        accepted:!!source && !!entry && source.skillKey !== entry.skillKey && !reason};
                }
                node = target && target.closest ? target.closest('.skills-slot[data-slot]') : null;
                if (!node || !_scaleEl.contains(node)) return null;
                var slot = loadoutSlot(Number(node.getAttribute('data-slot')));
                var activeSourceNode = _list.querySelector('.skills-library-row.dragging[data-skill-key]');
                var activeSource = activeSourceNode ? entryByKey(activeSourceNode.getAttribute('data-skill-key')) : null;
                return {view:_dragTargetView, hit:{slot:slot}, node:node,
                    accepted:!!activeSource && activeSource.equippable === true && !!slot
                        && !slot.writeBlocked && !_coordinator.isWriteBlocked()};
            },
            renderGhost:function(source) {
                var ghost = document.createElement('div'); ghost.className = 'workbench-drag-ghost skills-drag-ghost';
                ghost.appendChild(iconNode(source.item.iconKey, 'skills-drag-icon'));
                var label = document.createElement('span');
                label.textContent = source.item.skillKey + (source.view === _dragSlotSourceView ? ' · 槽位 ' + source.item.slot : '');
                ghost.appendChild(label);
                return ghost;
            },
            onDragStart:function(source) {
                // 已显示的注释不会仅因 isSuppressed 自动消失；拖拽开始时主动收起，
                // 避免大尺寸技能说明遮住快捷槽落点。
                if (typeof PanelTooltip !== 'undefined' && PanelTooltip) PanelTooltip.hide();
                if (source && source.node) source.node.classList.add('dragging');
            },
            onDragEnd:function(source) { if (source && source.node) source.node.classList.remove('dragging'); }
        });
    }

    function dragRejectMessage(reason) {
        if (reason === 'slot_locked') return '该快捷槽当前不可写。';
        if (reason === 'skill_not_equippable') return '该技能不能装备到快捷栏。';
        if (reason === 'equipped_skill_locked') return '已装备技能需先卸载，才能交换列表顺序。';
        return '该技能当前无法调整顺序。';
    }

    function entryByKey(skillKey) {
        var entries = sourceEntries();
        for (var i = 0; i < entries.length; i++) if (entries[i].skillKey === skillKey) return entries[i];
        return null;
    }

    function loadoutSlot(number) {
        var slots = _snapshot && _snapshot.loadout || [];
        for (var i=0;i<slots.length;i++) if (Number(slots[i].slot) === number) return slots[i];
        return null;
    }

    function requestManageView() {
        if (_view !== 'trainer' || !_initData || _trainerExpired) return;
        var panelInstanceId = _coordinator.getPanelInstanceId() || String(_initData.panelInstanceId || '');
        if (!panelInstanceId || _coordinator.getState() !== 'idle') return;
        var sent = Bridge.send({
            type:'panel', panel:'skills', cmd:'switch_manage', panelInstanceId:panelInstanceId,
            payload:{v:1, focusSkillKey:String(_selectedKey || '')}
        });
        if (sent === false) { toast('启动器连接不可用，暂时无法切换页面。'); return; }
        beginSwitchWait('切换中…', '切换到技能管理未完成，请重试。');
    }

    function openHelp() {
        if (!_shell) return;
        var trainer = _view === 'trainer';
        var title = trainer ? '技能研习帮助' : '技能管理帮助';
        var message = trainer
            ? '研习技能\n• 从左侧选择想学习或升级的技能。\n• 点击等级刻度、拖动滑条或直接输入目标等级。\n• 查看研习后余额，再确认完成研习。'
            : '装备与排序\n• 点击技能，再点击下方快捷槽。\n• 技能可拖到快捷槽；快捷槽之间可直接拖动移动或交换。\n• 拖到另一个技能格可交换技能库顺序。\n• 悬停或聚焦快捷槽后，点击右上角 × 可以卸载技能。';
        var detail = trainer
            ? '等级规则\n• 未学技能第一次固定学习 1 级。\n• 已学技能可点任意可见刻度；− / + 用于逐级微调。\n• 滑动时旧消耗会保留，松开后自动计算消耗且只计算最终等级。\n\n页面切换\n• “管理技能”可进入快捷技能管理。\n• 返回研习后会自动恢复当前目标并重新计算。'
            : manageHelpDetail();
        var actions = [{id:'close', label:'知道了', primary:true}];
        var modal = _shell.openModal({
            kind:'skills-help', title:title, message:message, detail:detail,
            actions:actions
        });
        if (modal && modal.dialog) {
            modal.dialog.setAttribute('aria-label', title);
        }
    }

    function requestTrainerView() {
        if (_view !== 'manage' || !_initData || _initData.canReturnTrainer !== true) return;
        var panelInstanceId = _coordinator.getPanelInstanceId() || String(_initData.panelInstanceId || '');
        if (!panelInstanceId || _coordinator.getState() !== 'idle') return;
        var sent = Bridge.send({
            type:'panel', panel:'skills', cmd:'switch_trainer', panelInstanceId:panelInstanceId,
            payload:{v:1, focusSkillKey:String(_selectedKey || '')}
        });
        if (sent === false) { toast('启动器连接不可用，暂时无法切换页面。'); return; }
        beginSwitchWait('返回中…', '返回研习未完成；若教师入口已失效，请重新与教师对话。');
    }

    function beginSwitchWait(buttonText, timeoutMessage) {
        cancelSwitchWait();
        _switchPending = true;
        if (_switchButton) { _switchButton.disabled = true; _switchButton.textContent = buttonText; }
        refreshStateControls();
        _switchWaitTimer = setTimeout(function() {
            _switchWaitTimer = null;
            _switchPending = false;
            if (_switchButton) _switchButton.textContent = _view === 'trainer' ? '管理技能' : '返回研习';
            refreshStateControls();
            toast(timeoutMessage);
        }, switchWaitTimeoutMs());
    }

    function cancelSwitchWait() {
        if (_switchWaitTimer !== null) {
            clearTimeout(_switchWaitTimer);
            _switchWaitTimer = null;
        }
        _switchPending = false;
    }

    function switchWaitTimeoutMs() {
        var configured = Number(_config.switchTimeoutMs);
        return isFinite(configured) && configured >= 50 ? configured : 3000;
    }

    function requestClose() {
        var panelInstanceId = _coordinator.getPanelInstanceId() || String(_initData && _initData.panelInstanceId || '');
        Panels.close();
        Bridge.send({type:'panel', panel:'skills', cmd:'close', panelInstanceId:panelInstanceId});
    }

    function cleanup() {
        cleanupView(true);
        _coordinator.close();
        if (_returnFocus && document.documentElement.contains(_returnFocus) && _returnFocus.focus) _returnFocus.focus();
        _returnFocus = null;
    }

    function cleanupView(detachScale) {
        cancelSwitchWait();
        cancelPreviewWork();
        if (_drag) { _drag.destroy(); _drag = null; }
        if (_dragBroker) { _dragBroker.clearSelection(); _dragBroker = null; }
        _dragSourceView = null; _dragSlotSourceView = null;
        _dragTargetView = null; _dragSlotTargetView = null; _dragOrderTargetView = null;
        skillFilterDefinitions().forEach(function(definition) {
            if (_filterNavigators[definition.id]) _filterNavigators[definition.id].destroy();
        });
        _filterNavigators = {}; _filterBoard = null; _filterResetButton = null;
        if (_density) { _density.destroy(); _density = null; }
        _densityToggle = null; _confirmationToggle = null;
        if (_shell) { _shell.destroy(); _shell = null; }
        _leftRoot = null; _rightRoot = null; _list = null; _search = null;
        _searchToggle = null; _searchControls = null; _searchClose = null; _searchExpanded = false;
        _refreshButton = null; _diagnosticButton = null; _switchButton = null; _helpButton = null; _closeButton = null;
        _pendingFocusKey = '';
        if (detachScale !== false && _scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        _snapshot = null; _preview = null; _schemaError = ''; _lastDiagnostic = null;
        _previewError = ''; _previewReceivedAt = 0; _trainerExpired = false;
        if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide();
    }

    function writesDisabled(entry) {
        return _trainerExpired || !_snapshot || _coordinator.isWriteBlocked() || !!(entry && (entry.writeBlocked || entry.stateHealth !== 'ok'));
    }

    function iconNode(iconKey, className) {
        var host = document.createElement('span'); host.className = className || 'skills-icon';
        var html = typeof Icons !== 'undefined' && Icons.html && iconKey
            ? Icons.html(String(iconKey), 'skills-icon-image', ' onerror="this.style.display=\'none\';this.parentNode.classList.add(\'missing\')"') : '';
        if (html) host.innerHTML = html;
        else host.classList.add('missing');
        host.addEventListener('error', function() { host.classList.add('missing'); }, true);
        var fallback = document.createElement('span'); fallback.className = 'skills-icon-fallback'; fallback.textContent = '技';
        host.appendChild(fallback); return host;
    }

    function bindSkillTooltip(node, entry, slot) {
        if (!node || typeof PanelTooltip === 'undefined' || !PanelTooltip || !PanelTooltip.bindAsyncHover) return;
        var model = entry || (slot && slot.skillKey ? {
            skillKey:slot.skillKey, iconKey:slot.iconKey, level:slot.level, maxLevel:slot.level,
            type:slot.stateHealth === 'unknown' ? '遗留快捷槽' : '技能', mp:'—', cooldownMs:NaN,
            description:slot.stateHealth === 'unknown' ? '该槽引用了当前技能表中不存在的技能；仅允许安全卸载。' : '暂无技能说明。'
        } : null);
        if (!model) return;
        PanelTooltip.bindAsyncHover(node, {
            key:'skill:' + String(model.skillKey || ''), item:model,
            renderBasic:function(value) { return buildSkillTooltipHtml(value); },
            isSuppressed:function() {
                var state = _drag && _drag.debugState ? _drag.debugState() : null;
                return !!(state && state.phase && state.phase !== 'idle');
            }
        });
    }

    function buildSkillTooltipHtml(entry) {
        if (!entry) return '';
        var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
        var meta = (entry.type || '未知类型') + ' · Lv.' + safeNumber(level) + '/' + safeNumber(entry.maxLevel)
            + ' · MP ' + safeNumber(entry.mp) + ' · CD ' + cooldownText(entry.cooldownMs);
        var state = healthLabel(entry);
        var intro = '<div class="skills-tt-title"><b>' + escapeHtml(entry.skillKey || '未知技能') + '</b></div>'
            + '<div class="skills-tt-meta">' + escapeHtml(meta) + '</div>'
            + '<div class="skills-tt-state">' + escapeHtml(state) + '</div>';
        return PanelTooltip.buildItemRichHtml({
            iconHtml:PanelTooltip.dynamicIconHtml(entry.iconKey || entry.skillKey, 'skills-tt-icon'),
            introWebHTML:intro,
            descHTML:normalizeAS2Description(entry.description || '暂无技能说明。'),
            rootClass:'skills-tooltip', layoutType:'wide', splitMode:'auto'
        });
    }

    function normalizeAS2Description(value) {
        return String(value == null ? '' : value).replace(/\r\n|\r|\n/g, '<br>');
    }

    function buildDiagnosticRecord(reason, entry) {
        var state = _coordinator.debugState();
        return {
            v:1,
            area:'skills',
            reason:String(reason || 'unknown'),
            view:_view,
            panelInstanceId:String(state.panelInstanceId || ''),
            revision:_snapshot ? Number(_snapshot.revision) : Number(state.lastAppliedRevision),
            writeState:String(state.state || ''),
            writeEpoch:Number(state.lastAppliedWriteEpoch),
            activeWrite:state.activeWrite || null,
            activeReconcile:state.activeReconcile || null,
            pendingCount:state.mux ? Number(state.mux.pendingCount || 0) : 0,
            selectedSkill:String(entry && entry.skillKey || _selectedKey || ''),
            entryHealth:entry ? String(entry.stateHealth || '') : '',
            trainerExpired:_trainerExpired,
            schemaError:String(_schemaError || ''),
            lastError:_lastDiagnostic,
            snapshotDiagnostics:redactDiagnosticValue(_snapshot && Array.isArray(_snapshot.diagnostics) ? _snapshot.diagnostics : [])
        };
    }

    function redactDiagnosticValue(value) {
        if (Array.isArray(value)) return value.map(redactDiagnosticValue);
        if (!value || typeof value !== 'object') return value;
        var result = {};
        Object.keys(value).forEach(function(key) {
            if (/session|token/i.test(key)) return;
            result[key] = redactDiagnosticValue(value[key]);
        });
        return result;
    }

    function copyDiagnostic(reason, entry) {
        var value = JSON.stringify(buildDiagnosticRecord(reason, entry), null, 2);
        copyText(value).then(function() { toast('诊断信息已复制。'); }, function() {
            toast('无法复制诊断信息，请截图反馈。');
        });
    }

    function copyText(value) {
        if (typeof _config.copyText === 'function') {
            try { return Promise.resolve(_config.copyText(value)); }
            catch (error) { return Promise.reject(error); }
        }
        if (typeof navigator !== 'undefined' && navigator.clipboard && navigator.clipboard.writeText) {
            return navigator.clipboard.writeText(value).catch(function() { return fallbackCopyText(value); });
        }
        return fallbackCopyText(value);
    }

    function fallbackCopyText(value) {
        return new Promise(function(resolve, reject) {
            var area = document.createElement('textarea'); area.value = value;
            area.setAttribute('readonly', 'readonly'); area.style.position = 'fixed'; area.style.left = '-9999px';
            document.body.appendChild(area); area.select();
            var copied = false;
            try { copied = document.execCommand('copy'); } catch (error) { copied = false; }
            document.body.removeChild(area);
            if (copied) resolve(); else reject(new Error('copy_failed'));
        });
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;')
            .replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
    }

    function empty(text, kind) {
        var node = document.createElement('div'); node.className = 'skills-empty' + (kind ? ' ' + kind : ''); node.textContent = text; return node;
    }
    function button(text, className, handler) {
        var node = document.createElement('button'); node.type = 'button'; node.className = className || ''; node.textContent = text;
        if (handler) node.addEventListener('click', handler); return node;
    }
    function safeNumber(value) { var number = Number(value); return isFinite(number) ? String(number) : '—'; }
    function cooldownText(value) { var ms=Number(value); return isFinite(ms) ? (ms/1000).toFixed(ms%1000?1:0)+'s' : '—'; }
    function healthLabel(entry) {
        if (entry.stateHealth === 'duplicate') return '重复';
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return '异常';
        if (_view === 'trainer') return Number(entry.currentLevel||0)>0 ? '已学' : '可学';
        if (entry.passive && !entry.equippable) return entry.enabled ? '被动 ON' : '被动 OFF';
        return entry.equippedSlots && entry.equippedSlots.length ? '槽 ' + entry.equippedSlots.join('/') : '可装备';
    }
    function compactStateLabel(entry) {
        if (entry.stateHealth !== 'ok' || entry.writeBlocked) return '!';
        if (_view === 'trainer') return Number(entry.currentLevel || 0) > 0 ? '已学' : '可学';
        if (entry.passive && !entry.equippable) return entry.enabled ? 'ON' : 'OFF';
        return entry.equippedSlots && entry.equippedSlots.length ? entry.equippedSlots.join('/') : '';
    }
    function skillAriaLabel(entry) {
        var level = entry.currentLevel != null ? entry.currentLevel : entry.level;
        return String(entry.skillKey || '未知技能') + '，等级 ' + safeNumber(level) + '/' + safeNumber(entry.maxLevel)
            + '，' + healthLabel(entry) + '；悬停查看技能说明';
    }
    function focusSibling(node, delta) {
        var rows = Array.prototype.slice.call(_list.querySelectorAll('.skills-library-row'));
        var index = rows.indexOf(node), next = rows[index+delta]; if (next) next.focus();
    }
    function focusKeyOf(node) { return node && node.getAttribute ? node.getAttribute('data-focus-key') || '' : ''; }
    function restoreFocusKey(key) {
        if (!key) return;
        var nodes = _scaleEl.querySelectorAll('[data-focus-key]');
        for (var i=0;i<nodes.length;i++) if (nodes[i].getAttribute('data-focus-key') === key) { nodes[i].focus(); return; }
    }
    function successMessage(cmd) {
        return {learnCommit:'技能研习完成。',equip:'快捷栏已更新。',unequip:'技能已卸载。',
            moveSlot:'快捷槽顺序已更新。',setPassive:'被动状态已更新。',reorder:'技能顺序已更新。'}[cmd] || '技能状态已更新。';
    }
    function errorMessage(error) {
        var messages = {invalid_payload:'无法完成技能操作，请重试。',unsupported_cmd:'暂不支持该操作。',
            skill_not_found:'技能已不存在。',not_learned:'该技能尚未学习。',stale_state:'技能状态已变化，请刷新。',
            trainer_session_expired:'当前教师已无法继续研习，请重新与教师对话。',level_locked:'角色等级不足。',insufficient_sp:'技能点不足。',
            max_level:'技能已满级。',initial_level_must_be_one:'未学技能只能先学习 1 级。',skill_table_full:'技能表已满。',
            slot_empty:'源快捷槽为空。',
            already_equipped:'普通模式下该技能已经装备。',not_equippable:'该技能不可装备。',corrupt_skill_state:'技能数据异常，暂时无法修改。',
            service_not_ready:'技能功能尚未准备好，请稍后重试。',reconcile_required:'上次操作结果尚未确认。',busy:'技能功能正忙，请稍后重试。',
            malformed_response:'技能数据异常，请重试。',timeout:'技能请求超时。',client_timeout:'技能请求超时。',disconnect:'连接已断开。'};
        return messages[error] || '技能操作失败。';
    }
    function toast(message) { if (typeof Toast !== 'undefined' && Toast.add) Toast.add(message); }

    Bridge.on('panel_resp', function(data) { _coordinator.handleResponse(data); });

    return {
        debugState: function() {
            return {view:_view, selectedKey:_selectedKey, desiredLevel:_desiredLevel, hasPreview:!!_preview,
                previewLoading:_previewLoading, previewError:_previewError, trainerExpired:_trainerExpired,
                schemaError:_schemaError, snapshotRevision:_snapshot && _snapshot.revision,
                densityMode:_density && _density.mode, loadoutConfirmationMode:_loadoutConfirmationMode,
                switchPending:_switchPending, filterPaths:{
                    form:filterPathsForView().form.slice(), status:filterPathsForView().status.slice(),
                    school:filterPathsForView().school.slice()
                },
                searchExpanded:_searchExpanded, searchQuery:_search ? String(_search.value || '') : '',
                drag:_drag && _drag.debugState(), coordinator:_coordinator.debugState()};
        },
        validateSnapshot: function(snapshot) { return validateSnapshot(snapshot, _view); }
    };
})();
