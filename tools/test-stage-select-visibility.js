'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const root=process.env.CF7_REPO_ROOT || path.resolve(__dirname,'..');
const out=process.env.CF7_UI_REVIEW_OUT || path.join(root,'tmp/stage-select-visibility');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
const {startServer}=require(path.join(root,'tools/lib/stage-select-dev-server'));
async function main(){
    fs.mkdirSync(out,{recursive:true});const {server,origin}=await startServer(path.join(root,'launcher/web'));
    let browser,page;const report={scope:'Production UI closure in real Edge/3D with mock Host; no game-entry or save E2E.',checks:[]};
    try{
        browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
        page=await browser.newPage({viewport:{width:1024,height:576}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
        await page.route('https://cfn-fonts.local/**',route=>route.fulfill({status:204,body:''}));
        if(process.env.CF7_UI_BASELINE_ROOT)await page.route('**/stage-select-view-model.js',route=>route.fulfill({path:path.join(process.env.CF7_UI_BASELINE_ROOT,'launcher/web/modules/stage-select/stage-select-view-model.js')}));
        await page.goto(origin+'/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked');
        await page.waitForFunction(()=>window.StageSelectHarnessHost);
        await page.evaluate(()=>{
            document.body.classList.add('stage-select-qa');document.querySelector('#debug-log')?.remove();document.querySelector('#qa-panel')?.remove();
            StageSelectHarnessHost.handleMessage=()=>{};
            StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地车库',debug:false});
        });
        const idle=()=>page.waitForFunction(()=>StageSelectDiorama.stats().state==='ready'&&!StageSelectDiorama.stats().moving,null,{timeout:60000});
        await idle();
        const labels=await page.locator('.stage-select-stage-button > .stage-select-stage-name').allTextContents();
        assert.ok(labels.length>0);assert.ok(labels.every(value=>value==='等待同步'),JSON.stringify(labels));
        assert.equal(await page.locator('.stage-select-card-anchor').count(),0);
        report.checks.push('runtime open and delayed snapshot conceal every name and card, including 3D short labels');
        await page.evaluate(()=>{
            const unlockedStages={};StageSelectData.getManifest().frames.forEach(f=>f.stageButtons.forEach(b=>unlockedStages[b.stageName]=true));
            unlockedStages['堕落城保卫战']=false;unlockedStages['据点M']=false;
            window.__visibilitySnapshot={currentFrameLabel:'基地车库',unlockedStages,stageDetails:{'据点M':{detail:'据点M的秘密详情',stageType:'秘密地图',clearHistory:{cleared:true,difficulties:['地狱']}}}};
            StageSelectPanel._debugApplySnapshot(JSON.parse(JSON.stringify(window.__visibilitySnapshot)));
        });await idle();
        for(const id of ['stage_10_17','stage_10_18']){
            const node=page.locator('.stage-select-stage-button[data-stage-id="'+id+'"]');
            assert.equal(await node.locator('.stage-select-stage-name').innerText(),'未解锁地点');
            assert.equal(await node.getAttribute('aria-label'),'未解锁地点');
            assert.equal(await page.locator('.stage-select-card-anchor[data-stage-id="'+id+'"]').count(),0);
        }
        const locked=page.locator('.stage-select-stage-button[data-stage-id="stage_10_18"]');
        await locked.focus();await page.keyboard.press('Enter');await idle();
        const surface=page.locator('.stage-focus-surface');assert.equal(await surface.isVisible(),true);
        assert.doesNotMatch(await surface.innerText(),/据点M|秘密详情|秘密地图|地狱/);
        assert.equal(await page.evaluate(()=>StageSelectCore.state._inspectorPreviewEl.getAttribute('src')),null);
        assert.equal(await page.locator('#stage-select-inspector-difficulties button').count(),0);
        await page.locator('#stage-select-inspector-name').focus();
        const tooltip=page.locator('#panel-tooltip');await tooltip.waitFor({state:'visible',timeout:3000});
        assert.match(await tooltip.innerText(),/未解锁地点/);assert.doesNotMatch(await tooltip.innerText(),/据点M/);
        await page.evaluate(()=>{const s=JSON.parse(JSON.stringify(window.__visibilitySnapshot));s.unlockedStages['据点M']=true;StageSelectPanel._debugApplySnapshot(s);});await idle();
        assert.equal(await page.locator('#stage-select-inspector-name').innerText(),'据点M');
        assert.equal(await page.locator('#stage-select-inspector-difficulties button').count(),4);
        assert.ok(await page.evaluate(()=>StageSelectCore.state._inspectorPreviewEl.getAttribute('src')));
        await page.evaluate(()=>StageSelectPanel._debugApplySnapshot(JSON.parse(JSON.stringify(window.__visibilitySnapshot))));await idle();
        assert.doesNotMatch(await surface.innerText(),/据点M|秘密详情|秘密地图|地狱/);
        assert.equal(await page.evaluate(()=>StageSelectCore.state._inspectorPreviewEl.getAttribute('src')),null);
        report.checks.push('locked 3D labels, accessible names, keyboard detail, preview, record, tooltip and difficulty controls do not disclose the destination');
        report.checks.push('authoritative unlock restores the selected destination, preview and controls; relocking removes stale disclosed content');
        await page.getByRole('button',{name:'返回总览',exact:true}).click();await idle();
        assert.equal(await surface.isVisible(),false);
        await page.screenshot({path:path.join(out,'stage-select-3d-locked.png')});
        const geometry=await page.locator('.stage-select-legend').evaluate(el=>{
            const r=el.getBoundingClientRect(),nodes=[...el.parentElement.children].filter(n=>n!==el&&getComputedStyle(n).display!=='none'&&n.getBoundingClientRect().width);
            return {x:r.x,right:r.right,items:el.querySelectorAll('.stage-select-legend-item').length,overlaps:nodes.some(n=>{const b=n.getBoundingClientRect();return Math.min(b.right,r.right)>Math.max(b.left,r.left)+1&&Math.min(b.bottom,r.bottom)>Math.max(b.top,r.top)+1;})};
        });assert.equal(geometry.items,5);assert.ok(geometry.x>=0&&geometry.right<=1024&&!geometry.overlaps,JSON.stringify(geometry));
        for(const id of ['nav_10_3','nav_10_4']){
            const nav=page.locator('[data-nav-id="'+id+'"]');assert.match(await nav.getAttribute('class'),/is-region-jump/);
            assert.match(await nav.getAttribute('aria-label'),/^查看区域：/);
            const box=await nav.boundingBox();assert.ok(box.height>=40&&box.x>=0&&box.x+box.width<=1024&&box.y>=42&&box.y+box.height<=576,JSON.stringify(box));
        }
        await page.emulateMedia({reducedMotion:'reduce'});
        assert.equal(await page.locator('[data-nav-id="nav_10_3"]').evaluate(el=>getComputedStyle(el).animationName),'none');
        await page.locator('[data-nav-id="nav_10_3"]').focus();
        await page.keyboard.press('Shift+Tab');await page.keyboard.press('Tab');
        assert.equal(await page.locator('[data-nav-id="nav_10_3"]').evaluate(el=>el===document.activeElement),true);
        assert.notEqual(await page.locator('[data-nav-id="nav_10_3"]').evaluate(el=>getComputedStyle(el).outlineStyle),'none');
        await page.screenshot({path:path.join(out,'stage-select-nav-focus.png')});
        await page.keyboard.press('Enter');
        assert.equal(await page.evaluate(()=>StageSelectCore.state._currentFrameLabel),'黑铁会总部');
        assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length),0);
        report.checks.push('five-item legend and two 44px semantic region-jump buttons fit 1024×576, also in reduced motion; keyboard focus and navigation send zero stage-enter messages');
        await page.evaluate(()=>{const s=JSON.parse(JSON.stringify(window.__visibilitySnapshot));s.forceUnlock=true;StageSelectPanel._debugApplySnapshot(s);});await idle();
        assert.equal(await page.locator('[data-stage-id="stage_10_18"] > .stage-select-stage-name').innerText(),'据点M');
        await page.evaluate(()=>{const s=JSON.parse(JSON.stringify(window.__visibilitySnapshot));s.forceUnlock=true;s.isChallengeMode=true;StageSelectPanel._debugApplySnapshot(s);});await idle();
        assert.equal(await page.locator('[data-stage-id="stage_10_18"] > .stage-select-stage-name').innerText(),'未解锁地点');
        await page.evaluate(()=>{const s=JSON.parse(JSON.stringify(window.__visibilitySnapshot));delete s.unlockedStages['据点M'];StageSelectPanel._debugApplySnapshot(s);});await idle();
        assert.equal(await page.locator('[data-stage-id="stage_10_18"] > .stage-select-stage-name').innerText(),'等待同步');
        report.checks.push('force unlock reveals known destinations; challenge disables it; missing unlock keys remain pending');
        await page.evaluate(()=>StageSelectRenderer.setFrame('地下2层','visibility-2d'));
        // Use a genuine flat frame and an authoritative false state for every destination.
        await page.evaluate(()=>{const f=StageSelectData.getFrame(StageSelectCore.state._currentFrameLabel),s={unlockedStages:{},stageDetails:{}};f.stageButtons.forEach(b=>s.unlockedStages[b.stageName]=false);StageSelectPanel._debugApplySnapshot(s);});
        assert.ok((await page.locator('.stage-select-stage-button > .stage-select-stage-name').allTextContents()).every(v=>v==='未解锁地点'||v==='未解锁'));
        const first=page.locator('.stage-select-stage-button').first();await first.focus();await page.keyboard.press('Enter');
        assert.equal(await page.locator('.stage-focus-map-caption').innerText(),'未解锁地点');
        await page.keyboard.press('Escape');
        await page.screenshot({path:path.join(out,'stage-select-2d-locked.png')});
        await page.evaluate(()=>StageSelectHarnessHost.open({mode:'dev',frameLabel:'基地车库'}));
        assert.notEqual(await page.locator('[data-stage-id="stage_10_18"] > .stage-select-stage-name').innerText(),'等待同步');
        assert.deepEqual(errors,[]);report.checks.push('flat map names and focus captions use the same concealment; developer fixtures retain immediate visibility');
        report.pass=true;
    }catch(error){report.pass=false;report.error=error.stack;process.exitCode=1;if(page)await page.screenshot({path:path.join(out,'stage-visibility-failure.png')}).catch(()=>{});}
    finally{if(browser)await browser.close();server.close();fs.writeFileSync(path.join(out,'stage-visibility-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
