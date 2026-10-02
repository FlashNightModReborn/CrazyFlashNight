/** Fixed samples over the production inventory renderer and quick-transfer controller. */
(function(root, factory) {
    var api=factory();
    if(typeof module!=='undefined'&&module.exports)module.exports=api;
    if(root)root.GuidanceInventoryDemo=api;
})(typeof window!=='undefined'?window:globalThis,function(){
    'use strict';
    function create(host) {
        var data, requests, controller, generation=0, destroyed=false, listeners=[];
        var doc=host.ownerDocument, root=doc.createElement('section');
        root.className='guidance-inventory-demo'; root.setAttribute('aria-label','库存演示'); host.appendChild(root);
        function snapshot() {
            var state=controller?controller.debugState():{};
            return {backpack:data['背包'].map(function(s){return s.occupied?s.item.quantity:0;}),
                battlebox:data['战备箱'].map(function(s){return s.occupied?s.item.quantity:0;}),
                mode:state.mode||null,pending:state.pendingCount||0,requests:requests.slice()};
        }
        function slot(container,index) {return data[container]&&data[container][index];}
        function ref(container,s) {return {containerId:container,slot:s.physicalSlot,expectedLease:s.lease};}
        function transfer(sources,target,done,batch) {
            if(destroyed)return false;
            for(var i=0;i<sources.length;i++) {
                var s=slot(sources[i].containerId,sources[i].slot);
                if(!s||!s.occupied||sources[i].expectedLease!==s.lease) {done({success:false,error:'stale_state'});return true;}
            }
            requests.push(batch?'autoTransferBatch':'autoTransfer');
            var completed=0;
            for(i=0;i<sources.length;i++) {
                s=slot(sources[i].containerId,sources[i].slot);
                var dest=data[target].filter(function(t){return !t.occupied;})[0];
                if(!dest)break;
                dest.item=JSON.parse(JSON.stringify(s.item));dest.occupied=true;dest.lease='demo:'+generation+':'+target+':'+dest.physicalSlot+':used';
                s.item=null;s.occupied=false;s.lease+=':empty';completed++;
            }
            if(completed===sources.length)done(batch?{success:true,completedCount:completed}:{success:true});
            else done(completed?{success:true,completedCount:completed,failure:{index:completed,error:'target_full'}}:{success:false,error:'target_full'});
            return true;
        }
        function perform(step,point) {
            if(destroyed||step.action!=='click')throw Error('不支持的演示动作');
            if(step.target==='deposit')controller.setMode('deposit');
            else if(step.target==='commit')controller.commit();
            else {
                var match=/^(backpack|battlebox)-([0-2])$/.exec(step.target);
                if(!match)throw Error('没有找到演示操作');
                var container=match[1]==='backpack'?'背包':'战备箱';
                controller.acceptClick({ctrlKey:!!step.ctrl,preventDefault:function(){},stopPropagation:function(){}},
                    {profile:'battlebox',viewMode:'storage',containerId:container,slot:slot(container,Number(match[2]))});
            }
            render();
            var recorded={action:'click',target:step.target,ctrl:!!step.ctrl,point:point||step.point||{x:0.5,y:0.5},expected:snapshot()};
            listeners.slice().forEach(function(fn){fn(recorded);});
        }
        function bind(node,target) {
            node.setAttribute('data-tutorial-target',target);
            node.addEventListener('click',function(event){
                var r=node.getBoundingClientRect();
                perform({action:'click',target:target,ctrl:event.ctrlKey},
                    {x:r.width?Math.max(0,Math.min(1,(event.clientX-r.left)/r.width)):0.5,
                     y:r.height?Math.max(0,Math.min(1,(event.clientY-r.top)/r.height)):0.5});
            });
        }
        function render() {
            if(destroyed)return;
            var focused=root.contains(doc.activeElement)&&doc.activeElement.getAttribute('data-tutorial-target');
            while(root.firstChild)root.removeChild(root.firstChild);
            var notice=doc.createElement('p');notice.className='guidance-demo-notice';notice.textContent='演示数据 · 可以自由练习';root.appendChild(notice);
            var columns=doc.createElement('div');columns.className='guidance-demo-columns';root.appendChild(columns);
            ['背包','战备箱'].forEach(function(container,c){
                var pane=doc.createElement('section'), heading=doc.createElement('h3');heading.textContent=container;pane.appendChild(heading);
                var grid=doc.createElement('div');grid.className='guidance-demo-grid';pane.appendChild(grid);columns.appendChild(pane);
                data[container].forEach(function(s,i){
                    var node=InventoryUI.renderOwnedSlot(container,s,{allowDiscard:false});
                    node.tabIndex=0;node.setAttribute('role','button');
                    var selected=controller.debugState().entries[container+':'+i];
                    node.classList.toggle('selected',!!selected);node.setAttribute('aria-pressed',selected?'true':'false');
                    bind(node,(c===0?'backpack':'battlebox')+'-'+i);
                    node.addEventListener('keydown',function(e){if(e.key==='Enter'||e.key===' '){e.preventDefault();perform({action:'click',target:(c===0?'backpack':'battlebox')+'-'+i,ctrl:e.ctrlKey});}});
                    grid.appendChild(node);
                });
            });
            var bar=doc.createElement('div');bar.className='guidance-demo-actions';root.appendChild(bar);
            [['deposit','选择存入'],['commit','存入所选']].forEach(function(spec){
                var btn=doc.createElement('button');btn.type='button';btn.textContent=spec[1];bind(btn,spec[0]);bar.appendChild(btn);
                if(spec[0]==='commit')btn.disabled=controller.debugState().pendingCount===0;
                else btn.setAttribute('aria-pressed',controller.getMode()==='deposit'?'true':'false');
            });
            var status=doc.createElement('p');status.className='guidance-demo-status';status.textContent='已选 '+controller.debugState().pendingCount+' 件';root.appendChild(status);
            if(focused){var restore=root.querySelector('[data-tutorial-target="'+focused+'"]');if(restore)restore.focus();}
        }
        function reset() {
            generation++; requests=[];
            data={'背包':['医疗包','手枪弹夹','解毒剂'].map(function(name,i){return {physicalSlot:i,occupied:true,lease:'demo:'+generation+':'+i,item:{name:name,displayName:name,itemKind:'stack',quantity:[3,5,2][i],icon:''}};}),
                '战备箱':[0,1,2].map(function(i){return {physicalSlot:i,occupied:false,lease:'demo:'+generation+':right:'+i};})};
            controller=new InventoryWorkbenchQuickTransfer.QuickTransferController({
                rightContainerId:'战备箱',getSlot:slot,slotRef:ref,getAuthorityState:function(){return {ready:true};},
                getGeneration:function(){return generation;},isGenerationCurrent:function(g){return !destroyed&&generation===g;},
                autoTransfer:function(source,target,done){return transfer([source],target,done,false);},
                autoTransferBatch:function(sources,target,done){return transfer(sources,target,done,true);}
            });
            render();
        }
        reset();
        return {root:root,snapshot:snapshot,reset:reset,execute:function(step){
            if(!/^(deposit|commit|backpack-[0-2]|battlebox-[0-2])$/.test(step.target))throw Error('演示目标无效');
            var node=root.querySelector('[data-tutorial-target="'+step.target+'"]');
            if(!node||node.disabled)throw Error('演示目标不可用');
            perform(step);
        },subscribe:function(fn){listeners.push(fn);return function(){listeners=listeners.filter(function(f){return f!==fn;});};},
            destroy:function(){destroyed=true;generation++;listeners=[];controller.reset();if(root.parentNode)root.parentNode.removeChild(root);}};
    }
    return {create:create};
});
