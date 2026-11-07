'use strict';
// Production renderer/CSS in Edge. Only the Host transport is simulated.
const fs=require('fs'),path=require('path'),http=require('http'),assert=require('assert/strict');
const root=path.resolve(__dirname,'..'),web=path.join(root,'launcher/web');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
const output=path.join(root,'tmp/stage-intro-browser');
const fixture=`<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="/css/panels.css">
<style>html,body{margin:0;width:100%;height:100%}.panel-scale-shell{position:absolute;transform:scale(var(--panel-scale));transform-origin:top left;width:var(--pss-w);height:var(--pss-h)}</style>
<div id="panel-container" data-panel="book-comic"><div id="panel-content"></div></div>
<script>
window.Panels={register:(id,s)=>window.spec=s};window.messages=[];window.pendingPrepared=[];
window.Bridge={on:(name,cb)=>window.reply=cb,off:()=>{},send:m=>{messages.push(m);if(m.cmd==='prepared')pendingPrepared.push(m);return true}};
</script><script src="/modules/panel-scale.js"></script><script src="/modules/book-comic-content.js"></script><script src="/modules/book-comic-panel.js"></script>
<script>window.comicRoot=spec.create();document.querySelector('#panel-content').append(comicRoot);
window.openIntro=n=>{spec.onClose();spec.onOpen(comicRoot,{v:2,introId:'intro:'+n,presentationId:'bookcomic:'+n,slot:'fixture',sceneId:'scene:1',pageId:'prologue',panelInstanceId:'fixture:'+n})};
window.ack=(m,extra={})=>reply({...m,...m.payload,success:true,...extra});</script>`;
const server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(url.pathname==='/intro-fixture'){res.setHeader('Content-Type','text/html;charset=utf-8');res.end(fixture);return;}
    const file=path.resolve(web,'.'+decodeURIComponent(url.pathname));
    if(!file.startsWith(web+path.sep)){res.writeHead(403).end();return;}
    const mime={'.css':'text/css','.js':'text/javascript','.png':'image/png','.html':'text/html;charset=utf-8'};
    fs.readFile(file,(error,bytes)=>{res.writeHead(error?404:200,{'Content-Type':mime[path.extname(file)]||'application/octet-stream'});res.end(error?'missing':bytes)});
});
async function main(){
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
    const base='http://127.0.0.1:'+server.address().port,errors=[];
    try{
        fs.mkdirSync(output,{recursive:true});
        const page=await browser.newPage({viewport:{width:1024,height:576}});
        page.on('pageerror',e=>errors.push(e.message));
        let release;const gate=new Promise(resolve=>release=resolve);
        await page.route('**/assets/book-comic/prologue.png',async route=>{await gate;await route.continue()});
        await page.goto(base+'/intro-fixture');await page.evaluate(()=>openIntro(1));
        await page.waitForTimeout(150);
        assert.equal(await page.evaluate(()=>pendingPrepared.length),0,'slow decode cannot prepare');
        assert.equal(await page.locator('[data-comic=play]').isDisabled(),true);
        release();await page.waitForFunction(()=>pendingPrepared.length===1);
        const prepared=await page.evaluate(()=>pendingPrepared[0]);
        assert.equal(prepared.payload.v,1,'business RPC remains v1');assert.equal('introId' in prepared.payload,false);
        const state=()=>page.evaluate(()=>({speech:document.querySelector('[data-comic=speech]').textContent,progress:document.querySelector('[data-comic=progress]').style.width,reading:document.querySelector('[data-comic=reading]').hidden}));
        const before=await state();
        assert.equal(await page.locator('canvas').evaluate(c=>Array.from(c.getContext('2d').getImageData(0,0,1024,384).data).some((v,i)=>i%4!==3&&v>0)),true,'static first frame is drawn');
        await page.keyboard.press('ArrowRight');await page.keyboard.press('r');await page.keyboard.press('Space');
        await page.waitForTimeout(250);assert.deepEqual(await state(),before,'content cannot advance before exact Host activation');
        await page.evaluate(m=>ack(m,{panelInstanceId:'foreign'}),prepared);
        assert.equal(await page.locator('[data-comic=play]').isDisabled(),true);
        await page.screenshot({path:path.join(output,'comic-static-before-activation.png')});
        await page.evaluate(m=>ack(m),prepared);
        await page.waitForFunction(()=>document.querySelector('[data-comic=play]').textContent==='暂停');
        await page.waitForFunction(()=>parseFloat(document.querySelector('[data-comic=progress]').style.width)>0);
        await page.locator('[data-comic=play]').click();await page.evaluate(m=>ack(m),prepared);
        assert.equal(await page.locator('[data-comic=play]').textContent(),'播放','duplicate ACK cannot restart a paused comic');
        await page.evaluate(()=>openIntro(2));await page.waitForFunction(()=>pendingPrepared.length===2);
        await page.evaluate(m=>ack(m),prepared);assert.equal(await page.locator('[data-comic=play]').isDisabled(),true,'old activation cannot affect replacement');
        await page.evaluate(()=>{spec.onClose();ack(pendingPrepared[1])});
        assert.equal(await page.locator('[data-comic=play]').count(),0,'late activation after close has no surface');
        await page.close();
        const transition=await browser.newPage({viewport:{width:1024,height:576}});
        transition.on('pageerror',e=>errors.push(e.message));
        await transition.addInitScript(()=>{window.__BREATHING_ROLL__=()=>1;window.outbox=[];window.listeners=[];window.chrome={webview:{postMessage:m=>outbox.push(m),addEventListener:(name,cb)=>listeners.push(cb)}};window.host=p=>listeners.forEach(cb=>cb({data:p}))});
        const projection=(phase,revision,state)=>({type:'scene_transition',version:3,requestId:'tr:1',revision,phase,imageId:'Andy',tip:'试点保护',targetScene:2,actionPending:false,connected:true,generation:0,revealAllowed:true,rewardReady:false,introId:'intro:1',introState:state});
        await transition.goto(base+'/scene-transition.html');
        const legacyCover=projection('cover',1,'loading');legacyCover.version=1;delete legacyCover.introId;delete legacyCover.introState;
        await transition.evaluate(p=>host(p),legacyCover);
        await transition.waitForFunction(()=>outbox.some(m=>m.kind==='covered'));
        await transition.evaluate(p=>host(p),projection('loading',2,'loading'));
        await transition.waitForFunction(()=>outbox.some(m=>m.kind==='covered'&&m.revision===2));
        await transition.evaluate(p=>host(p),projection('reveal',3,'loading'));
        const opacity=await transition.evaluate(async()=>{const frames=[];for(let i=0;i<12;i++){await new Promise(requestAnimationFrame);frames.push(getComputedStyle(document.querySelector('#transition')).opacity)}return frames});
        assert(opacity.every(x=>x==='1'),'intro remains opaque even with ordinary revealAllowed');
        assert.equal(await transition.evaluate(()=>outbox.some(m=>m.kind==='revealed')),false);
        await transition.reload();await transition.evaluate(p=>host(p),projection('intro',4,'opening'));
        await transition.waitForFunction(()=>outbox.some(m=>m.kind==='covered'&&m.revision===4));
        assert.equal(await transition.locator('#transition').isVisible(),true,'recreated protection document covers the retired timeline');
        const foreignHide=projection('hide',5,'complete');foreignHide.introId='intro:2';
        await transition.evaluate(p=>host(p),foreignHide);
        assert.equal(await transition.locator('#transition').isVisible(),true,'foreign terminal cannot remove current protection');
        await transition.screenshot({path:path.join(output,'recreated-intro-cover.png')});
        await transition.evaluate(p=>host(p),projection('hide',5,'complete'));
        assert.equal(await transition.locator('#transition').isVisible(),false);
        assert.deepEqual(errors,[]);
        const result={kind:'real-edge-renderer-fixture',physicalGameAcceptance:false,comic:['slow decode','static frame','exact activation','keyboard admission','duplicate ACK','replacement','late close'],transition:['legacy-to-intro upgrade','opaque intro reveal','recreated intro covered receipt','foreign terminal rejection','terminal hide']};
        fs.writeFileSync(path.join(output,'result.json'),JSON.stringify(result,null,2));
        console.log('PASS: stage intro Edge renderer: slow decode, exact activation, input/late ACK guards, opaque reveal and recreated protection. Host transport fixture; not physical game acceptance.');
    }finally{await browser.close();server.close()}
}
main().catch(error=>{console.error(error);server.close();process.exitCode=1});
