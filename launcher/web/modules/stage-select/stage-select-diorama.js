/* 单座废城：总览/特写/取景共用一个缓存，仅在交互和过渡时出帧。 */
var StageSelectDiorama = (function() {
    'use strict';
    var moduleUrl = new URL('./stage-select-diorama-scene.js', document.currentScript.src).href;
    var S = StageSelectCore.state;
    var cache = null, pending = null, mount = null, active = false, failed = false;
    var generation = 0;
    var focused = '', focusHost = null;
    var presets = {};
    try { presets = JSON.parse(localStorage.getItem('cf7.stage-camera.base-gate.v1') || '{}'); } catch (_) {}

    if (!presets || typeof presets !== 'object' || Array.isArray(presets)) presets={};

    function changed() {
        if (!active || !cache || focused) return;
        S._visualStagePoints = cache.view.pins();
        S._buttonLayerEl.querySelectorAll('.stage-select-stage-button').forEach(function(node) {
            var pin=S._visualStagePoints[node.dataset.stageId];
            if (pin) {
                var anchor=S._cardLayerEl.querySelector('[data-stage-id="'+node.dataset.stageId+'"]');
                place({id:node.dataset.stageId},node,anchor,parseFloat(node.style.getPropertyValue('--stage-card-height')) || 240);
            }
        });
    }
    function preset(key) { return cache && cache.view.valid(presets[key]) ? presets[key] : null; }

    function supports(frame) {
        return !StageSelectData.getManifest().testOnly && frame.frameLabel === StageSelectDioramaData.frameLabel;
    }
    function status(message, retry) {
        if (!mount) return;
        var el = mount.querySelector('.stage-select-diorama-status');
        el.hidden = !message;
        el.querySelector('span').textContent = message || '';
        el.querySelector('button').hidden = !retry;
        mount.dataset.state = message ? (retry ? 'error' : 'loading') : 'ready';
        // 模型未准备好时保留关闭/区域菜单，入口层不接收误操作。
        var touring=window.StageSelectCameraEditor && StageSelectCameraEditor.isOpen();
        S._buttonLayerEl.inert = !!message || !!touring;
        if (S._cardLayerEl) S._cardLayerEl.inert = !!message || !!touring;
        if (window.StageSelectCameraEditor) StageSelectCameraEditor.refreshButtons();
    }
    function contextLost() {
        failed = true;
        if (cache) cache.view.stop();
        if (window.StageSelectCameraEditor) StageSelectCameraEditor.hide();
        if (active && focused) StageSelectInspector.clearSelection();
        if (active) status('废城画面暂时中断，请重试。', true);
    }
    function ensure() {
        if (pending) return pending;
        var token = generation;
        pending = import(moduleUrl).then(function(module) {
            return module.createScene(StageSelectDioramaData, contextLost, changed);
        }).then(function(scene) {
            if (token !== generation) { scene.dispose(); return null; }
            cache = scene;
            return scene;
        }).finally(function() { if (token === generation) pending = null; });
        return pending;
    }
    function show() {
        if (cache && !failed) {
            if (!focused) {
                mount.prepend(cache.canvas);
                cache.view.resize(1024,576);
                if (!StageSelectCameraEditor.isOpen()) cache.view.overview(preset('overview'),false);
                else cache.render();
            } else cache.render();
            status('', false);
            return;
        }
        status('正在载入废城…', false);
        ensure().then(function(scene) {
            if (!active || !scene) return;
            mount.prepend(scene.canvas);
            scene.view.overview(preset('overview'),false);
            status('', false);
            if (S._selectedStageId) StageSelectInspector.renderInspector();
        }).catch(function(error) {
            if (!active) return;
            failed = true;
            status('废城画面未能载入，请重试。', true);
            StageSelectCore.logDev('diorama: ' + error.message);
        });
    }
    function retry() {
        if (pending) return;
        if (cache) cache.dispose();
        cache = null;
        failed = false;
        generation++;
        show();
    }
    function bind(frame) {
        active = supports(frame);
        S._visualStagePoints = active ? (cache && !focused ? cache.view.pins() : StageSelectDioramaData.pins) : null;
        S._el.classList.toggle('is-diorama', active);
        if (!active) { hide(); return; }
        if (!mount) {
            mount = document.createElement('div');
            mount.className = 'stage-select-diorama';
            mount.innerHTML = '<div class="stage-select-diorama-status" role="status"><span></span><button type="button" data-audio-cue="confirm">重试</button></div>';
            mount.querySelector('button').addEventListener('click', retry);
        }
        S._stageEl.prepend(mount);
        mount.hidden = false;
        if (failed && cache) { status('废城画面暂时中断，请重试。', true); return; }
        show();
    }
    function hide() {
        active = false;
        focused = ''; focusHost = null;
        if (cache) { cache.view.stop(); cache.view.edit(false); }
        if (window.StageSelectCameraEditor) StageSelectCameraEditor.hide();
        if (mount) mount.hidden = true;
        if (S._buttonLayerEl) S._buttonLayerEl.inert = false;
        if (S._cardLayerEl) S._cardLayerEl.inert = false;
    }
    function focus(id, host) {
        if (!active || !cache || failed) return;
        var changedFocus=focused !== id;
        focused=id; focusHost=host;
        host.appendChild(cache.canvas);
        cache.view.resize(host.clientWidth,host.clientHeight);
        if (changedFocus) cache.view.focus(id,preset(id),!S._el.classList.contains('is-camera-editing'));
        else cache.render();
    }
    function overview() {
        if (!focused) return;
        focused=''; focusHost=null;
        if (!cache) return;
        mount.prepend(cache.canvas); cache.view.resize(1024,576);
        if (active && !failed) cache.view.overview(preset('overview'));
        else cache.view.stop();
    }
    function edit(enabled) { return cache ? cache.view.edit(enabled) : Promise.resolve(); }
    function exportPresets() {
        if (!cache) return;
        var value=cache.view.snapshot();
        if (!cache.view.valid(value)) throw new Error('当前取景超出可保存范围，请恢复默认取景后调整。');
        var result=Object.assign({},presets);result[focused || 'overview']=value;
        return result;
    }
    function savePreset() {
        if (!cache) return;
        presets=exportPresets();
        localStorage.setItem('cf7.stage-camera.base-gate.v1',JSON.stringify(presets));
        return presets;
    }
    function loadPresets(value) {
        if (!value || Array.isArray(value) || typeof value !== 'object' || !cache) throw new Error('预设内容无效');
        Object.keys(value).forEach(function(key) {
            if ((key !== 'overview' && !Object.prototype.hasOwnProperty.call(StageSelectDioramaData.pins,key)) || !cache.view.valid(value[key])) throw new Error('预设内容无效：'+key);
        });
        presets=value; localStorage.setItem('cf7.stage-camera.base-gate.v1',JSON.stringify(presets));
        if (focused) cache.view.focus(focused,preset(focused),false); else cache.view.overview(preset('overview'),false);
    }
    function place(button, node, anchor, cardHeight) {
        var pin = S._visualStagePoints && S._visualStagePoints[button.id];
        if (!pin) return;
        node.style.left = pin.x + 'px';
        node.style.top = pin.y + 'px';
        node.style.width = '40px';
        node.style.minHeight = '40px';
        node.style.setProperty('--diorama-label-x', pin.labelX + 'px');
        node.style.setProperty('--diorama-label-y', pin.labelY + 'px');
        if (anchor) {
            // 独立卡片在固定舞台内钳制，不沿用旧 Flash 元件的 133.7px 偏移。
            var width = parseFloat(anchor.style.getPropertyValue('--stage-card-width')) || 167;
            var left = pin.x-width/2;
            var top = Math.min(pin.y-20, pin.y+pin.labelY-16)-cardHeight-6;
            if (top < 54) {
                top = Math.max(pin.y+20, pin.y+pin.labelY+16)+6;
                if (top+cardHeight > 568) {
                    // 上下空间不足时放在侧面，避免卡片升层后遮住自己的点击入口。
                    left = pin.x+Math.max(20, pin.labelX+70)+6;
                    if (left+width > 1016) left = pin.x+Math.min(-20, pin.labelX-70)-width-6;
                    top = pin.y-cardHeight/2;
                }
            }
            anchor.style.left = Math.max(8, Math.min(1024-width-8, left)) + 'px';
            anchor.style.top = Math.max(54, Math.min(576-cardHeight-8, top)) + 'px';
        }
    }
    window.addEventListener('pagehide', function() {
        active = false;
        generation++;
        if (cache) cache.dispose();
        cache = null;
    });
    return { bind: bind, hide: hide, place: place, retry: retry,focus:focus,overview:overview,edit:edit,
        savePreset:savePreset,loadPresets:loadPresets,exportPresets:exportPresets,
        snapshotCamera:function() { return cache ? cache.view.snapshot() : null; },
        restoreCamera:function(value) {
            if(!active || !cache || failed || !cache.view.valid(value))return;
            if(focused)cache.view.focus(focused,value,false);else cache.view.overview(value,false);
        },
        hover:function(id) { if(active&&cache&&!failed)cache.view.hover(id); },
        resetCamera:function() { if(cache) { if(focused)cache.view.focus(focused,null,false);else cache.view.overview(null,false); } },
        stats: function() { return Object.assign({ active: active, pending: !!pending, failed: failed,
            state: mount && mount.dataset.state || 'empty' }, cache ? cache.stats() : {}); } };
})();
