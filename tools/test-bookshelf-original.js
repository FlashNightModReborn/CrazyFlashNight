#!/usr/bin/env node
'use strict';
// Production controllers with isolated DOM/transport doubles. No player/CF7 save writes.
const assert = require('assert'), fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.resolve(__dirname, '..'), origin = 'https://cf7-originals.local';
let passed = 0;
function check(value, label) { assert.ok(value, label); passed++; }
const handlers = new Map(), timers = new Map();
let serial = 0;
function element(tag) {
    const node = {attributes:{}, children:[], hidden:false, focuses:0, controls:{}, labels:{},
        setAttribute(k,v) {this.attributes[k]=v;}, replaceChildren(...children) {this.children=children;},
        remove() {this.removed=true;}, focus() {this.focuses++;},
        querySelector(selector) { return selector.startsWith('.') ? this.labels[selector] : this.controls[selector.match(/"([^"]+)"/)[1]]; },
        set innerHTML(html) { this.controls={}; this.labels={'.bookshelf-original-keys':{}};
            for (const [,name] of html.matchAll(/data-original="([^"]+)"/g)) this.controls[name]={}; },
        set textContent(text) {this.text=text;this.children=[];}, get textContent() {return this.text;}};
    if (tag==='iframe') node.contentWindow={sent:[],postMessage(data,target){this.sent.push({data,target});}};
    return node;
}
const win={addEventListener:(k,f)=>handlers.set(k,f),removeEventListener:(k,f)=>{if(handlers.get(k)===f)handlers.delete(k);}};
const context={window:win,document:{createElement:element},URL,
    setTimeout:f=>{let id=++serial;timers.set(id,f);return id;},clearTimeout:id=>timers.delete(id)};
vm.runInNewContext(fs.readFileSync(path.join(root,'launcher/web/modules/bookshelf-original.js'),'utf8'),context);
const host=element('div'),toolbar=element('div'), pending=[],releases=[]; let backs=0;
const controller=new win.BookshelfOriginal(host,toolbar,{back:()=>backs++,prepare:(d,done)=>pending.push({d,done}),release:s=>releases.push(s)});
const definition={chapter:1,language:'cn'};
function receipt(chapter=1, language='cn') {
    const session='11111111-1111-4111-8111-'+String(++serial).padStart(12,'0');
    return {success:true,session,origin,playerUrl:origin+'/player/'+(chapter===1?'local':'a'.repeat(64))+'/cf'+chapter+'-'+language+'/player.html#'+session};
}
controller.show(definition);
check(!controller.frame && pending.length===1,'movie never loads before Host authorizes content');
controller.show(definition);check(pending.length===1,'unrelated renders preserve pending player');
pending.shift().done({success:false,error:'not_owned'});
check(!controller.frame && controller.message.textContent.includes('未拥有'),'ownership failure is explicit and retryable');
controller.get('restart').onclick();pending.shift().done({success:false,error:'development_content_missing'});
check(!controller.frame && controller.message.textContent.includes('开发环境无需启动 Steam'),'missing development assets do not ask for a Steam launch');
controller.get('restart').onclick();pending.shift().done(receipt());
const first=controller.frame, firstSession=controller.session;
check(first.attributes.sandbox==='allow-scripts allow-same-origin','separate origin has its own storage without popup/top navigation grants');
check(first.name==='bookshelf-original' && first.src.startsWith(origin+'/player/local/cf1-cn/'),'fixed isolated origin, no caller chosen movie URL');
const reply=(patch={})=>({source:controller.frame.contentWindow,origin,data:{channel:'bookshelf-original.v1',session:controller.session,state:'playing'},...patch});
const ready=reply();
for(const invalid of [reply({source:{}}),reply({origin:'null'}),reply({origin:'https://overlay.local'}),
    reply({data:{...ready.data,session:'old'}}),reply({data:{...ready.data,state:'applied'}}),
    reply({data:{...ready.data,channel:'bookshelf'}})]) {
    handlers.get('message')(invalid);check(!controller.ready,'foreign or CF7 business replies cannot control the player');
}
handlers.get('message')(ready);check(controller.ready && controller.message.hidden,'exact readiness is accepted');
controller.get('pause').onclick();
check(first.contentWindow.sent[0].data.action==='pause' && first.contentWindow.sent[0].target===origin,'pause targets the exact player origin');
handlers.get('message')(reply({data:{...ready.data,state:'paused'}}));
check(controller.paused && controller.get('pause').textContent==='继续','paused state comes from movie acknowledgment');
controller.get('pause').onclick();check(first.contentWindow.sent[1].data.action==='play','resume remains a player control');
controller.show(definition);check(controller.frame===first,'same chapter/language never reloads on a snapshot render');
controller.get('restart').onclick();pending.shift().done(receipt());const second=controller.frame;
check(first.removed && second!==first && releases.includes(firstSession),'restart retires the old movie and releases only its lease');
handlers.get('message')(ready);check(!controller.ready && second.focuses===0,'late old-movie reply cannot revive or focus it');
controller.get('back').onclick();check(backs===1,'back is a local presentation action');
controller.hide();check(second.removed && !controller.frame && timers.size===0,'hide removes frame and timer');
controller.show({chapter:5,language:'en'});const late=pending.shift();controller.hide();const lateReceipt=receipt(5,'en');late.done(lateReceipt);
check(!controller.frame && releases.includes(lateReceipt.session),'late authorization after back is released without mounting');
for(const bad of ['https://evil.test/player.html','https://overlay.local/overlay.html',origin+'/ruffle/ruffle.js']) {
    controller.show(definition);const r=receipt();r.playerUrl=bad;pending.shift().done(r);
    check(!controller.frame && releases.includes(r.session),'unexpected resource route cannot become a player');controller.hide();
}
controller.destroy();controller.destroy();
check(!handlers.has('message') && timers.size===0,'destroy/rebind cleanup is idempotent');

async function childTest() {
    const received=[],messages=[],stage=element('main');let loaded,script,plays=0,pauses=0;
    const parent={postMessage:(data,target)=>messages.push({data,target})};
    const session='11111111-1111-4111-8111-111111111111';
    const info={chapter:5,language:'cn',swfFileName:'cf5-cn.swf',
        movieUrl:origin+'/session/'+session+'/movie.swf',baseUrl:origin+'/session/'+session+'/exes/'};
    const api={load:async args=>{loaded=args;},suspend:()=>pauses++,resume:()=>plays++};
    const child={location:{origin,href:origin+'/player/'+ 'a'.repeat(64)+'/cf5-cn/player.html#'+session,hash:'#'+session},
        parent,URL, fetch:async url=>({ok:true,json:async()=>info,arrayBuffer:async()=>new ArrayBuffer(8)}),
        document:{getElementById:()=>stage,createElement:()=>script={},head:{appendChild(){Promise.resolve().then(()=>script.onload());}}}};
    child.window={addEventListener:(type,f)=>received.push(f)};
    Object.defineProperty(child.window,'RufflePlayer',{get(){return this._ruffle;},set(value){
        value.newest=()=>({createPlayer:()=>({ruffle:()=>api})});this._ruffle=value;}});
    vm.runInNewContext(fs.readFileSync(path.join(root,'launcher/web/modules/bookshelf/original/player.js'),'utf8'),child);
    await new Promise(resolve=>setImmediate(resolve));
    const config=child.window.RufflePlayer.config;
    check(config.openUrlMode==='deny' && config.allowScriptAccess===false && !config.showSwfDownload,'movie cannot open links or get parent script authority');
    check(config.contextMenu==='on' && config.deviceFontRenderer==='canvas','original custom menu and Chinese device fonts remain available');
    check(script.src===origin+'/ruffle/ruffle.js','Ruffle comes only from the isolated closed resource origin');
    check(loaded.data.byteLength===8 && loaded.swfFileName==='cf5-cn.swf' && loaded.base===info.baseUrl,'uses unchanged data bytes and stable movie filename');
    check(messages[0].data.state==='playing' && messages[0].target==='https://overlay.local','readiness is addressed only to the parent');
    const command={source:parent,origin:'https://overlay.local',data:{channel:'bookshelf-original.v1',session,action:'pause'}};
    for(const bad of [{...command,source:{}},{...command,origin:'null'},{...command,data:{...command.data,session:'old'}},
        {...command,data:{...command.data,action:'commit'}}]) received[0](bad);
    check(pauses===0 && plays===0,'foreign and business commands are ignored');
    received[0](command);received[0]({...command,data:{...command.data,action:'play'}});
    check(pauses===1 && plays===1,'versioned Ruffle API handles only suspend/resume');
    const contract=JSON.parse(fs.readFileSync(path.join(root,'launcher/contracts/bookshelf-original.v1.json'),'utf8'));
    check(Object.keys(contract.commands).join(',')==='prepare,release' && Object.values(contract.commands).every(c=>c.access==='read'),'closed Host-only read contract');
    console.log('Bookshelf original boundary/lifecycle: '+passed+' passed; no real Host or save E2E claim.');
}
childTest().catch(error=>{console.error(error);process.exitCode=1;});
