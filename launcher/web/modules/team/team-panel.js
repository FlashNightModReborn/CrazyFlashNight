(function() {
    'use strict';

    // 战队壳层 = 薄协调器：不再渲染自己的顶栏/画布（避免子面板二次缩放损失空间），
    // 而是把唯一一条 tab 条（.team-tabs）注入当前激活子视图列表页 header 的
    // .team-tabs-slot 槽位（替换原「战宠管理/佣兵管理」标题位，徽标/资源条/关闭钮
    // 由子面板自有 header 承载）。切换标签时 tab 条 DOM 整体迁移到目标子视图。
    var PET_TABS = { partner: true, pet: true, mechanical: true };
    var TABS = [
        { id: 'mercenary', label: '佣兵' },
        { id: 'partner',   label: '伙伴' },
        { id: 'pet',       label: '战宠' },
        { id: 'mechanical', label: '机械' }
    ];
    var _el;
    var _tabsEl = null;
    var _activeTab = null;
    var _activeController = null;
    var _lastTab = 'partner';
    var _views = {};
    // 世界内雇佣候选（NPC 处，旧 Symbol 2035 的 web 等价）：改为「置顶在 roster 顶部的真·战队卡」
    // 的内聚式设计——玩家可与现役队员比较、满员先解雇腾位。候选下发给 kind 匹配的控制器置顶渲染，
    // 不再是壳层独立浮层。整段写操作（world_hire/world_adopt）在控制器内走各自通道。
    var _hireCandidate = null;

    Panels.register('team', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
        onClose: onClose
    });

    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'team-host';
        _el.innerHTML =
            '<div class="team-view" data-view="mercenary"></div>' +
            '<div class="team-view" data-view="partner"></div>';

        _views.mercenary = _el.querySelector('[data-view="mercenary"]');
        _views.pet = _el.querySelector('[data-view="partner"]');
        var mercEl = MercTeamController.create(_views.mercenary);
        var petEl = PetTeamController.create(_views.pet);
        _views.mercenary.appendChild(mercEl);
        _views.pet.appendChild(petEl);

        _tabsEl = document.createElement('nav');
        _tabsEl.className = 'team-tabs';
        _tabsEl.setAttribute('aria-label', '战队分类');
        var html = '';
        for (var i = 0; i < TABS.length; i++) {
            html += '<button class="team-tab" type="button" data-tab="' + TABS[i].id + '">' + TABS[i].label + '</button>';
        }
        _tabsEl.innerHTML = html;
        var tabs = _tabsEl.querySelectorAll('.team-tab');
        for (var t = 0; t < tabs.length; t++) {
            tabs[t].addEventListener('click', function() { switchTab(this.dataset.tab); });
        }

        container.appendChild(_el);
        return _el;
    }

    function onOpen(el, initData) {
        ensureCss();
        window.TeamPanelHost = { requestClose: requestClose };
        // 世界内雇佣：携 {view:'hire', kind, detail} → 切到 kind 对应 tab，候选置顶进 roster
        // （非独立浮层；玩家可与现役比较、满员先解雇）。控制器据 hireCandidate 渲染置顶候选卡。
        if (initData && initData.view === 'hire' && initData.detail) {
            _hireCandidate = initData.detail;
            switchTab(initData.initialTab || (initData.kind === 'pet' ? 'partner' : 'mercenary'), true);
            return;
        }
        switchTab(initData && initData.initialTab ? initData.initialTab : _lastTab, true);
    }

    function controllerFor(tab) {
        return PET_TABS[tab] ? PetTeamController : MercTeamController;
    }

    function switchTab(tab, initial) {
        if (!PET_TABS[tab] && tab !== 'mercenary') tab = 'partner';
        if (_activeController && _activeController.isBusy && _activeController.isBusy()) return;
        if (!initial && tab === _activeTab) {
            _activeController.resetToList();
            return;
        }
        if (_activeController) _activeController.onClose();

        _activeTab = tab;
        _lastTab = tab;
        _activeController = controllerFor(tab);
        _views.mercenary.hidden = tab !== 'mercenary';
        _views.pet.hidden = tab === 'mercenary';
        mountTabs(tab === 'mercenary' ? _views.mercenary : _views.pet);
        var tabs = _tabsEl.querySelectorAll('.team-tab');
        for (var i = 0; i < tabs.length; i++) tabs[i].classList.toggle('team-tab-active', tabs[i].dataset.tab === tab);

        // 候选只投给 kind 匹配的 tab（merc 候选→佣兵 tab；pet 候选→宠物各 tab），切走再切回不丢
        var cand = candidateFor(tab);
        if (PET_TABS[tab]) _activeController.onOpen(_views.pet.firstChild, { rosterType: tab, embedded: true, hireCandidate: cand });
        else _activeController.onOpen(_views.mercenary.firstChild, { embedded: true, hireCandidate: cand });
    }

    function candidateFor(tab) {
        if (!_hireCandidate) return null;
        var isPetTab = !!PET_TABS[tab];
        var isPetCand = _hireCandidate.kind === 'pet';
        return (isPetTab === isPetCand) ? _hireCandidate : null;
    }

    // tab 条迁移到目标子视图列表页 header 的槽位
    function mountTabs(view) {
        var slot = view.querySelector('.team-tabs-slot');
        if (slot && _tabsEl.parentNode !== slot) slot.appendChild(_tabsEl);
    }

    function requestClose() {
        if (_activeController && _activeController.isBusy && _activeController.isBusy()) return;
        Panels.close();
        Bridge.send({ type: 'panel', panel: 'team', cmd: 'close' });
    }

    function onClose() {
        if (_activeController) _activeController.onClose();
        _activeController = null;
        _activeTab = null;
        _hireCandidate = null;
        window.TeamPanelHost = null;
    }

    function ensureCss() {
        ensureLink('pet-panel-css', 'css/pet_panel.css');
        ensureLink('merc-panel-css', 'css/merc_panel.css');
        ensureLink('team-panel-css', 'css/team_panel.css');
    }

    function ensureLink(id, href) {
        if (document.getElementById(id)) return;
        var link = document.createElement('link');
        link.id = id;
        link.rel = 'stylesheet';
        link.href = href;
        document.head.appendChild(link);
    }
})();
