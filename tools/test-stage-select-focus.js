'use strict';
const fs=require('fs'), path=require('path'), assert=require('assert/strict');
const {startServer}=require('./lib/stage-select-dev-server');
const root=path.resolve(__dirname,'..'), out=path.join(root,'tmp/stage-select-focus');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
async function main() {
    fs.mkdirSync(out,{recursive:true});
    const {server,origin}=await startServer(path.join(root,'launcher/web'));
    const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
    const page=await browser.newPage({viewport:{width:1024,height:576}});
    const errors=[], report={scope:'Real Edge/GLB/mouse with mock Host. Clear fixtures are UI visibility evidence, not player-save E2E.',checks:[]};
    page.on('pageerror',e=>errors.push(e.message));
    await page.route('https://cfn-fonts.local/**',route=>route.fulfill({status:204,body:''}));
    const idle=()=>page.waitForFunction(()=>StageSelectDiorama.stats().state==='ready'&&!StageSelectDiorama.stats().moving);
    const pose=()=>page.evaluate(()=>StageSelectDiorama.snapshotCamera());
    const near=(a,b)=>{for(const key of ['position','target'])a[key].forEach((n,i)=>assert.ok(Math.abs(n-b[key][i])<1e-7));assert.ok(Math.abs(a.span-b.span)<1e-7);};
    const select=async(id)=>{ await page.locator('.stage-select-stage-button[data-stage-id="'+id+'"] > .stage-select-stage-name').dblclick(); await idle(); };
    const back=async()=>{await page.getByRole('button',{name:'返回总览',exact:true}).click();await idle();};
    try {
        await page.goto(origin+'/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked');
        await page.evaluate(()=>{document.body.classList.add('stage-select-qa');document.querySelector('#debug-log')?.remove();document.querySelector('#qa-panel')?.remove();StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地门口'});});
        await idle();
        await page.evaluate(()=>StageSelectPanel._debugApplySnapshot({unlockedStages:StageSelectCore.state._runtimeSnapshot.unlockedStages,stageDetails:{'地铁站':{detail:'僵尸喜爱黑暗的环境，于是地铁站成为了整个废城最为凶险的地区。',task:true,highestDifficulty:'修罗'}}}));
        const overviewBeforeFocus=await pose();
        await select('stage_0_9');
        const focusedPose=await pose();
        const tourPose=await page.evaluate(id=>StageSelectDiorama.getTourCamera(id),'stage_0_9');
        assert.ok(Math.abs(focusedPose.span-(overviewBeforeFocus.span+(tourPose.span-overviewBeforeFocus.span)*.5))<1e-7);
        const stats=await page.evaluate(()=>StageSelectDiorama.stats());
        assert.equal(stats.focusId,'stage_0_9'); assert.equal(stats.highlighted,'stage_0_9');
        assert.ok(stats.width<650 && stats.height>400); assert.equal(stats.editing,false);
        assert.equal(await page.locator('.stage-select-diorama-canvas').count(),1);
        await page.screenshot({path:path.join(out,'3d-brief.png')});
        const bounds=await page.locator('.stage-focus-panel').evaluate(el=>{const r=el.getBoundingClientRect(), b=el.querySelector('.stage-focus-enter').getBoundingClientRect();return {right:r.right,bottom:r.bottom,enterHeight:b.height,enterBottom:b.bottom,overflow:el.scrollHeight>el.clientHeight+1};});
        assert.ok(bounds.right<=1024&&bounds.bottom<=576&&bounds.enterBottom<=576&&bounds.enterHeight>=40&&!bounds.overflow,JSON.stringify(bounds));
        report.checks.push('3D context focus keeps theater geometry and highlight on one canvas; fixed 60:40 detail and visible action at 1024x576');
        assert.equal(await page.locator('.stage-focus-pager').isVisible(),true);
        assert.match(await page.locator('.stage-focus-pager span').innerText(),/10 \/ 16/);
        const pagerGeometry=await page.locator('.stage-focus-surface > .workbench-header').evaluate(header=>{
            const pager=header.querySelector('.stage-focus-pager'), r=pager.getBoundingClientRect(), h=header.getBoundingClientRect();
            const scene=document.querySelector('.stage-focus-viewport').getBoundingClientRect();
            return {inActions:pager.parentElement.classList.contains('workbench-header-actions'),
                outsideScene:r.bottom<=scene.top+1, fitsHeader:r.left>=h.left&&r.right<=h.right&&r.top>=h.top&&r.bottom<=h.bottom,
                overflow:header.scrollWidth>header.clientWidth+1};
        });
        assert.deepEqual(pagerGeometry,{inActions:true,outsideScene:true,fitsHeader:true,overflow:false});
        await page.locator('[data-focus-pager="next"]').focus(); await page.keyboard.press('Enter'); await idle();
        assert.equal(await page.evaluate(()=>StageSelectCore.state._selectedStageId),'stage_0_10');
        assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusPager),'next');
        const expectedName=await page.evaluate(()=>StageSelectDiorama.orderButtons(StageSelectData.getFrame('基地门口'))[10].stageName);
        assert.ok((await page.locator('.stage-select-inspector-name').innerText()).includes(expectedName.replace(/^外交-/,'')));
        await page.locator('[data-focus-pager="prev"]').focus(); await page.keyboard.press('Enter'); await idle();
        assert.equal(await page.evaluate(()=>StageSelectCore.state._selectedStageId),'stage_0_9');
        assert.equal(await page.evaluate(()=>document.activeElement.dataset.focusPager),'prev');
        assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length),0);
        report.checks.push('header pager stays outside the scene and fits 1024px; Enter preserves pager focus, context and selection without sending enter');
        await page.getByRole('tab',{name:'情报',exact:true}).click();
        assert.match(await page.locator('.stage-focus-content').innerText(),/通关后解锁/);
        assert.equal(await page.locator('.stage-focus-reward').count(),0);
        await page.evaluate(()=>StageSelectPanel._debugApplySnapshot({unlockedStages:StageSelectCore.state._runtimeSnapshot.unlockedStages,stageDetails:{'地铁站':{clearHistory:{cleared:true,difficulties:['修罗']}}}}));
        assert.ok(await page.locator('.stage-focus-reward').count()>0);
        assert.ok(await page.locator('.stage-focus-enemy').count()>0);
        assert.match(await page.locator('.stage-focus-history').innerText(),/修罗/);
        await page.screenshot({path:path.join(out,'3d-intel.png')});
        const sent=await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length);
        await page.locator('#stage-select-inspector-difficulties [data-difficulty="冒险"]').click();
        assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length),sent);
        assert.match(await page.locator('#stage-focus-enter').innerText(),/冒险/);
        await page.evaluate(()=>StageSelectPanel._debugApplySnapshot({unlockedStages:StageSelectCore.state._runtimeSnapshot.unlockedStages,stageDetails:{'地铁站':{clearHistory:{cleared:false,difficulties:[]}}}}));
        assert.equal(await page.locator('.stage-focus-reward').count(),0);
        assert.match(await page.locator('#stage-focus-enter').innerText(),/冒险/);
        report.checks.push('unrecorded/task recommendation never reveals intel; true clear reveals; history removal clears DOM; selected mode survives refresh');
        await back();
        near(await pose(),overviewBeforeFocus);
        await select('stage_0_9');
        assert.equal(await page.getByRole('tab',{name:'情报',exact:true}).getAttribute('aria-selected'),'true');
        assert.match(await page.locator('#stage-focus-enter').innerText(),/冒险/);
        report.checks.push('return restores the exact pre-focus camera and per-stage tab/difficulty view state');
        await page.keyboard.press('Control+Shift+C');
        await page.waitForFunction(()=>StageSelectDiorama.stats().editing);
        const before=await page.evaluate(()=>StageSelectDiorama.savePreset()['stage_0_9']);
        const canvas=await page.locator('.stage-select-diorama-canvas').boundingBox();
        await page.mouse.move(canvas.x+canvas.width/2,canvas.y+100);await page.mouse.down();await page.mouse.move(canvas.x+canvas.width/2+65,canvas.y+130,{steps:12});await page.mouse.up();
        await page.locator('[data-camera="save"]').click();
        const after=await page.evaluate(()=>JSON.parse(localStorage.getItem(StageSelectDioramaData.presetKey))['stage_0_9']);
        assert.notDeepEqual(after.position,before.position);
        await page.locator('[data-camera="export"]').click();
        const exported=JSON.parse(await page.locator('.stage-camera-editor textarea').inputValue());assert.deepEqual(exported['stage_0_9'],after);
        await page.locator('.stage-camera-editor textarea').fill('{"overview":{"position":[0,0,0]}}');
        await page.locator('[data-camera="import"]').click();
        assert.match(await page.locator('.stage-camera-editor [role=status]').innerText(),/无效/);
        await page.locator('.stage-camera-editor textarea').fill(JSON.stringify(exported));await page.locator('[data-camera="import"]').click();
        await page.evaluate(()=>StageSelectRenderer.requestClose('escape'));
        assert.equal(await page.locator('.stage-focus-surface').isVisible(),true);
        assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing),false);
        await back(); await select('stage_0_9');
        await page.getByRole('button',{name:'游览地点',exact:true}).click();
        await page.evaluate(()=>StageSelectDiorama.peekStage('stage_0_9'));
        const reopened=await page.evaluate(()=>StageSelectDiorama.savePreset()['stage_0_9']);
        for (const key of ['position','target']) reopened[key].forEach((n,i)=>assert.ok(Math.abs(n-after[key][i])<1e-8));
        assert.ok(Math.abs(reopened.span-after.span)<1e-8);
        await page.evaluate(()=>{StageSelectHarnessHost.close();StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地门口'});});await idle();
        assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().focusId),'');
        assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().width),1024);
        report.checks.push('real orbit gesture changes camera; per-stage save/export/import validates; active tour retains custom closeups and reopen restores overview');
        await page.keyboard.press('Control+Shift+C');await page.waitForFunction(()=>StageSelectDiorama.stats().editing);
        await page.mouse.move(700,250);await page.mouse.wheel(0,-70);await page.locator('[data-camera="save"]').click();await page.locator('[data-camera="close"]').click();
        const projection=await page.evaluate(()=>{const p=StageSelectCore.state._visualStagePoints.stage_0_9,n=StageSelectRenderer.findNodeById('stage_0_9');return {x:p.x,left:parseFloat(n.style.left),y:p.y,top:parseFloat(n.style.top)};});
        assert.ok(Math.abs(projection.x-projection.left)<.01);assert.ok(Math.abs(projection.y-projection.top)<.01);
        await select('stage_0_9');await page.evaluate(()=>document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());
        await page.waitForFunction(()=>StageSelectDiorama.stats().state==='error');
        assert.equal(await page.locator('.stage-focus-surface').isVisible(),false);
        await page.locator('.stage-select-diorama-status button').click();await idle();
        report.checks.push('overview camera keeps marker projection aligned; graphics loss during focus exits to retry and recovers');
        await page.evaluate(()=>{StageSelectRenderer.setFrame('地下2层','qa');});
        const id=await page.locator('.stage-select-stage-button:not(.is-direct-entry)').first().getAttribute('data-stage-id');
        await page.locator('.stage-select-stage-button[data-stage-id="'+id+'"]').dblclick();
        assert.equal(await page.locator('.stage-focus-location').isVisible(),true);
        assert.equal(await page.locator('.stage-focus-location svg circle').count(),2);
        assert.equal(await page.locator('.stage-focus-panel').isVisible(),true);
        await page.screenshot({path:path.join(out,'2d-brief.png')});
        await page.keyboard.press('Escape');assert.equal(await page.locator('.stage-focus-surface').isVisible(),false);
        report.checks.push('2D map offers same brief/intel/actions with highlighted location and Escape return');
        await page.evaluate(()=>StageSelectRenderer.setFrame('黑铁会总部','qa'));
        await page.waitForFunction(()=>StageSelectCore.state._currentFrameLabel==='黑铁会总部'&&StageSelectDiorama.stats().state==='ready'&&!StageSelectDiorama.stats().moving);
        await page.locator('.stage-select-stage-button[data-stage-id="stage_18_6"] > .stage-select-stage-name').hover();
        report.naturalSide=await page.locator('.stage-select-card-anchor[data-stage-id="stage_18_6"]').getAttribute('data-placement');
        // 2026-10-29 Flash 手感合同：快捷卡只停上/下方，难度行朝向节点（上方卡在底边、下方卡在顶边）。
        assert.ok(['above','below'].includes(report.naturalSide));
        await page.evaluate(()=>{
            const button=StageSelectViewModel.findStageButtonById('stage_18_6'),state=StageSelectCore.state;
            // 旧版会回灌的方向记忆不得再影响停靠。
            state._cardPlacementById[state._catalogId+'/'+state._currentFrameLabel+'/'+button.id]='right';
            StageSelectRenderer.placeCardAnchor(button,StageSelectRenderer.findNodeById(button.id),
                document.querySelector('.stage-select-card-anchor[data-stage-id="'+button.id+'"]'),true);
        });
        const sideCard=page.locator('.stage-select-card-anchor[data-stage-id="stage_18_6"] > .stage-select-card');
        await sideCard.waitFor({state:'visible'});
        report.sideAction=await sideCard.evaluate(el=>{
            const anchor=el.parentElement,row=el.querySelector(':scope > .stage-select-difficulties');
            return {side:anchor.dataset.placement,actionPosition:anchor.dataset.actionPosition,
                connectionY:anchor._cardConnection.y2-parseFloat(anchor.style.top),rowTop:row.offsetTop,
                rowBottom:row.offsetTop+row.offsetHeight,actionDirection:getComputedStyle(row).flexDirection};
        });
        assert.equal(report.sideAction.side,report.naturalSide,'remembered side no longer overrides geometry');
        assert.equal(report.sideAction.actionPosition,report.sideAction.side==='above'?'bottom':'top');
        assert.equal(report.sideAction.actionDirection,'row');
        assert.ok(report.sideAction.connectionY>=report.sideAction.rowTop-8&&report.sideAction.connectionY<=report.sideAction.rowBottom+8);
        await sideCard.evaluate(el=>Promise.all(el.getAnimations().map(animation=>animation.finished.catch(()=>{}))));
        await page.screenshot({path:path.join(out,'black-dragon-side-actions.png')});
        report.checks.push('black-dragon quick card stays vertical, ignores remembered side, and puts difficulty and connector on the node-facing edge');
        assert.deepEqual(errors,[]);report.pass=true;
    } catch(error) {report.pass=false;report.error=error.stack;report.pageErrors=errors;await page.screenshot({path:path.join(out,'failure.png')});process.exitCode=1;}
    finally {await browser.close();server.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
