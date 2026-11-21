/* U7 地铁线路图：站点投影 + 目的地直接进入。C# 裁决站点准入，AS2 执行进关。 */
(function() {
    'use strict';
    var Runtime = window.SubwaySelectRuntime;
    var shell, element, scale, mux, instance, snapshot, descriptions;
    var selectedFeature, hoveredFeature;
    var phase = 'closed', busy = false, generation = 0;
    var disposers = [];
    var errors = {
        locked:'该目的地尚未解锁。',
        not_enterable:'该条目只作展示，不能从这里进入。',
        unknown_entry:'目的地已失效，请重新打开线路图。',
        pending_stage_settlement:'请先处理上一关的奖励或结算。',
        enter_refused:'暂时无法进入该关卡。',
        stage_config_unavailable:'关卡资料尚未就绪，请稍后重试。',
        stage_config_failed:'关卡资料读取失败，请重新打开线路图。',
        disconnected:'游戏连接已断开，请恢复连接后再试。',
        not_sent:'请求未能发送，请再试一次。',
        timeout:'进入结果未确认，请观察游戏状态后再操作。',
        client_timeout:'进入结果未确认，请观察游戏状态后再操作。',
        malformed_response:'暂时无法确认进入结果，请观察游戏状态。',
        busy:'上一个进入请求仍在处理中。',
        panel_instance_expired:'面板已失效，请从隧道据点重新打开。'
    };
    function byId(id) { return element.querySelector('#subway-' + id); }
    function cue(name) { if (window.BootstrapAudio) window.BootstrapAudio.cue(name); }
    function status(text) { if (element) byId('status').textContent = text; }
    function listen(node, event, handler) {
        node.addEventListener(event, handler);
        disposers.push(function() { node.removeEventListener(event, handler); });
    }
    function create() { shell = document.createElement('div'); shell.className = 'panel-scale-shell appearance-service-shell stage-door-shell subway-scale-shell'; return shell; }
    function onOpen(host, data) {
        generation++; instance = data.panelInstanceId; snapshot = null;
        selectedFeature = hoveredFeature = descriptions = null;
        phase = 'loading'; busy = false; disposers = [];
        host.innerHTML = '<section class="appearance-service-panel stage-door-panel subway-panel">'
            + '<button class="appearance-service-close" id="subway-close" aria-label="关闭">×</button>'
            + '<main class="stage-door-body"><div class="subway-map">'
            + '<img class="subway-map-art" src="assets/subway/route-map.svg" alt="尘都市区地铁运行路线图" draggable="false">'
            + '<div class="subway-route-layer" id="subway-route-layer"></div>'
            + '<ol class="subway-stations" id="subway-stations" aria-label="线路站点"></ol></div>'
            + '<section class="subway-destinations" aria-label="目的地"><h2>目的地</h2>'
            + '<div class="stage-door-entries" id="subway-entries" role="list"></div></section></main>'
            + '<footer class="appearance-service-footer"><div class="subway-feature-info">'
            + '<h2 id="subway-feature-title">站点 / 线路介绍</h2><p id="subway-feature-text">点击站点或线路查看介绍。</p></div>'
            + '<p class="stage-door-status" id="subway-status" role="status" aria-live="polite">正在读取线路…</p></footer></section>';
        element = host;
        scale = window.PanelScale.attach(shell, 1024, 576);
        mux = new Runtime.RequestMux({send:function(message) { return Bridge.send(message); }, panelInstanceId:instance});
        listen(byId('close'), 'click', requestClose);
        loadDescriptions();
        loadRouteInteractions();
        readSnapshot();
    }
    function loadDescriptions() {
        var opened = generation;
        fetch('assets/subway/descriptions.json').then(function(response) {
            if (!response.ok) throw new Error('descriptions_unavailable');
            return response.json();
        }).then(function(data) {
            if (opened !== generation || !data || data.version !== 1) return;
            descriptions = data; showDescription();
        }).catch(function() { });
    }
    function loadRouteInteractions() {
        var opened = generation;
        fetch('assets/subway/route-interactions.svg').then(function(response) {
            if (!response.ok) throw new Error('route_interactions_unavailable');
            return response.text();
        }).then(function(source) {
            if (opened !== generation) return;
            var documentNode = new DOMParser().parseFromString(source, 'image/svg+xml');
            if (documentNode.querySelector('parsererror')) return;
            var svg = document.importNode(documentNode.documentElement, true);
            svg.setAttribute('class', 'subway-route-interactions');
            byId('route-layer').appendChild(svg);
            svg.querySelectorAll('.subway-route').forEach(function(route) {
                var feature = {type:'route', id:route.getAttribute('data-route')};
                bindFeature(route, feature);
            });
            listen(svg, 'mousemove', function(event) {
                var route = event.target.closest('.subway-route');
                setHovered(route ? {type:'route', id:route.getAttribute('data-route')} : null);
            });
            listen(svg, 'mouseleave', function() { setHovered(null); });
            refreshRouteColors(); updateFeatureStates();
        }).catch(function() { });
    }
    function bindFeature(node, feature) {
        listen(node, 'focus', function() { setHovered(feature); });
        listen(node, 'blur', function() { setHovered(null); });
        listen(node, 'click', function() { selectFeature(feature); });
        listen(node, 'keydown', function(event) {
            if (event.key !== 'Enter' && event.key !== ' ') return;
            event.preventDefault(); selectFeature(feature);
        });
        node.setAttribute('aria-pressed', 'false');
    }
    function setHovered(feature) {
        if (sameFeature(hoveredFeature, feature) || (!hoveredFeature && !feature)) return;
        hoveredFeature = feature; updateFeatureStates();
    }
    function selectFeature(feature) {
        selectedFeature = feature; updateFeatureStates(); showDescription();
    }
    function sameFeature(left, right) {
        return !!left && !!right && left.type === right.type && left.id === right.id;
    }
    function updateFeatureStates() {
        if (!element) return;
        var visibleStations = {};
        [hoveredFeature, selectedFeature].forEach(function(feature) {
            if (!feature) return;
            if (feature.type === 'station') { visibleStations[feature.id] = true; return; }
            var route = element.querySelector('.subway-route[data-route="' + feature.id + '"]');
            if (!route) return;
            var contacts = route.getAttribute('data-contacts');
            if (contacts) contacts.split(' ').forEach(function(id) { visibleStations[id] = true; });
        });
        element.querySelectorAll('.subway-station').forEach(function(station) {
            var id = station.getAttribute('data-station');
            var selected = sameFeature(selectedFeature, {type:'station', id:id});
            station.classList.toggle('selected', selected);
            station.classList.toggle('hovered', sameFeature(hoveredFeature, {type:'station', id:id}));
            station.classList.toggle('is-name-visible', visibleStations[id] === true);
            station.setAttribute('aria-pressed', selected ? 'true' : 'false');
        });
        element.querySelectorAll('.subway-route').forEach(function(route) {
            var id = route.getAttribute('data-route');
            var selected = sameFeature(selectedFeature, {type:'route', id:id});
            route.classList.toggle('selected', selected);
            route.classList.toggle('hovered', sameFeature(hoveredFeature, {type:'route', id:id}));
            route.setAttribute('aria-pressed', selected ? 'true' : 'false');
        });
    }
    function showDescription() {
        if (!element) return;
        var fallback = descriptions && descriptions.default;
        var title = fallback && fallback.title || '站点 / 线路介绍';
        var text = fallback && fallback.description || '点击站点或线路查看介绍。';
        if (selectedFeature && descriptions) {
            var group = descriptions[selectedFeature.type === 'station' ? 'stations' : 'routes'];
            var item = group && group[selectedFeature.id];
            if (item) {
                title = item.title || title;
                text = item.description || (selectedFeature.type === 'station' ? '该站点介绍待补充。' : '该线路介绍待补充。');
            }
        }
        byId('feature-title').textContent = title;
        byId('feature-text').textContent = text;
    }
    function refreshRouteColors() {
        if (!snapshot || !element) return;
        var unlocked = {};
        snapshot.stations.forEach(function(station) { unlocked[station.id] = station.frame > 1; });
        element.querySelectorAll('.subway-route').forEach(function(route) {
            var value = route.getAttribute('data-requires');
            var required = value ? value.split(' ') : [];
            var colored = required.length > 0 && required.every(function(id) { return unlocked[id] === true; });
            route.setAttribute('data-unlocked', colored ? 'true' : 'false');
            route.querySelectorAll('.subway-route-line').forEach(function(path) {
                path.setAttribute('stroke', colored ? path.getAttribute('data-color') : '#6A6769');
            });
        });
    }
    function stationSymbol(station) {
        var status = {1:'情况未知', 2:'站点损坏', 3:'待清理', 4:'已控制'};
        var dot = document.createElement('li');
        dot.className = 'subway-station' + (station.locked ? ' locked' : '');
        dot.setAttribute('data-station', station.id);
        dot.setAttribute('data-frame', station.frame);
        var mark = document.createElement('img');
        mark.className = 'subway-station-dot'; mark.src = 'assets/subway/station-' + station.frame + '.svg';
        mark.alt = ''; mark.draggable = false; mark.setAttribute('aria-hidden', 'true');
        var name = document.createElement('span'); name.className = 'subway-station-name'; name.textContent = station.name;
        dot.appendChild(mark); dot.appendChild(name);
        dot.setAttribute('aria-label', station.name + '（' + status[station.frame] + '）');
        dot.setAttribute('role', 'button'); dot.tabIndex = 0;
        dot.title = station.name + ' · ' + status[station.frame];
        listen(dot, 'mouseenter', function() { setHovered({type:'station', id:station.id}); });
        listen(dot, 'mouseleave', function() { setHovered(null); });
        bindFeature(dot, {type:'station', id:station.id});
        return dot;
    }
    function entryCard(entry) {
        var card = document.createElement('article');
        card.className = 'stage-door-entry' + (entry.highlighted ? ' highlighted' : '');
        card.setAttribute('role', 'listitem');
        var title = document.createElement('span'); title.className = 'stage-door-entry-name'; title.textContent = entry.name;
        card.appendChild(title);
        if (entry.description) {
            var description = document.createElement('span'); description.className = 'stage-door-entry-description';
            description.textContent = entry.description; card.appendChild(description);
        }
        var actions = document.createElement('div'); actions.className = 'stage-door-entry-actions';
        if (entry.enterable) {
            var badge = document.createElement('span'); badge.className = 'stage-door-entry-difficulty';
            badge.textContent = entry.difficulty; actions.appendChild(badge);
            var enter = document.createElement('button'); enter.type = 'button';
            enter.className = 'appearance-service-button primary subway-entry-enter';
            enter.textContent = '进入'; enter.disabled = busy;
            listen(enter, 'click', function() { beginEnter(entry); });
            actions.appendChild(enter);
        } else {
            card.classList.add('display-only');
            var note = document.createElement('span'); note.className = 'stage-door-entry-note';
            note.textContent = '仅记录'; actions.appendChild(note);
        }
        card.appendChild(actions);
        return card;
    }
    function refresh() {
        if (!element || !snapshot) return;
        var stations = byId('stations'); stations.textContent = '';
        snapshot.stations.forEach(function(station) { stations.appendChild(stationSymbol(station)); });
        refreshRouteColors(); updateFeatureStates();
        var list = byId('entries'); list.textContent = '';
        if (!snapshot.entries.length) {
            var empty = document.createElement('p'); empty.className = 'stage-door-empty';
            empty.textContent = '当前没有可用目的地。'; list.appendChild(empty);
        }
        snapshot.entries.forEach(function(entry) { list.appendChild(entryCard(entry)); });
        updateEnterButtons();
    }
    function updateEnterButtons() {
        if (!element) return;
        element.querySelectorAll('.subway-entry-enter').forEach(function(button) { button.disabled = busy; });
    }
    function readSnapshot() {
        phase = 'loading'; status('正在读取线路…');
        request('snapshot', {v:1}, function(result) {
            var state = Runtime.normalizeState(result);
            if (state) {
                snapshot = state; phase = 'editing';
                status(''); refresh();
                return;
            }
            phase = 'error';
            status(errors[result && result.error] || '线路资料暂时不可用，请重新打开。');
        });
    }
    function beginEnter(entry) {
        if (busy || phase !== 'editing') return;
        cue('activate');
        status('正在进入 ' + entry.name + '…');
        request('enter', {v:1, entryId:entry.id}, function(result) {
            var outcome = Runtime.normalizeEnter(result);
            if (outcome && outcome.success) { requestClose(); return; }
            if (result && result.enterUnknown) {
                status('进入结果未确认，请观察游戏状态后再操作。');
            } else {
                status(errors[outcome && outcome.error || result && result.error] || '暂时无法进入该关卡。');
            }
        });
    }
    function request(cmd, payload, callback) {
        if (busy || !mux) return;
        var opened = generation;
        busy = true; updateEnterButtons();
        mux.request(cmd, payload, function(result) {
            if (opened !== generation || phase === 'closed') return;
            busy = false; updateEnterButtons(); callback(result);
        });
    }
    function requestClose() {
        if (busy || phase === 'closed') return false;
        var sent = false;
        try { sent = Bridge.send({type:'panel', panel:'subway', cmd:'close', panelInstanceId:instance}) !== false; } catch (_) { }
        if (!sent) { status('关闭请求未能发送，请再试一次。'); return false; }
        cue('back'); Panels.close(); return true;
    }
    function cleanup() {
        generation++; phase = 'closed'; busy = false; snapshot = null;
        selectedFeature = hoveredFeature = descriptions = null;
        disposers.forEach(function(dispose) { dispose(); }); disposers = [];
        if (mux) mux.destroy(); if (scale) scale.detach();
        mux = scale = null; instance = ''; element = null;
        if (shell) shell.textContent = '';
    }
    Panels.register('subway', {create:create, onOpen:onOpen, onClose:cleanup, onRequestClose:requestClose, onForceClose:cleanup});
    window.SubwaySelectPanel = {debugState:function() { return {phase:phase, busy:busy, state:snapshot, instance:instance, selected:selectedFeature}; }};
})();
