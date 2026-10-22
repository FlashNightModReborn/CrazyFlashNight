'use strict';
const fs=require('fs'),path=require('path');
const {connectExactTarget,evaluateByValue}=require('../workbench-live-e2e/kshop/cdp-client');
const {sha256Bytes,sleep}=require('../workbench-live-e2e/kshop/common');
const TARGETS=Object.freeze({series:'[data-book="crazy-flasher"]',chapter6:'[data-chapter="6"]',
    play:'[data-action="remake"]',return:'[data-action="remake"]',close:'#bookshelf-close'});
async function openInput({cdpBinding,runtimeIdentity,writer,runDir}) {
    if (cdpBinding.runtimePid!==runtimeIdentity.pid || cdpBinding.exclusiveBeforeLaunch!==true)
        throw Error('CF6 input requires the exact runtime-owned CDP binding');
    const {client}=await connectExactTarget(cdpBinding.port,'https://overlay.local/overlay.html',30000,200);
    await client.call('Runtime.enable',{},10000);await client.call('Page.enable',{},10000);
    async function readState() {
        return evaluateByValue(client,`(function(){var p=document.getElementById('panel-container');
            var selected=document.querySelector('[data-chapter="6"]');var a=document.querySelector('[data-action="remake"]');
            return {url:String(location.href),panel:p?p.getAttribute('data-panel'):'',hidden:!p||p.hidden||p.style.display==='none',
            chapter6:!!selected&&selected.getAttribute('aria-pressed')==='true',
            action:a?{text:a.textContent.trim(),disabled:!!a.disabled}:null,
            status:String((document.getElementById('bookshelf-status')||{}).textContent||'')};})()`,'CF6 visible bookshelf');
    }
    async function click(name) {
        const selector=TARGETS[name];if (!selector) throw Error('input target outside fixed allowlist');
        const state=await readState();
        if (state.url!=='https://overlay.local/overlay.html'||state.panel!=='bookshelf'||state.hidden)
            throw Error('bookshelf page is not visible');
        if (name==='play' && (!state.chapter6 || !state.action || state.action.text.includes('返回原角色')))
            throw Error('CF6 play button is not in the expected chapter state');
        if (name==='return' && (!state.action || !state.action.text.includes('返回原角色')))
            throw Error('CF6 return button is not showing the production return action');
        const geometry=await evaluateByValue(client,`(function(s){var e=document.querySelector(s);if(!e)return null;
            var r=e.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2,h=document.elementFromPoint(x,y),c=getComputedStyle(e);
            return {x:x,y:y,enabled:!e.disabled,visible:r.width>0&&r.height>0&&c.display!=='none'&&c.visibility!=='hidden',
            hit:!!h&&(h===e||e.contains(h)),text:e.textContent.trim()};})(${JSON.stringify(selector)})`,'CF6 hit tested button');
        if (!geometry||!geometry.enabled||!geometry.visible||!geometry.hit) throw Error('button is not visibly actionable: '+name);
        const sequence=writer.events.length;
        for (const type of ['mouseMoved','mousePressed','mouseReleased']) await client.call('Input.dispatchMouseEvent',{
            type,x:geometry.x,y:geometry.y,button:type==='mouseMoved'?'none':'left',buttons:type==='mousePressed'?1:0,clickCount:1
        },10000);
        await sleep(150);
        const proof=writer.events.find(event=>event.sequence>sequence&&event.kind==='dom_input'&&event.isTrusted===true
            &&event.target?.visible===true&&event.target?.enabled===true&&event.target?.hitTargetMatches===true
            &&event.target.text===geometry.text);
        if (!proof) throw Error('trusted visible page input proof missing for '+name);
        writer.append({kind:'cf6_candidate_page_input',target:name,selector,geometry,inputSequence:proof.sequence,
            runtimePid:runtimeIdentity.pid,physicalInputAttestation:false});
        return {afterSequence:sequence,inputSequence:proof.sequence,name};
    }
    async function screenshot(name) {
        if (!/^[a-z0-9-]+\.png$/.test(name)) throw Error('invalid screenshot name');
        const result=await client.call('Page.captureScreenshot',{format:'png',captureBeyondViewport:false},15000);
        const bytes=Buffer.from(result.data,'base64'),file=path.join(runDir,name);
        fs.writeFileSync(file,bytes,{flag:'wx'});return {file,sha256:sha256Bytes(bytes),bytes:bytes.length};
    }
    return {readState,click,screenshot,close:()=>client.close()};
}
module.exports={openInput,TARGETS};
