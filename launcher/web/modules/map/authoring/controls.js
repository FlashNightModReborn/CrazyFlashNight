/* 地图作者控件：只组装结构化意图和模拟事实，不求值游戏规则。 */
(function(root) {
    'use strict';
    function clone(value) { return JSON.parse(JSON.stringify(value)); }
    function node(tag, cls, text) { var n=document.createElement(tag);n.className=cls||'';if(text!==undefined)n.textContent=text;return n; }
    function button(text, callback) { var n=node('button','mw-button',text);n.type='button';n.onclick=callback;return n; }
    function field(host, text, value, options) {
        options=options||{};var label=node('label','mw-field',text),input;
        if(options.choices) {
            input=node('select');options.choices.forEach(function(choice){var id=Array.isArray(choice)?choice[0]:choice,labelText=Array.isArray(choice)?choice[1]:choice;
                var option=node('option','',labelText);option.value=id;input.appendChild(option);});
        } else { input=node(options.multiline?'textarea':'input');if(!options.multiline)input.type=options.type||'text';if(input.type==='number')input.step=options.step||'1'; }
        if(input.type==='checkbox')input.checked=value===true;else input.value=value===undefined||value===null?'':value;
        input.setAttribute('aria-label',text);input.id=options.id||'';input.disabled=options.disabled===true;
        if(options.change)input.onchange=function(){options.change(input.type==='checkbox'?input.checked:input.type==='number'?Number(input.value):input.value);};
        if(options.min!==undefined)input.min=options.min;if(options.max!==undefined)input.max=options.max;
        label.appendChild(input);host.appendChild(label);return input;
    }
    function dialog(shell, title, body, save, label, detail) {
        var modal=shell.openModal({kind:'map-authoring-editor',title:title,detail:detail||'',actions:[{id:'cancel',label:'返回'},
            ...(save?[{id:'save',label:label||'加入草稿',primary:true,close:false,onSelect:function(){if(save()!==false&&!modal.closed)shell.closeModal('saved');}}]:[])]});
        if(!modal)return null;body.classList.add('mw-dialog-body');modal.dialog.insertBefore(body,modal.dialog.querySelector('.workbench-modal-actions'));
        var focus=body.querySelector('input,select,button,textarea');if(focus)focus.focus();return modal;
    }
    function labels(values, property) { return Object.keys(values||{}).map(function(id){return [id,values[id][property||'label']||id];}); }
    var types=[['always','总是满足'],['all','全部满足'],['any','任一满足'],['rule','引用已有条件'],['chain','任务链区间'],['task','任务状态'],['infra','基建等级 / 交通工具'],['flag','世界事实']];
    var taskStates=[['finished','历史已完成'],['notFinished','历史未完成'],['active','当前进行中'],['deliverable','已达成交付条件'],['available','当前可以接取']];
    function defaultRule(type,catalog,definition) {
        if(type==='all'||type==='any')return {type:type,children:[{type:'always'}]};
        if(type==='chain')return {type:type,key:(catalog.chains||[])[0]||'主线',min:0};
        if(type==='task')return {type:type,key:String((catalog.tasks||[])[0]?.id||'0'),state:'finished'};
        if(type==='infra')return {type:type,key:(catalog.infrastructure||[])[0]||'自行车',min:1};
        if(type==='flag')return {type:type,key:(catalog.flags||[])[0]?.id||'',value:true};
        if(type==='rule')return {type:type,key:Object.keys(definition.rules||{})[0]||''};
        return {type:'always'};
    }
    function condition(value, catalog, definition) {
        var current=clone(value||{type:'always'}),host=node('div','mw-condition-editor');
        function render() {host.replaceChildren();build(current,host,0,function(next){current=next;render();});}
        function build(rule,parent,depth,replace) {
            var row=node('fieldset','mw-condition-node');row.appendChild(node('legend','','条件 '+(depth+1)));parent.appendChild(row);
            field(row,'判断方式',rule.type,{choices:types.filter(function(t){return t[0]!=='flag'||(catalog.flags||[]).length>0;}),change:function(type){replace(defaultRule(type,catalog,definition));}});
            if(rule.type==='all'||rule.type==='any') {
                (rule.children||[]).forEach(function(child,index){var group=node('div','mw-condition-child');row.appendChild(group);
                    build(child,group,depth+1,function(next){rule.children[index]=next;render();});
                    var remove=button('移除这个条件',function(){rule.children.splice(index,1);render();});remove.disabled=rule.children.length<2;group.appendChild(remove);});
                var add=button('增加子条件',function(){rule.children.push({type:'always'});render();});add.disabled=depth>=6||rule.children.length>=32;row.appendChild(add);
            } else if(rule.type==='rule') field(row,'条件名称',rule.key,{choices:labels(definition.rules),change:function(v){rule.key=v;}});
            else if(rule.type==='chain'||rule.type==='infra') {
                field(row,rule.type==='chain'?'任务链':'基建项目',rule.key,{choices:rule.type==='chain'?catalog.chains:catalog.infrastructure,change:function(v){rule.key=v;}});
                field(row,'至少',rule.min===undefined?'':rule.min,{type:'number',min:0,change:function(v){rule.min=v;}});
                var maximum=field(row,'至多（留空表示无上限）',rule.max===undefined?'':rule.max,{type:'number',min:0});
                maximum.onchange=function(){if(maximum.value==='')delete rule.max;else rule.max=Number(maximum.value);};
            } else if(rule.type==='task') {
                field(row,'任务',rule.key,{choices:(catalog.tasks||[]).map(function(t){return [String(t.id),t.title+' · '+t.id];}),change:function(v){rule.key=v;}});
                field(row,'状态',rule.state,{choices:taskStates,change:function(v){rule.state=v;}});
            } else if(rule.type==='flag') {
                field(row,'世界事实',rule.key,{choices:(catalog.flags||[]).map(function(f){return [f.id,f.label];}),change:function(v){rule.key=v;}});
                field(row,'要求存在',rule.value,{type:'checkbox',change:function(v){rule.value=v;}});
            }
        }
        render();return {element:host,value:function(){return clone(current);}};
    }
    function conditionLabel(rule,definition) {
        if(!rule)return '未配置';if(rule.type==='always')return '总是满足';if(rule.type==='rule')return definition.rules?.[rule.key]?.label||'条件引用';
        if(rule.type==='all'||rule.type==='any')return (rule.type==='all'?'全部':'任一')+'满足 · '+rule.children.length+' 项';
        if(rule.type==='chain'||rule.type==='infra')return rule.key+' ≥ '+(rule.min===undefined?0:rule.min)+(rule.max===undefined?'':'，≤ '+rule.max);
        if(rule.type==='task')return '任务 '+rule.key+' · '+(taskStates.find(function(x){return x[0]===rule.state;})||['','未知状态'])[1];
        return '世界事实 · '+(rule.value?'存在':'不存在');
    }
    function reasonTree(reason) {
        var n=node('div','mw-reason');if(!reason)return n;
        n.appendChild(node('p','',({passed:'满足',failed:'未满足',unknown:'未知'})[reason.state]+' · '+(reason.label||'条件')+(reason.detail?'：'+reason.detail:'')));
        (reason.children||[]).forEach(function(r){n.appendChild(reasonTree(r));});return n;
    }
    function factEditor(scenario,catalog,definition,onSave) {
        var next=clone(scenario),host=node('div','mw-scenario-editor');
        ['chains','tasks','infrastructure','flags','scene','navigation','dynamic'].forEach(function(key){if(!next.facts[key]||typeof next.facts[key]!=='object')next.facts[key]={};});
        if(!Array.isArray(next.facts.activeOrder))next.facts.activeOrder=[];
        field(host,'方案名称',next.label,{change:function(v){next.label=v;}});
        host.appendChild(node('p','','模拟只修改本方案，不写玩家存档。链进度不是历史任务全完成；可交付性请单独设置。数字留空表示未知，不会当成 0 或默认放行。'));
        function numericFact(parent,label,container,key){var input=field(parent,label,container[key],{type:'number',min:0});
            input.onchange=function(){if(input.value==='')delete container[key];else container[key]=Number(input.value);};return input;}
        var chains=node('div','mw-form-grid');host.appendChild(chains);
        (catalog.chains||[]).forEach(function(chain){numericFact(chains,chain+'：已完成的最大链序号',next.facts.chains,chain);});
        (catalog.infrastructure||[]).forEach(function(key){numericFact(chains,key+' 等级（0 为未建成）',next.facts.infrastructure,key);});
        (catalog.flags||[]).forEach(function(flag){field(chains,flag.label,next.facts.flags[flag.id],{type:'checkbox',change:function(v){next.facts.flags[flag.id]=v;}});});
        field(chains,'当前地点',next.facts.scene.stageFlag,{choices:labels(definition.locations).map(function(x){return [definition.locations[x[0]].sceneName,x[1]];}),change:function(v){next.facts.scene={stageFlag:v,frameLabel:'',entrance:'',mapFrame:'',inCombat:next.facts.scene.inCombat};}});
        field(chains,'当前在战斗地图',next.facts.scene.inCombat,{type:'checkbox',change:function(v){next.facts.scene.inCombat=v;}});
        field(chains,'当前不能离开的原因',next.facts.navigation.reason,{choices:[['','可以离开'],['combat_active','战斗进行中'],['pending_stage_settlement','奖励结算未完成']],change:function(v){next.facts.navigation.reason=v;}});
        field(chains,'室友外观',next.facts.dynamic.roommateGender,{choices:[['男','男'],['女','女'],['','未知']],change:function(v){next.facts.dynamic.roommateGender=v;}});
        var taskBox=node('fieldset','mw-task-facts');taskBox.appendChild(node('legend','','单个任务事实'));host.appendChild(taskBox);
        var selected=String((catalog.tasks||[])[0]?.id||''),taskFields=node('div','mw-form-grid'),orderInput;
        field(taskBox,'选择任务',selected,{choices:(catalog.tasks||[]).map(function(t){return [String(t.id),t.title+' · '+t.id];}),change:function(id){selected=id;taskForm();}});taskBox.appendChild(taskFields);
        function taskForm(){taskFields.replaceChildren();var fact=next.facts.tasks[selected]||(next.facts.tasks[selected]={});
            numericFact(taskFields,'历史完成次数',fact,'finished');
            ['active','deliverable','available'].forEach(function(key){var text={active:'当前进行中',deliverable:'已达成交付条件',available:'当前可接取'}[key];
                field(taskFields,text,fact[key]===undefined?'unknown':String(fact[key]),{choices:[['unknown','未知'],['false','否'],['true','是']],change:function(v){
                    if(v==='unknown')delete fact[key];else fact[key]=v==='true';
                    if(key==='active'){var order=next.facts.activeOrder;next.facts.activeOrder=order.filter(function(x){return x!==selected;});if(fact.active)next.facts.activeOrder.push(selected);if(orderInput)orderInput.value=next.facts.activeOrder.join(',');}
                }});});
        }
        taskForm();
        orderInput=field(host,'进行中任务次序（任务编号，用逗号分隔；用于验证交付优先级）',next.facts.activeOrder.join(','),{change:function(v){next.facts.activeOrder=v.split(',').map(function(x){return x.trim();}).filter(Boolean);}});
        return {element:host,save:function(){if(!next.label.trim())return false;onSave(next);return true;}};
    }
    root.MapAuthoringControls={clone:clone,node:node,button:button,field:field,dialog:dialog,labels:labels,condition:condition,conditionLabel:conditionLabel,reasonTree:reasonTree,factEditor:factEditor};
})(window);
