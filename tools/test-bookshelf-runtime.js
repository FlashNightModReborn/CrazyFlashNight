/* Production transport and asset closure checks; this does not execute Flash or write saves. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const P = require('../launcher/web/modules/panel-runtime.js');
const R = require('../launcher/web/modules/bookshelf-runtime.js');
const root = path.resolve(__dirname, '..');
let passed = 0;
function check(value, message) { assert.ok(value, message); passed++; }
async function main() {
    check(R.books.length === 3 && R.books.filter(b => b.pages === 15).length === 2, 'two preserved books and one playable book');
    for (const id of ['dust','babylon']) {
        for (let page=1;page<=15;page++) check(R.pageUrl(id,page).endsWith(String(page).padStart(2,'0')+'.svg'), 'all original pages reachable');
    }
    for (const args of [['dust',0],['dust',16],['dust',1.5],['dust','1'],['../dust',1],['repair-campus',1]])
        check(R.pageUrl(...args) === null, 'invalid or non-reading page rejected');
    const router = new P.PanelResponseRouter({onError:()=>{}});
    let sent, replies=0;
    const mux = new R.RequestMux({panelInstanceId:'bookshelf.instance.1',router,send:m=>{sent=m;return true;}});
    mux.request('snapshot',{v:1,token:'bookshelf.test'},()=>replies++);
    const response = {...sent,type:'panel_resp',success:true};
    for (const patch of [{panelInstanceId:'old'},{panel:'sleep'},{domain:'sleep'},{cmd:'commit'},{callId:'wrong'}]) {
        router.handleResponse({...response,...patch});check(replies === 0, 'foreign response rejected');
    }
    router.handleResponse(response);check(replies === 1,'exact response accepted');
    router.handleResponse(response);check(replies === 1,'duplicate reply ignored');
    mux.request('commit',{v:1,token:'bookshelf.test',kind:'switch',target:'b'},()=>replies++);
    check(mux.request('commit',{},()=>{}) === null,'concurrent writes suppressed');
    const late={...sent,type:'panel_resp'};mux.destroy();router.handleResponse(late);
    check(replies === 1,'retired panel ignores late write response');
    let unknown;
    const timeoutMux=new R.RequestMux({panelInstanceId:'bookshelf.timeout',timeoutMs:10,router,send:()=>true});
    timeoutMux.request('commit',{v:1,token:'bookshelf.timeout'},r=>unknown=r);
    await new Promise(resolve=>setTimeout(resolve,150));
    check(unknown && unknown.requiresReconcile && unknown.error === 'client_timeout','lost write reply retains reconcile requirement');
    timeoutMux.destroy();
    let rejected;
    const failedMux=new R.RequestMux({panelInstanceId:'bookshelf.rejected',router,send:()=>false});
    failedMux.request('commit',{v:1,token:'bookshelf.failed'},r=>rejected=r);
    check(rejected && rejected.error === 'not_sent' && !rejected.requiresReconcile,'known local non-delivery is distinct from unknown');
    failedMux.destroy();
    const assets=path.join(root,'launcher/web/assets/bookshelf');
    const manifest=JSON.parse(fs.readFileSync(path.join(assets,'manifest.json'),'utf8'));
    const hash=data=>crypto.createHash('sha256').update(data).digest('hex');
    check(hash(fs.readFileSync(path.join(root,manifest.source))) === manifest.sourceSha256,'source SWF identity');
    const actual=[];
    function walk(dir,prefix='') {for(const entry of fs.readdirSync(dir,{withFileTypes:true})) {
        if(entry.isDirectory())walk(path.join(dir,entry.name),prefix+entry.name+'/');
        else if(entry.name!=='manifest.json')actual.push(prefix+entry.name);
    }}
    walk(assets);assert.deepStrictEqual(actual.sort(),Object.keys(manifest.files).sort());passed++;
    let total=0;
    for(const [file,expected] of Object.entries(manifest.files)) {
        const data=fs.readFileSync(path.join(assets,file)); total+=data.length;
        check(hash(data)===expected.sha256 && data.length===expected.bytes,'page integrity '+file);
        check(!/<script\b|<foreignObject\b|(?:href|src)=["'](?:https?:|file:|javascript:)/i.test(data.toString()),'passive local vector page '+file);
    }
    check(total===manifest.totalBytes && total<1024*1024,'complete bounded asset closure');
    console.log(`Bookshelf runtime/assets: ${passed} passed; no Flash, SOL or gameplay claim.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
