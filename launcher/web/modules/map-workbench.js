/* 地图内容工作台；草稿与模拟在 Web，领域投影与可恢复文件批次在同一 C# 内核。 */
(function() {
    'use strict';
    var U=MapAuthoringControls,E=MapAuthoringEditors,root,shell,refs={},mux,scale,help,guide,lifetime;
    var active=false,busy=false,epoch=0,instance='',frameReady=false,frameSession='',focusMode=false;
    var base,draft,baseRender,renderDefinition,digest='',taskDigest='',catalog=null,previewData=null,runtime=null;
    var ops=[],operation='',operationKind='',unknown=false,valid=false,draftConflict=false,previewAssets={},assets=[];
    var pageId='',kind='scene',selectedId='',treeSignature='',scenarios=[],live=null,liveAt='',viewMode='author';
    var draftKey='cf7.map.workbench.draft.v2',scenarioKey='cf7.map.workbench.scenarios.v2';
    function id(){return Array.from(crypto.getRandomValues(new Uint8Array(16)),function(x){return x.toString(16).padStart(2,'0');}).join('');}
    function status(message,bad){refs.status.textContent=message;shell.setStatus(bad?'需要处理':busy?'处理中':'地图创作',bad?'error':busy?'pending':'ready');}
    function persist(){try{localStorage.setItem(draftKey,JSON.stringify({digest:digest,taskDigest:taskDigest,changes:ops,operation:operation,operationKind:operationKind,unknown:unknown}));localStorage.setItem(scenarioKey,JSON.stringify(scenarios));}catch(e){status('浏览器草稿空间不足；请导出草稿保留当前修改。',true);}}
    function controls(){
        if(!root)return;
        root.querySelectorAll('[data-mw-edit]').forEach(function(n){n.disabled=busy||unknown||draftConflict||refs.before.checked||!catalog;});
        refs.form.querySelectorAll('input,select,textarea,button').forEach(function(n){if(!n.dataset.originalDisabled)n.dataset.originalDisabled=n.disabled?'1':'0';n.disabled=n.dataset.originalDisabled==='1'||busy||unknown||draftConflict||refs.before.checked;});
        root.querySelectorAll('.mw-dialog-body input,.mw-dialog-body select,.mw-dialog-body textarea,.mw-dialog-body button,.workbench-modal-actions [data-action="save"]').forEach(function(n){if(!n.dataset.originalDisabled)n.dataset.originalDisabled=n.disabled?'1':'0';n.disabled=n.dataset.originalDisabled==='1'||busy;});
        refs.apply.disabled=busy||unknown||draftConflict||!valid||!ops.length;
        refs.undo.disabled=busy||unknown||draftConflict||ops.length>0||!refs.history.value;
        refs.refresh.disabled=busy;refs.reset.disabled=busy||unknown;refs.stepBack.disabled=busy||unknown||draftConflict||!ops.length;
        refs.scenarioA.disabled=busy||draftConflict;refs.scenarioB.disabled=busy||draftConflict;refs.readLive.disabled=busy||draftConflict||!!window.MapWorkbenchDevApi;
        refs.readLive.title=window.MapWorkbenchDevApi?'离线模式没有游戏实时事实':'';
        refs.editScenario.disabled=busy||draftConflict||refs.scenarioA.value==='live';refs.editScenarioB.disabled=busy||draftConflict||refs.scenarioB.value==='live';refs.copyScenario.disabled=busy||draftConflict;
        refs.side.disabled=draftConflict;refs.before.disabled=draftConflict;refs.editing.disabled=draftConflict||viewMode!=='author';
        refs.authorView.disabled=busy||draftConflict;refs.playerView.disabled=busy||draftConflict;
        refs.authorView.setAttribute('aria-pressed',String(viewMode==='author'));refs.playerView.setAttribute('aria-pressed',String(viewMode==='player'));
        refs.viewNote.textContent=viewMode==='author'?'隐藏内容仍可编辑，不改变游戏条件。':'按所选方案显示；画布只读，隐藏页面会说明原因。';
        root.querySelectorAll('[data-mw-camera]').forEach(function(n){n.disabled=draftConflict;});
        refs.conflictExport.disabled=busy;refs.conflictReset.disabled=busy||unknown;refs.conflictQuery.disabled=busy||!operation;
        refs.draftImport.disabled=busy||unknown||draftConflict;
        refs.count.textContent=ops.length+' 项草稿操作';
        refs.form.setAttribute('aria-busy',String(busy));renderFrame();
    }
    function markEdit(n){n.dataset.mwEdit='';return n;}
    function request(cmd,payload){
        if(busy)return Promise.reject(new Error('当前操作尚未完成'));
        var owner=epoch,focusId=document.activeElement?.id;busy=true;controls();
        return new Promise(function(resolve,reject){
            mux.request(cmd,payload||{},{singleFlight:true,write:['apply','undo','recover'].includes(cmd)},function(response){
                if(!active||owner!==epoch)return;
                busy=false;controls();
                if(!response.success){
                    if(['apply','undo','recover'].includes(cmd)){unknown=true;persist();}
                    var message=response.clientSynthetic?'请求结果尚未确认。写入会先核对结果，草稿继续保留。':response.error||'操作失败';
                    status(message,true);controls();reject(new Error(message));return;
                }
                resolve(response.data);
                if(focusId)queueMicrotask(function(){if(active&&!busy)document.getElementById(focusId)?.focus();});
            });
        });
    }
    function collection(definition,targetKind){
        if(!definition)return [];targetKind=targetKind||kind;
        if(targetKind==='task')return (catalog?.tasks||[]).map(function(t){var copy=U.clone(t);ops.filter(function(o){return o.kind==='task'&&o.id===String(t.id);}).forEach(function(o){Object.assign(copy,o.values);});return copy;});
        var dictionary={location:'locations',npc:'npcs',placement:'placements',rule:'rules'};
        if(dictionary[targetKind])return Object.keys(definition[dictionary[targetKind]]).map(function(key){return Object.assign({id:key},definition[dictionary[targetKind]][key]);});
        if(targetKind==='page')return definition.pageOrder.map(function(key){return definition.pages[key];});
        var page=definition.pages[pageId];if(!page)return [];
        if(targetKind==='filter')return page.filters.slice().sort(function(a,b){return a.buttonRect.y-b.buttonRect.y;});
        return targetKind==='avatar'?[...(page.staticAvatars||[]),...(page.dynamicAvatars||[])]:page[{scene:'sceneVisuals',hotspot:'hotspots',filter:'filters'}[targetKind]]||[];
    }
    function selected(definition){return collection(definition).find(function(x){return String(x.id)===selectedId;})||null;}
    function choose(targetKind,targetId){
        if(busy||unknown||draftConflict)return;kind=targetKind;selectedId=String(targetId);
        if(kind==='page')pageId=selectedId;
        refs.page.value=pageId;renderTree();updateFields();renderFrame();
    }
    function addOperation(operationValue){
        if(busy||unknown||draftConflict)return;
        var op=U.clone(operationValue),action=op.action||'edit';
        if(action==='edit'){
            var prior=[...ops].reverse().find(function(p){return p.kind===op.kind&&p.id===op.id&&(p.pageId||'')===(op.pageId||'')&&['edit','create'].includes(p.action||'edit');});
            if(prior)Object.assign(prior.values,op.values);else ops.push(op);
        }else ops.push(op);
        valid=false;persist();preview().catch(function(){});
    }
    function change(target,values){addOperation(Object.assign({},target,{values:values}));}
    function context(){
        var target={kind:kind,id:selectedId,pageId:pageId},definition=refs.before.checked?base:draft,item=selected(definition);
        return {shell:shell,kind:kind,id:selectedId,pageId:pageId,item:item,definition:definition,catalog:catalog,assets:assets,previewAssets:previewAssets,newId:id,
            change:function(values){change(target,values);},condition:function(key,label){editCondition(target,key,label,item[key]);},
            asset:function(key){assetLibrary(target,key);},variants:function(){editVariants(target,item.variants||[]);},
            taskEndpoints:function(){E.taskEndpoints(context(),function(values){change(target,values);});},
            openSource:function(sourceKind,sourceId){request('open-source',{kind:sourceKind,id:sourceId}).then(function(data){status('制作源：'+data.path);}).catch(function(){});}
        };
    }
    function scenario(which){
        var value=which==='B'?refs.scenarioB.value:refs.scenarioA.value;
        if(value==='live'){if(!live)throw new Error('尚未读取游戏事实；请点击“读取游戏事实”，或选择模拟方案。');return {label:'实时只读 · '+liveAt,facts:live};}
        var found=scenarios.find(function(s){return s.id===value;});if(!found)throw new Error('请先选择一个剧情方案。');return found;
    }
    async function preview(){
        if(draftConflict){status('项目已变化，旧草稿预览已暂停。请使用右侧处理入口。',true);showDraftConflict();return;}
        if(!catalog||!base)return;
        var a=scenario('A'),b=scenario('B');status('正在校验内容、引用与两个剧情方案…');
        var data=await request('preview',{expectedDigest:digest,expectedTaskDigest:taskDigest,changes:ops,facts:a.facts,compareFacts:b.facts});
        draft=data.definition;renderDefinition=data.renderDefinition;previewData=data;valid=true;
        previewAssets=Object.assign(previewAssets,data.previewAssets||{});
        (data.assets||[]).forEach(addAsset);refreshPageList();renderTree();updateFields();controls();
        status(ops.length?'草稿已通过内容与引用检查；“检查并应用”会列出全部变更文件。':'选中对象查看属性；剧情方案与运行中的游戏相互独立。');
    }
    function currentProjection(before,side){if(!previewData)return null;return previewData[(side==='B'?'compare':'')+(before?(side==='B'?'BaseProjection':'baseProjection'):(side==='B'?'Projection':'projection'))];}
    function showDraftConflict(){
        if(!busy)shell.setStatus('需要处理','error');
        refs.frame.hidden=true;refs.emptyPreview.hidden=true;refs.conflict.hidden=false;
        refs.conflictTitle.textContent=unknown?'本次写入尚未确认完成，预览已暂停':'旧草稿与当前项目不一致';
        refs.conflictText.textContent=unknown
            ?'当前项目已经更新，且有一笔写入尚未确认完成。请先核对写入结果；不要丢弃草稿或重复提交。'
            :'项目的地图或任务资料已经更新。已保留 '+ops.length+' 项未应用修改；旧草稿预览已暂停，继续等待不会自动解决。';
        refs.conflictReset.hidden=unknown;refs.conflictQuery.hidden=!unknown;
        refs.caption.textContent=unknown?'预览已暂停：请先核对写入结果。':'预览已暂停：请导出保留的草稿，或明确放弃试用修改后加载当前项目。';
    }
    function renderFrame(){
        if(draftConflict){showDraftConflict();return;}
        refs.conflict.hidden=true;
        if(!frameReady||!draft||!renderDefinition||!previewData)return;
        var before=refs.before.checked,side=refs.side.value,projection=currentProjection(before,side);
        if(!projection)return;
        var definition=before?baseRender:renderDefinition;
        var missing=!definition.pages[pageId];refs.frame.hidden=missing;refs.emptyPreview.hidden=!missing;
        if(missing){refs.emptyPreview.textContent=before?'保存前不存在这个页面。关闭“对比保存前”查看新页面。':'新页面尚未通过校验；请查看错误，或撤销草稿末步。';return;}
        var label;try{label=scenario(side).label;}catch(e){label='尚未选定方案';}
        refs.caption.textContent=(viewMode==='author'?'创作视图':'玩家预览')+' · '+definition.pages[pageId].title+' · '+(before?'磁盘原内容':valid?'当前草稿':'上次通过校验的预览（当前草稿尚未通过）')+' · '+label+' · '+(projection.snapshot.pageStates[pageId]?.visible?'该页面可见':'该方案中页面隐藏')+'；不执行导航或修改存档。';
        refs.frame.contentWindow.postMessage({type:'map-authoring-input',action:'state',session:frameSession,
            definition:definition,snapshot:projection.snapshot,previewAssets:previewAssets,pageId:pageId,kind:kind,id:selectedId,
            viewMode:viewMode,editing:viewMode==='author'&&refs.editing.checked,before:before,busy:busy||unknown,rasterScale:refs.frame.getBoundingClientRect().width/Math.max(1,refs.frame.clientWidth)},location.origin);
    }
    function refreshPageList(){
        if(!draft)return;var signature=JSON.stringify(draft.pageOrder.map(function(key){return [key,draft.pages[key].title];}));
        if(refs.page.dataset.signature!==signature){refs.page.replaceChildren();draft.pageOrder.forEach(function(key){var o=U.node('option','',draft.pages[key].title);o.value=key;refs.page.appendChild(o);});refs.page.dataset.signature=signature;}
        if(!draft.pages[pageId])pageId=draft.pageOrder[0];refs.page.value=pageId;
    }
    function renderTree(){
        if(!draft)return;var groups=Object.keys(E.names),rows=groups.map(function(group){return [group,collection(draft,group).map(function(it){return [String(it.id),it.label||it.title];})];});
        var signature=pageId+JSON.stringify(rows),oldScroll=refs.tree.scrollTop,focused=document.activeElement?.dataset.mwTree;
        if(signature!==treeSignature){
            treeSignature=signature;refs.tree.replaceChildren();
            rows.forEach(function(group){var details=U.node('details','mw-tree-group');details.open=group[0]===kind;
                var title=U.node('summary','',E.names[group[0]]+' · '+group[1].length);
                title.setAttribute('aria-label','选择内容类型：'+E.names[group[0]]);
                title.onclick=function(){choose(group[0],kind===group[0]&&group[1].some(function(it){return it[0]===selectedId;})?selectedId:group[1][0]?.[0]||'');};
                details.appendChild(title);
                var list=U.node('div','mw-tree-items');list.setAttribute('role','group');details.appendChild(list);
                group[1].forEach(function(item){var b=markEdit(U.button(item[1],function(){choose(group[0],item[0]);}));b.dataset.mwTree=group[0]+'/'+item[0];b.setAttribute('role','treeitem');b.setAttribute('aria-label','选择'+E.names[group[0]]+'：'+item[1]);list.appendChild(b);});
                refs.tree.appendChild(details);});
            refs.tree.scrollTop=oldScroll;if(focused)Array.from(refs.tree.querySelectorAll('[data-mw-tree]')).find(function(n){return n.dataset.mwTree===focused;})?.focus();
        }
        refs.tree.querySelectorAll('[data-mw-tree]').forEach(function(n){n.setAttribute('aria-selected',String(n.dataset.mwTree===kind+'/'+selectedId));});
        if(!selected(draft)){selectedId=String(collection(draft)[0]?.id||'');}
        controls();
    }
    function updateFields(){
        if(!draft||!catalog)return;var it=selected(refs.before.checked?base:draft);
        refs.objectTitle.textContent=it?(it.label||it.title):'尚未选择'+E.names[kind];
        refs.identity.textContent=it?'稳定标识：'+it.id+(it.locationId?' · 地点：'+draft.locations[it.locationId]?.label:''):'可新建对象或选择已有内容。';
        E.properties(refs.form,context());renderReasons();controls();
    }
    function objectReasons(projection){
        if(!projection)return [];var it=selected(draft);
        if(kind==='location')return [projection.locations[selectedId]?.visibleReason,projection.locations[selectedId]?.enterReason];
        if(kind==='hotspot')return [projection.locations[it?.locationId]?.visibleReason,projection.locations[it?.locationId]?.enterReason];
        if(kind==='placement')return [projection.placements[selectedId]?.reason];
        if(kind==='page')return [projection.snapshot.pageStates[selectedId]?.reason];
        if(kind==='scene')return [projection.visualReasons[pageId]?.[selectedId]];
        if(kind==='avatar')return [projection.avatarReasons[selectedId]];
        if(kind==='rule')return [projection.ruleReasons[selectedId]];return [];
    }
    function projectionSummary(p){
        if(!p)return '尚未取得投影';
        var it=selected(draft);
        if(kind==='task'){var roles=p.taskEndpoints[selectedId]||{};return ['get','finish'].map(function(role){var e=roles[role];return (role==='get'?'接取':'交付')+'：'+(e?.resolved?e.npcName+' · '+(draft.locations[e.locationId]?.label||'无地图位置'):(e?.reason||'未配置'));}).join('\n');}
        if(kind==='npc'){var places=Object.values(p.placements).filter(function(s){return s.npcId===selectedId&&s.present;});return '当前在场驻点：'+places.length+'；已接入真实实例：'+places.filter(function(s){return s.worldReady;}).length;}
        if(kind==='placement'){var s=p.placements[selectedId];return s?(s.present?'人物在场':'人物不在场')+' · '+(s.worldReady?'真实实例就绪':'真实实例未接入 / 来源变化')+(s.conflict?'\n'+s.conflict:''):'驻点不存在';}
        if(kind==='location'||kind==='hotspot'){var s=p.locations[kind==='location'?selectedId:it?.locationId];return s?(s.visible?'地图可见':'地图隐藏')+' · '+(s.enterable?'地点可进入':'地点不可进入'):'地点不存在';}
        if(kind==='scene'||kind==='avatar'){var visible=kind==='scene'?p.snapshot.visualVisibility[pageId]?.[selectedId]:p.snapshot.avatarVisibility[selectedId];return visible?'表现可见':'表现隐藏 / 事实未知';}
        return '';
    }
    function renderReasons(){
        refs.reasons.replaceChildren();if(!previewData)return;
        ['A','B'].forEach(function(side){var p=currentProjection(refs.before.checked,side),box=U.node('section','mw-scenario-result');
            var label;try{label=scenario(side).label;}catch(e){label='未选择';}
            box.appendChild(U.node('h3','','方案 '+side+' · '+label));box.appendChild(U.node('p','',projectionSummary(p)));
            objectReasons(p).filter(Boolean).forEach(function(reason){box.appendChild(U.reasonTree(reason));});
            if(kind==='avatar'||kind==='scene'){var appearance=kind==='avatar'?p.appearances.avatars[selectedId]:p.appearances.visuals[pageId]?.[selectedId];
                if(appearance){box.appendChild(U.node('p','','外观：'+(appearance.state==='unknown'?'未知，暂不显示':appearance.variantId?'命中变体 '+appearance.variantId:'默认图片')));
                    (appearance.branches||[]).forEach(function(b){box.appendChild(U.reasonTree(b.reason));});}}
            refs.reasons.appendChild(box);});
    }
    function editCondition(target,key,label,value){
        var editor=U.condition(value,catalog,draft);
        U.dialog(shell,label,editor.element,function(){change(target,{[key]:editor.value()});},'加入草稿','条件由 C# 同一求值器检查；未知事实不会默认放行。');
    }
    function editVariants(target,original){
        var variants=U.clone(original),ctx=context();
        function show(){
            if(!active)return;var body=U.node('div','mw-variants');
            body.appendChild(U.node('p','','从上到下采用第一个满足条件的外观；没有命中则用默认图片。更靠前条件未知时不猜测外观。'));
            variants.forEach(function(v,index){var card=U.node('fieldset');card.appendChild(U.node('legend','','外观变化 '+(index+1)));body.appendChild(card);
                U.field(card,'图片',v.assetUrl,{choices:E.assetChoices(ctx),change:function(url){v.assetUrl=url;}});
                card.appendChild(U.button('条件：'+U.conditionLabel(v.when,draft),function(){
                    var editor=U.condition(v.when,catalog,draft),modal=U.dialog(shell,'外观变化条件',editor.element,function(){v.when=editor.value();show();});
                    modal.spec.onClose=function(reason){if(reason==='escape'||reason==='action:cancel')show();};
                }));
                card.appendChild(U.button('移除这一变化',function(){variants.splice(index,1);show();}));
                if(index>0)card.appendChild(U.button('提高优先级',function(){[variants[index-1],variants[index]]=[variants[index],variants[index-1]];show();}));
            });
            var add=U.button('增加外观变化',function(){variants.push({id:'variant_'+id().slice(0,12),when:{type:'always'},assetUrl:E.assetChoices(ctx)[0]?.[0]||''});show();});add.disabled=variants.length>=16;body.appendChild(add);
            U.dialog(shell,'剧情外观变化',body,function(){change(target,{variants:variants});});
        }show();
    }
    function newObject(){if(kind==='task'){status('本工作台不增删任务。请选择其他内容类型。',true);return;}E.create(kind,context(),function(op){ops.push(op);kind=op.kind;selectedId=op.id;if(kind==='page')pageId=op.id;valid=false;persist();preview().catch(function(){});});}
    function copyObject(){
        if(kind!=='page'&&kind!=='scene'){status('可复制整页或图块；人物身份与驻点请显式新建。',true);return;}
        var next=kind+'_'+id().slice(0,12);addOperation({kind:kind,pageId:pageId,id:selectedId,action:'copy',values:{newId:next,title:(selected(draft).title||selected(draft).label)+'副本'}});
        selectedId=next;if(kind==='page')pageId=next;
    }
    function selectedReferences(){var key=kind+'/'+(kind==='filter'?pageId+'/':'')+selectedId;return previewData?.references?.[key]||[];}
    function referenceBody(){
        var body=U.node('div','mw-reference-list'),list=selectedReferences();
        body.appendChild(U.node('p','',list.length?'以下引用会受到影响：':'没有发现直接引用。最终操作仍由 C# 校验。'));
        list.forEach(function(r){var label=r.label;if(r.owner.startsWith('task/'))label=catalog.tasks.find(function(t){return String(t.id)===r.owner.slice(5);})?.title||label;
            body.appendChild(U.node('p','',(r.blocking?'需要先处理 · ':'关联影响 · ')+label+' · '+r.via));});return body;
    }
    function deleteObject(){
        if(!selected(draft)||kind==='task'){status('任务不在本工作台的删除范围。',true);return;}
        var target={kind:kind,pageId:pageId,id:selectedId,action:'delete',values:{}},list=selectedReferences(),body=referenceBody();
        var blocked=list.some(function(r){return r.blocking;});
        if(blocked)body.appendChild(U.node('p','','请先在对应对象中解绑或重绑；地点和驻点也可先取消“启用”。不会静默删除任务或其他消费者。'));
        U.dialog(shell,'删除'+E.names[kind]+'：'+(selected(draft).label||selected(draft).title),body,blocked?null:function(){addOperation(target);},'从草稿删除');
    }
    function reorder(delta){
        var list=collection(draft),at=list.findIndex(function(it){return String(it.id)===selectedId;});if(at<0||at+delta<0||at+delta>=list.length)return;
        if(!['page','scene','avatar','hotspot','filter'].includes(kind)){status('此类稳定身份不支持排序。',true);return;}
        if(kind==='avatar'){var page=draft.pages[pageId],group=(page.dynamicAvatars||[]).some(function(a){return a.id===selectedId;})?page.dynamicAvatars:page.staticAvatars;at=group.findIndex(function(a){return a.id===selectedId;});if(at+delta<0||at+delta>=group.length)return;}
        addOperation({kind:kind,pageId:pageId,id:selectedId,action:'reorder',values:{index:at+delta}});
    }
    function addAsset(asset){var at=assets.findIndex(function(a){return a.assetUrl===asset.assetUrl;});if(at<0)assets.push(asset);else assets[at]=asset;}
    function rememberAsset(data){if(data.cancelled)return false;addAsset(data.metadata);previewAssets[data.assetUrl]=data.previewDataUrl;status('图片已进入候选区，尚未写入发布目录。');return true;}
    function assetLibrary(target,key){
        var ctx=context(),selectedUrl=target&&selected(draft)?selected(draft)[key]||'':'',owner=epoch;
        if(!selectedUrl)selectedUrl=assets[0]?.assetUrl||'';
        function show(){
            if(!active||epoch!==owner)return;var body=U.node('div','mw-asset-library'),actions=U.node('div','mw-inline-actions');body.appendChild(actions);
            var select=U.field(body,'已有图片 / 未应用候选',selectedUrl,{choices:assets.map(function(a){return [a.assetUrl,E.assetLabel(a,draft)+' · '+a.width+'×'+a.height+(a.candidate?' · 候选':'')];}),change:function(v){selectedUrl=v;inspect();}});
            var view=U.node('div','mw-asset-compare'),meta=U.node('p','mw-readonly');body.append(view,meta);
            async function inspect(){
                if(!selectedUrl)return;try{var data=await request('asset-inspect',{assetUrl:selectedUrl});if(!active||owner!==epoch||modal.closed)return;
                    previewAssets[data.assetUrl]=data.previewDataUrl;addAsset(data.metadata);view.replaceChildren();
                    if(target&&selected(draft)?.[key]){var oldUrl=selected(draft)[key],figure=U.node('figure');figure.appendChild(U.node('figcaption','','当前对象使用'));var image=U.node('img');image.alt='当前对象的图片';image.src=previewAssets[oldUrl]||oldUrl;figure.appendChild(image);view.appendChild(figure);}
                    var figure=U.node('figure');figure.appendChild(U.node('figcaption','','选中候选'));var image=U.node('img');image.alt='选中图片的透明边缘与内容';image.src=data.previewDataUrl;figure.appendChild(image);view.appendChild(figure);
                    meta.textContent=data.metadata.width+'×'+data.metadata.height+' 像素 · '+Math.round((data.metadata.bytes||0)/1024)+' KiB\n来源：'+JSON.stringify(data.metadata.source||{kind:'已登记地图素材'})+'\n透明边缘在棋盘背景上显示。';
                }catch(e){}
            }
            actions.appendChild(U.button('从图片文件导入',function(){
                if(window.MapWorkbenchDevApi){refs.imageImport.onchange=async function(){var file=refs.imageImport.files[0];refs.imageImport.value='';if(!file)return;busy=true;controls();try{var data=await MapWorkbenchDevApi.uploadImage(file);busy=false;controls();if(active&&owner===epoch&&rememberAsset(data)){selectedUrl=data.assetUrl;show();}}catch(e){busy=false;controls();status(e.message,true);}};refs.imageImport.click();}
                else request('asset-pick',{}).then(function(data){if(rememberAsset(data)){selectedUrl=data.assetUrl;show();}}).catch(function(){});
            }));
            actions.appendChild(U.button('从发布元件提取',function(){extractAsset(function(data){selectedUrl=data.assetUrl;show();});}));
            actions.appendChild(U.button('裁切成新候选',function(){
                var a=assets.find(function(x){return x.assetUrl===selectedUrl;});if(!a)return;
                var crop={x:0,y:0,w:a.width,h:a.height},form=U.node('div','mw-form-grid');
                ['x','y','w','h'].forEach(function(k){U.field(form,({x:'像素左边',y:'像素上边',w:'像素宽度',h:'像素高度'})[k],crop[k],{type:'number',min:k==='w'||k==='h'?1:0,change:function(v){crop[k]=v;}});});
                U.dialog(shell,'裁切图片（原图保留）',form,function(){request('asset-crop',{assetUrl:selectedUrl,sourceDigest:a.sha256,crop:crop}).then(function(data){rememberAsset(data);selectedUrl=data.assetUrl;show();}).catch(function(){});},'生成候选');
            }));
            var modal=U.dialog(shell,'素材库 · 图片先进入候选',body,target?function(){if(!selectedUrl)return false;change(target,{[key]:selectedUrl});}:null,'用于当前对象');
            select.focus();inspect();
        }show();
    }
    function extractAsset(done){
        var body=U.node('div','mw-form-grid'),sources=catalog.assetSources||[],selected=0,frame=1,zoom=1;
        U.field(body,'已发现的发布元件','0',{choices:sources.map(function(s,i){return [String(i),s.linkage+' · '+s.sourceSwf+(s.ready?'':' · 不可直接提取')];}),change:function(v){selected=Number(v);detail.textContent=sources[selected].reason+'；共 '+sources[selected].frameCount+' 帧。';}});
        var detail=U.node('p','',sources[0]?.reason||'没有已发现来源。');body.appendChild(detail);
        U.field(body,'提取第几帧',frame,{type:'number',min:1,max:512,change:function(v){frame=v;}});U.field(body,'提取倍率',zoom,{type:'number',step:'.125',min:.125,max:2,change:function(v){zoom=v;}});
        U.dialog(shell,'从 SWF 生成静态图片候选',body,function(){var source=sources[selected];if(!source?.ready){status(source?.reason||'请选择可提取元件。',true);return false;}
            request('asset-extract',{sourceSwf:source.sourceSwf,sourceDigest:source.sourceDigest,linkage:source.linkage,frame:frame,zoom:zoom}).then(function(data){rememberAsset(data);done(data);}).catch(function(){});
        },'提取为候选','不输入数字 SpriteId。元件由真实发布目录发现，源摘要变化时拒绝提取；静态图片不执行 Flash 场景脚本。');
    }
    function scenarioOptions(){
        [refs.scenarioA,refs.scenarioB].forEach(function(select,index){var previous=select.value;select.replaceChildren();scenarios.forEach(function(s){var o=U.node('option','','模拟 · '+s.label);o.value=s.id;select.appendChild(o);});var o=U.node('option','','实时只读'+(live?' · '+liveAt:' · 尚未读取'));o.value='live';select.appendChild(o);select.value=[...scenarios.map(function(s){return s.id;}),'live'].includes(previous)?previous:scenarios[Math.min(index,scenarios.length-1)]?.id;});
        controls();
    }
    function editScenario(copyCurrent,side){
        side=side||'A';var selector=side==='B'?refs.scenarioB:refs.scenarioA;
        if(copyCurrent&&scenarios.length>=16){status('最多保留 16 个模拟方案。请编辑已有方案。',true);return;}
        var original;try{original=scenario(side);}catch(e){status(e.message,true);return;}
        if(!copyCurrent&&selector.value==='live')return;
        var value=copyCurrent?{id:id(),label:original.label+'副本',facts:U.clone(original.facts)}:U.clone(original);
        var editor=U.factEditor(value,catalog,draft,function(next){var at=scenarios.findIndex(function(s){return s.id===next.id;});if(at<0)scenarios.push(next);else scenarios[at]=next;persist();scenarioOptions();selector.value=next.id;preview().catch(function(){});});
        U.dialog(shell,copyCurrent?'复制为独立模拟方案':'编辑模拟方案',editor.element,editor.save,'保存模拟方案','不修改任何玩家存档。');
    }
    async function readLive(){
        var interests=new Set();function walk(v){if(!v||typeof v!=='object')return;if(v.type==='task'&&v.state==='available')interests.add(String(v.key));Object.values(v).forEach(walk);}walk(draft);if(kind==='task'&&selectedId)interests.add(selectedId);
        try{var data=await request('facts',{taskIds:Array.from(interests)});live=data.facts;liveAt=new Date(data.capturedAtUtc).toLocaleTimeString();scenarioOptions();refs.scenarioA.value='live';await preview();}catch(e){}
    }
    function review(){
        var body=U.node('div','mw-impact');(previewData?.impact||[]).forEach(function(file){body.appendChild(U.node('p','',(file.kind==='create'?'新增：':'更新：')+file.path));});
        body.appendChild(U.node('p','','记录恢复信息后逐文件替换；不是多文件系统原子事务。应用后请退出启动器并重新打开同一候选，不是只返回游戏标题页。撤回不会覆盖后续独立编辑。'));
        U.dialog(shell,'核对应用范围',body,function(){apply();},'应用以上 '+(previewData?.impact||[]).length+' 个文件');
    }
    async function apply(){operation=id();operationKind='apply';unknown=true;persist();try{var data=await request('apply',{expectedDigest:digest,expectedTaskDigest:taskDigest,changes:ops,operationId:operation});adopt(data);await loadCatalog();await preview();status('已应用到项目；请退出启动器后重新打开同一候选，再复验游戏。');}catch(e){if(unknown)await queryOperation();}}
    async function undo(){operation=refs.history.value;operationKind='undo';unknown=true;persist();try{var data=await request('undo',{operationId:operation});adopt(data);await loadCatalog();await preview();status('已精确撤回本批文件；请退出启动器后重新打开同一候选。');}catch(e){if(unknown)await queryOperation();}}
    async function queryOperation(){
        if(!operation)return;try{var data=await request('query',{operationId:operation});
            var complete=operationKind==='undo'?data.state==='original':data.state==='applied';
            if(complete&&data.definition){adopt(data);await loadCatalog();await preview();status(operationKind==='undo'?'已确认撤回完成。':'已确认应用完成。');}
            else{
                unknown=['partial','recovery_required'].includes(data.state);valid=false;
                if(data.state==='superseded'||data.definition&&(data.digest!==digest||data.taskDigest!==taskDigest))draftConflict=true;
                persist();controls();
                if(!unknown&&!draftConflict){await loadCatalog();await preview();}
                status(({original:'该批未应用或已回退，草稿保留。',not_found:'没有发生本次写入，草稿保留。',superseded:'项目已有后续修改，保护当前文件；可导出草稿后重读。',partial:'批次尚未完成，可点击“恢复未完成批次”。',recovery_required:'批次需要恢复；外部改动不会被覆盖。'})[data.state]||'已核对结果。',true);
            }
        }catch(e){}
    }
    function adopt(data,skipPersist){
        if(!data?.definition)return;base=data.definition;draft=U.clone(base);baseRender=data.renderDefinition;renderDefinition=baseRender;digest=data.digest;taskDigest=data.taskDigest||'';runtime=data.runtime||runtime;
        ops=[];unknown=false;valid=false;draftConflict=false;previewData=null;treeSignature='';refreshPageList();selectedId=String(collection(draft)[0]?.id||'');
        refs.history.replaceChildren(U.node('option','','选择已应用的批次…'));refs.history.firstChild.value='';
        (data.recent||[]).forEach(function(r){var state={applied:'已应用',original:'已撤回',prepared:'应用未完成',undoing:'撤回未完成'}[r.phase]||'历史记录';
            var when=r.createdAt?new Date(r.createdAt).toLocaleString():'未知时间';
            var o=U.node('option','',when+' · '+(r.changeCount?r.changeCount+' 项修改 · ':'')+state);o.value=r.operationId;o.title=r.operationId;refs.history.appendChild(o);});
        if(operation)refs.history.value=operation;
        refs.loadState.textContent=runtime?(runtime.definitionDigest===digest&&runtime.taskDigest===taskDigest?'磁盘内容与当前游戏加载内容一致。':'磁盘内容与当前游戏已加载内容不同；应用后重启生效。'):'离线作者模式：没有运行中的游戏会话。';
        if(!scenarios.length){scenarios=[{id:id(),label:'初始进度',facts:U.clone(data.initialFacts||{})},{id:id(),label:'对照进度',facts:U.clone(data.initialFacts||{})}];}
        scenarioOptions();if(!skipPersist)persist();
    }
    async function loadCatalog(){status('正在发现已发布场景、真实 NPC、任务源和素材…');catalog=await request('catalog',{});(catalog.assets||[]).forEach(addAsset);renderTree();updateFields();controls();}
    async function refresh(restore){
        if(unknown&&operation){await queryOperation();return;}
        if(!restore&&ops.length){await loadCatalog();await preview();return;}
        var saved=null;if(restore)try{saved=JSON.parse(localStorage.getItem(draftKey)||'null');var stored=JSON.parse(localStorage.getItem(scenarioKey)||'null');if(Array.isArray(stored)&&stored.length&&stored.length<=16&&stored.every(function(s){return /^[a-f0-9]{32}$/.test(s.id)&&typeof s.label==='string'&&s.label.length<=100&&s.facts&&typeof s.facts==='object'&&!Array.isArray(s.facts);}))scenarios=stored;}catch(e){}
        status('正在读取当前项目…');
        try{var data=await request('read',{});if(data.definition.version!==2){status('请先完成第二阶段地图迁移，再使用本内容创作工作台。',true);return;}adopt(data,restore);
            var contentChanged=false;
            if(restore&&saved&&Array.isArray(saved.changes)&&(saved.changes.length||saved.unknown===true)){
                ops=saved.changes;operation=saved.operation||'';operationKind=saved.operationKind||'';unknown=saved.unknown===true;
                contentChanged=saved.digest!==digest||saved.taskDigest!==taskDigest;
                if(contentChanged){digest=saved.digest;taskDigest=saved.taskDigest;valid=false;draftConflict=true;}
            }
            // 先恢复浏览器草稿；未知写入先查原批次，不能把自己已经完成的保存误判为外部冲突。
            persist();if(unknown&&operation){await queryOperation();return;}await loadCatalog();
            if(contentChanged){status('项目已变化，旧草稿预览已暂停。请在右侧选择保留导出、放弃试用草稿，或核对未确认写入。',true);controls();return;}
            if(unknown){await queryOperation();return;}await preview();persist();
        }catch(e){status(e.message||'地图内容读取失败，请重读或查看帮助。',true);}
    }
    function exportDraft(){var a=U.node('a'),url=URL.createObjectURL(new Blob([JSON.stringify({version:2,expectedDigest:digest,expectedTaskDigest:taskDigest,changes:ops},null,2)],{type:'application/json'}));a.href=url;a.download='map-content-draft.json';a.click();URL.revokeObjectURL(url);}
    function discardDraft(){
        if(busy||unknown)return;
        ops=[];draftConflict=false;valid=false;previewData=null;operation='';operationKind='';persist();
        refs.frame.hidden=false;refs.caption.textContent='正在重新读取当前项目并准备预览…';controls();
        refresh(false).catch(function(e){status(e.message,true);});
    }
    async function importDraft(file){
        if(draftConflict){status('请先处理旧草稿冲突，再导入与当前项目一致的草稿。',true);return;}
        if(!file||file.size>256*1024||busy||unknown){status('草稿须不超过 256 KiB，且当前没有未确认写入。',true);return;}
        var owner=epoch;try{var value=JSON.parse(await file.text());if(!active||epoch!==owner)return;
            if(value.version!==2||value.expectedDigest!==digest||value.expectedTaskDigest!==taskDigest||!Array.isArray(value.changes)||value.changes.length>256)throw new Error('草稿版本或原内容摘要不一致，请先核对。');
            var previous=ops;ops=value.changes;try{await preview();persist();}catch(e){ops=previous;valid=false;persist();throw e;}
        }catch(e){status(e.message,true);}
    }
    function camera(action,extra){if(frameReady)refs.frame.contentWindow.postMessage(Object.assign({type:'map-authoring-input',action:action,session:frameSession},extra||{}),location.origin);}
    function changeViewMode(mode){if(busy||draftConflict||viewMode===mode)return;viewMode=mode;controls();}
    function focusCanvas(){focusMode=!focusMode;shell.setProfile(focusMode?'canvas-editor-focus':'canvas-editor');refs.focus.textContent=focusMode?'显示属性':'专注画布';refs.focus.setAttribute('aria-pressed',String(focusMode));}
    function closePanel(){persist();Bridge.send({type:'panel',panel:'map-workbench',domain:'map_workbench',cmd:'close',callId:'map-close-'+id(),panelInstanceId:instance,payload:{}});}
    function close(reason){if(shell.hasModal()){shell.closeModal('escape');return;}if((!reason||reason==='escape')&&guide.isActive()){guide.close('escape');return;}if((!reason||reason==='escape')&&focusMode){focusCanvas();return;}closePanel();}
    function frameMessage(event){
        if(!active||event.source!==refs.frame.contentWindow||event.origin!==location.origin||event.data?.type!=='map-authoring-preview')return;
        var data=event.data;if(data.event==='ready'){frameReady=true;renderFrame();return;}if(data.session!==frameSession)return;
        if(data.event==='presentation'&&data.viewMode==='author'){changeViewMode('author');return;}
        if(data.event==='error'||data.event==='notice'){status(data.message,true);return;}
        if(data.event==='close'||data.event==='escape'){close('escape');return;}
        if(data.event==='view'){if(data.pageId===pageId&&data.viewMode===viewMode)refs.zoomLabel.textContent=Math.round(data.zoom*100)+'%';return;}
        if(data.event==='page-select'){if(data.pageId&&draft?.pages[data.pageId]&&data.pageId!==pageId&&!busy&&!unknown&&!draftConflict&&!guide.isActive()&&!shell.hasModal()){pageId=data.pageId;kind='page';selectedId=pageId;refs.page.value=pageId;treeSignature='';renderTree();updateFields();renderFrame();}return;}
        var targetKind=['scene','hotspot','avatar'].includes(data.kind)?data.kind:kind;
        if(busy||unknown||draftConflict||viewMode!=='author'||guide.isActive()||refs.before.checked||data.pageId!==pageId||!collection(draft,targetKind).some(function(x){return String(x.id)===data.id;}))return;
        if(kind!==targetKind)treeSignature='';kind=targetKind;selectedId=data.id;renderTree();updateFields();
        if(data.event==='move'&&['scene','avatar','hotspot'].includes(kind)&&Number.isFinite(data.dx)&&Number.isFinite(data.dy)){
            var it=selected(draft),target={kind:kind,id:selectedId,pageId:pageId};
            if(kind==='avatar')change(target,{relX:Math.round((it.relX+data.dx)*100)/100,relY:Math.round((it.relY+data.dy)*100)/100});
            else change(target,{rect:Object.assign({},it.rect,{x:Math.round((it.rect.x+data.dx)*100)/100,y:Math.round((it.rect.y+data.dy)*100)/100})});
        }
    }
    function create(){
        root=U.node('section','map-workbench-panel panel-scale-shell');shell=new Workbench.DualPaneShell({profile:'canvas-editor',title:'地图内容工作台',status:'读取内容',leftLabel:'内容对象与属性',rightLabel:'生产地图 · 剧情预览',slotMarkers:false});root.appendChild(shell.getRoot());
        guide=MapWorkbenchHelp.create({host:shell.getRoot(),onClose:closePanel,context:function(){var it=draft&&selected(draft);return {label:E.names[kind]+(it?' · '+(it.label||it.title||selectedId):'（尚未选择）'),changes:ops.length};}});
        help=new WorkbenchComponents.HelpAction({shell:shell,spec:{kind:'map-workbench-help',ariaLabel:'查看地图创作帮助',onOpen:function(opener){guide.open(opener);}}});
        var closeButton=U.button('关闭',closePanel);closeButton.dataset.headerAction='close';shell.addHeaderAction(closeButton);
        var left=U.node('div','mw-library'),scroll=U.node('div','mw-library-scroll'),right=U.node('div','mw-editor');left.appendChild(scroll);
        shell.mountInitial({instanceKey:'map-objects',mount:function(h){h.appendChild(left);},unmount:function(){}},{instanceKey:'map-preview',mount:function(h){h.appendChild(right);},unmount:function(){}});
        refs.page=markEdit(U.node('select'));refs.page.setAttribute('aria-label','地图页面');refs.page.onchange=function(){pageId=refs.page.value;kind='page';selectedId=pageId;treeSignature='';renderTree();updateFields();renderFrame();};scroll.appendChild(refs.page);
        var startGuide=U.button('第一次使用：跟着做一遍',function(){guide.open(startGuide,'入门练习');});scroll.appendChild(startGuide);
        var actions=U.node('div','mw-object-actions');[['新建',newObject],['复制',copyObject],['删除',deleteObject],['上移',function(){reorder(-1);}],['下移',function(){reorder(1);}],['查看引用',function(){U.dialog(shell,'所选内容的引用',referenceBody(),null);}]].forEach(function(x){actions.appendChild(markEdit(U.button(x[0],x[1])));});scroll.appendChild(actions);
        refs.tree=U.node('div','mw-object-tree');refs.tree.setAttribute('role','tree');refs.tree.setAttribute('aria-label','地图内容对象树');
        refs.tree.onkeydown=function(e){var nodes=Array.from(refs.tree.querySelectorAll('summary,[data-mw-tree]')).filter(function(n){return n.getClientRects().length>0;}),at=nodes.indexOf(document.activeElement),next=e.key==='ArrowDown'?at+1:e.key==='ArrowUp'?at-1:e.key==='Home'?0:e.key==='End'?nodes.length-1:-1;if(next>=0&&next<nodes.length){e.preventDefault();nodes[next].focus();}};scroll.appendChild(refs.tree);
        refs.objectTitle=U.node('h2');refs.identity=U.node('small','mw-identity');refs.form=U.node('div','mw-fields');
        var topicGuide=U.button('怎样编辑这类对象？',function(){guide.openFor(topicGuide,kind);});scroll.append(refs.objectTitle,refs.identity,topicGuide,refs.form);
        var reasons=U.node('details','mw-reason-section');reasons.appendChild(U.node('summary','','对照原因与当前值'));refs.reasons=U.node('div');reasons.appendChild(refs.reasons);scroll.appendChild(reasons);
        var history=U.node('details','mw-history');history.appendChild(U.node('summary','','应用历史 / 精确撤回'));refs.history=U.node('select');refs.history.setAttribute('aria-label','已应用批次');refs.history.onchange=controls;refs.undo=U.button('撤回所选批次',function(){undo();});history.append(refs.history,refs.undo);scroll.appendChild(history);
        var draftActions=U.node('div','mw-save-actions');refs.reset=U.button('放弃草稿重读',discardDraft);refs.refresh=U.button('重读 / 核对结果',function(){refresh(false).catch(function(e){status(e.message,true);});});refs.stepBack=U.button('撤销草稿末步',function(){ops.pop();valid=false;persist();preview().catch(function(){});});
        refs.draftImport=U.button('导入草稿',function(){refs.import.click();});
        draftActions.append(refs.stepBack,refs.reset,refs.refresh,U.button('导出草稿',exportDraft),refs.draftImport,U.button('恢复未完成批次',function(){if(!unknown||!operation){status('没有待恢复的本次批次。');return;}request('recover',{operationId:operation}).then(function(){unknown=false;queryOperation();}).catch(function(){});}));
        refs.import=U.node('input');refs.import.type='file';refs.import.accept='.json';refs.import.hidden=true;refs.import.onchange=function(){importDraft(refs.import.files[0]);refs.import.value='';};
        refs.imageImport=U.node('input');refs.imageImport.type='file';refs.imageImport.accept='image/png,image/webp,image/jpeg';refs.imageImport.hidden=true;draftActions.append(refs.import,refs.imageImport);scroll.appendChild(draftActions);
        var footer=U.node('div','mw-decision-footer');refs.apply=U.button('检查并应用',review);refs.apply.classList.add('mw-primary');refs.count=U.node('span','mw-count');refs.status=U.node('p','mw-status');refs.status.setAttribute('aria-live','polite');footer.append(refs.count,refs.apply,refs.status);left.appendChild(footer);
        var viewBar=U.node('div','mw-view-mode');viewBar.setAttribute('role','group');viewBar.setAttribute('aria-label','画布视图');
        refs.authorView=U.button('创作视图',function(){changeViewMode('author');});refs.playerView=U.button('玩家预览',function(){changeViewMode('player');});refs.viewNote=U.node('span');viewBar.append(refs.authorView,refs.playerView,refs.viewNote);right.appendChild(viewBar);
        var scenariosBar=U.node('div','mw-scenario-bar');refs.scenarioA=U.field(scenariosBar,'方案 A','',{choices:[]});refs.scenarioB=U.field(scenariosBar,'方案 B','',{choices:[]});
        [refs.scenarioA,refs.scenarioB].forEach(function(s){s.onchange=function(){preview().catch(function(e){status(e.message,true);});controls();};});
        refs.editScenario=U.button('编辑 A',function(){editScenario(false);});refs.editScenarioB=U.button('编辑 B',function(){editScenario(false,'B');});refs.copyScenario=U.button('复制 A 为模拟',function(){editScenario(true);});scenariosBar.append(refs.editScenario,refs.editScenarioB,refs.copyScenario);
        refs.readLive=U.button('读取游戏事实',readLive);scenariosBar.appendChild(refs.readLive);right.appendChild(scenariosBar);
        var bar=U.node('div','mw-toolbar');refs.side=U.field(bar,'显示方案','A',{choices:[['A','A'],['B','B']],change:function(){renderFrame();}});
        refs.before=U.field(bar,'对比保存前',false,{type:'checkbox',change:function(){renderFrame();updateFields();}});refs.editing=U.field(bar,'编辑边框',true,{type:'checkbox',change:renderFrame});
        bar.appendChild(U.button('−',function(){camera('zoom',{factor:1/1.25});}));refs.zoomLabel=U.node('span','mw-zoom','100%');bar.appendChild(refs.zoomLabel);bar.appendChild(U.button('+',function(){camera('zoom',{factor:1.25});}));
        bar.appendChild(U.button('玩家取景',function(){camera('fit');}));bar.appendChild(U.button('聚焦所选',function(){camera('focus');}));refs.focus=U.button('专注画布',focusCanvas);refs.focus.setAttribute('aria-pressed','false');bar.appendChild(refs.focus);
        bar.querySelectorAll('button').forEach(function(button){if(button!==refs.focus)button.dataset.mwCamera='';});
        bar.appendChild(markEdit(U.button('素材库 / 导入',function(){var target=['scene','avatar'].includes(kind)&&selected(draft)?{kind:kind,id:selectedId,pageId:pageId}:null;assetLibrary(target,target?'assetUrl':'');})));right.appendChild(bar);
        refs.frame=U.node('iframe','mw-preview');refs.frame.title='真实生产地图剧情预览';refs.frame.setAttribute('sandbox','allow-scripts allow-same-origin');right.appendChild(refs.frame);
        refs.emptyPreview=U.node('p','mw-empty-preview');refs.emptyPreview.hidden=true;right.appendChild(refs.emptyPreview);
        refs.conflict=U.node('section','mw-draft-conflict');refs.conflict.hidden=true;refs.conflict.setAttribute('role','region');refs.conflict.setAttribute('aria-label','处理旧草稿冲突');
        var conflictCard=U.node('div','mw-conflict-card');refs.conflictTitle=U.node('h2');refs.conflictText=U.node('p');refs.conflictText.setAttribute('role','status');
        var conflictActions=U.node('div','mw-inline-actions');refs.conflictExport=U.button('导出保留的草稿',exportDraft);refs.conflictReset=U.button('放弃试用草稿并加载当前项目',discardDraft);refs.conflictQuery=U.button('核对写入结果',queryOperation);
        conflictActions.append(refs.conflictExport,refs.conflictReset,refs.conflictQuery);
        conflictCard.append(refs.conflictTitle,refs.conflictText,conflictActions,U.node('p','mw-conflict-note','放弃只清除未应用草稿，不撤回已保存内容或修改玩家存档。导出的旧草稿需核对后迁回，不能直接覆盖新版本。'));
        refs.conflict.appendChild(conflictCard);right.appendChild(refs.conflict);
        refs.caption=U.node('small','mw-caption','正在准备地图内容预览…');refs.loadState=U.node('small','mw-load-state');right.append(refs.caption,refs.loadState);
        mux=new PanelRuntime.PanelRequestMux({send:function(m){return Bridge.send(m);},router:PanelRuntime.sharedResponseRouter,timeoutMs:60000,callPrefix:'map-edit',
            createMessage:function(c){return {type:'panel',panel:'map-workbench',domain:'map_workbench',cmd:c.entry.cmd,callId:c.entry.callId,panelInstanceId:c.session.panelInstanceId,payload:c.payload};},
            validateResponse:function(d,e,s){return d.type==='panel_resp'&&d.panel==='map-workbench'&&d.domain==='map_workbench'&&d.cmd===e.cmd&&d.callId===e.callId&&d.panelInstanceId===s.panelInstanceId;}});
        return root;
    }
    function cleanup(){if(!active)return;persist();active=false;epoch++;guide.close('panel-close');mux.closeSession();lifetime?.dispose();lifetime=null;refs.frame.src='about:blank';frameReady=false;if(scale)scale.detach();scale=null;shell.closeModal('panel-close');}
    function open(node,data){
        if(!data?.panelInstanceId)return false;if(active)cleanup();active=true;epoch++;instance=data.panelInstanceId;busy=false;unknown=false;valid=false;draftConflict=false;operation='';catalog=null;previewData=null;assets=[];previewAssets={};scenarios=[];live=null;treeSignature='';viewMode='author';refs.before.checked=false;
        refs.conflict.hidden=true;refs.frame.hidden=false;refs.caption.textContent='正在准备地图内容预览…';
        frameSession=id();frameReady=false;lifetime=new WorkbenchLifecycle.DisposableStack();window.addEventListener('message',frameMessage);lifetime.defer(function(){window.removeEventListener('message',frameMessage);});
        mux.openSession({panelInstanceId:instance});scale=PanelScale.attach(root,1024,576,{onUpdate:renderFrame});refs.frame.src='modules/map/authoring/preview.html';refresh(true);return true;
    }
    Panels.register('map-workbench',{create:create,onOpen:open,onRebind:open,onRequestClose:close,onClose:cleanup});
})();
