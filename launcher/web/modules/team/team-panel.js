(function() {
    'use strict';

    // ── 依赖 fail-fast：缺共享层 / 子控制器直接报错，不做半初始化 ──
    if (typeof TeamShared === 'undefined'
            || typeof MercTeamController === 'undefined'
            || typeof PetTeamController === 'undefined') {
        throw new Error('team-panel.js 需要先加载 team/team-shared.js、merc-panel.js 与 pet-panel.js');
    }

    // 战队壳层 = 薄协调器：不渲染自己的顶栏/画布（避免子面板二次缩放损失空间）。
    // 两个子控制器（merc / pet）均已双栏工作台化：唯一一条 tab 条（.team-tabs）
    // 经 initData.tabNav 传给当前激活控制器，由其 _shell.addHeaderAction(tabNav)
    // 作为 header 第一个 action 注入；切换标签时子 controller 重建 Shell（对齐
    // Skills/Crafting 换 view 重建的现役模式），tab 条 DOM 随 initData 迁入新壳。
    // CSS 全量走 panels.css 静态闭包（css/workbench/team.css），无运行时注入。
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
    // 世界内雇佣候选（NPC 处，旧 Symbol 2035 的 web 等价）：「置顶在 roster 顶部的真·战队卡」
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
            '<div class="team-view" data-view="pets"></div>';

        _views.mercenary = _el.querySelector('[data-view="mercenary"]');
        _views.pets = _el.querySelector('[data-view="pets"]');
        var mercEl = MercTeamController.create(_views.mercenary);
        var petEl = PetTeamController.create(_views.pets);
        _views.mercenary.appendChild(mercEl);
        _views.pets.appendChild(petEl);

        _tabsEl = document.createElement('nav');
        _tabsEl.className = 'team-tabs';
        _tabsEl.setAttribute('aria-label', '战队分类');
        var html = '';
        for (var i = 0; i < TABS.length; i++) {
            html += '<button class="team-tab" type="button" data-tab="' + TABS[i].id + '" data-audio-cue="select">' + TABS[i].label + '</button>';
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
        if (_activeController && _activeController.isBusy && _activeController.isBusy()) {
            // 用户切换被操作锁拦下时给反馈；initial 程序化打开保持静默
            if (!initial) TeamShared.toast('操作进行中，请稍候…');
            return;
        }
        if (!initial && tab === _activeTab) {
            _activeController.resetToList();
            return;
        }
        // teardown 前记录焦点是否在 tab 条内：旧 controller onClose 会销毁承载 _tabsEl 的
        // Shell，焦点掉 BODY；新 Shell 重建后按 WAI tabs 惯例把焦点还到「新激活」tab。
        // 程序化切换（initial 打开 / 候选路由）时 activeElement 本就不在 tabs 内，不触发恢复。
        var refocusTab = !!(_tabsEl && _tabsEl.contains(document.activeElement));
        if (_activeController) _activeController.onClose();

        _activeTab = tab;
        _lastTab = tab;
        _activeController = controllerFor(tab);
        _views.mercenary.hidden = tab !== 'mercenary';
        _views.pets.hidden = tab === 'mercenary';
        var tabs = _tabsEl.querySelectorAll('.team-tab');
        for (var i = 0; i < tabs.length; i++) {
            var active = tabs[i].dataset.tab === tab;
            tabs[i].classList.toggle('team-tab-active', active);
            tabs[i].setAttribute('aria-current', active ? 'true' : 'false');
        }

        // 候选只投给 kind 匹配的 tab（merc 候选→佣兵 tab；pet 候选→宠物各 tab），切走再切回不丢；
        // tabNav 必须是子壳 header 的第一个 action
        var cand = candidateFor(tab);
        if (PET_TABS[tab]) _activeController.onOpen(_views.pets.firstChild, { rosterType: tab, embedded: true, hireCandidate: cand, tabNav: _tabsEl });
        else _activeController.onOpen(_views.mercenary.firstChild, { embedded: true, hireCandidate: cand, tabNav: _tabsEl });

        if (refocusTab) {
            var refocusEl = _tabsEl.querySelector('.team-tab[data-tab="' + tab + '"]');
            if (refocusEl) refocusEl.focus();
        }
    }

    function candidateFor(tab) {
        if (!_hireCandidate) return null;
        var isPetTab = !!PET_TABS[tab];
        var isPetCand = _hireCandidate.kind === 'pet';
        return (isPetTab === isPetCand) ? _hireCandidate : null;
    }

    function requestClose() {
        if (_activeController && _activeController.isBusy && _activeController.isBusy()) {
            // 关闭被操作锁拦下时同样给反馈，不再静默
            TeamShared.toast('操作进行中，请稍候…');
            return;
        }
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
})();
