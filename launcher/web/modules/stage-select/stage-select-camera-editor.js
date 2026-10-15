/* 玩家游览与开发取景共用操作；只有显式保存/导入才持久化视觉预设。 */
var StageSelectCameraEditor = (function() {
    'use strict';
    var S=StageSelectCore.state, panel, note, output, body, presetArea, enabled=false, developer=false, entryCamera=null;
    var toggles=[], tourCursor=-1;
    function refreshButtons() {
        var available=S._el && S._el.classList.contains('is-diorama')
            && (!S._selectedStageId || StageSelectDiorama.canFocus(S._selectedStageId));
        toggles.forEach(function(el) {
            el.hidden=!available; el.disabled=!available || StageSelectDiorama.stats().state!=='ready';
            el.textContent=enabled ? '结束游览' : el.dataset.tourLabel;
            el.setAttribute('aria-pressed',String(enabled));
        });
    }
    function createToggle(label) {
        var el=document.createElement('button');el.type='button';el.className='stage-camera-toggle stage-focus-action';
        el.dataset.tourLabel=label || '游览地图';el.dataset.audioCue='select';
        el.addEventListener('click',function(e){e.stopPropagation();if(enabled)hide();else show(false);});
        toggles.push(el);refreshButtons();return el;
    }
    function collapse(value) {
        body.hidden=value;panel.classList.toggle('is-collapsed',value);
        var toggle=panel.querySelector('[data-camera="collapse"]');
        toggle.textContent=value ? '展开' : '收起';toggle.setAttribute('aria-expanded',String(!value));
        if(value)toggle.focus();
    }
    function syncTourPinToggle() {
        if(!panel)return;
        var pinBtn=panel.querySelector('[data-camera="toggle-pins"]');
        if(pinBtn){
            pinBtn.setAttribute('aria-pressed',String(!!S._tourPinsVisible));
            pinBtn.classList.toggle('is-active',!!S._tourPinsVisible);
        }
        if(S._el)S._el.classList.toggle('is-tour-pins-visible',!!(enabled && S._tourPinsVisible));
    }
    function stepPoi(delta) {
        var ids=StageSelectDiorama.getTourStageIds ? StageSelectDiorama.getTourStageIds() : [];
        if(!ids.length)return;
        if(tourCursor<0){
            var currentFocus=StageSelectDiorama.stats().focusId || S._selectedStageId || '';
            var foundIdx=ids.indexOf(currentFocus);
            tourCursor=foundIdx>=0 ? foundIdx : (delta>0 ? -1 : 0);
        }
        tourCursor=(tourCursor+delta+ids.length)%ids.length;
        var targetId=ids[tourCursor];
        if(StageSelectDiorama.peekStage && StageSelectDiorama.peekStage(targetId)){
            var btn=StageSelectViewModel.findStageButtonById(targetId);
            var label=btn ? StageSelectViewModel.getStageDisplayName(btn) : targetId;
            note.textContent='侦察定位 ['+(tourCursor+1)+'/'+ids.length+']：'+label+' — 结束游览后恢复原视角。';
        }
    }
    function hide() {
        var restore=enabled && !developer ? entryCamera : null;
        enabled=false;tourCursor=-1;S._tourPinsVisible=false;
        if(panel)panel.hidden=true;
        if(S._el){
            S._el.classList.remove('is-camera-editing');
            S._el.classList.remove('is-tour-pins-visible');
        }
        StageSelectDiorama.edit(false);
        if(restore)StageSelectDiorama.restoreCamera(restore);
        entryCamera=null;
        [S._buttonLayerEl,S._cardLayerEl,S._navLayerEl].forEach(function(el){if(el)el.inert=StageSelectInspector.isInspectorOpen();});
        refreshButtons();
    }
    function ensure() {
        if(panel)return;
        panel=document.createElement('div');panel.className='stage-camera-editor';
        panel.innerHTML='<div class="stage-camera-heading"><strong></strong><button data-camera="collapse" aria-expanded="true">收起</button><button data-camera="close">结束游览</button></div><div class="stage-camera-body"><span>左键旋转 · WASD / 方向键移动 · 滚轮缩放 · Shift 加速</span><div class="stage-camera-actions"><button data-camera="prev-poi">◀ 上一地标</button><button data-camera="next-poi">下一地标 ▶</button><button data-camera="toggle-pins" aria-pressed="false">◎ 地标标签</button><button data-camera="save">保存当前预设</button><button data-camera="reset">默认取景</button><button data-camera="export">导出预设</button><button data-camera="import">导入预设</button></div><div class="stage-camera-presets" hidden><div class="stage-camera-preset-heading"><span>镜头预设</span><button data-camera="fold-presets">收起预设</button></div><textarea aria-label="镜头预设 JSON"></textarea></div><span role="status"></span></div>';
        panel.querySelectorAll('button').forEach(function(el){el.type='button';});
        body=panel.querySelector('.stage-camera-body');note=panel.querySelector('[role="status"]');output=panel.querySelector('textarea');presetArea=panel.querySelector('.stage-camera-presets');
        panel.addEventListener('click',function(e){
            e.stopPropagation();var btn=e.target.closest ? e.target.closest('button[data-camera]') : e.target;
            var action=btn && btn.dataset ? btn.dataset.camera : '';
            try {
                if(action==='close'){hide();return;}
                if(action==='collapse'){collapse(!body.hidden);return;}
                if(action==='prev-poi'){stepPoi(-1);return;}
                if(action==='next-poi'){stepPoi(1);return;}
                if(action==='toggle-pins'){S._tourPinsVisible=!S._tourPinsVisible;syncTourPinToggle();return;}
                if(action==='fold-presets'){presetArea.hidden=true;panel.querySelector('[data-camera="export"]').focus();return;}
                if(action==='save'){StageSelectDiorama.savePreset();note.textContent='已保存到本机，重新打开选关仍可使用。';}
                if(action==='reset'){
                    tourCursor=-1;
                    if(developer)StageSelectDiorama.resetCamera();else StageSelectDiorama.restoreCamera(entryCamera);
                    StageSelectDiorama.edit(true).catch(showError);
                    if(!developer)note.textContent='已恢复初始视角 — 结束游览后恢复原视角。';
                }
                if(action==='export'){presetArea.hidden=false;output.value=JSON.stringify(StageSelectDiorama.exportPresets(),null,2);output.focus();output.select();note.textContent='预设已选中，可复制保存；可收起文本或整个工具栏继续取景。';}
                if(action==='import'){
                    if(presetArea.hidden){presetArea.hidden=false;output.value='';output.focus();note.textContent='粘贴预设后，再点击导入。';}
                    else{StageSelectDiorama.loadPresets(JSON.parse(output.value));StageSelectDiorama.edit(true).catch(showError);note.textContent='预设已载入并保存。';}
                }
            } catch(error){showError(error);}
        });
        panel.addEventListener('keydown',function(e){if(e.key==='Escape'){e.preventDefault();e.stopPropagation();hide();}});
    }
    function showError(error){note.textContent=error.message;}
    function show(asDeveloper) {
        if(!S._el || !S._el.classList.contains('is-diorama') || StageSelectDiorama.stats().state!=='ready'
            || !StageSelectDiorama.canFocus(S._selectedStageId))return;
        ensure();
        if(!enabled)entryCamera=StageSelectDiorama.snapshotCamera();
        developer=asDeveloper!==false;enabled=true;tourCursor=-1;S._tourPinsVisible=false;
        S._stageEl.appendChild(panel);panel.hidden=false;presetArea.hidden=true;collapse(false);
        panel.querySelector('strong').textContent=developer ? '镜头取景' : '地图游览';
        panel.querySelector('[data-camera="close"]').textContent=developer ? '结束取景' : '结束游览';
        ['save','export','import'].forEach(function(action){panel.querySelector('[data-camera="'+action+'"]').hidden=!developer;});
        var inOverview=!S._selectedStageId;
        ['prev-poi','next-poi','toggle-pins'].forEach(function(action){
            var el=panel.querySelector('[data-camera="'+action+'"]');
            if(el)el.hidden=developer || !inOverview;
        });
        syncTourPinToggle();
        panel.querySelector('[data-camera="reset"]').textContent=developer ? '默认取景' : '复位视角';
        note.textContent=developer ? (StageSelectDiorama.stats().focusId ? '正在调整当前关卡特写，右键也可平移。' : '正在调整废城总览，右键也可平移。') : '结束游览后恢复原视角。';
        S._el.classList.add('is-camera-editing');
        [S._buttonLayerEl,S._cardLayerEl,S._navLayerEl].forEach(function(el){if(el)el.inert=true;});
        refreshButtons();StageSelectDiorama.edit(true).catch(showError);
    }
    document.addEventListener('keydown',function(e){
        if(e.ctrlKey&&e.shiftKey&&e.code==='KeyC'&&window.Panels&&Panels.getActive()==='stage-select'){
            e.preventDefault();if(enabled&&developer)hide();else show(true);
        }
    });
    return {show:show,hide:hide,isOpen:function(){return enabled;},createToggle:createToggle,refreshButtons:refreshButtons};
})();
