'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {startServer}=require('./lib/stage-select-dev-server');
const root=path.resolve(__dirname,'..'),out=path.join(root,'tmp/stage-select-intel');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
async function main(){
    fs.mkdirSync(out,{recursive:true});const {server,origin}=await startServer(path.join(root,'launcher/web'));
    const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
    const page=await browser.newPage({viewport:{width:1024,height:576}}),errors=[];
    const report={scope:'Real local item icons/enemy portraits/shared tooltip in Edge; clear history is mock Host data.',checks:[]};
    page.on('pageerror',e=>errors.push(e.message));
    await page.route('https://cfn-fonts.local/**',r=>r.fulfill({status:204,body:''}));
    const details=data=>page.evaluate(value=>StageSelectPanel._debugApplySnapshot({stageDetails:{'地铁站':value}}),data);
    try{
        await page.goto(origin+'/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked');
        await page.evaluate(()=>{document.body.classList.add('stage-select-qa');document.querySelector('#debug-log')?.remove();document.querySelector('#qa-panel')?.remove();StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地门口'});});
        await page.waitForFunction(()=>StageSelectDiorama.stats().state==='ready');
        await details({stageType:'无限过图',detail:'僵尸喜爱黑暗的环境，于是地铁站成为了整个废城最为凶险的地区。'.repeat(18),clearHistory:{cleared:true,difficulties:['地狱']}});
        await page.locator('.stage-select-stage-button[data-stage-id="stage_0_9"] > .stage-select-stage-name').click();
        await page.waitForFunction(()=>!StageSelectDiorama.stats().moving);
        const layout=await page.evaluate(()=>{
            const q=s=>document.querySelector(s).getBoundingClientRect(),top=q('.stage-focus-topbar'),art=q('.stage-focus-preview'),brief=q('.stage-select-inspector-detail'),name=q('.stage-select-inspector-name'),history=q('.stage-focus-history'),tabs=q('.stage-focus-tabs'),scroll=document.querySelector('.stage-focus-content');
            return {height:top.height,artBeforeText:art.bottom<=brief.top+1,centers:[name,history,tabs].map(r=>(r.top+r.bottom)/2),nativeDetails:document.querySelectorAll('.stage-focus-panel details').length,scrollable:scroll.scrollHeight>scroll.clientHeight,scrollbar:getComputedStyle(scroll).scrollbarColor};
        });
        assert.ok(layout.height<=36,JSON.stringify(layout));assert.ok(Math.max(...layout.centers)-Math.min(...layout.centers)<3);assert.equal(layout.artBeforeText,true);assert.equal(layout.nativeDetails,0);assert.equal(layout.scrollable,true);assert.notEqual(layout.scrollbar,'auto');
        await page.screenshot({path:path.join(out,'brief.png')});report.checks.push('1024x576 heading/type/history/tabs share one line; art precedes long brief; custom dark scrollbars replace native disclosure and scrollbar styling');
        await page.getByRole('tab',{name:'情报',exact:true}).click();
        await page.waitForFunction(()=>['.stage-focus-reward img','.stage-focus-enemy img'].every(selector=>{const images=[...document.querySelectorAll(selector)];return images.length && images.every(img=>img.complete&&img.naturalWidth>0);}));
        const portraits=await page.locator('.stage-focus-enemy').evaluateAll(nodes=>nodes.map(el=>({ref:el.dataset.portraitRef,source:el.dataset.portraitSource,url:el.querySelector('img').src,name:el.getAttribute('aria-label')})));
        assert.ok(portraits.every(p=>p.ref && /enemy-portraits\//.test(p.url)),JSON.stringify(portraits));
        assert.equal(await page.locator('.stage-focus-enemy').evaluateAll(nodes=>nodes.every(el=>{const r=el.querySelector('img').getBoundingClientRect(),b=el.getBoundingClientRect();return r.width>30&&r.height>30&&r.top>=b.top&&r.bottom<=b.bottom&&r.left>=b.left&&r.right<=b.right;})),true);
        const tiles=await page.locator('.stage-focus-token').evaluateAll(nodes=>nodes.map(el=>({text:el.textContent,title:el.title,w:el.getBoundingClientRect().width,label:el.getAttribute('aria-label')})));
        assert.ok(tiles.every(t=>!t.text&&!t.title&&t.label&&t.w<=48));
        await page.screenshot({path:path.join(out,'intel.png')});report.portraits=portraits;report.checks.push('reward grid renders real static item icons; enemy grid resolves accepted identity portraits; compact 42/48px tiles retain accessible names');
        const reward=page.locator('.stage-focus-reward').first(),label=await reward.getAttribute('aria-label');await reward.hover();
        await page.waitForFunction(()=>PanelTooltip.isVisible());assert.match(await page.locator('#panel-tooltip').innerText(),new RegExp(label));
        await page.screenshot({path:path.join(out,'tooltip.png')});
        await page.getByRole('tab',{name:'简报',exact:true}).click();assert.equal(await page.evaluate(()=>PanelTooltip.isVisible()),false);
        await page.getByRole('tab',{name:'情报',exact:true}).click();
        for(let i=0;i<30 && !await page.locator('.stage-focus-enemy:focus').count();i++)await page.keyboard.press('Tab');
        assert.equal(await page.locator('.stage-focus-enemy:focus').count(),1);
        await page.waitForFunction(()=>PanelTooltip.isVisible());
        await details({clearHistory:{cleared:false,difficulties:[]}});assert.equal(await page.locator('.stage-focus-token').count(),0);assert.equal(await page.evaluate(()=>PanelTooltip.isVisible()),false);
        await page.getByRole('button',{name:'返回总览',exact:true}).click();
        const tooltip=await page.evaluate(()=>PanelTooltip.debugState());assert.equal(tooltip.bindingCount,0);assert.equal(tooltip.activeScopeCount,0);
        assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length),0);assert.deepEqual(errors,[]);report.checks.push('shared tooltip works with hover and keyboard; tab/history changes and close release stale content/bindings without stage-enter writes');report.pass=true;
    }catch(error){report.pass=false;report.error=error.stack;report.pageErrors=errors;process.exitCode=1;await page.screenshot({path:path.join(out,'failure.png')});}
    finally{await browser.close();server.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
