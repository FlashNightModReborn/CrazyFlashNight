/* 地图维护视图；C# 校验编辑，隔离子文档运行完整生产地图面板。 */
(function() {
    'use strict';
    var root, shell, refs = {}, mux, scale;
    var frameReady=false, frameSession='', focusMode=false;
    var active = false, busy = false, epoch = 0, base, draft, digest, patches = {}, operation = '', operationKind = '', unknown = false;
    var pageId = 'base', kind = 'scene', selectedId = '';
    var draftKey = 'cf7.map.workbench.draft.v1';
    function clone(v) { return JSON.parse(JSON.stringify(v)); }
    function el(tag, cls, text) { var n=document.createElement(tag); n.className=cls||''; if(text!==undefined)n.textContent=text; return n; }
    function button(text, action) { var n=el('button','mw-button',text); n.type='button'; n.onclick=action; return n; }
    function status(text, bad) { refs.status.textContent=text; shell.setStatus(bad?'需要处理':'地图维护',bad?'error':'ready'); }
    function changes() { return Object.keys(patches).map(function(k){return patches[k];}); }
    function persist() { try { localStorage.setItem(draftKey,JSON.stringify({digest:digest,changes:changes(),operation:operation,operationKind:operationKind,unknown:unknown})); } catch(e){} }
    function controls() {
        refs.apply.disabled=busy||unknown||!changes().length;
        refs.undo.disabled=busy||unknown||changes().length>0||!refs.history.value;
        refs.refresh.disabled=busy;
        refs.reset.disabled=busy||unknown;
        refs.page.disabled=busy; refs.kind.disabled=busy;
        refs.form.querySelectorAll('input').forEach(function(n){n.disabled=busy||unknown||refs.before.checked;});
        refs.count.textContent=changes().length+' 个对象待保存';
    }
    function request(cmd,payload,done) {
        busy=true; controls();
        mux.request(cmd,payload||{}, {singleFlight:true,write:cmd==='apply'||cmd==='undo'},function(resp) {
            if(!active)return;
            busy=false;
            if(!resp.success) {
                if(resp.clientSynthetic&&(cmd==='apply'||cmd==='undo'))unknown=true;
                status(resp.clientSynthetic?'结果尚未确认；请点击“重新读取 / 核对结果”。草稿仍保留。':resp.error||'操作失败',true);
                persist(); controls(); return;
            }
            done(resp.data); controls();
        });
    }
    function collection(d) {
        var p=d.pages[pageId];
        return kind==='page'?[p]:kind==='avatar'?(p.staticAvatars||[]).concat(p.dynamicAvatars||[]):p[kind==='scene'?'sceneVisuals':kind==='filter'?'filters':'hotspots'];
    }
    function item(d) { return collection(d).find(function(x){return x.id===selectedId;})||collection(d)[0]; }
    function sourceFor(d,slot) { return Object.keys(d.avatarSources).map(function(k){return d.avatarSources[k];}).find(function(x){return x.assetUrl===slot.assetUrl;})||{}; }
    function values(d,it) {
        if(kind==='scene')return it.rect;
        if(kind==='filter')return null;
        if(kind==='avatar') { var s=sourceFor(d,it);return {x:it.relX===undefined?s.relX:it.relX,y:it.relY===undefined?s.relY:it.relY,w:it.w===undefined?(s.size||{}).w:it.w,h:it.h===undefined?(s.size||{}).h:it.h}; }
        return null;
    }
    function append(values) {
        var key=pageId+'/'+kind+'/'+selectedId;
        var c=patches[key]||{pageId:pageId,kind:kind,id:selectedId,values:{}};
        Object.assign(c.values,values); patches[key]=c; persist(); controls();
    }
    function preview() {
        request('preview',{expectedDigest:digest,changes:changes()},function(data){draft=data.definition; render(); status('候选已校验；保存后重新启动游戏生效。');});
    }
    function updateFields() {
        if(!draft)return;
        refs.form.replaceChildren();
        var d=refs.before.checked?base:draft,it=item(d);if(!it)return;
        selectedId=it.id;
        refs.objectTitle.textContent=it.label||it.title||it.id;
        refs.identity.textContent='标识：'+it.id+(it.hotspotId?' · 地点：'+it.hotspotId:'');
        var v=values(d,it);
        if(v)['x','y','w','h'].forEach(function(k) {
            var label=el('label','',({x:'横坐标',y:'纵坐标',w:'宽度',h:'高度'})[k]+(kind==='avatar'&&(k==='x'||k==='y')?'（相对地点）':''));
            var input=el('input');input.type='number';input.step='.1';input.value=v[k];input.id='mw-'+k;
            input.onchange=function(){
                var r=Object.assign({},values(draft,item(draft)));r[k]=Number(input.value);
                if(kind==='avatar'){var a={};a[k==='x'?'relX':k==='y'?'relY':k]=r[k];append(a);}
                else {var a={};a[kind==='scene'?'rect':'buttonRect']=r;append(a);}
                preview();
            };label.appendChild(input);refs.form.appendChild(label);
        });
        if(kind==='page'||kind==='filter'||kind==='hotspot') {
            var label=el('label','','显示名称'),input=el('input');input.type='text';input.maxLength=100;input.value=it[kind==='page'?'title':'label'];input.id='mw-label';
            input.onchange=function(){var a={};a[kind==='page'?'title':'label']=input.value;append(a);preview();};label.appendChild(input);refs.form.appendChild(label);
        }
        if(kind==='filter'||kind==='page') {
            var extraLabel=el('label','',kind==='filter'?'筛选显示顺序（越小越靠前）':'页签名称'),extra=el('input');
            extra.type=kind==='filter'?'number':'text';extra.id=kind==='filter'?'mw-order':'mw-tab-label';extra.value=kind==='filter'?it.buttonRect.y:it.tabLabel;
            extra.onchange=function(){if(kind==='filter')append({buttonRect:Object.assign({},item(draft).buttonRect,{y:Number(extra.value)})});else append({tabLabel:extra.value});preview();};
            extraLabel.appendChild(extra);refs.form.appendChild(extraLabel);
        }
        controls();
    }
    function list() {
        if(!draft)return;refs.list.replaceChildren();
        collection(draft).forEach(function(it){var o=el('option','',it.label||it.title||it.id);o.value=it.id;refs.list.appendChild(o);});refs.list.value=selectedId;
    }
    function render() {
        if(!active||!draft)return;
        if(frameReady)refs.frame.contentWindow.postMessage({type:'map-authoring-input',action:'state',session:frameSession,
            definition:refs.before.checked?base:draft,pageId:pageId,kind:kind,id:selectedId,gender:refs.gender.value,
            editing:refs.editing.checked,before:refs.before.checked,busy:busy||unknown,
            rasterScale:refs.frame.getBoundingClientRect().width/Math.max(1,refs.frame.clientWidth)},location.origin);
        updateFields();
    }
    function camera(action,extra) { if(frameReady)refs.frame.contentWindow.postMessage(Object.assign({type:'map-authoring-input',action:action,session:frameSession},extra||{}),location.origin); }
    function focusCanvas() { focusMode=!focusMode;shell.setProfile(focusMode?'canvas-editor-focus':'canvas-editor');refs.focus.textContent=focusMode?'显示属性':'专注画布';refs.focus.setAttribute('aria-pressed',String(focusMode)); }
    function close() { if(focusMode){focusCanvas();return;}request('close',{},function(){}); }
    function frameMessage(e) {
        if(!active||e.source!==refs.frame.contentWindow||e.origin!==location.origin||!e.data||e.data.type!=='map-authoring-preview')return;
        var data=e.data;
        if(data.event==='ready'){frameReady=true;render();return;}
        if(data.session!==frameSession)return;
        if(data.event==='error'||data.event==='notice'){status(data.message,true);return;}
        if(data.event==='close'||data.event==='escape'){close();return;}
        if(data.event==='view'){
            refs.zoomLabel.textContent=Math.round(data.zoom*100)+'%';
            if(data.pageId&&draft.pages[data.pageId]&&data.pageId!==pageId){pageId=data.pageId;refs.page.value=pageId;selectedId=item(draft).id;list();render();}
            if(kind==='filter'&&data.filterId&&selectedId!==data.filterId&&collection(draft).some(function(it){return it.id===data.filterId;})){selectedId=data.filterId;list();updateFields();}return;
        }
        if(busy||unknown||refs.before.checked||data.pageId!==pageId||!collection(draft).some(function(it){return it.id===data.id;}))return;
        selectedId=data.id;list();updateFields();
        if(data.event==='move'&&(kind==='scene'||kind==='avatar')&&Number.isFinite(data.dx)&&Number.isFinite(data.dy)){
            var r=Object.assign({},values(draft,item(draft)));r.x=Math.round((r.x+data.dx)*100)/100;r.y=Math.round((r.y+data.dy)*100)/100;
            if(kind==='avatar')append({relX:r.x,relY:r.y});else append({rect:r});preview();
        }
    }
    function adopt(data) {
        base=data.definition;draft=clone(base);digest=data.digest;patches={};unknown=false;
        refs.page.replaceChildren();base.pageOrder.forEach(function(id){var o=el('option','',base.pages[id].title);o.value=id;refs.page.appendChild(o);});
        if(!base.pages[pageId])pageId=base.pageOrder[0];refs.page.value=pageId;
        refs.history.replaceChildren(el('option','','选择一次已保存修改…'));refs.history.firstChild.value='';
        (data.recent||[]).forEach(function(r){var o=el('option','',r.createdAt.slice(0,19)+' · '+r.operationId.slice(0,8));o.value=r.operationId;refs.history.appendChild(o);});
        if(operation)refs.history.value=operation;
        selectedId=item(draft).id;list();render();persist();controls();
    }
    function refresh(restore) {
        if(unknown&&operation){request('query',{operationId:operation},function(data){
            unknown=false;
            var complete=operationKind==='undo'?data.state==='original':data.state==='applied';
            if(complete&&data.definition)adopt(data);
            var messages={applied:'修改已写入项目',original:'当前文件为修改前内容',superseded:'项目已有后续修改',not_found:'没有找到本次写入记录'};
            status((messages[data.state]||'已核对当前配置')+(complete?'。':'；草稿仍保留，可导出或继续核对。'),!complete);persist();});return;}
        if(!restore&&changes().length){preview();return;}
        var saved;try{saved=JSON.parse(localStorage.getItem(draftKey)||'null');}catch(e){}
        request('read',{},function(data){adopt(data);status('编辑预览即时；保存后重启游戏生效。');
            if(restore&&saved&&Array.isArray(saved.changes)&&saved.changes.length){
                saved.changes.forEach(function(c){patches[c.pageId+'/'+c.kind+'/'+c.id]=c;});
                if(saved.digest===digest){persist();if(!saved.unknown)preview();}
                else {digest=saved.digest;persist();status('项目已改变，旧草稿仍保留；可先导出，再选择“放弃草稿并重读”。',true);}
            }
            if(restore&&saved&&saved.unknown&&saved.operation){operation=saved.operation;operationKind=saved.operationKind||'apply';unknown=true;refresh(false);}
        });
    }
    function newId(){return Array.from(crypto.getRandomValues(new Uint8Array(16)),function(x){return x.toString(16).padStart(2,'0');}).join('');}
    function apply() { operation=newId();operationKind='apply';unknown=true;persist();request('apply',{expectedDigest:digest,changes:changes(),operationId:operation},function(data){adopt(data);status('已保存到项目。重启游戏查看完整地图与小地图；可撤回本次修改。');}); }
    function undo(){operation=refs.history.value;operationKind='undo';unknown=true;persist();request('undo',{operationId:operation},function(data){adopt(data);status('已核对并恢复原配置；重启游戏生效。');});}
    function exportDraft(){var a=el('a'),u=URL.createObjectURL(new Blob([JSON.stringify({version:1,expectedDigest:digest,changes:changes()},null,2)],{type:'application/json'}));a.href=u;a.download='map-draft.json';a.click();URL.revokeObjectURL(u);}
    function importDraft(file){
        if(!file||busy||unknown)return;
        if(file.size>256*1024){status('草稿超过 256 KiB。',true);return;}
        var generation=epoch;
        file.text().then(function(text){
            if(!active||generation!==epoch)return;
            var data=JSON.parse(text);
            if(data.version!==1||data.expectedDigest!==digest||!Array.isArray(data.changes)||data.changes.length>256)throw new Error('草稿版本或配置摘要不匹配，请先核对原配置。');
            var seen={};data.changes.forEach(function(c){var key=c.pageId+'/'+c.kind+'/'+c.id;if(seen[key])throw new Error('同一地图对象只能出现一条草稿修改。');seen[key]=true;});
            request('preview',{expectedDigest:digest,changes:data.changes},function(result){patches={};data.changes.forEach(function(c){patches[c.pageId+'/'+c.kind+'/'+c.id]=c;});draft=result.definition;persist();list();render();status('草稿已导入并通过 C# 校验，尚未保存。');});
        }).catch(function(e){if(active&&generation===epoch)status(e.message,true);});
    }
    function create() {
        root=el('section','map-workbench-panel panel-scale-shell');
        shell=new Workbench.DualPaneShell({profile:'canvas-editor',title:'地图工作台',status:'读取地图定义',leftLabel:'对象与属性',rightLabel:'玩家地图预览',slotMarkers:false});root.appendChild(shell.getRoot());
        shell.addHeaderAction(button('帮助',function(){refs.help.hidden=!refs.help.hidden;}));
        shell.addHeaderAction(button('关闭',function(){request('close',{},function(){});}));
        var left=el('div','mw-library'),right=el('div','mw-editor');shell.mountInitial({instanceKey:'map-objects',mount:function(h){h.appendChild(left);},unmount:function(){}},{instanceKey:'map-layout',mount:function(h){h.appendChild(right);},unmount:function(){}});
        refs.page=el('select');refs.page.setAttribute('aria-label','地图页面');refs.page.onchange=function(){pageId=refs.page.value;selectedId=item(draft).id;list();render();};left.appendChild(refs.page);
        refs.kind=el('select');refs.kind.setAttribute('aria-label','对象类别');[['scene','场景图块'],['avatar','NPC 头像'],['filter','筛选名称与顺序'],['hotspot','地点显示名'],['page','页面标题']].forEach(function(x){var o=el('option','',x[1]);o.value=x[0];refs.kind.appendChild(o);});refs.kind.onchange=function(){kind=refs.kind.value;selectedId=item(draft).id;list();render();};left.appendChild(refs.kind);
        refs.list=el('select','mw-list');refs.list.setAttribute('aria-label','地图对象');refs.list.onchange=function(){if(busy||unknown)return;selectedId=refs.list.value;render();};left.appendChild(refs.list);
        refs.objectTitle=el('h2');refs.identity=el('small','mw-identity');refs.form=el('div','mw-fields');left.append(refs.objectTitle,refs.identity,refs.form);
        var actions=el('div','mw-save-actions');refs.apply=button('保存到项目',apply);refs.apply.classList.add('mw-primary');refs.reset=button('放弃草稿并重读',function(){patches={};persist();refresh(false);});refs.refresh=button('重新读取 / 核对结果',function(){refresh(false);});refs.export=button('导出草稿',exportDraft);
        actions.append(refs.apply,refs.reset,refs.refresh,refs.export);left.appendChild(actions);
        refs.import=el('input');refs.import.type='file';refs.import.accept='.json';refs.import.hidden=true;refs.import.onchange=function(){importDraft(refs.import.files[0]);refs.import.value='';};actions.appendChild(button('导入草稿',function(){refs.import.click();}));actions.appendChild(refs.import);
        var history=el('div','mw-history');refs.history=el('select');refs.history.setAttribute('aria-label','已保存的修改');refs.history.onchange=controls;refs.undo=button('撤回所选修改',undo);history.append(refs.history,refs.undo);left.appendChild(history);
        refs.count=el('small','mw-count');refs.status=el('p','mw-status');refs.status.setAttribute('aria-live','polite');left.append(refs.count,refs.status);
        var bar=el('div','mw-toolbar'),label=el('label','','对比保存前 ');refs.before=el('input');refs.before.type='checkbox';refs.before.onchange=render;label.appendChild(refs.before);bar.appendChild(label);
        label=el('label','','编辑边框 ');refs.editing=el('input');refs.editing.type='checkbox';refs.editing.checked=true;refs.editing.onchange=render;label.appendChild(refs.editing);bar.appendChild(label);
        bar.appendChild(button('−',function(){camera('zoom',{factor:1/1.25});}));refs.zoomLabel=el('span','mw-zoom','100%');refs.zoomLabel.setAttribute('aria-label','观察倍率');bar.appendChild(refs.zoomLabel);
        bar.appendChild(button('+',function(){camera('zoom',{factor:1.25});}));bar.appendChild(button('玩家取景',function(){camera('fit');}));bar.appendChild(button('聚焦所选',function(){camera('focus');}));
        refs.focus=button('专注画布',focusCanvas);refs.focus.setAttribute('aria-pressed','false');bar.appendChild(refs.focus);
        refs.gender=el('select');refs.gender.setAttribute('aria-label','室友预览');['male','female'].forEach(function(x){var o=el('option','',x==='male'?'室友：男':'室友：女');o.value=x;refs.gender.appendChild(o);});refs.gender.onchange=render;bar.appendChild(refs.gender);right.appendChild(bar);
        refs.frame=el('iframe','mw-preview');refs.frame.title='真实玩家地图设计预览';refs.frame.setAttribute('sandbox','allow-scripts allow-same-origin');right.appendChild(refs.frame);
        refs.caption=el('small','mw-caption','设计态 · 全部解锁，无任务标记，不执行导航。滚轮缩放；中键或空格＋拖动平移；玩家取景复位。');right.appendChild(refs.caption);
        refs.help=el('div','mw-help','预览直接使用生产地图的页签、分层筛选、标签、头像和自动取景。关闭“编辑边框”可观察玩家外观；“专注画布”隐藏属性栏，Esc 返回。选择图块或头像后拖动边框，或修改左侧坐标与尺寸。筛选按钮沿用生产布局，仅修改名称和纵向排序。预览相机不保存。保存后请使用“地图工作台测试启动.cmd”重启候选；正式入口尚未部署本轮变更。');refs.help.hidden=true;right.appendChild(refs.help);
        mux=new PanelRuntime.PanelRequestMux({send:function(m){return Bridge.send(m);},router:PanelRuntime.sharedResponseRouter,timeoutMs:15000,callPrefix:'map-edit',
            createMessage:function(c){return {type:'panel',panel:'map-workbench',domain:'map_workbench',cmd:c.entry.cmd,callId:c.entry.callId,panelInstanceId:c.session.panelInstanceId,payload:c.payload};},
            validateResponse:function(d,e,s){return d.type==='panel_resp'&&d.panel==='map-workbench'&&d.domain==='map_workbench'&&d.cmd===e.cmd&&d.callId===e.callId&&d.panelInstanceId===s.panelInstanceId;}});
        return root;
    }
    Panels.register('map-workbench',{create:create,onOpen:function(node,data){if(!data||!data.panelInstanceId)return false;active=true;epoch++;busy=false;unknown=false;operation='';refs.before.checked=false;frameSession=newId();frameReady=false;window.addEventListener('message',frameMessage);mux.openSession({panelInstanceId:data.panelInstanceId});scale=PanelScale.attach(root,1024,576,{onUpdate:render});refs.frame.src='modules/map/authoring/preview.html';refresh(true);return true;},
        onRequestClose:close,onClose:function(){persist();active=false;epoch++;mux.closeSession();window.removeEventListener('message',frameMessage);refs.frame.src='about:blank';frameReady=false;if(scale)scale.detach();}});
})();
