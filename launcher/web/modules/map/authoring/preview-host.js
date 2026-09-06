/* 隔离子文档：加载原生产地图及其 CSS，只返回设计快照，绝不连接 Launcher/AS2 桥。 */
(function() {
    'use strict';
    var session='', input, panel, panelRoot, loaded=false, loading=false, listeners={}, overlay, dragging=null, panning=null, space=false, lastDefinition='', lastPage='', lastGender='';
    window.MapAuthoringPreview=true;
    function post(event, value) { parent.postMessage(Object.assign({type:'map-authoring-preview',session:session,event:event},value||{}),location.origin); }
    function snapshot() { return {version:2,defaultPageId:input.pageId,unlocks:MapPanelData.normalizeUnlockFlags({}),enabledHotspotIds:MapPanelData.getAllHotspotIds(),dynamicAvatarState:{roommateGender:input.gender},markers:[],tips:[]}; }
    window.Bridge={on:function(type,cb){(listeners[type]||(listeners[type]=[])).push(cb);},send:function(m){
        if(m.type!=='panel'||m.panel!=='map')return false;
        if(m.cmd==='close'){post('close');return true;}
        var response={type:'panel_resp',panel:'map',cmd:m.cmd,callId:m.callId,success:m.cmd==='snapshot'||m.cmd==='refresh'};
        if(response.success)response.snapshot=snapshot();else {response.error='设计预览不执行导航';post('notice',{message:response.error});}
        setTimeout(function(){(listeners.panel_resp||[]).forEach(function(cb){cb(response);});},0);return true;
    }};
    window.Panels={register:function(id,value){if(id==='map')panel=value;},isOpen:function(){return loaded;},getActive:function(){return 'map';},close:function(){}};
    window.Toast={add:function(text){post('notice',{message:text});}};
    function script(src) { return new Promise(function(resolve,reject){var s=document.createElement('script');s.src=src;s.onload=resolve;s.onerror=function(){reject(new Error('地图预览资源未加载：'+src));};document.head.appendChild(s);}); }
    async function boot() {
        loading=true;window.MapDefinitionData=input.definition;
        try {
            var files=['map-avatar-source-data.js','map-panel-data.js','map-fit-presets.js','map-scale-policy.js','stage-select-data.js','map-canvas-stage-renderer.js','map/map-hittest-engine.js','map/map-hotspot-hitcapture.js','map/map-scene-visual-layer.js','map/map-avatar-layer.js','map-panel.js'];
            for(var i=0;i<files.length;i++)await script('modules/'+files[i]);
            panelRoot=panel.create();document.getElementById('map-authoring-root').appendChild(panelRoot);loaded=true;
            panel.onOpen(panelRoot,{page:input.pageId});
            document.addEventListener('map-authoring-layout',targets);
            installCamera();update();post('loaded');
        }catch(e){post('error',{message:e.message});}finally{loading=false;}
    }
    function update() {
        if(!loaded)return;
        var json=JSON.stringify(input.definition);
        if(json!==lastDefinition||input.pageId!==lastPage||input.gender!==lastGender){
            lastDefinition=json;lastPage=input.pageId;lastGender=input.gender;
            MapPanel.authoring.setDefinition(input.definition,snapshot(),input.rasterScale);
        }
        targets();
    }
    function avatarRect(slot,page) {
        var source=MapAvatarSourceData.getByAssetUrl(slot.assetUrl)||{},h=page.hotspots.find(function(x){return x.id===slot.hotspotId;});
        return {x:h.rect.x+(slot.relX===undefined?source.relX:slot.relX),y:h.rect.y+(slot.relY===undefined?source.relY:slot.relY),w:slot.w===undefined?(source.size||{}).w:slot.w,h:slot.h===undefined?(source.size||{}).h:slot.h};
    }
    function targets() {
        if(!loaded||dragging)return;
        var view=MapPanel.authoring.getView();if(!view.pageId)return;
        var page=MapPanelData.getPage(view.pageId),fit=document.getElementById('map-stage-content-fit');
        if(!overlay){overlay=document.createElement('div');overlay.className='map-authoring-targets';}
        if(overlay.parentNode!==fit)fit.appendChild(overlay);
        overlay.replaceChildren();overlay.hidden=!input.editing||input.before;
        var visible=MapPanelData.getVisibleHotspots(page.id,view.filterId).map(function(h){return h.id;});
        var items=input.kind==='scene'?MapPanelData.getVisibleSceneVisuals(page.id,view.filterId).map(function(x){return {id:x.id,rect:x.rect};}):input.kind==='avatar'?(page.staticAvatars||[]).concat(page.dynamicAvatars||[]).filter(function(x){return visible.indexOf(x.hotspotId)>=0;}).map(function(x){return {id:x.id,rect:avatarRect(x,page)};}):[];
        items.forEach(function(it){
            var n=document.createElement('button');n.type='button';n.className='map-authoring-target'+(it.id===input.id?' is-selected':'');n.dataset.targetId=it.id;n.setAttribute('aria-label','编辑 '+it.id);
            ['x','y','w','h'].forEach(function(k){n.style[({x:'left',y:'top',w:'width',h:'height'})[k]]=it.rect[k]/(k==='x'||k==='w'?page.width:page.height)*100+'%';});
            n.onpointerdown=function(e){if(e.button!==0||space||!input.editing||input.busy||input.before)return;e.preventDefault();e.stopPropagation();input.id=it.id;
                overlay.querySelectorAll('button').forEach(function(b){b.classList.toggle('is-selected',b===n);});
                dragging={x:e.clientX,y:e.clientY,scale:fit.getBoundingClientRect().width/page.width,visualScale:fit.getBoundingClientRect().width/fit.clientWidth,id:it.id,pageId:page.id,target:n};n.setPointerCapture(e.pointerId);post('select',{pageId:page.id,id:it.id});};
            n.onpointermove=function(e){if(!dragging||dragging.target!==n)return;n.style.transform='translate('+((e.clientX-dragging.x)/dragging.visualScale)+'px,'+((e.clientY-dragging.y)/dragging.visualScale)+'px)';};
            n.onpointerup=function(e){if(!dragging||dragging.target!==n)return;var d=dragging;dragging=null;
                post('move',{pageId:d.pageId,id:d.id,dx:(e.clientX-d.x)/d.scale,dy:(e.clientY-d.y)/d.scale});};
            n.onpointercancel=function(){dragging=null;targets();};overlay.appendChild(n);
        });
        post('view',{pageId:page.id,filterId:view.filterId,zoom:view.camera.zoom});
    }
    function zoom(factor,point) {
        var v=MapPanel.authoring.getView(),c=v.camera,next=Math.max(.5,Math.min(6,c.zoom*factor)),r=next/c.zoom;
        var x=point?point.x:v.width/2,y=point?point.y:v.height/2;
        MapPanel.authoring.setCamera({zoom:next,x:(x-v.width/2)*(1-r)+c.x*r,y:(y-v.height/2)*(1-r)+c.y*r});
    }
    function focusSelected() {
        var v=MapPanel.authoring.getView(),p=MapPanelData.getPage(v.pageId),it=(input.kind==='avatar'?(p.staticAvatars||[]).concat(p.dynamicAvatars||[]):p.sceneVisuals).find(function(x){return x.id===input.id;});
        if(!it)return;
        var visible=input.kind==='avatar'?MapPanelData.getVisibleHotspots(p.id,v.filterId).some(function(h){return h.id===it.hotspotId;}):MapPanelData.getVisibleSceneVisuals(p.id,v.filterId).some(function(s){return s.id===it.id;});
        if(!visible){MapPanel.authoring.setFilter('all');MapPanel.authoring.setCamera({zoom:1});v=MapPanel.authoring.getView();}
        var rect=input.kind==='avatar'?avatarRect(it,p):it.rect;
        var factor=Math.min(v.width/(rect.w*v.scale),v.height/(rect.h*v.scale))*.65;
        var next=Math.max(.5,Math.min(6,v.camera.zoom*factor)),r=next/v.camera.zoom;
        MapPanel.authoring.setCamera({zoom:next,x:v.camera.x*r+(v.width/2-((rect.x+rect.w/2)*v.scale+v.offsetX))*r,y:v.camera.y*r+(v.height/2-((rect.y+rect.h/2)*v.scale+v.offsetY))*r});
    }
    function installCamera() {
        var stage=document.getElementById('map-stage-frame');stage.tabIndex=0;
        stage.addEventListener('wheel',function(e){e.preventDefault();var b=stage.getBoundingClientRect();zoom(e.deltaY<0?1.15:1/1.15,{x:e.clientX-b.left,y:e.clientY-b.top});},{passive:false});
        stage.addEventListener('pointerdown',function(e){if(!(e.button===1||(space&&e.button===0)))return;e.preventDefault();e.stopPropagation();panning={x:e.clientX,y:e.clientY,c:MapPanel.authoring.getView().camera};stage.setPointerCapture(e.pointerId);},true);
        stage.addEventListener('pointermove',function(e){if(!panning)return;MapPanel.authoring.setCamera({zoom:panning.c.zoom,x:panning.c.x+e.clientX-panning.x,y:panning.c.y+e.clientY-panning.y});});
        stage.addEventListener('pointerup',function(){panning=null;});stage.addEventListener('pointercancel',function(){panning=null;});
        document.addEventListener('keydown',function(e){
            var ownsCamera=e.target===stage||e.target===document.body||e.target.classList.contains('map-authoring-target');
            if(ownsCamera&&e.code==='Space'){space=true;panelRoot.classList.add('is-authoring-pan');e.preventDefault();}
            if(ownsCamera&&e.key==='Home'){e.preventDefault();MapPanel.authoring.setCamera({zoom:1});}
            if(e.target===stage&&['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].indexOf(e.key)>=0){e.preventDefault();var c=MapPanel.authoring.getView().camera;MapPanel.authoring.setCamera({zoom:c.zoom,x:c.x+(e.key==='ArrowLeft'?24:e.key==='ArrowRight'?-24:0),y:c.y+(e.key==='ArrowUp'?24:e.key==='ArrowDown'?-24:0)});}
            if(e.key==='Escape'){e.preventDefault();post('escape');}
        });
        document.addEventListener('keyup',function(e){if(e.code==='Space'){space=false;panelRoot.classList.remove('is-authoring-pan');}});
        window.addEventListener('blur',function(){space=false;panning=null;panelRoot.classList.remove('is-authoring-pan');});
    }
    window.addEventListener('message',function(e){
        if(e.source!==parent||e.origin!==location.origin||!e.data||e.data.type!=='map-authoring-input')return;
        if(e.data.action==='state') {session=e.data.session;input=e.data;if(!loaded&&!loading)boot();else update();}
        else if(loaded&&e.data.session===session){if(e.data.action==='fit')MapPanel.authoring.setCamera({zoom:1});if(e.data.action==='zoom')zoom(e.data.factor);if(e.data.action==='focus')focusSelected();}
    });
    window.addEventListener('pagehide',function(){if(loaded)panel.onClose();});
    window.addEventListener('error',function(e){post('error',{message:e.message});});
    post('ready');
})();
