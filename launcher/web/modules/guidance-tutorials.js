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
    var KEY_TOKEN_RE=/\{(left|right|up|down|attack|jump|interact)\}/;
    var GUIDE_SUBTITLES={
        map:'熟悉基地界面入口与任务提示标记，随时查看地图、任务进度与个人物品。'
    };
    var MAP_CARDS=[
        {title:'地图与传送',tone:'crystal',icon:'map'},
        {title:'帮助与演示',tone:'crystal',icon:'help'},
        {title:'任务与物品栏',tone:'danger',icon:'alert'},
        {title:'重置版按键',tone:'warning',icon:'keys'}
    ];
    function bind(text,keys){return text.replace(/\{(left|right|up|down|attack|jump|interact)\}/g,function(_,key){return (keys||DEFAULT_KEYS)[key]||DEFAULT_KEYS[key];});}
    function hasKeyTokens(guide){
        return (guide&&guide.pages||[]).some(function(p){
            return KEY_TOKEN_RE.test(p.text||'')||(p.visual||[]).some(function(n){return KEY_TOKEN_RE.test(n.text||'');});
        });
    }
    function makeIcon(doc,kind){
        var ns='http://www.w3.org/2000/svg',svg=doc.createElementNS(ns,'svg');
        svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('aria-hidden','true');svg.setAttribute('focusable','false');
        svg.setAttribute('class','guidance-feature-svg');
        function add(tag,attrs){var el=doc.createElementNS(ns,tag);Object.keys(attrs).forEach(function(k){el.setAttribute(k,attrs[k]);});svg.appendChild(el);}
        if(kind==='map'){
            add('path',{d:'M12 21s6-5.2 6-10a6 6 0 1 0-12 0c0 4.8 6 10 6 10Z',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linejoin':'round'});
            add('circle',{cx:'12',cy:'11',r:'2.2',fill:'currentColor'});
        }else if(kind==='help'){
            add('circle',{cx:'12',cy:'12',r:'9',fill:'none',stroke:'currentColor','stroke-width':'1.8'});
            add('path',{d:'M9.6 9.4a2.5 2.5 0 0 1 4.6 1.3c0 1.6-2.2 1.9-2.2 3.4',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round'});
            add('circle',{cx:'12',cy:'17.2',r:'1.1',fill:'currentColor'});
        }else if(kind==='alert'){
            add('circle',{cx:'12',cy:'12',r:'9',fill:'none',stroke:'currentColor','stroke-width':'1.8'});
            add('path',{d:'M12 7.5v5.6',fill:'none',stroke:'currentColor','stroke-width':'2.2','stroke-linecap':'round'});
            add('circle',{cx:'12',cy:'16.7',r:'1.2',fill:'currentColor'});
        }else{
            add('rect',{x:'3',y:'6',width:'18',height:'12',rx:'2.5',fill:'none',stroke:'currentColor','stroke-width':'1.8'});
            add('path',{d:'M7 10h2M11 10h2M15 10h2M8 14h8',fill:'none',stroke:'currentColor','stroke-width':'1.8','stroke-linecap':'round'});
        }
        return svg;
    }
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
    function appendCopyNodes(parent,text,keys){
        var doc=parent.ownerDocument,start=0,pattern=/\{(left|right|up|down|attack|jump|interact)\}/g,match;
        while((match=pattern.exec(text))){
            parent.appendChild(doc.createTextNode(text.slice(start,match.index)));
            var key=doc.createElement('kbd');key.textContent=(keys||DEFAULT_KEYS)[match[1]]||DEFAULT_KEYS[match[1]];parent.appendChild(key);start=pattern.lastIndex;
        }
        parent.appendChild(doc.createTextNode(text.slice(start)));
    }
    function copy(doc,text,keys,tag){
        var p=doc.createElement(tag||'p');p.className='guidance-copy';
        appendCopyNodes(p,text,keys);
        return p;
    }
    function buildStructuredList(doc,text,keys){
        var lines=String(text||'').split(/\r?\n/).map(function(l){return l.trim();}).filter(Boolean);
        if(lines.length<=1&&!/^([^：。；]{1,8})：/.test(lines[0]||'')){
            return copy(doc,text,keys);
        }
        var list=doc.createElement('ul');list.className='guidance-list';
        lines.forEach(function(line){
            var li=doc.createElement('li');li.className='guidance-row';
            var match=/^([^：。；]{1,8})：(.+)$/.exec(line);
            if(match){
                if(match[1]==='注意')li.classList.add('is-caution');
                var label=doc.createElement('span');label.className='guidance-row-label';label.textContent=match[1];
                li.appendChild(label);
                li.appendChild(copy(doc,match[2],keys,'span'));
            }else{
                if(/^系统设置/.test(line))li.classList.add('is-note');
                li.appendChild(copy(doc,line,keys,'span'));
            }
            list.appendChild(li);
        });
        return list;
    }
    function buildMapGrid(doc,text,keys){
        var lines=String(text||'').split(/\r?\n/).map(function(l){return l.trim();}).filter(Boolean);
        var grid=doc.createElement('div');grid.className='guidance-feature-grid';
        lines.forEach(function(line,index){
            var meta=MAP_CARDS[index]||{title:'说明 '+(index+1),tone:'crystal',icon:'help'};
            var card=doc.createElement('article');card.className='guidance-feature-card';card.setAttribute('data-tone',meta.tone);
            var iconBox=doc.createElement('div');iconBox.className='guidance-feature-icon';iconBox.appendChild(makeIcon(doc,meta.icon));
            var body=doc.createElement('div');body.className='guidance-feature-body';
            var title=doc.createElement('h3');title.className='guidance-feature-title';title.textContent=meta.title;
            body.appendChild(title);
            body.appendChild(copy(doc,line,keys,'p'));
            card.appendChild(iconBox);card.appendChild(body);
            grid.appendChild(card);
        });
        return grid;
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
        var root=doc.createElement('section');root.className='guidance-tutorials';root.setAttribute('aria-label','操作教程');root.setAttribute('data-browser-native','');
        root.setAttribute('data-briefing',options.briefing?'true':'false');
        host.appendChild(root);
        var menu=doc.createElement('nav');menu.className='guidance-menu';menu.setAttribute('aria-label','教程目录');root.appendChild(menu);
        var page=doc.createElement('div');page.className='guidance-page';root.appendChild(page);
        var adapter=null,unsubscribe=null,epoch=0,timers=[],disposed=false,recording=false,recorded=[],path=[],lastPoint=0,current=null;
        var selectedButton=null,status=null,cursor=null,lesson=null,recordedJourney=null,playing=false;
        var guideChoosers=Object.create(null);
        function button(parent,label,fn,cls){var b=doc.createElement('button');b.type='button';b.textContent=label;b.className=cls||'';b.addEventListener('click',fn);parent.appendChild(b);return b;}
        function setBriefing(flag){root.setAttribute('data-briefing',flag?'true':'false');page.scrollTop=0;}
        function selectGuide(id){if(guideChoosers[id])guideChoosers[id]();}
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
        function select(btn,title,meta){
            disposeAdapter();while(page.firstChild)page.removeChild(page.firstChild);
            if(selectedButton)selectedButton.setAttribute('aria-current','false');selectedButton=btn;btn.setAttribute('aria-current','page');
            page.scrollTop=0;
            page.setAttribute('data-guide-id',meta&&meta.id?meta.id:'');
            page.setAttribute('data-guide-kind',meta&&meta.kind?meta.kind:'');
            var stage=doc.createElement('div');stage.className='guidance-page-inner';page.appendChild(stage);
            var head=doc.createElement('header');head.className='guidance-page-head';stage.appendChild(head);
            var titles=doc.createElement('div');titles.className='guidance-page-titles';head.appendChild(titles);
            if(meta&&meta.eyebrow){
                var eyebrow=doc.createElement('span');eyebrow.className='guidance-eyebrow';eyebrow.textContent=meta.eyebrow;titles.appendChild(eyebrow);
            }
            var h=doc.createElement('h2');h.textContent=title;titles.appendChild(h);
            if(meta&&meta.subtitle){
                var sub=doc.createElement('p');sub.className='guidance-subtitle';sub.textContent=meta.subtitle;titles.appendChild(sub);
            }
            if(meta&&meta.badge){
                var badge=doc.createElement('p');badge.className='guidance-key-badge';badge.textContent=meta.badge;
                if(meta.badgeTitle)badge.title=meta.badgeTitle;
                head.appendChild(badge);
            }
            status=null;cursor=null;current=null;
            return stage;
        }
        function showGuide(btn,guide){
            var usesKeys=hasKeyTokens(guide);
            var stage=select(btn,guide.title,{
                id:guide.id,
                kind:guide.kind,
                eyebrow:guide.kind==='tutorial'?'核心指引':'场景操作图示',
                subtitle:GUIDE_SUBTITLES[guide.id]||'',
                badge:usesKeys?(options.keys?'当前按键绑定':'默认键位 · 可在设置修改'):'',
                badgeTitle:usesKeys?(options.keys?'按键采用打开教程时的绑定。':'以下使用默认键位。自定义按键请以系统设置为准；场景提示会显示当前绑定。'):''
            });
            lesson=guide;
            if(guide.id==='map'&&guide.pages.length===1&&!guide.pages[0].visual){
                stage.appendChild(buildMapGrid(doc,guide.pages[0].text,options.keys));
                return;
            }
            var multi=guide.pages.length>1;
            var sections=doc.createElement('div');
            sections.className='guidance-sections'+(multi?' is-multi':' is-single');
            stage.appendChild(sections);
            guide.pages.forEach(function(p){
                var visual=diagram(doc,p,options.keys,catalog.keyLabels);
                var card=doc.createElement('section');
                card.className='guidance-card'+(visual?' has-visual':'');
                if(multi||p.title!==guide.title){
                    var h=doc.createElement('h3');h.className='guidance-card-title';h.textContent=p.title;card.appendChild(h);
                }
                if(visual&&multi){
                    var split=doc.createElement('div');split.className='guidance-card-split';
                    var copyWrap=doc.createElement('div');copyWrap.className='guidance-card-copy';
                    copyWrap.appendChild(buildStructuredList(doc,p.text,options.keys));
                    var frame=doc.createElement('div');frame.className='guidance-diagram-frame';frame.appendChild(visual);
                    split.appendChild(copyWrap);split.appendChild(frame);
                    card.appendChild(split);
                }else{
                    if(visual){
                        var singleFrame=doc.createElement('div');singleFrame.className='guidance-diagram-frame';singleFrame.appendChild(visual);
                        card.appendChild(singleFrame);
                    }
                    card.appendChild(buildStructuredList(doc,p.text,options.keys));
                }
                sections.appendChild(card);
            });
        }
        function showDemo(btn,journey){
            var stage=select(btn,journey.title,{id:journey.id,kind:'demo',eyebrow:'交互演示 · 工作台'});
            lesson=null;current=journey;recordedJourney=null;
            var bar=doc.createElement('div');bar.className='guidance-playback';stage.appendChild(bar);
            button(bar,'播放演示',function(){play();},'is-primary');button(bar,'停止',pause);button(bar,'重新开始',reset);
            var sep=doc.createElement('span');sep.className='guidance-playback-sep';sep.setAttribute('aria-hidden','true');bar.appendChild(sep);
            button(bar,'记录操作',record);button(bar,'完成记录',finishRecording);
            button(bar,'回放记录',function(){if(recordedJourney)play(recordedJourney);else status.textContent='请先记录一段练习。';});
            status=doc.createElement('p');status.className='guidance-step';status.setAttribute('aria-live','polite');status.textContent='可播放示范，也可以直接操作演示物品。';stage.appendChild(status);
            var container=doc.createElement('div');container.className='guidance-demo-host';stage.appendChild(container);
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
        function appendGroup(parent,label){
            var group=doc.createElement('div');group.className='guidance-menu-group';
            if(label){
                var heading=doc.createElement('p');heading.className='guidance-menu-heading';heading.setAttribute('aria-hidden','true');heading.textContent=label;
                group.appendChild(heading);
            }
            parent.appendChild(group);
            return group;
        }
        var choices=[], initial=null;
        if(!options.domain){
            var allGuides=(catalog&&catalog.guides)||[];
            var tutorialGuides=allGuides.filter(function(g){return g.kind==='tutorial';});
            var sceneGuides=allGuides.filter(function(g){return g.kind!=='tutorial';});
            if(tutorialGuides.length){
                var tg=appendGroup(menu,'新手必读');
                tutorialGuides.forEach(function(g){
                    var btn=button(tg,g.title,function(){showGuide(btn,g);},'guidance-menu-item');
                    var choose=function(){showGuide(btn,g);};
                    choices.push(choose);guideChoosers[g.id]=choose;
                    if(g.id===options.guideId)initial=choose;
                });
            }
            if(sceneGuides.length){
                var sg=appendGroup(menu,'场景操作');
                sceneGuides.forEach(function(g){
                    var btn=button(sg,g.title,function(){showGuide(btn,g);},'guidance-menu-item');
                    var choose=function(){showGuide(btn,g);};
                    choices.push(choose);guideChoosers[g.id]=choose;
                    if(g.id===options.guideId)initial=choose;
                });
            }
        }
        var demoList=(journeys&&journeys.journeys||[]).filter(function(j){return !options.domain||j.domain===options.domain;});
        if(demoList.length){
            var dg=options.domain?menu:appendGroup(menu,'工作台演示');
            demoList.forEach(function(j){
                var btn=button(dg,j.title,function(){showDemo(btn,j);},'guidance-menu-item');
                choices.push(function(){showDemo(btn,j);});
            });
        }
        if(initial)initial();else if(choices.length)choices[0]();
        return {root:root,play:play,stop:pause,reset:reset,record:record,finishRecording:finishRecording,
            setBriefing:setBriefing,selectGuide:selectGuide,
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
