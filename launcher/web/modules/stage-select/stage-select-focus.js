/* 共享双栏关卡详情：同一情报/操作，左侧按地图采用二维定位或三维特写。 */
var StageSelectFocus = (function() {
    'use strict';
    var S = StageSelectCore.state, shell, surface, viewport, content, footer, tabs, history;
    var selected = '', mode = '简单', tab = 'brief', current = null;
    var tooltipScope=null, contentGeneration=0;
    var escape = StageSelectCore.escapeHtml;
    function button(text, action, className) {
        var el = document.createElement('button');
        el.type = 'button'; el.textContent = text; el.className = className || 'stage-focus-action';
        el.dataset.audioCue = action === 'back' ? 'back' : 'select';
        return el;
    }
    function view(key, el) {
        return { instanceKey:key, mount:function(host) { host.appendChild(el); }, unmount:function() { el.remove(); } };
    }
    function ensure() {
        if (surface) return;
        shell = new Workbench.DualPaneShell({ profile:'stage-focus', title:'关卡详情', eyebrow:'', subtitle:'',
            slotMarkers:false, leftLabel:'地点', rightLabel:'关卡简报' });
        surface = shell.getRoot(); surface.classList.add('stage-focus-surface'); surface.hidden = true;
        S._stageEl.appendChild(surface);
        surface.addEventListener('keydown', function(e) {
            if (e.key !== 'Tab') return;
            var items=Array.from(surface.querySelectorAll('button, summary, [tabindex="0"]')).filter(function(el) {
                return !el.disabled && el.getClientRects().length && el.tabIndex >= 0;
            });
            var first=items[0], last=items[items.length-1];
            if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
            else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
        });
        var back = button('返回总览', 'back');
        back.addEventListener('click', function() { StageSelectInspector.clearSelection({restoreFocus:true}); });
        shell.addHeaderAction(back);
        shell.addHeaderAction(StageSelectCameraEditor.createToggle('游览地点'));
        var close = button('关闭选关', 'back');
        close.addEventListener('click', function() { StageSelectRenderer.requestClose(); });
        shell.addHeaderAction(close);
        viewport = document.createElement('div'); viewport.className = 'stage-focus-viewport';
        viewport.innerHTML = '<div class="stage-focus-location" aria-hidden="true"></div>';
        var panel = S._inspectorEl;
        panel.classList.add('stage-focus-panel');
        var heading = panel.querySelector('.stage-select-inspector-head');
        heading.appendChild(S._inspectorTypeEl);
        S._inspectorCloseEl.hidden = true;
        history = document.createElement('div'); history.className = 'stage-focus-history'; history.dataset.slot='stage-records';
        tabs = document.createElement('div'); tabs.className = 'stage-focus-tabs'; tabs.setAttribute('role','tablist');
        [['brief','简报'],['intel','情报']].forEach(function(pair) {
            var item = button(pair[1]); item.dataset.focusTab = pair[0]; item.setAttribute('role','tab');
            item.id = 'stage-focus-tab-'+pair[0]; item.setAttribute('aria-controls','stage-focus-content');
            item.addEventListener('click', function() { tab = pair[0]; renderContent(); });
            item.addEventListener('keydown', function(e) {
                if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
                e.preventDefault(); e.stopPropagation();
                var next = tabs.querySelector('[data-focus-tab="'+(pair[0] === 'brief' ? 'intel' : 'brief')+'"]');
                next.click(); next.focus();
            });
            tabs.appendChild(item);
        });
        content = document.createElement('div'); content.className = 'stage-focus-content';
        content.id = 'stage-focus-content'; content.tabIndex = 0; content.setAttribute('role','tabpanel');
        var topbar=document.createElement('div');topbar.className='stage-focus-topbar';
        topbar.append(heading,history,tabs);
        footer = document.createElement('div'); footer.className = 'stage-focus-footer';
        var label = document.createElement('div'); label.className = 'stage-focus-section-title'; label.textContent = '出战难度';
        var enter = button('出发', null, 'stage-focus-enter'); enter.id = 'stage-focus-enter'; enter.dataset.audioCue = '';
        enter.addEventListener('click', function() {
            if (current) StageSelectInspector.requestStageActivation(current.button, mode, enter);
        });
        footer.append(label, S._inspectorDiffEl, enter);
        S._inspectorDiffEl.setAttribute('aria-label','出战难度');
        panel.replaceChildren(topbar, S._inspectorTaskEl, S._inspectorLockEl, content, footer);
        shell.mountInitial(view('stage-focus-scene',viewport), view('stage-focus-information',panel));
    }
    function historyFor(state) {
        var value = state.clearHistory;
        return value && value.cleared === true && Array.isArray(value.difficulties) && value.difficulties.length ? value : null;
    }
    function releaseContent() {
        contentGeneration++;
        if(tooltipScope)tooltipScope.dispose();tooltipScope=null;
    }
    function tip(node,text) {
        tooltipScope.bindAsync(node,{key:text,item:text,renderBasic:function(value){return '<b>'+escape(value)+'</b>';}});
    }
    function iconToken(name,kind) {
        var node=button('',null,'stage-focus-token stage-focus-'+kind);node.setAttribute('aria-label',name);
        node.innerHTML=kind==='enemy'
            ? '<svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="11" r="6"/><path d="M5 29v-5a11 11 0 0 1 22 0v5z"/></svg>'
            : '<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M4 8l12-5 12 5v16l-12 5-12-5zm1 0 11 5 11-5M16 13v15"/></svg>';
        var img=document.createElement('img');img.alt='';img.draggable=false;
        img.addEventListener('load',function(){node.classList.add('has-art');});
        img.addEventListener('error',function(){node.classList.remove('has-art');});
        node.appendChild(img);tip(node,name);return node;
    }
    function renderContent() {
        if (!current) return;
        var state=current.state, info=historyFor(state);
        releaseContent();var generation=contentGeneration;
        tooltipScope=PanelTooltip.createScope('stage-focus',{profile:'dense-inspect'});
        S._inspectorNameEl.tabIndex=0;history.tabIndex=0;
        tip(S._inspectorNameEl,current.button.stageName+' · '+(state.stageType || '普通关卡'));
        tip(history,info ? '已通关 · '+state.clearHistory.difficulties.join(' / ') : '暂无通关记录');
        tabs.querySelectorAll('button').forEach(function(el) {
            var active = el.dataset.focusTab === tab;
            el.setAttribute('aria-selected', String(active)); el.tabIndex = active ? 0 : -1;
        });
        content.setAttribute('aria-labelledby','stage-focus-tab-'+tab);
        content.replaceChildren();
        if (tab === 'brief') {
            var preview = document.createElement('div'); preview.className='stage-focus-preview';
            preview.appendChild(S._inspectorPreviewEl.parentElement);
            content.appendChild(preview);
            content.appendChild(S._inspectorDetailEl);
        } else if (!info) {
            content.innerHTML='<p class="stage-focus-empty">通关后解锁奖励与敌人情报。</p><p class="stage-focus-muted">暂无通关记录。早期存档中的通关经历需要再完成一次才能记入。</p>';
        } else {
            var data = window.StageSelectIntelData && StageSelectIntelData.stages[current.button.stageName];
            if (!data) { content.innerHTML='<p class="stage-focus-empty">暂无该关卡的情报资料。</p>'; return; }
            content.innerHTML='<h3>通关奖励池</h3><p class="stage-focus-muted">以下为可能产出，并非每次必得；任务奖励另行结算。</p>';
            var items=document.createElement('div'); items.className='stage-focus-rewards';
            data.rewards.forEach(function(name) {
                items.appendChild(iconToken(name,'reward'));
            });
            if (!data.rewards.length) items.textContent='未配置普通通关奖励池。';
            content.appendChild(items);
            Icons.load(function(){
                if(generation!==contentGeneration)return;
                items.querySelectorAll('.stage-focus-reward').forEach(function(node){
                    var url=Icons.resolveStatic(node.getAttribute('aria-label'));if(url)node.querySelector('img').src=url;
                });
            });
            var heading=document.createElement('h3'); heading.textContent='常规敌人'; content.appendChild(heading);
            var enemies=document.createElement('div'); enemies.className='stage-focus-enemies';
            content.appendChild(enemies);
            data.enemies.forEach(function(enemy){
                var node=iconToken(enemy.name,'enemy');enemies.appendChild(node);
                EnemyPortraits.mount(node,node.querySelector('img'),{portraitRef:enemy.portraitRef,consumer:'stage-select'});
            });
            if(!data.enemies.length)enemies.textContent='暂无可公开的常规敌人资料。';
            var note=document.createElement('p'); note.className='stage-focus-muted'; note.textContent='不同难度与关内事件可能带来变化。'; content.appendChild(note);
        }
    }
    function pickDifficulty(difficulty) {
        if (!current) return;
        mode = difficulty;
        S._inspectorDiffEl.querySelectorAll('button').forEach(function(el) {
            var active=el.dataset.difficulty === mode;
            el.setAttribute('aria-pressed',String(active)); el.classList.toggle('is-chosen',active);
        });
        var enter=footer.querySelector('.stage-focus-enter'); enter.textContent='以'+mode+'难度出发';
        enter.disabled=!current.state.unlocked || !!S._busyStageName;
    }
    function render(buttonData, state) {
        ensure();
        var changed=selected !== buttonData.id;
        selected=buttonData.id; current={button:buttonData,state:state};
        if (changed) { tab='brief'; mode=state.task ? state.highestDifficulty : '简单'; }
        if (StageSelectViewModel.isChallengeMode()) mode='地狱';
        S._el.classList.add('is-stage-focused'); surface.hidden=false;
        history.textContent=historyFor(state) ? '已通关·'+(state.clearHistory.difficulties.length===1 ? state.clearHistory.difficulties[0] : state.clearHistory.difficulties.length+'难度') : '暂无记录';
        history.setAttribute('aria-label',historyFor(state) ? '已通关 · '+state.clearHistory.difficulties.join(' / ') : '暂无通关记录');
        S._inspectorDiffEl.querySelectorAll('button').forEach(function(el) { el.dataset.focusDifficulty='true'; });
        footer.hidden=!state.unlocked;
        var scroll=changed ? 0 : content.scrollTop;
        pickDifficulty(mode); renderContent(); content.scrollTop=scroll;
        S._buttonLayerEl.inert=true; S._cardLayerEl.inert=true; S._navLayerEl.inert=true;
        if (S._el.classList.contains('is-diorama')) {
            viewport.querySelector('.stage-focus-location').hidden=true;
            StageSelectDiorama.focus(buttonData.id,viewport);
        } else {
            StageSelectDiorama.overview();
            var map=viewport.querySelector('.stage-focus-location'), point=StageSelectViewModel.getStageNavPoint(buttonData,StageSelectRenderer.computeDirectSizing);
            map.hidden=false;
            var bg=S._backgroundEl.style, rect={x:parseFloat(bg.left)||0,y:parseFloat(bg.top)||0,w:parseFloat(bg.width)||1024,h:parseFloat(bg.height)||576};
            map.innerHTML='<svg viewBox="0 0 1024 576" role="img" aria-label="当前地点位置"><image href="'+escape(S._backgroundEl.src)+'" x="'+rect.x+'" y="'+rect.y+'" width="'+rect.w+'" height="'+rect.h+'" preserveAspectRatio="none" opacity=".65"/><circle cx="'+point.x+'" cy="'+point.y+'" r="22" class="stage-focus-map-ring"/><circle cx="'+point.x+'" cy="'+point.y+'" r="5" class="stage-focus-map-dot"/></svg><div class="stage-focus-map-caption">'+escape(buttonData.stageName)+'</div>';
        }
    }
    function hide() {
        releaseContent();if(content)content.replaceChildren();
        if (window.StageSelectCameraEditor && (selected || !S._el.classList.contains('is-diorama'))) StageSelectCameraEditor.hide();
        if (surface) surface.hidden=true;
        if (S._el) S._el.classList.remove('is-stage-focused');
        selected=''; current=null;
        var touring=window.StageSelectCameraEditor && StageSelectCameraEditor.isOpen();
        if (S._navLayerEl) S._navLayerEl.inert=!!touring;
        if (S._buttonLayerEl) S._buttonLayerEl.inert=!!touring;
        if (S._cardLayerEl) S._cardLayerEl.inert=!!touring;
        StageSelectDiorama.overview();
    }
    return {render:render,hide:hide,pickDifficulty:pickDifficulty};
})();
