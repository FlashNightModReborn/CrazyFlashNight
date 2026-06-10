(function() {
    'use strict';

    var DESIGN_W = 1024;
    var DESIGN_H = 576;
    var PET_TABS = { partner: true, pet: true, mechanical: true };
    var _el;
    var _activeTab = null;
    var _activeController = null;
    var _lastTab = 'partner';
    var _resizeObserver = null;
    var _views = {};

    Panels.register('team', {
        create: createDOM,
        onOpen: onOpen,
        onRequestClose: requestClose,
        onClose: onClose
    });

    function createDOM(container) {
        _el = document.createElement('div');
        _el.className = 'team-scale-root';
        _el.innerHTML =
            '<div class="team-scale-shell"><section class="team-panel">' +
                '<header class="team-header">' +
                    '<div class="team-title"><span class="team-title-mark"></span><span>战队</span></div>' +
                    '<nav class="team-tabs" aria-label="战队分类">' +
                        tabHtml('mercenary', '佣兵') + tabHtml('partner', '伙伴') +
                        tabHtml('pet', '战宠') + tabHtml('mechanical', '机械') +
                    '</nav>' +
                    '<button class="team-close" type="button" aria-label="关闭">×</button>' +
                '</header>' +
                '<div class="team-content">' +
                    '<div class="team-view" data-view="mercenary"></div>' +
                    '<div class="team-view" data-view="partner"></div>' +
                '</div>' +
            '</section></div>';

        _views.mercenary = _el.querySelector('[data-view="mercenary"]');
        _views.pet = _el.querySelector('[data-view="partner"]');
        var mercEl = MercTeamController.create(_views.mercenary);
        var petEl = PetTeamController.create(_views.pet);
        _views.mercenary.appendChild(mercEl);
        _views.pet.appendChild(petEl);

        _el.querySelector('.team-close').addEventListener('click', requestClose);
        var tabs = _el.querySelectorAll('.team-tab');
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].addEventListener('click', function() { switchTab(this.dataset.tab); });
        }
        container.appendChild(_el);
        return _el;
    }

    function tabHtml(id, label) {
        return '<button class="team-tab" type="button" data-tab="' + id + '">' + label + '</button>';
    }

    function onOpen(el, initData) {
        ensureCss();
        bindScale();
        window.TeamPanelHost = { requestClose: requestClose };
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
        var tabs = _el.querySelectorAll('.team-tab');
        for (var i = 0; i < tabs.length; i++) tabs[i].classList.toggle('team-tab-active', tabs[i].dataset.tab === tab);

        if (PET_TABS[tab]) _activeController.onOpen(_views.pet.firstChild, { rosterType: tab, embedded: true });
        else _activeController.onOpen(_views.mercenary.firstChild, { embedded: true });
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
        window.TeamPanelHost = null;
        unbindScale();
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

    function updateScale() {
        if (!_el) return;
        var w = _el.clientWidth || 0;
        var h = _el.clientHeight || 0;
        var scale = Math.min(w / DESIGN_W, h / DESIGN_H);
        _el.style.setProperty('--team-scale', (isFinite(scale) && scale > 0 ? scale : 1).toFixed(4));
    }

    function bindScale() {
        unbindScale();
        window.addEventListener('resize', updateScale);
        if (typeof ResizeObserver !== 'undefined') {
            _resizeObserver = new ResizeObserver(updateScale);
            _resizeObserver.observe(_el);
        }
        updateScale();
    }

    function unbindScale() {
        window.removeEventListener('resize', updateScale);
        if (_resizeObserver) _resizeObserver.disconnect();
        _resizeObserver = null;
    }
})();
