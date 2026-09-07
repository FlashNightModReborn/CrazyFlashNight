/* 地图内容表单：稳定身份只读，编辑范围由 C# 维护内核再次验证。 */
(function(root) {
    'use strict';
    var U=root.MapAuthoringControls;
    var names={page:'地图页',hotspot:'地点表现',scene:'场景图块',filter:'分层',avatar:'人物头像',location:'物理地点',npc:'人物身份',placement:'人物驻点',rule:'剧情条件',task:'任务端点'};
    function choices(ctx,kind){return U.labels(ctx.definition[({location:'locations',npc:'npcs',placement:'placements',rule:'rules'})[kind]]);}
    function assetChoices(ctx){return (ctx.assets||ctx.catalog.assets||[]).filter(function(a){return a.ready!==false;}).map(function(a){return [a.assetUrl,assetLabel(a,ctx.definition)+' · '+a.width+'×'+a.height];});}
    function assetLabel(asset,definition){
        if(asset.ready===false)return '不可用：'+asset.assetUrl.split('/').pop()+' · '+asset.error;
        for(var page of Object.values(definition.pages||{}))for(var item of [...(page.sceneVisuals||[]),...(page.staticAvatars||[])])if(item.assetUrl===asset.assetUrl)return item.label;
        return asset.source?.name||asset.source?.linkage||asset.assetUrl.split('/').pop();
    }
    function eligibleWorld(ctx,npcId,locationId){var npc=ctx.definition.npcs[npcId],loc=ctx.definition.locations[locationId];if(!npc||!loc)return [];
        return Object.values(ctx.catalog.occurrences||{}).filter(function(o){return o.ready&&o.sceneKey===loc.sceneName&&[...npc.runtimeNames,...npc.aliases].includes(o.taskName);});}
    function worldFields(host,ctx,value,changed){
        var eligible=eligibleWorld(ctx,value.npcId,value.locationId),old=value.worldBinding,items=[['','只配置地图展示，暂不接入真实实例']].concat(eligible.map(function(o){return [o.occurrenceId,o.runtimeName+' · '+o.sceneKey+(o.instanceName?' · '+o.instanceName:'')];}));
        var select=U.field(host,'真实场景中的 NPC 实例',old?.occurrenceId||'',{choices:items,change:function(id){var o=eligible.find(function(x){return x.occurrenceId===id;});changed(o?{occurrenceId:o.occurrenceId,sourceDigest:o.sourceDigest}:null);}});
        if(old){var match=eligible.find(function(o){return o.occurrenceId===old.occurrenceId;});
            host.appendChild(U.node('p','mw-world-status',match&&match.sourceDigest===old.sourceDigest?'真实实例已绑定；在场与否由剧情投影决定。':'来源缺失或发生变化，请重新绑定。'));
            if(match)host.appendChild(U.button('更新该实例的来源绑定',function(){changed({occurrenceId:match.occurrenceId,sourceDigest:match.sourceDigest});}));
        }else host.appendChild(U.node('p','mw-world-status','地图展示已配置 ≠ 真实 NPC 已接入。'+(eligible.length?'请选择上方实例完成接入。':'当前没有匹配且就绪的实例，请在场景制作源补齐。')));
        return select;
    }
    function properties(host,ctx){
        host.replaceChildren();var item=ctx.item;if(!item){host.appendChild(U.node('p','','这里还没有对象，可点击“新建”。'));return;}
        function edit(key,label,opts){U.field(host,label,item[key],Object.assign({},opts,{id:'mw-'+key,change:function(v){ctx.change({[key]:v});}}));}
        if(ctx.kind==='task'){
            host.appendChild(U.node('p','','只维护这个既有任务的接取与交付端点。任务 ID、前置、目标、对白、奖励及远程交付开关均为只读。'));
            host.appendChild(U.button('编辑接取 / 交付端点',ctx.taskEndpoints));
            host.appendChild(U.node('p','mw-readonly','任务链：'+item.chain+'\n来源：'+item.sourceFile+'\n前置：'+JSON.stringify(item.prerequisites||[])+'\n奖励：'+JSON.stringify(item.rewards||[])));
            host.appendChild(U.button('打开任务制作源',function(){ctx.openSource('task',ctx.id);}));return;
        }
        edit(ctx.kind==='page'?'title':'label','显示名称');
        if(ctx.kind==='page'){edit('tabLabel','页签名称');edit('width','页面宽度',{type:'number',min:1});edit('height','页面高度',{type:'number',min:1});}
        if(['location','placement'].includes(ctx.kind))edit('enabled','启用',{type:'checkbox'});
        if(ctx.kind==='hotspot')edit('locationId','所代表的物理地点',{choices:choices(ctx,'location')});
        if(ctx.kind==='location'){
            U.field(host,'真实场景',item.sceneName,{disabled:true});host.appendChild(U.node('small','','场景类型由已发布来源确认；复制表现不复制路由。'));
            host.appendChild(U.button('打开场景制作源',function(){ctx.openSource('scene',item.sceneName);}));
        }
        if(ctx.kind==='npc'){
            edit('placementPolicy','驻点数量策略',{choices:[['unique','同时只在一处'],['multiple','允许同时多处（跟随仍须唯一）']]});
            ['runtimeNames','aliases'].forEach(function(key){var field=U.field(host,key==='runtimeNames'?'现场任务检索名（每行一个）':'历史别名（每行一个）',(item[key]||[]).join('\n'),{multiline:true});
                field.onchange=function(){ctx.change({[key]:field.value.split('\n').map(function(x){return x.trim();}).filter(Boolean)});};});
        }
        if(ctx.kind==='placement'){
            edit('npcId','人物身份',{choices:choices(ctx,'npc')});edit('locationId','驻点位置',{choices:choices(ctx,'location')});
            worldFields(host,ctx,item,function(binding){ctx.change({worldBinding:binding});});
            if(item.worldBinding)host.appendChild(U.button('打开 NPC 制作源',function(){ctx.openSource('npc',item.worldBinding.occurrenceId);}));
        }
        if(ctx.kind==='avatar'){
            var views=ctx.definition.pages[ctx.pageId].hotspots;
            var availablePlaces=choices(ctx,'placement').filter(function(p){return views.some(function(h){return h.locationId===ctx.definition.placements[p[0]].locationId;});});
            U.field(host,'人物驻点',item.placementId,{choices:availablePlaces,change:function(id){var p=ctx.definition.placements[id],h=views.find(function(h){return h.id===item.hotspotId&&h.locationId===p.locationId;})||views.find(function(h){return h.locationId===p.locationId;});ctx.change({placementId:id,hotspotId:h.id});}});
            edit('hotspotId','头像附着的地点表现',{choices:views.filter(function(h){return h.locationId===ctx.definition.placements[item.placementId].locationId;}).map(function(h){return [h.id,h.label];})});
            [['relX','相对地点横坐标'],['relY','相对地点纵坐标'],['w','宽度'],['h','高度']].forEach(function(p){edit(p[0],p[1],{type:'number',step:'.1'});});
        }
        if(ctx.kind==='scene'||ctx.kind==='hotspot'){
            var rect=item.rect;['x','y','w','h'].forEach(function(key){U.field(host,({x:'横坐标',y:'纵坐标',w:'宽度',h:'高度'})[key],rect[key],{id:'mw-'+key,type:'number',step:'.1',change:function(v){ctx.change({rect:Object.assign({},rect,{[key]:v})});}});});
            if(ctx.kind==='hotspot')host.appendChild(U.node('small','','已连接图块时，地点边界随图块并集更新。'));
        }
        if(ctx.kind==='filter'){
            U.field(host,'分层显示顺序（越小越靠前）',item.buttonRect.y,{id:'mw-order',type:'number',change:function(v){ctx.change({buttonRect:Object.assign({},item.buttonRect,{y:v})});}});
            edit('viewMode','表现方式',{choices:[['default','普通分层'],['hierarchy','层级关系视图']]});
        }
        if(ctx.kind==='scene'||ctx.kind==='filter'){
            var h=U.node('fieldset','mw-memberships');h.appendChild(U.node('legend','','包含的地点表现'));host.appendChild(h);
            ctx.definition.pages[ctx.pageId].hotspots.forEach(function(spot){U.field(h,spot.label,(item.hotspotIds||[]).includes(spot.id),{type:'checkbox',disabled:ctx.kind==='filter'&&ctx.id==='all',change:function(checked){var list=(item.hotspotIds||[]).filter(function(id){return id!==spot.id;});if(checked)list.push(spot.id);ctx.change({hotspotIds:list});}});});
        }
        if(ctx.kind==='scene'){
            var f=U.node('fieldset','mw-memberships');f.appendChild(U.node('legend','','图块出现在哪些分层'));host.appendChild(f);
            ctx.definition.pages[ctx.pageId].filters.forEach(function(filter){U.field(f,filter.label,(item.filterIds||[]).includes(filter.id),{type:'checkbox',change:function(checked){var list=(item.filterIds||[]).filter(function(id){return id!==filter.id;});if(checked)list.push(filter.id);ctx.change({filterIds:list});}});});
        }
        if(['page','scene','avatar'].includes(ctx.kind)){
            var assetKey=ctx.kind==='page'?'backgroundAssetUrl':'assetUrl';
            if(!(ctx.kind==='avatar'&&item.kind==='roommateGender')){
                host.appendChild(U.button(ctx.kind==='page'?'选择 / 导入背景':'选择 / 导入图片',function(){ctx.asset(assetKey);}));
                if(item[assetKey]){var img=U.node('img','mw-asset-thumb');img.src=ctx.previewAssets[item[assetKey]]||item[assetKey];img.alt='当前'+names[ctx.kind]+'图片';host.appendChild(img);}
                if(ctx.kind==='page'&&item[assetKey])host.appendChild(U.button('移除背景图片',function(){ctx.change({backgroundAssetUrl:null});}));
            }
            if(ctx.kind!=='page')host.appendChild(U.button('编辑剧情外观变化（'+(item.variants||[]).length+' 项）',ctx.variants));
        }
        var conditions=ctx.kind==='location'?['visibleWhen','enterWhen']:ctx.kind==='placement'?['presenceWhen']:ctx.kind==='rule'?['condition']:['page','scene','avatar'].includes(ctx.kind)?['visibleWhen']:[];
        conditions.forEach(function(key){var label={visibleWhen:'显示条件',enterWhen:'可进入条件',presenceWhen:'人物在场条件',condition:'条件内容'}[key];
            var b=U.button(label+'：'+U.conditionLabel(item[key],ctx.definition),function(){ctx.condition(key,label);});b.classList.add('mw-wide');host.appendChild(b);});
    }
    function create(kind,ctx,commit){
        var body=U.node('div','mw-form-grid'),value={},nextId=kind+'_'+ctx.newId().slice(0,12);
        U.field(body,'名称','新'+names[kind],{change:function(v){value[kind==='page'?'title':'label']=v;}});value[kind==='page'?'title':'label']='新'+names[kind];
        function choose(key,label,items){value[key]=items[0]?.[0]||'';U.field(body,label,value[key],{choices:items,change:function(v){value[key]=v;}});}
        if(kind==='page')value.tabLabel=value.title;
        if(kind==='location'){
            var used=Object.values(ctx.definition.locations).map(function(l){return l.sceneName;});
            var scenes=Object.values(ctx.catalog.scenes||{}).filter(function(s){return s.ready&&!used.includes(s.sceneKey);});
            if(!scenes.length){body.appendChild(U.node('p','','没有尚未登记的已就绪场景。已有地点请复用“地点表现”；新场景请先在制作源发布并接入。'));U.dialog(ctx.shell,'新增物理地点',body,null);return;}
            choose('sceneName','已接入且尚未登记的真实场景',scenes.map(function(s){return [s.sceneKey,s.sceneKey];}));value.sceneKind=scenes[0].sceneKind;
        }
        if(kind==='npc'){
            var usedNames=Object.values(ctx.definition.npcs).flatMap(function(n){return [...n.runtimeNames,...n.aliases].map(function(s){return s.toLowerCase();});});
            var known=[...new Set(Object.values(ctx.catalog.occurrences||{}).filter(function(o){return o.ready;}).map(function(o){return o.taskName;}).filter(function(name){return name&&!usedNames.includes(name.toLowerCase());}))];
            if(!known.length){body.appendChild(U.node('p','','已发现的人物都已登记，请复用原人物身份；新增 NPC 本体请先在场景制作源完成并发布。'));U.dialog(ctx.shell,'新建人物身份',body,null);return;}
            choose('runtimeName','真实 NPC 的任务检索名',known.map(function(s){return [s,s];}));value.aliases=[];
        }
        if(kind==='hotspot')choose('locationId','复用的物理地点',choices(ctx,'location'));
        if(kind==='scene'||kind==='avatar')choose('assetUrl','已校验的图片',assetChoices(ctx));
        if(kind==='scene'){
            choose('hotspotId','关联地点表现',ctx.definition.pages[ctx.pageId].hotspots.map(function(h){return [h.id,h.label];}));
            body.appendChild(U.node('p','','需要新图片时，可先关闭此页，点击“素材库 / 导入”，再新建图块。'));
        }
        if(kind==='avatar'){
            var views=ctx.definition.pages[ctx.pageId].hotspots;
            var places=choices(ctx,'placement').filter(function(p){return views.some(function(h){return h.locationId===ctx.definition.placements[p[0]].locationId;});});
            if(!places.length){body.appendChild(U.node('p','','请先为本页某个物理地点创建人物驻点，再添加头像。'));U.dialog(ctx.shell,'新建人物头像',body,null);return;}
            value.placementId=places[0][0];var anchors=U.node('div');
            function showAnchors(){anchors.replaceChildren();var matches=views.filter(function(h){return h.locationId===ctx.definition.placements[value.placementId].locationId;});value.hotspotId=matches[0].id;U.field(anchors,'头像附着的地点表现',value.hotspotId,{choices:matches.map(function(h){return [h.id,h.label];}),change:function(id){value.hotspotId=id;}});}
            U.field(body,'人物驻点',value.placementId,{choices:places,change:function(id){value.placementId=id;showAnchors();}});body.appendChild(anchors);showAnchors();
        }
        if(kind==='placement'){choose('npcId','人物身份',choices(ctx,'npc'));choose('locationId','驻点位置',choices(ctx,'location'));body.appendChild(U.node('p','','创建后在属性栏绑定真实实例和人物在场条件。'));}
        U.dialog(ctx.shell,'新建'+names[kind],body,function(){
            if(kind==='page')value.tabLabel=value.title;
            if(kind==='npc'){value.runtimeNames=[value.runtimeName];delete value.runtimeName;}
            if(kind==='scene'){value.hotspotIds=value.hotspotId?[value.hotspotId]:[];delete value.hotspotId;}
            commit({kind:kind,id:nextId,pageId:ctx.pageId,action:'create',values:value});
        });
    }
    function taskEndpoints(ctx,commit){
        var body=U.node('div','mw-endpoint-editor'),fields={};
        body.appendChild(U.node('p','','旧任务空地点表示任意同名现场。改为固定驻点会收窄匹配；跟随模式必须唯一解析出在场且已接入的真实 NPC。奖励、对白和其他任务内容不改变。'));
        ['get','finish'].forEach(function(role){var card=U.node('fieldset','mw-endpoint');card.appendChild(U.node('legend','',role==='get'?'接取端点':'交付端点'));body.appendChild(card);
            var original=ctx.item[role+'_endpoint'],state=original?U.clone(original):{mode:'legacy',npcId:Object.keys(ctx.definition.npcs)[0]||'',placementId:''};fields[role]={original:original,state:state};
            U.field(card,'选择方式',state.mode,{choices:(original?[]:[['legacy','保留旧任务设置']]).concat([['fixed','固定驻点'],['followCurrent','跟随当前唯一驻点']]),change:function(v){state.mode=v;details();}});
            var part=U.node('div');card.appendChild(part);
            function details(){part.replaceChildren();if(state.mode==='legacy'){part.appendChild(U.node('p','',(ctx.item[role+'_npc']||'未配置人物')+' · '+(ctx.item[role+'_npc_hotspot']||'任意同名现场')));return;}
                U.field(part,'人物身份',state.npcId,{choices:choices(ctx,'npc'),change:function(v){state.npcId=v;state.placementId='';details();}});
                if(state.mode==='fixed'){var places=Object.keys(ctx.definition.placements).filter(function(id){return ctx.definition.placements[id].npcId===state.npcId;});
                    if(!places.includes(state.placementId))state.placementId=places[0]||'';
                    U.field(part,'固定驻点',state.placementId,{choices:places.map(function(id){var p=ctx.definition.placements[id];return [id,p.label+' · '+ctx.definition.locations[p.locationId].label];}),change:function(v){state.placementId=v;}});
                }else delete state.placementId;
            }details();
        });
        U.dialog(ctx.shell,'编辑任务：'+ctx.item.title,body,function(){var updates={};Object.keys(fields).forEach(function(role){var f=fields[role];if(f.state.mode!=='legacy'&&JSON.stringify(f.state)!==JSON.stringify(f.original))updates[role+'_endpoint']=f.state;});if(Object.keys(updates).length)commit(updates);});
    }
    root.MapAuthoringEditors={names:names,properties:properties,create:create,taskEndpoints:taskEndpoints,assetChoices:assetChoices,assetLabel:assetLabel};
})(window);
