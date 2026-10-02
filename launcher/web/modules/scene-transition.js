/* Fixed U12 document. The existing Loot panel owns the one settlement view and business session. */
(function () {
    'use strict';
    var root=document.getElementById('transition'),shell=root.querySelector('.transition-shell');
    var image=document.getElementById('transition-image'),tip=document.getElementById('transition-tip');
    var title=document.getElementById('transition-title'),status=document.getElementById('transition-status');
    var actions=document.getElementById('transition-actions'),activity=document.getElementById('transition-activity');
    var report=document.getElementById('transition-report'),copy=root.querySelector('.transition-copy');
    var reportView=null,reportKey='',reportFingerprint='';
    var reportRejected=false,automaticAttempt='',autoTimer=null,presentationSignature='';
    var current=null,epoch=0,loadedId='',actionRequest=null,covered=false,revealed=false,animation=null,rendering=0;
    var scale=PanelScale.attach(shell,1024,576,{onUpdate:function(s){
        shell.style.transform='translate('+((root.clientWidth-1024*s)/2)+'px,'+((root.clientHeight-576*s)/2)+'px) scale('+s+')';
    }});
    function send(message){ if(window.chrome && window.chrome.webview)window.chrome.webview.postMessage(message); }
    function receipt(kind){ if(current)send({type:'scene_transition_presented',requestId:current.requestId,revision:current.revision,generation:current.generation,kind:kind}); }
    function duration(){return matchMedia('(prefers-reduced-motion: reduce)').matches?0:210;}
    async function fade(to,generation){
        if(animation){animation.cancel();animation=null;}
        // Cover is a barrier, so only the ready world's reveal may be transparent.
        if(to===0){
            animation=root.animate([{opacity:1},{opacity:0}],{duration:duration(),fill:'forwards',easing:'ease-out'});
            try {await animation.finished;} catch (_) {return false;}
        }
        if(generation!==epoch)return false;
        covered=to===1;root.classList.toggle('is-covered',covered);
        if(animation){animation.cancel();animation=null;}
        await new Promise(requestAnimationFrame);await new Promise(requestAnimationFrame);
        if(generation!==epoch)return false;
        rendering=0;return true;
    }
    async function prepareImage(id,generation){
        if(loadedId===id)return;
        image.hidden=true;image.src=SceneTransitionCatalog[id];
        try {await image.decode();if(generation===epoch){image.hidden=false;loadedId=id;}}
        catch (_) {if(generation===epoch)loadedId=id; /* The opaque fallback still grants a truthful curtain receipt. */}
    }
    function valid(p){return p && p.type==='scene_transition' && (p.version===1 || p.version===2
        && typeof p.reportVisible==='boolean' && typeof p.reportHandoff==='boolean'
        && (!p.reportHandoff || p.reportVisible) && LootView.normalizeSettlementReport(p.report)
        && p.report.rewardStashed===true)
        && /^tr:[1-9][0-9]*$/.test(p.requestId) && Number.isSafeInteger(p.revision) && p.revision>0
        && ['cover','loading','reveal','error','hide'].indexOf(p.phase)>=0 && Object.hasOwn(SceneTransitionCatalog,p.imageId)
        && typeof p.tip==='string' && p.tip.length<=2048 && typeof p.actionPending==='boolean';}
    async function adopt(p){
        if(!valid(p))return;
        if(!Number.isSafeInteger(p.generation) || p.generation<0)return;
        if(current && current.generation===p.generation && (Number(p.requestId.slice(3))<Number(current.requestId.slice(3))
            || p.requestId===current.requestId && p.revision<current.revision))return;
        if(p.phase==='hide'){
            epoch++;if(animation)animation.cancel();animation=null;rendering=0;covered=false;current=null;
            if (Panels.getActive()==='loot' && !LootPanel.isPreview()) { LootPanel.sceneReady();return; }
            root.hidden=true;destroyReport();return;
        }
        var same=current && current.generation===p.generation && current.requestId===p.requestId && current.imageId===p.imageId;
        if (same && (current.version!==p.version || JSON.stringify(current.report)!==JSON.stringify(p.report)
            || current.reportVisible===false && p.reportVisible===true)) return;
        if(!same)reportRejected=false;
        else if(current.reportHandoff===true && p.reportHandoff===false)reportRejected=true;
        if (!same || current.phase!=='error' && p.phase==='error' || current.reportVisible===true && p.reportVisible===false
            || current.reportHandoff===true && p.reportHandoff===false) actionRequest=null;
        var samePhase=same && current.phase===p.phase && current.revealAllowed===p.revealAllowed && current.connected===p.connected
            && current.reportVisible===p.reportVisible && current.reportHandoff===p.reportHandoff && current.reportReady===p.reportReady;
        current=p;root.hidden=false;scale.update();
        var showingReport=p.version===2 && p.reportVisible && p.phase!=='error';
        if (p.version===2) {
            var key=p.requestId+':'+p.report.runId, fingerprint=JSON.stringify(p.report);
            if (key!==reportKey || fingerprint!==reportFingerprint) {
                var retained=reportView && !LootPanel.isPreview() && fingerprint===reportFingerprint;
                if(!retained) {
                    destroyReport();
                    if (!Panels.preview('loot',p.report)) return;
                    reportView={presentation:LootPanel.reportPresentation,hasModal:LootPanel.hasModal,
                        update:LootPanel.updatePreview,destroy:function(){Panels.close();}};
                }
                reportKey=key;reportFingerprint=fingerprint;
            }
        } else destroyReport();
        var wasVisible=!report.hidden;
        report.hidden=!showingReport;copy.hidden=showingReport;
        if(wasVisible!==showingReport && reportView) LootPanel.setVisible(showingReport);
        tip.textContent=p.tip;title.textContent=p.phase==='error'?'场景加载失败':'正在加载场景';
        actions.hidden=p.phase!=='error';activity.hidden=p.phase==='error';
        var pending=p.actionPending || !!actionRequest || p.phase!=='error' && p.reportHandoff===true || p.connected===false;
        actions.querySelectorAll('button').forEach(function(button){button.disabled=pending;});
        if(reportView)reportView.update({visible:showingReport,pending:pending,connected:p.connected,rejected:reportRejected});
        if(showingReport)publishPresentation();
        scheduleAutomaticHandoff();
        status.textContent=p.connected===false?'连接暂时中断，等待恢复':pending && p.phase==='error'?'等待游戏确认，请勿重复操作':
            p.phase==='error'?'可以重试加载，或按原流程返回安全地点':'请稍候';
        if(samePhase && revealed){root.hidden=true;receipt('revealed');return;}
        if(samePhase){
            if(!rendering && covered && (showingReport || p.phase==='cover'||p.phase==='loading'))receipt('covered');
            return;
        }
        var generation=++epoch;
        rendering=generation;
        revealed=false;
        if(animation){animation.cancel();animation=null;}
        // Install the solid backing synchronously, including replacement during a reveal.
        root.classList.add('is-covered');
        if(!same){
            covered=false;
            var imageReady=prepareImage(p.imageId,generation);
            if(!showingReport)await imageReady;
        } else if (!showingReport && loadedId!==p.imageId) await prepareImage(p.imageId,generation);
        if(generation!==epoch)return;
        if(!showingReport && p.phase==='reveal' && p.revealAllowed===true && p.connected!==false){
            if(await fade(0,generation)){revealed=true;root.hidden=true;receipt('revealed');}
        } else {
            if(await fade(1,generation)) {
                if(showingReport || p.phase==='cover'||p.phase==='loading'||p.phase==='error')receipt('covered');
                if(p.phase==='error' && !pending)actions.querySelector('button').focus();
            }
        }
    }
    function destroyReport(){if(reportView)reportView.destroy();reportView=null;reportKey='';reportFingerprint='';presentationSignature='';}
    function publishPresentation(){
        if(!current||!reportView||report.hidden||current.connected===false)return;
        var viewState=reportView.presentation();
        var message={type:'scene_transition_report_view',requestId:current.requestId,revision:current.revision,
            generation:current.generation,viewState:viewState};
        var signature=JSON.stringify(message);
        if(signature===presentationSignature)return;
        presentationSignature=signature;send(message);
    }
    function scheduleAutomaticHandoff(){
        if(autoTimer!==null)return;
        autoTimer=setTimeout(function(){
            autoTimer=null;
            if(!current||report.hidden||!reportView||current.rewardReady!==true||current.phase==='error'
                ||current.connected===false||current.actionPending||current.reportHandoff||actionRequest
                ||reportRejected||automaticAttempt===current.requestId)return;
            if(reportView.hasModal()){scheduleAutomaticHandoff();return;}
            automaticAttempt=current.requestId;
            publishPresentation();requestAction('manageReport');
        },80);
    }
    function requestAction(verb){
        if(!current||current.connected===false||actionRequest||current.actionPending)return;
        if(verb==='closeReport'||verb==='manageReport'){
            if(report.hidden||current.reportHandoff)return;
        }else if(current.phase!=='error')return;
        actionRequest={verb:verb,requestId:current.requestId,generation:current.generation};
        actions.querySelectorAll('button').forEach(function(b){b.disabled=true;});
        if(reportView)reportView.update({visible:!report.hidden,pending:true,connected:current.connected,rejected:reportRejected});
        status.textContent='等待游戏确认，请勿重复操作';
        send({type:'scene_transition_action',requestId:current.requestId,revision:current.revision,generation:current.generation,verb:verb});
    }
    root.addEventListener('click',function(event){
        var button=event.target.closest('[data-transition-action]');
        if(!button || button.disabled || !current || current.connected===false || actionRequest)return;
        requestAction(button.dataset.transitionAction);
    });
    window.addEventListener('transition-close-preview',function(){requestAction('closeReport');});
    report.addEventListener('scroll',publishPresentation,true);
    report.addEventListener('input',publishPresentation);
    report.addEventListener('click',function(){requestAnimationFrame(publishPresentation);});
    Bridge.on('scene_transition_complete',function(){
        LootPanel.sceneReady();current=null;covered=false;
        if(Panels.getActive()!=='loot'){root.hidden=true;destroyReport();}
    });
    Bridge.on('panel_cmd',function(p){
        if(p.panel!=='loot'||p.cmd!=='close'||Panels.getActive()==='loot')return;
        report.hidden=true;copy.hidden=false;
        if(!current)root.hidden=true;
    });
    window.addEventListener('keydown',function(event){
        if(!report.hidden)return; // The unchanged settlement focus scope owns its keyboard and modal layers.
        if(event.key==='Escape'){event.preventDefault();return;}
        if(event.key==='Tab' && current && current.phase==='error'){
            var buttons=Array.from(actions.querySelectorAll('button:not(:disabled)'));
            if(buttons.length){event.preventDefault();var i=buttons.indexOf(document.activeElement);buttons[(i+(event.shiftKey?-1:1)+buttons.length)%buttons.length].focus();}
        }
    });
    if(window.chrome && window.chrome.webview)window.chrome.webview.addEventListener('message',function(event){adopt(event.data);});
    window.addEventListener('unload',function(){epoch++;if(autoTimer!==null)clearTimeout(autoTimer);if(animation)animation.cancel();destroyReport();scale.detach();});
    send({type:'scene_transition_ready'});
})();
