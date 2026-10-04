#!/usr/bin/env node
'use strict';
// Explicit local asset compatibility probe. Isolated browser/profile; no Steam
// entitlement claim, executable launch, SWF output file or real player save use.
const fs=require('fs'),path=require('path'),assert=require('assert'),crypto=require('crypto');
const root=path.resolve(__dirname,'..');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
const arg=name=>(process.argv.find(a=>a.startsWith('--'+name+'='))||'').slice(name.length+3);
const collection=arg('collection-root'),out=path.resolve(arg('out')||'tmp/bookshelf-original-runtime');
if(!collection)throw new Error('--collection-root is required for this explicit local paid-asset probe');
fs.mkdirSync(out,{recursive:true});
const origin='https://cf7-originals.local',parentOrigin='https://overlay.local';
const headerSource=fs.readFileSync(path.join(root,'launcher/src/Guardian/BookshelfOriginalWebResources.cs'),'utf8');
const csp=[...headerSource.match(/ContentSecurityPolicy\s*=([\s\S]*?);\r?\n/)[1].matchAll(/"([^"\n]*)"/g)].map(m=>m[1]).join('');
const expected=fs.readFileSync(path.join(root,'launcher/src/Tasks/BookshelfOriginalContent.cs'),'utf8');
const hashes=Object.fromEntries([...expected.matchAll(/\["([1-6]-(?:cn|en))"\]\s*=\s*"([0-9a-f]{64})"/g)].map(m=>[m[1],m[2]]));
const ruffle=[...expected.match(/RuffleFiles\s*=\s*\{([\s\S]*?)\}/)[1].matchAll(/"([^"]+)"/g)].map(m=>m[1]);
const hash=data=>crypto.createHash('sha256').update(data).digest('hex');
function movieBytes(chapter,language) {
    const key=chapter+'-'+language;
    const file=chapter===1?path.join(root,'flashswf/originals/crazy-flasher-1.swf')
        :path.join(collection,'exes/crazyflasher'+key+'_secure.exe');
    const stat=fs.statSync(file);assert(stat.size<64*1024*1024);
    const fd=fs.openSync(file,'r');try {
        let offset=0,size=stat.size;
        if(chapter!==1){const footer=Buffer.alloc(8);fs.readSync(fd,footer,0,8,stat.size-8);
            assert.strictEqual(footer.readUInt32LE(0),0xfa123456);size=footer.readUInt32LE(4);offset=stat.size-8-size;}
        assert(size>=8&&size<=24*1024*1024&&offset>=0);
        const data=Buffer.alloc(size);assert.strictEqual(fs.readSync(fd,data,0,size,offset),size);
        assert.strictEqual(data.subarray(0,3).toString(),'FWS');assert.strictEqual(data.readUInt32LE(4),size);
        assert.strictEqual(hash(data),hashes[key]);return data;
    } finally {fs.closeSync(fd);}
}
async function main(){
    const edge=[process.env['ProgramFiles(x86)'],process.env.ProgramFiles].filter(Boolean)
        .map(p=>path.join(p,'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    const browser=await chromium.launch({headless:true,executablePath:edge,args:['--autoplay-policy=no-user-gesture-required']});
    const report={scope:'isolated Chromium production wrapper/CSP and unchanged local assets; not Steam/Host/CF7 E2E',
        browser:browser.version(),cases:[],storage:[]};
    try {
        for(const chapter of (arg('chapter') ? [Number(arg('chapter'))] : [1,2,3,4,5,6]))for(const language of chapter===1||arg('chapter')?['cn']:['cn','en']){
            const data=movieBytes(chapter,language),context=await browser.newContext({viewport:{width:1000,height:650}});
            let session=crypto.randomUUID();const namespace=chapter===1?'local':'a'.repeat(64);
            const doc=origin+'/player/'+namespace+'/cf'+chapter+'-'+language+'/player.html';
            const violations=[],foreignRequests=[],consoleErrors=[];
            await context.addInitScript(()=>{
                window.__bookStorageReads=[];window.__bookViolations=[];
                window.addEventListener('securitypolicyviolation',e=>__bookViolations.push(e.blockedURI));
                const get=Storage.prototype.getItem;
                Storage.prototype.getItem=function(key){const value=get.call(this,key);
                    if(String(key).includes('crazyflasher'))__bookStorageReads.push({key,value});return value;};
                // Ruffle initializes a Map by enumerating Storage properties; that
                // path does not call getItem. Observe those reads as well.
                const storage=window.localStorage;
                const observed=new Proxy(storage,{get(target,key){const value=Reflect.get(target,key,target);
                    if(typeof key==='string'&&key.includes('crazyflasher'))__bookStorageReads.push({key,value});
                    return typeof value==='function'?value.bind(target):value;}});
                Object.defineProperty(window,'localStorage',{get:()=>observed});
            });
            await context.route('**/*',async route=>{
                const uri=new URL(route.request().url());let body,type='text/plain',status=200,headers={};
                if(uri.origin===parentOrigin&&uri.pathname==='/overlay.html'){
                    body='<!doctype html><style>html,body,iframe{margin:0;width:100%;height:100%;border:0;overflow:hidden}</style>'
                        +'<script>window.states=[];addEventListener("message",e=>{if(e.origin==="'+origin+'"&&e.data.channel==="bookshelf-original.v1")states.push(e.data);});</script>'
                        +'<iframe name="bookshelf-original" sandbox="allow-scripts allow-same-origin" allow="autoplay" src="'+doc+'#'+session+'"></iframe>';type='text/html';
                } else if(uri.origin===origin){
                    headers={'Content-Security-Policy':csp,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'};
                    const p=uri.pathname,prefix='/session/'+session+'/';
                    if(p===new URL(doc).pathname){body=fs.readFileSync(path.join(root,'launcher/web/modules/bookshelf/original/player.html'));type='text/html';}
                    else if(p==='/player.js'){body=fs.readFileSync(path.join(root,'launcher/web/modules/bookshelf/original/player.js'));type='text/javascript';}
                    else if(p===prefix+'manifest.json'){body=JSON.stringify({chapter,language,swfFileName:'cf'+chapter+'-'+language+'.swf',
                        movieUrl:origin+prefix+'movie.swf',baseUrl:origin+prefix+'exes/'});type='application/json';}
                    else if(p===prefix+'movie.swf'){body=data;type='application/x-shockwave-flash';}
                    else if(p.startsWith('/ruffle/')&&ruffle.includes(p.slice(8))){body=fs.readFileSync(path.join(root,'flashswf/_ruffle',p.slice(8)));type=p.endsWith('.wasm')?'application/wasm':'text/javascript';}
                    else{status=404;body='';}
                }else{foreignRequests.push(uri.origin);await route.abort();return;}
                await route.fulfill({status,contentType:type,body,headers});
            });
            const page=await context.newPage();page.on('console',m=>{if(m.type()==='error')consoleErrors.push(m.text().slice(0,250));});
            async function open(){await page.goto(parentOrigin+'/overlay.html');await page.waitForFunction(()=>states.length>0,null,{timeout:30000});
                assert.strictEqual(await page.evaluate(()=>states.at(-1).state),'playing');return page.frames().find(f=>f.url().startsWith(doc));}
            try {
                const frame=await open();
                await frame.evaluate(async()=>{try{await fetch('https://example.com/probe-blocked');}catch{};
                    const popup=window.open('https://example.com/probe-blocked');if(popup)throw Error('sandbox popup grant');});
                await page.waitForTimeout(2500);
                assert.strictEqual(foreignRequests.length,0,'no external request reaches the network');
                const blocked=await frame.evaluate(()=>__bookViolations);assert(blocked.includes('https://example.com/probe-blocked'));
                if(language==='cn' && [4,5].includes(chapter)){
                    await page.mouse.click(500,chapter===4?310:415,{delay:100});await page.waitForTimeout(8500);
                    await page.mouse.click(chapter===4?280:125,chapter===4?175:585,{delay:100});await page.waitForTimeout(1500);
                    await page.screenshot({path:path.join(out,'cf'+chapter+'-canvas-font.png')});
                    if(chapter===4){await page.mouse.click(500,615,{delay:100});await page.waitForTimeout(2000);await page.keyboard.press('q');}
                    else{await page.mouse.click(380,585,{delay:100});await page.waitForTimeout(800);await page.mouse.click(175,265,{delay:100});await page.waitForTimeout(2500);}
                    const saved=await frame.evaluate(()=>Object.entries(localStorage).filter(([key])=>key.includes('crazyflasher')));
                    assert(saved.length>0,'actual game SharedObject is flushed in the isolated profile');
                    const firstSession=session;session=crypto.randomUUID();const next=await open();await page.waitForTimeout(1500);
                    const readAtLoad=await next.evaluate(()=>__bookStorageReads);
                    const kept=await next.evaluate(()=>Object.entries(localStorage).filter(([key])=>key.includes('crazyflasher')));
                    await next.evaluate(()=>{__bookStorageReads.length=0;});
                    await page.mouse.click(500,chapter===4?310:415,{delay:100});await page.waitForTimeout(8500);
                    if(chapter===4){await page.mouse.click(280,175,{delay:100});await page.waitForTimeout(800);await page.mouse.click(500,615,{delay:100});await page.waitForTimeout(1500);}
                    else{await page.mouse.click(125,585,{delay:100});await page.waitForTimeout(1500);}
                    const read=readAtLoad.concat(await next.evaluate(()=>__bookStorageReads));
                    if(chapter===5 && read.length===0)await page.screenshot({path:path.join(out,'cf5-readback.png')});
                    if(!read.some(r=>saved.some(([key,value])=>r.key===key&&r.value===value)))
                        console.log(JSON.stringify({chapter,saved:saved.map(([key,value])=>({key,bytes:value.length})),reads:read.map(r=>({key:r.key,bytes:r.value?.length}))}));
                    for(const [key,value]of saved){assert(kept.some(([k,v])=>k===key&&v===value),'same saved bytes survive session rotation');
                        assert(read.some(r=>r.key===key&&r.value===value),'actual Ruffle readback uses the stable key and saved value');
                        assert(!key.includes(firstSession)&&!key.includes(session),'content GUID is absent from actual storage key');}
                    report.storage.push({chapter,language,sessionRotated:true,actualReadback:true,
                        keys:saved.map(([key,value])=>({key,bytes:value.length,sha256:hash(value)}))});
                }
                report.cases.push({chapter,language,loaded:true,payloadBytes:data.length,payloadSha256:hash(data),externalNetworkRequests:foreignRequests.length,
                    deliberateBlockedFetch:true,consoleErrors:consoleErrors.slice(0,5)});
                console.log('original wrapper: cf'+chapter+'-'+language+' passed');
            }finally{await context.close();}
        }
        fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
        console.log('Original wrapper/CSP: '+report.cases.length+' variants; session-rotation SharedObject readback passed for '
            +report.storage.map(s=>'CF'+s.chapter).join('/')+'.');
    }finally{await browser.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
