/** One embedded help renderer, semantic recorder and replay engine for all tutorial owners. */
(function(root,factory){
    var api=factory();if(typeof module!=='undefined'&&module.exports)module.exports=api;
    if(root)root.GuidanceTutorials=api;
})(typeof window!=='undefined'?window:globalThis,function(){
    'use strict';
    var domainFactories=Object.create(null);
    function registerDomain(id,create){
        if(!/^[a-z][a-z0-9-]{0,47}$/.test(id)||typeof create!=='function'||domainFactories[id])throw Error('教程领域注册无效');
        domainFactories[id]=create;
    }
    registerDomain('workbench',function(host){return GuidanceInventoryDemo.create(host);});
    var DEFAULT_KEYS={left:'A',right:'D',up:'W',down:'S',attack:'J',jump:'K',interact:'E'};
    function bind(text,keys){return text.replace(/\{(left|right|up|down|attack|jump|interact)\}/g,function(_,key){return (keys||DEFAULT_KEYS)[key]||DEFAULT_KEYS[key];});}
    function diagram(doc,page,keys,labels){
        if(!page.visual||!page.visual.length)return null;
        var ns='http://www.w3.org/2000/svg',svg=doc.createElementNS(ns,'svg');
        svg.setAttribute('class','guidance-diagram');svg.setAttribute('role','img');svg.setAttribute('aria-label',page.title);svg.setAttribute('focusable','false');
        var left=1024,top=576,right=0,bottom=0;
        function add(type,attributes){var el=doc.createElementNS(ns,type);Object.keys(attributes).forEach(function(key){el.setAttribute(key,attributes[key]);});svg.appendChild(el);return el;}
        page.visual.forEach(function(node){
            left=Math.min(left,node.x);top=Math.min(top,node.y);right=Math.max(right,node.x+node.width);bottom=Math.max(bottom,node.y+node.height);
            if(node.type==='key'){
                add('rect',{x:node.x,y:node.y,width:node.width,height:node.height,rx:5,fill:'none',stroke:'currentColor','stroke-width':3});
                var value=bind(node.text,keys);value=labels&&Object.prototype.hasOwnProperty.call(labels,value)?labels[value]:value;
                var size=Math.min(node.fontSize,Math.max(10,(node.width-5)/Math.max(value.length*.62,1)));
                add('text',{x:node.x+node.width/2,y:node.y+node.height/2,'text-anchor':'middle','dominant-baseline':'central','font-size':size,'font-weight':700,fill:'currentColor'}).textContent=value;
            }else if(node.type==='text'){
                add('text',{x:node.x+2,y:node.y+node.fontSize+2,'font-size':node.fontSize,fill:'currentColor'}).textContent=bind(node.text,keys);
            }else{
                var x=node.x,y=node.y,w=node.width,h=node.height;
                add('ellipse',{cx:x+w/2,cy:y+h/2,rx:w/2,ry:h/2,fill:'none',stroke:'currentColor','stroke-width':2.5});
                add('path',{d:'M '+(x+w/2)+' '+(y+h*.36)+' L '+x+' '+(y+h*.36)+' Q '+x+' '+y+' '+(x+w/2)+' '+y+' Z',fill:'currentColor'});
                add('path',{d:'M '+x+' '+(y+h*.36)+' H '+(x+w)+' M '+(x+w/2)+' '+y+' V '+(y+h*.36),fill:'none',stroke:'currentColor','stroke-width':2.5});
            }
        });
        svg.setAttribute('viewBox',[left-8,top-8,right-left+16,bottom-top+16].join(' '));
        return svg;
    }
    function copy(doc,text,keys){
        var p=doc.createElement('p');p.className='guidance-copy';var start=0,pattern=/\{(left|right|up|down|attack|jump|interact)\}/g,match;
        while((match=pattern.exec(text))){
            p.appendChild(doc.createTextNode(text.slice(start,match.index)));
            var key=doc.createElement('kbd');key.textContent=(keys||DEFAULT_KEYS)[match[1]]||DEFAULT_KEYS[match[1]];p.appendChild(key);start=pattern.lastIndex;
        }
        p.appendChild(doc.createTextNode(text.slice(start)));return p;
    }
    function equal(a,b){
        if(a===b)return true;
        if(!a||!b||typeof a!=='object'||typeof b!=='object'||Array.isArray(a)!==Array.isArray(b))return false;
        var ak=Object.keys(a).sort(),bk=Object.keys(b).sort();
        return ak.length===bk.length&&ak.every(function(k,i){return k===bk[i]&&equal(a[k],b[k]);});
    }
    function point(p){return p&&Number.isFinite(p.x)&&Number.isFinite(p.y)&&p.x>=0&&p.x<=1&&p.y>=0&&p.y<=1;}
    function validate(journey){
        if(!journey||journey.version!==1||!domainFactories[journey.domain]||!Array.isArray(journey.steps)||!journey.steps.length||journey.steps.length>128)throw Error('练习记录格式无效');
        journey.steps.forEach(function(s){
            if(s.action!=='click'||!/^[-a-z0-9]{1,48}$/.test(s.target)||!s.expected||!point(s.point)
                ||(s.ctrl!=null&&typeof s.ctrl!=='boolean')||(s.path!=null&&(!Array.isArray(s.path)||s.path.length>64||s.path.some(function(p){return !point(p);}))))throw Error('练习步骤无效');
        });
        return JSON.parse(JSON.stringify(journey));
    }
    function mount(host,options){
        options=options||{};
        var doc=host.ownerDocument,catalog=options.catalog||window.GuidanceCatalog;
        var journeys=options.journeys||window.TutorialJourneys;
        var root=doc.createElement('section');root.className='guidance-tutorials';root.setAttribute('aria-label','操作教程');root.setAttribute('data-browser-native','');host.appendChild(root);
        var menu=doc.createElement('nav');menu.className='guidance-menu';menu.setAttribute('aria-label','教程目录');root.appendChild(menu);
        var page=doc.createElement('div');page.className='guidance-page';root.appendChild(page);
        var adapter=null,unsubscribe=null,epoch=0,timers=[],disposed=false,recording=false,recorded=[],path=[],lastPoint=0,current=null;
        var selectedButton=null,status=null,cursor=null,lesson=null,recordedJourney=null,playing=false;
        function button(parent,label,fn,cls){var b=doc.createElement('button');b.type='button';b.textContent=label;b.className=cls||'';b.addEventListener('click',fn);parent.appendChild(b);return b;}
        function stop(){
            epoch++;playing=false;
            timers.splice(0).forEach(function(t){clearTimeout(t.id);t.resolve(false);});
            if(cursor)cursor.hidden=true;
        }
        function disposeAdapter(){stop();recording=false;path=[];if(unsubscribe)unsubscribe();unsubscribe=null;if(adapter)adapter.destroy();adapter=null;if(cursor&&cursor.parentNode)cursor.parentNode.removeChild(cursor);cursor=null;}
        function pause(){stop();if(status)status.textContent='已停止，可重新播放或自由练习。';}
        function wait(ms){return new Promise(function(resolve){var entry={resolve:resolve,id:setTimeout(function(){timers=timers.filter(function(t){return t!==entry;});resolve(true);},ms)};timers.push(entry);});}
        function move(p){
            if(!cursor)return;
            cursor.hidden=false;cursor.style.left=(p.x*100)+'%';cursor.style.top=(p.y*100)+'%';
        }
        function targetPoint(node,p){var r=root.getBoundingClientRect(),t=node.getBoundingClientRect();return {x:(t.left-r.left+t.width*p.x)/r.width,y:(t.top-r.top+t.height*p.y)/r.height};}
        async function play(input){
            if(disposed||!adapter)return false;
            stop();recording=false;
            var journey;
            try {journey=validate(input||current);if(journey.domain!==current.domain)throw Error('练习记录不属于当前演示页面');}catch(error){status.textContent=error.message;return false;}
            var localEpoch=epoch,activeAdapter=adapter;activeAdapter.reset();playing=true;
            try {
                for(var i=0;i<journey.steps.length;i++){
                    if(disposed||localEpoch!==epoch||activeAdapter!==adapter)return false;
                    var step=journey.steps[i],node=activeAdapter.root.querySelector('[data-tutorial-target="'+step.target+'"]');
                    if(!node||node.disabled)throw Error('操作目标不可用，已停止播放。');
                    status.textContent=(i+1)+' / '+journey.steps.length+'　'+(step.text||'');
                    for(var pi=0;pi<(step.path||[]).length;pi++){
                        move(step.path[pi]);if(!(await wait(options.stepMs===0?0:25))||localEpoch!==epoch)return false;
                    }
                    move(targetPoint(node,step.point));
                    if(!(await wait(options.stepMs==null?700:options.stepMs))||localEpoch!==epoch)return false;
                    activeAdapter.execute(step);
                    if(!equal(activeAdapter.snapshot(),step.expected))throw Error('结果与教程预期不一致，已停止播放。');
                }
                status.textContent='演示完成，可以重播或亲自练习。';playing=false;if(cursor)cursor.hidden=true;
                return true;
            }catch(error){if(localEpoch===epoch){stop();status.textContent=error.message;}return false;}
        }
        function reset(){stop();recording=false;if(adapter)adapter.reset();if(status)status.textContent='已恢复演示数据。';}
        function record(){
            if(!adapter||disposed)return false;
            reset();recorded=[];path=[];recording=true;recordedJourney=null;
            status.textContent='正在记录你的练习操作。';return true;
        }
        function finishRecording(){
            recording=false;
            if(!recorded.length){status.textContent='尚未记录操作。';return null;}
            recordedJourney={version:1,id:'recorded',domain:current.domain,title:'我的练习',steps:recorded.slice()};
            status.textContent='已记录 '+recorded.length+' 个步骤，可以回放。';return JSON.parse(JSON.stringify(recordedJourney));
        }
        function onPointer(event){
            if(!recording||!adapter||!adapter.root.contains(event.target))return;
            var now=Date.now();if(now-lastPoint<40||path.length>=64)return;lastPoint=now;
            var r=root.getBoundingClientRect(),p={x:(event.clientX-r.left)/r.width,y:(event.clientY-r.top)/r.height};
            if(point(p))path.push(p);
        }
        root.addEventListener('pointermove',onPointer);
        function select(btn,title){
            disposeAdapter();while(page.firstChild)page.removeChild(page.firstChild);
            if(selectedButton)selectedButton.setAttribute('aria-current','false');selectedButton=btn;btn.setAttribute('aria-current','page');
            var h=doc.createElement('h2');h.textContent=title;page.appendChild(h);status=null;cursor=null;current=null;
        }
        function showGuide(btn,guide){
            select(btn,guide.title);lesson=guide;
            var note=doc.createElement('p');note.className='guidance-help-link';
            note.textContent=options.keys?'按键采用打开教程时的绑定。':'以下使用默认键位。自定义按键请以系统设置为准；场景提示会显示当前绑定。';page.appendChild(note);
            guide.pages.forEach(function(p){
                var h=doc.createElement('h3');h.textContent=p.title;page.appendChild(h);
                var visual=diagram(doc,p,options.keys,catalog.keyLabels);if(visual)page.appendChild(visual);
                page.appendChild(copy(doc,p.text,options.keys));
            });
        }
        function showDemo(btn,journey){
            select(btn,journey.title);lesson=null;current=journey;recordedJourney=null;
            var bar=doc.createElement('div');bar.className='guidance-playback';page.appendChild(bar);
            button(bar,'播放演示',function(){play();});button(bar,'停止',pause);button(bar,'重新开始',reset);
            button(bar,'记录操作',record);button(bar,'完成记录',finishRecording);
            button(bar,'回放记录',function(){if(recordedJourney)play(recordedJourney);else status.textContent='请先记录一段练习。';});
            status=doc.createElement('p');status.className='guidance-step';status.setAttribute('aria-live','polite');status.textContent='可播放示范，也可以直接操作演示物品。';page.appendChild(status);
            var container=doc.createElement('div');container.className='guidance-demo-host';page.appendChild(container);
            var create=domainFactories[journey.domain];
            if(!create){status.textContent='该教程暂时无法加载。';return;}
            adapter=create(container);
            if(!adapter||!adapter.root||!container.contains(adapter.root)
                ||['execute','snapshot','reset','subscribe','destroy'].some(function(name){return typeof adapter[name]!=='function';})){
                if(adapter&&typeof adapter.destroy==='function')adapter.destroy();adapter=null;
                status.textContent='演示页面未就绪。';return;
            }
            unsubscribe=adapter.subscribe(function(step){
                if(!recording||playing)return;
                if(recorded.length>=128){finishRecording();return;}
                step.path=path.slice();path=[];recorded.push(step);
            });
            cursor=doc.createElement('span');cursor.className='guidance-pointer';cursor.setAttribute('aria-hidden','true');cursor.hidden=true;root.appendChild(cursor);
        }
        var choices=[], initial=null;
        if(!options.domain)(catalog&&catalog.guides||[]).forEach(function(g){var btn=button(menu,g.title,function(){showGuide(btn,g);});
            var choose=function(){showGuide(btn,g);};choices.push(choose);if(g.id===options.guideId)initial=choose;});
        (journeys&&journeys.journeys||[]).filter(function(j){return !options.domain||j.domain===options.domain;}).forEach(function(j){
            var btn=button(menu,j.title,function(){showDemo(btn,j);});choices.push(function(){showDemo(btn,j);});
        });
        if(initial)initial();else if(choices.length)choices[0]();
        return {root:root,play:play,stop:pause,reset:reset,record:record,finishRecording:finishRecording,
            snapshot:function(){return adapter?adapter.snapshot():null;},
            destroy:function(){if(disposed)return;disposed=true;disposeAdapter();root.removeEventListener('pointermove',onPointer);if(root.parentNode)root.parentNode.removeChild(root);}};
    }
    function createSecondary(host,options){
        options=options||{};
        var doc=host.ownerDocument,root=doc.createElement('section'),view=null;root.setAttribute('data-browser-native','');
        var back=doc.createElement('button');back.type='button';back.textContent=options.backLabel||'返回';back.className='guidance-secondary-close';root.appendChild(back);
        var copy=doc.createElement('p');copy.className='guidance-help-link';copy.textContent=options.introduction||'';root.appendChild(copy);
        if(options.helpSpec){var details=doc.createElement('details'),summary=doc.createElement('summary'),text=doc.createElement('p');summary.textContent='功能说明';text.className='guidance-copy';text.textContent=(options.helpSpec.message||'')+'\n\n'+(options.helpSpec.detail||'');details.appendChild(summary);details.appendChild(text);root.appendChild(details);}
        var body=doc.createElement('div');root.appendChild(body);
        var secondary=new WorkbenchComponents.SecondaryPage({root:root,host:host,removeOnDestroy:true,
            className:'guidance-secondary',role:'dialog',ariaLabel:options.title||'操作教程',
            onOpen:function(){view=mount(body,{domain:options.domain});},
            onClose:function(){if(view)view.destroy();view=null;}});
        back.addEventListener('click',function(){secondary.close('back');});
        return secondary;
    }
    function openSecondary(host,existing,options){
        var page=existing||createSecondary(host,options);
        page.open({opener:host.ownerDocument.activeElement});return page;
    }
    function consumeEscape(page,reason,callback){
        if(reason!=='escape'||!page||!page.isActive())return false;
        page.close('escape');callback(false,'consumed');return true;
    }
    function disposeSecondary(page){if(page)page.destroy();return null;}
    return {registerDomain:registerDomain,mount:mount,createSecondary:createSecondary,openSecondary:openSecondary,
        consumeEscape:consumeEscape,disposeSecondary:disposeSecondary,validate:validate,equal:equal};
});
