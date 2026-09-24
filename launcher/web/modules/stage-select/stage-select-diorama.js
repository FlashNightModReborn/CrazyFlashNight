/* Per-frame visual scenes share the existing authoritative selection/entry flow. */
var StageSelectDiorama = (function() {
    'use strict';
    var baseUrl=new URL('./',document.currentScript.src),S=StageSelectCore.state;
    var config=null,cache=null,pending=null,mount=null,active=false,failed=false,generation=0,loadAbort=null;
    var focused='',focusHost=null,presets={},fallbackImage=null,presentationId='',environmentEnabled=true,comparison=null;
    function forFrame(frame){
        if(StageSelectData.getManifest().testOnly)return null;
        if(frame.frameLabel===StageSelectDioramaData.frameLabel)return StageSelectDioramaData;
        if(typeof StageSelectBlackironData!=='undefined'&&frame.frameLabel===StageSelectBlackironData.frameLabel)return StageSelectBlackironData;
        if(typeof StageSelectFallenData!=='undefined'&&frame.frameLabel===StageSelectFallenData.frameLabel)return StageSelectFallenData;
        return null;
    }
    function presetKey(){var key=config && config.presetKey || 'cf7.stage-camera.base-gate.v1';return config&&config.presentationViews?key+'.'+presentationId:key;}
    function loadSaved(){
        try{presets=JSON.parse(localStorage.getItem(presetKey())||'{}');}catch(_){presets={};}
        if(!presets||Array.isArray(presets)||typeof presets!=='object')presets={};
    }
    function discard(){
        generation++;if(loadAbort)loadAbort.abort();loadAbort=null;pending=null;
        if(cache)cache.dispose();cache=null;focused='';focusHost=null;
        if(fallbackImage)fallbackImage.remove();fallbackImage=null;
    }
    function changed(){
        if(!active||!cache||focused)return;
        S._visualStagePoints=cache.view.pins();
        S._buttonLayerEl.querySelectorAll('.stage-select-stage-button').forEach(function(node){
            var anchor=S._cardLayerEl.querySelector('[data-stage-id="'+node.dataset.stageId+'"]');
            place({id:node.dataset.stageId},node,anchor,parseFloat(node.style.getPropertyValue('--stage-card-height'))||240);
        });
        if(S._navLayerEl)S._navLayerEl.querySelectorAll('[data-nav-id]').forEach(function(node){placeNav({id:node.dataset.navId},node);});
    }
    function preset(key){return cache&&cache.view.valid(presets[key])?presets[key]:null;}
    function status(message,retry,fallback){
        if(!mount)return;
        var el=mount.querySelector('.stage-select-diorama-status');el.hidden=!message;
        el.querySelector('span').textContent=message||'';el.querySelector('button').hidden=!retry;
        mount.dataset.state=fallback?'fallback':message?(retry?'error':'loading'):'ready';
        var touring=window.StageSelectCameraEditor&&StageSelectCameraEditor.isOpen();
        var blocked=!!message&&!fallback||!!touring||StageSelectInspector.isInspectorOpen();
        S._buttonLayerEl.inert=blocked;if(S._cardLayerEl)S._cardLayerEl.inert=blocked;
        if(window.StageSelectCameraEditor)StageSelectCameraEditor.refreshButtons();
        updateComparison();
    }
    function useFallback(message){
        if(cache)cache.dispose();cache=null;focused='';focusHost=null;failed=true;
        if(config.fallback){
            if(!fallbackImage){fallbackImage=document.createElement('img');fallbackImage.className='stage-select-diorama-fallback';fallbackImage.alt=config.frameLabel+'二维总览';fallbackImage.src=StageSelectCore.resolveAssetUrl(config.fallback);mount.prepend(fallbackImage);}
            S._visualStagePoints=config.fallbackPins||config.pins;status(message+' 已切换二维，可继续选关。',true,true);
            S._buttonLayerEl.querySelectorAll('.stage-select-stage-button').forEach(function(node){var anchor=S._cardLayerEl.querySelector('[data-stage-id="'+node.dataset.stageId+'"]');place({id:node.dataset.stageId},node,anchor,parseFloat(node.style.getPropertyValue('--stage-card-height'))||240);});
            if(S._selectedStageId)StageSelectInspector.renderInspector();
        }else status(message+' 请重试。',true);
    }
    function contextLost(){
        if(!active)return;
        failed=true;if(cache)cache.view.stop();StageSelectCameraEditor.hide();
        if(!config.fallback){
            if(focused)StageSelectInspector.clearSelection();
            status((config.name||config.frameLabel)+'画面暂时中断，请重试。',true);return;
        }
        useFallback((config.name||config.frameLabel)+'画面暂时中断。');
    }
    function ensure(){
        if(pending)return pending;
        var token=generation,wanted=config,controller=new AbortController();loadAbort=controller;
        var url=new URL(config.scene==='fallen'?'stage-select-fallen-scene.js':config.scene==='blackiron'?'stage-select-blackiron-scene.js':'stage-select-diorama-scene.js',baseUrl).href;
        pending=import(url).then(function(module){
            if(token!==generation)return null;
            return module.createScene(wanted,function(){if(token===generation)contextLost();},function(){if(token===generation)changed();},function(id){
                if(!active||token!==generation||focused)return;
                var node=StageSelectRenderer.findNodeById(id);if(node)node.click();
            },controller.signal);
        }).then(function(scene){
            if(token!==generation){if(scene)scene.dispose();return null;}
            if(scene&&scene.setPresentation){scene.setPresentation(presentationId);scene.setEnvironment(environmentEnabled);}
            cache=scene;return scene;
        }).finally(function(){if(token===generation){pending=null;loadAbort=null;}});
        return pending;
    }
    function show(){
        if(cache&&!failed){
            if(!focused){mount.prepend(cache.canvas);cache.view.resize(1024,576);if(!StageSelectCameraEditor.isOpen())cache.view.overview(preset('overview'),false);else cache.render();}
            else cache.render();status('',false);return;
        }
        var token=generation;
        status('正在载入'+(config.name||config.frameLabel)+'…',false);
        ensure().then(function(scene){
            if(!active||token!==generation||!scene)return;
            if(fallbackImage)fallbackImage.remove();fallbackImage=null;
            mount.prepend(scene.canvas);scene.view.resize(1024,576);scene.view.overview(preset('overview'),false);changed();status('',false);
            if(S._selectedStageId)StageSelectInspector.renderInspector();
        }).catch(function(error){
            if(!active||token!==generation)return;
            useFallback((config.name||config.frameLabel)+'画面未能载入。');StageSelectCore.logDev('diorama: '+error.message);
        });
    }
    function retry(){if(!active||pending)return;discard();failed=false;show();}
    function bind(frame){
        var next=forFrame(frame);
        if(next!==config){StageSelectCameraEditor.hide();discard();failed=false;config=next;presentationId=config&&config.defaultPresentation||'';environmentEnabled=true;loadSaved();}
        active=!!next;S._visualStagePoints=active?(cache&&!focused?cache.view.pins():config.pins):null;
        S._el.classList.toggle('is-diorama',active);
        if(!active){hide();return;}
        if(!mount){
            mount=document.createElement('div');mount.className='stage-select-diorama';
            mount.innerHTML='<div class="stage-select-diorama-status" role="status"><span></span><button type="button" data-audio-cue="confirm">重试</button></div>';
            mount.querySelector('button').addEventListener('click',retry);
        }
        S._stageEl.prepend(mount);mount.hidden=false;updateComparison();
        if(failed){useFallback((config.name||config.frameLabel)+'画面暂时不可用。');return;}show();
    }
    function updateComparison(){
        if(comparison)comparison.remove();comparison=null;
        if(!config||!config.presentationViews||failed)return;
        comparison=document.createElement('div');comparison.className='stage-select-diorama-comparison';
        comparison.setAttribute('role','group');comparison.setAttribute('aria-label','总部取景对比');
        Object.keys(config.presentationViews).forEach(function(id){
            var button=document.createElement('button');button.type='button';button.textContent=config.presentationViews[id].label;
            button.setAttribute('aria-pressed',String(presentationId===id));
            button.addEventListener('click',function(e){
                e.stopPropagation();if(!cache||failed||focused)return;StageSelectCameraEditor.hide();
                presentationId=id;loadSaved();cache.setPresentation(id);cache.view.overview(preset('overview'),false);changed();updateComparison();
                comparison.querySelector('[aria-pressed="true"]').focus({preventScroll:true});
            });comparison.appendChild(button);
        });
        var label=document.createElement('label'),input=document.createElement('input');input.type='checkbox';input.checked=environmentEnabled;
        input.addEventListener('change',function(){if(cache&&!failed){environmentEnabled=input.checked;cache.setEnvironment(environmentEnabled);updateComparison();}});
        label.append(input,document.createTextNode('周边环境'));comparison.appendChild(label);
        comparison.addEventListener('click',function(e){e.stopPropagation();});mount.appendChild(comparison);
        comparison.querySelectorAll('button,input').forEach(function(el){el.disabled=!cache||failed;});
    }
    function hide(){
        active=false;focused='';focusHost=null;
        if(cache){cache.view.stop();cache.view.edit(false);}
        if(window.StageSelectCameraEditor)StageSelectCameraEditor.hide();
        if(pending || config&&config.releaseOnHide){discard();failed=false;}
        if(mount)mount.hidden=true;
        if(S._buttonLayerEl)S._buttonLayerEl.inert=false;if(S._cardLayerEl)S._cardLayerEl.inert=false;
    }
    function focus(id,host){
        if(!active||!cache||failed)return;var changedFocus=focused!==id;focused=id;focusHost=host;
        host.appendChild(cache.canvas);cache.view.resize(host.clientWidth,host.clientHeight);
        if(changedFocus)cache.view.focus(id,preset(id),!S._el.classList.contains('is-camera-editing'));else cache.render();
    }
    function overview(){
        if(!focused)return;focused='';focusHost=null;if(!cache)return;
        mount.prepend(cache.canvas);cache.view.resize(1024,576);
        if(active&&!failed)cache.view.overview(preset('overview'));else cache.view.stop();
    }
    function edit(enabled){return cache?cache.view.edit(enabled):Promise.resolve();}
    function exportPresets(){
        if(!cache)return;var value=cache.view.snapshot();if(!cache.view.valid(value))throw new Error('当前取景超出可保存范围，请恢复默认取景后调整。');
        var result=Object.assign({},presets);result[focused||'overview']=value;return result;
    }
    function savePreset(){if(!cache)return;presets=exportPresets();localStorage.setItem(presetKey(),JSON.stringify(presets));return presets;}
    function loadPresets(value){
        if(!value||Array.isArray(value)||typeof value!=='object'||!cache)throw new Error('预设内容无效');
        Object.keys(value).forEach(function(key){if((key!=='overview'&&!Object.prototype.hasOwnProperty.call(config.pins,key))||!cache.view.valid(value[key]))throw new Error('预设内容无效：'+key);});
        presets=value;localStorage.setItem(presetKey(),JSON.stringify(presets));if(focused)cache.view.focus(focused,preset(focused),false);else cache.view.overview(preset('overview'),false);
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
        var label=node.querySelector('.stage-select-stage-name');
        if(pin.shortLabel && label){
            // Only the map caption is abbreviated; accessible names and all gameplay data stay full.
            if(!node.hasAttribute('aria-label'))node.setAttribute('aria-label',label.textContent);
            label.textContent=pin.shortLabel;node.dataset.compactLabel='true';
            node.style.setProperty('--diorama-label-width',pin.labelWidth+'px');
        }
        var leader=node.querySelector('.stage-select-location-leader'),ns='http://www.w3.org/2000/svg';
        if(!leader){
            leader=document.createElementNS(ns,'svg');leader.setAttribute('class','stage-select-location-leader');leader.setAttribute('aria-hidden','true');leader.setAttribute('width','1');leader.setAttribute('height','1');
            ['stage-select-leader-edge','stage-select-leader-ink'].forEach(function(cls){var path=document.createElementNS(ns,'path');path.setAttribute('class',cls);leader.appendChild(path);});
            node.prepend(leader);
        }
        var dx=pin.labelX,dy=pin.labelY,len=Math.hypot(dx,dy),halfW=((label&&label.offsetWidth)||pin.labelWidth||140)/2+3,halfH=((label&&label.offsetHeight)||pin.labelHeight||30)/2+3;
        var trim=Math.min(dx?halfW/Math.abs(dx):Infinity,dy?halfH/Math.abs(dy):Infinity),end=1-trim,start=15/len;
        var pathData=len>0&&end>start?'M '+(dx*start)+' '+(dy*start)+' L '+(dx*end)+' '+(dy*end):'';
        if(pin.leaderBend){
            var bx=pin.leaderBend[0],by=pin.leaderBend[1],first=Math.hypot(bx,by),lx=dx-bx,ly=dy-by;
            var lastTrim=Math.min(lx?halfW/Math.abs(lx):Infinity,ly?halfH/Math.abs(ly):Infinity);
            pathData='M '+(bx*15/first)+' '+(by*15/first)+' L '+bx+' '+by+' L '+(dx-lx*lastTrim)+' '+(dy-ly*lastTrim);
        }
        leader.querySelectorAll('path').forEach(function(path){path.setAttribute('d',pathData);});
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
    function placeNav(nav,node){
        if(!active||config.scene!=='fallen')return;
        var pin=S._visualStagePoints&&S._visualStagePoints[nav.id];
        if(!pin){node.style.left='912px';node.style.top=nav.id==='nav_11_2'?'536px':'488px';return;}
        node.classList.add('is-diorama-nav');node.style.left=(pin.x+pin.labelX)+'px';node.style.top=(pin.y+pin.labelY)+'px';node.style.width=pin.labelWidth+'px';
    }
    window.addEventListener('pagehide',function(){active=false;discard();});
    return {bind:bind,hide:hide,place:place,placeNav:placeNav,retry:retry,focus:focus,overview:overview,edit:edit,
        canFocus:function(){return !!(active&&cache&&!failed);},
        fallbackMap:function(){return active&&failed&&config.fallback?{src:StageSelectCore.resolveAssetUrl(config.fallback),x:0,y:0,w:1024,h:576}:null;},
        orderButtons:function(frame){var c=forFrame(frame),list=(frame.stageButtons||[]).slice();return c&&c.displayOrder?list.sort(function(a,b){return c.displayOrder.indexOf(a.id)-c.displayOrder.indexOf(b.id);}):list;},
        savePreset:savePreset,loadPresets:loadPresets,exportPresets:exportPresets,
        snapshotCamera:function(){return cache?cache.view.snapshot():null;},
        restoreCamera:function(value){if(!active||!cache||failed||!cache.view.valid(value))return;if(focused)cache.view.focus(focused,value,false);else cache.view.overview(value,false);},
        hover:function(id){if(active&&cache&&!failed)cache.view.hover(id);},
        resetCamera:function(){if(cache){if(focused)cache.view.focus(focused,null,false);else cache.view.overview(null,false);}},
        stats:function(){return Object.assign({active:active,pending:!!pending,failed:failed,frameLabel:config&&config.frameLabel||'',state:mount&&mount.dataset.state||'empty'},cache?cache.stats():{});}
    };
})();
