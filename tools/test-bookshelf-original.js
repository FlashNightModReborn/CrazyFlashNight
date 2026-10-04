#!/usr/bin/env node
'use strict';
// Player boundary/lifecycle tests. No real Host, player saves or SP writes.
const assert = require('assert'), fs = require('fs'), path = require('path'), vm = require('vm');
const root = path.resolve(__dirname, '..');
let passed = 0;
function check(value, label) { assert.ok(value, label); passed++; }
const handlers = new Map(), timers = new Map(), elements = [];
let serial = 0;
function element(tag) {
    const node = {tagName:tag.toUpperCase(), attributes:{}, children:[], hidden:false, focuses:0,
        setAttribute(k,v) {this.attributes[k]=v;}, replaceChildren(...children) {this.children=children;},
        remove() {this.removed=true;}, focus() {this.focuses++;}, controls:{},
        querySelector(selector) {return this.controls[selector.match(/"([^"]+)"/)[1]];},
        set innerHTML(html) { this.controls={}; for (const [,name] of html.matchAll(/data-original="([^"]+)"/g)) this.controls[name]={}; },
        set textContent(text) {this.text=text;this.children=[];}, get textContent() {return this.text;}};
    if (tag==='iframe') node.contentWindow={sent:[],postMessage(data,origin){this.sent.push({data,origin});}};
    elements.push(node); return node;
}
const win={addEventListener:(k,f)=>handlers.set(k,f),removeEventListener:(k,f)=>{if(handlers.get(k)===f)handlers.delete(k);}};
const context={window:win,document:{createElement:element},crypto:{randomUUID:()=>String(++serial).padStart(36,'0')},
    setTimeout:f=>{let id=++serial;timers.set(id,f);return id;},clearTimeout:id=>timers.delete(id)};
vm.runInNewContext(fs.readFileSync(path.join(root,'launcher/web/modules/bookshelf-original.js'),'utf8'),context);
const host=element('div'),toolbar=element('div'); let backs=0;
const player=new win.BookshelfOriginal(host,toolbar,{back:()=>backs++});
player.show(); const first=player.frame, firstSession=player.session;
check(first.attributes.sandbox==='allow-scripts','movie cannot share the parent origin, storage or navigation authority');
check(first.src==='modules/bookshelf/original/player.html#'+firstSession,'fixed local frame, no caller-chosen movie URL');
const reply=(patch={})=>({source:player.frame.contentWindow,origin:'null',data:{channel:'bookshelf-original.v1',session:player.session,state:'playing'},...patch});
const originalReady=reply();
for (const invalid of [reply({source:{}}),reply({origin:'https://overlay.local'}),reply({data:{...originalReady.data,session:'old'}}),
        reply({data:{...originalReady.data,state:'applied'}}),reply({data:{...originalReady.data,channel:'bookshelf'}})]) {
    handlers.get('message')(invalid); check(!player.ready,'foreign or business-like replies cannot control the player');
}
handlers.get('message')(originalReady);
check(player.ready && !player.paused && player.message.hidden,'current movie becomes playable');
player.get('pause').onclick();
check(first.contentWindow.sent[0].data.action==='pause' && first.contentWindow.sent[0].data.session===firstSession,'pause targets only the current movie session');
handlers.get('message')(reply({data:{...originalReady.data,state:'paused'}}));
check(player.paused && player.get('pause').textContent==='继续','pause is shown after the movie acknowledges it');
player.get('pause').onclick();check(first.contentWindow.sent[1].data.action==='play','resume stays within the player protocol');
player.show();check(player.frame===first,'unrelated renders do not restart the original');
player.get('restart').onclick(); const second=player.frame;
check(first.removed && second!==first && player.session!==firstSession,'restart removes the old movie and rotates its identity');
handlers.get('message')(originalReady);check(!player.ready && second.focuses===0,'late old-movie replies cannot focus or revive it');
player.get('back').onclick();check(backs===1,'back is a presentation callback');
player.hide();check(second.removed && !player.frame && timers.size===0,'leaving tears down the frame and load timer');
player.show();player.destroy();player.destroy();
check(!handlers.has('message') && timers.size===0 && !player.frame,'close/rebind cleanup is idempotent');

async function childTest() {
    const received=[],messages=[],stage=element('main'); let loaded,script,plays=0,pauses=0;
    const parent={postMessage:(data,origin)=>messages.push({data,origin})};
    const session='11111111-1111-4111-8111-111111111111';
    const child={location:{href:'https://overlay.local/modules/bookshelf/original/player.html#'+session,
        hostname:'overlay.local',hash:'#'+session},parent,URL,
        document:{getElementById:()=>stage,createElement:()=>script={},head:{appendChild(){}}}};
    child.window={addEventListener:(type,f)=>received.push(f)};
    vm.runInNewContext(fs.readFileSync(path.join(root,'launcher/web/modules/bookshelf/original/player.js'),'utf8'),child);
    const config=child.window.RufflePlayer.config;
    check(config.allowNetworking==='none' && config.openUrlMode==='deny' && config.allowScriptAccess===false,'old SWF web links and script access are disabled');
    check(config.forceScale && config.scale==='showAll','original allowscale=false cannot leave a tiny or cropped stage');
    check(script.src==='https://cfn-assets.local/_ruffle/ruffle.js','uses shipped local Ruffle');
    child.window.RufflePlayer.newest=()=>({createPlayer:()=>({load:async args=>{loaded=args.url;},play:()=>plays++,pause:()=>pauses++})});
    await script.onload();
    check(loaded==='https://cfn-assets.local/originals/crazy-flasher-1.swf','movie source is fixed to the imported original');
    check(messages[0].data.state==='playing' && messages[0].origin==='https://overlay.local','readiness is addressed to the parent origin');
    const command={source:parent,origin:'https://overlay.local',data:{channel:'bookshelf-original.v1',session,action:'pause'}};
    for(const bad of [{...command,source:{}},{...command,origin:'null'},{...command,data:{...command.data,session:'old'}},
        {...command,data:{...command.data,action:'commit'}}]) received[0](bad);
    check(pauses===0 && plays===0,'foreign and non-player commands are rejected');
    received[0](command); received[0]({...command,data:{...command.data,action:'play'}});
    check(pauses===1 && plays===1,'only pause/resume are accepted');
    console.log(`Bookshelf original isolation/lifecycle: ${passed} passed; no Host or save E2E claim.`);
}
childTest().catch(error=>{console.error(error);process.exitCode=1;});
