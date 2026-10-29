'use strict';
const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {startServer}=require('./lib/stage-select-dev-server');
const root=path.resolve(__dirname,'..'),out=path.join(root,'tmp/stage-select-navigation');
const {chromium}=require(path.join(root,'launcher/perf/node_modules/playwright'));
async function main(){
    fs.mkdirSync(out,{recursive:true});
    const {server,origin}=await startServer(path.join(root,'launcher/web'));
    const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true});
    const page=await browser.newPage({viewport:{width:1024,height:576}}),errors=[];
    const report={scope:'Real Edge keyboard/mouse and GLB with mock Host; blur/context loss are injected lifecycle events, not physical WebView2 proof.',checks:[]};
    page.on('pageerror',e=>errors.push(e.message));
    await page.route('https://cfn-fonts.local/**',r=>r.fulfill({status:204,body:''}));
    const pose=()=>page.evaluate(()=>StageSelectDiorama.snapshotCamera());
    const frames=()=>page.evaluate(()=>StageSelectDiorama.stats().frames);
    const near=(a,b)=>{for(const key of ['position','target'])a[key].forEach((n,i)=>assert.ok(Math.abs(n-b[key][i])<1e-7));assert.ok(Math.abs(a.span-b.span)<1e-7);};
    const idle=()=>page.waitForFunction(()=>StageSelectDiorama.stats().state==='ready'&&!StageSelectDiorama.stats().moving);
    const movingMode=()=>page.waitForFunction(()=>StageSelectDiorama.stats().editing);
    try{
        await page.goto(origin+'/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked');
        await page.evaluate(()=>{document.body.classList.add('stage-select-qa');document.querySelector('#debug-log')?.remove();document.querySelector('#qa-panel')?.remove();StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地门口'});});await idle();
        const original=await pose(),stored=await page.evaluate(()=>localStorage.getItem('cf7.stage-camera.base-gate.v1'));
        await page.evaluate(value=>StageSelectDiorama.restoreCamera({...value,span:4.99}),original);near(await pose(),original);
        await page.evaluate(value=>StageSelectDiorama.restoreCamera({...value,span:5}),original);assert.equal((await pose()).span,5);
        await page.evaluate(value=>StageSelectDiorama.restoreCamera(value),original);
        report.checks.push('Existing maps retain the default minimum camera span of 5');
        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        assert.equal(await page.locator('[data-camera="save"]').isVisible(),false);
        assert.equal(await page.locator('.stage-select-button-layer').evaluate(el=>getComputedStyle(el).opacity),'0');
        await page.mouse.move(720,180);await page.mouse.down();await page.keyboard.down('w');await page.keyboard.down('d');
        await page.mouse.move(790,220,{steps:15});await page.waitForTimeout(180);
        await page.keyboard.up('w');await page.keyboard.up('d');await page.mouse.up();
        const traveled=await pose();assert.notDeepEqual(traveled.target,original.target);
        const direction=p=>p.position.map((n,i)=>n-p.target[i]);assert.notDeepEqual(direction(traveled),direction(original));
        await page.waitForTimeout(100);const stopped=await frames();await page.waitForTimeout(180);assert.equal(await frames(),stopped);
        await page.evaluate(()=>StageSelectPanel._debugApplySnapshot({stageDetails:{'地铁站':{task:true,highestDifficulty:'修罗'}}}));
        assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing),true);near(await pose(),traveled);
        assert.equal(await page.locator('[data-camera="toggle-pins"]').isVisible(),true);
        await page.locator('[data-camera="toggle-pins"]').click();
        assert.equal(await page.locator('.stage-select-panel').evaluate(el=>el.classList.contains('is-tour-pins-visible')),true);
        await page.locator('[data-camera="toggle-pins"]').click();
        assert.equal(await page.locator('.stage-select-panel').evaluate(el=>el.classList.contains('is-tour-pins-visible')),false);
        await page.locator('[data-camera="next-poi"]').click();await idle();
        assert.notDeepEqual((await pose()).target,traveled.target);
        await page.getByRole('button',{name:'结束游览',exact:true}).first().click();near(await pose(),original);
        assert.equal(await page.evaluate(()=>localStorage.getItem('cf7.stage-camera.base-gate.v1')),stored);
        assert.equal(await page.evaluate(()=>StageSelectCore.state._cardLayerEl.inert || StageSelectCore.state._navLayerEl.inert),false);
        report.checks.push('visible player tour button; simultaneous WASD and mouse orbit; POI stepping and landmark pin toggle; snapshot preserves tour; release stops frames; exit restores view without writing presets');

        const nearArray=(a,b,tolerance=1e-7)=>a.forEach((n,i)=>assert.ok(Math.abs(n-b[i])<tolerance,`${n} != ${b[i]}`));
        const viewOffset=p=>p.position.map((n,i)=>n-p.target[i]);
        await page.evaluate(()=>{StageSelectHarnessHost.close();StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地门口'});});await idle();
        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        const poi=await page.evaluate(()=>{
            const ids=StageSelectDiorama.getTourStageIds(),frame=StageSelectData.getFrame(StageSelectCore.state._currentFrameLabel);
            const ordered=StageSelectDiorama.orderButtons(frame).filter(b=>!StageSelectViewModel.isDirectEntry(b)&&StageSelectDiorama.canFocus(b.id)).map(b=>b.id);
            const button=StageSelectViewModel.findStageButtonById(ids[0]);
            window.__navigationPoi={title:document.querySelector('.stage-camera-poi-title'),detail:document.querySelector('.stage-camera-poi-detail')};
            return {ids,ordered,id:ids[0],name:StageSelectViewModel.getStageDisplayName(button),title:document.querySelector('.stage-camera-poi-title').textContent,
                detail:document.querySelector('.stage-camera-poi-detail').textContent,compass:document.querySelector('.stage-camera-poi-compass').textContent};
        });
        assert.deepEqual(poi.ids,poi.ordered);assert.ok(poi.title.includes('1 / '+poi.ids.length));assert.ok(poi.title.includes(poi.name));
        assert.ok(poi.detail.length>0);assert.ok(poi.compass.length>0);
        assert.equal(await page.locator('.stage-camera-poi').isVisible(),true);assert.equal(await page.locator('.stage-camera-poi-select').isVisible(),true);
        const livePoi=await page.evaluate(()=>{
            const id=StageSelectDiorama.getTourStageIds()[0],button=StageSelectViewModel.findStageButtonById(id),name=button.stageName;
            const current=StageSelectCore.state._runtimeSnapshot,stageDetails=Object.assign({},current.stageDetails);
            stageDetails[name]=Object.assign({},stageDetails[name],{detail:'导览首句情报。第二句不进入摘要'});
            StageSelectPanel._debugApplySnapshot(Object.assign({},current,{stageDetails}));
            return {id,stageName:name,detail:document.querySelector('.stage-camera-poi-detail').textContent};
        });
        assert.equal(livePoi.detail,'导览首句情报');
        const lockedPoi=await page.evaluate(info=>{
            const name=info.stageName,current=StageSelectCore.state._runtimeSnapshot,unlockedStages=Object.assign({},current.unlockedStages,{[name]:false}),stageDetails=Object.assign({},current.stageDetails);
            stageDetails[name]=Object.assign({},stageDetails[name],{detail:'LOCKED_SECRET_DETAIL'});
            StageSelectPanel._debugApplySnapshot(Object.assign({},current,{unlockedStages,stageDetails}));
            return {title:document.querySelector('.stage-camera-poi-title').textContent,detail:document.querySelector('.stage-camera-poi-detail').textContent};
        },livePoi);
        assert.ok(lockedPoi.title.includes('未解锁地点'));assert.ok(!lockedPoi.title.includes(livePoi.stageName));
        assert.ok(!lockedPoi.detail.includes('LOCKED_SECRET_DETAIL'));assert.ok(lockedPoi.detail.includes('尚未解锁'));
        await page.evaluate(info=>{
            const current=StageSelectCore.state._runtimeSnapshot,unlockedStages=Object.assign({},current.unlockedStages,{[info.stageName]:true}),stageDetails=Object.assign({},current.stageDetails);
            stageDetails[info.stageName]=Object.assign({},stageDetails[info.stageName],{detail:'导览首句情报。第二句不进入摘要'});
            StageSelectPanel._debugApplySnapshot(Object.assign({},current,{unlockedStages,stageDetails}));
        },livePoi);
        await page.locator('[data-camera="next-poi"]').click();await idle();assert.ok((await page.locator('.stage-camera-poi-title').textContent()).includes('2 /'));
        await page.locator('[data-camera="prev-poi"]').click();await idle();assert.ok((await page.locator('.stage-camera-poi-title').textContent()).includes('1 /'));
        assert.equal(await page.locator('.stage-camera-poi-detail').textContent(),'导览首句情报');
        for(const selector of ['[data-camera="next-poi"]','.stage-camera-poi-select','[data-camera="toggle-pins"]','[data-camera="collapse"]','[data-camera="reset"]','[data-camera="close"]']){
            await page.locator(selector).focus();const controlStart=await pose();await page.keyboard.press('ArrowRight');await page.waitForTimeout(70);near(await pose(),controlStart);
        }
        const syncFrames=await frames();await page.evaluate(()=>StageSelectCameraEditor.sync());assert.equal(await frames(),syncFrames);
        assert.equal(await page.evaluate(()=>window.__navigationPoi.title===document.querySelector('.stage-camera-poi-title')&&window.__navigationPoi.detail===document.querySelector('.stage-camera-poi-detail')),true);
        const selectedPoi=await page.evaluate(()=>{document.querySelector('[data-camera="next-poi"]').click();return {id:StageSelectDiorama.getTourStageIds()[1],moving:StageSelectDiorama.stats().moving};});
        assert.equal(selectedPoi.moving,true);
        await page.locator('.stage-camera-poi-select').click();await idle();
        assert.equal(await page.evaluate(()=>StageSelectCore.state._selectedStageId),selectedPoi.id);
        assert.equal(await page.locator('.stage-focus-surface').isVisible(),true);
        assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing),false);
        const selectedPose=await pose();assert.notEqual(selectedPose.span,original.span);
        await page.waitForTimeout(450);near(await pose(),selectedPose);
        assert.equal(await page.evaluate(()=>StageSelectCore.state._selectedStageId),selectedPoi.id);
        assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length),0);
        await page.getByRole('button',{name:'返回总览',exact:true}).click();await idle();near(await pose(),original);
        report.checks.push('ordered POI identity/detail/compass use safe ViewModel projections; locked text is concealed; tour control arrows do not pan; sync is render-idle; select restores entry before detail and sends zero enter');

        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        await page.evaluate(()=>{window.__navigationTourOpener=document.activeElement;});
        const rightStart=await pose();
        for(let i=0;i<3;i++){await page.mouse.move(30,180);await page.mouse.down({button:'right'});await page.mouse.move(1000,180,{steps:12});await page.mouse.up({button:'right'});}
        const rightEnd=await pose(),rightBounds=await page.evaluate(()=>{
            const home=StageSelectDioramaData.camera.gltfTarget,current=StageSelectDiorama.snapshotCamera(),radius=(StageSelectDioramaData.camera.maxSpan||240)*1.15;
            return {distance:Math.hypot(current.target[0]-home[0],current.target[2]-home[2]),radius};
        });
        assert.ok(rightBounds.distance<=rightBounds.radius+1e-7,JSON.stringify(rightBounds));assert.ok(rightBounds.distance>rightBounds.radius-1e-5,JSON.stringify(rightBounds));
        nearArray(viewOffset(rightEnd),viewOffset(rightStart));assert.equal(rightEnd.span,rightStart.span);
        await page.evaluate(()=>{
            const current=StageSelectDiorama.snapshotCamera(),home=StageSelectDioramaData.camera.gltfTarget,radius=(StageSelectDioramaData.camera.maxSpan||240)*1.15;
            let fx=current.target[0]-current.position[0],fz=current.target[2]-current.position[2];const length=Math.hypot(fx,fz);fx/=length;fz/=length;
            const rx=-fz,rz=fx,target=[home[0]+rx*(radius-1),current.target[1],home[2]+rz*(radius-1)],delta=target.map((n,i)=>n-current.target[i]);
            StageSelectDiorama.restoreCamera({position:current.position.map((n,i)=>n+delta[i]),target,span:current.span});
        });await idle();await movingMode();
        const walkBoundaryStart=await pose();await page.keyboard.down('Shift');await page.keyboard.down('d');await page.waitForTimeout(220);await page.keyboard.up('d');await page.keyboard.up('Shift');
        const walkBoundaryEnd=await pose(),walkBounds=await page.evaluate(()=>{
            const home=StageSelectDioramaData.camera.gltfTarget,current=StageSelectDiorama.snapshotCamera(),radius=(StageSelectDioramaData.camera.maxSpan||240)*1.15;
            return {distance:Math.hypot(current.target[0]-home[0],current.target[2]-home[2]),radius};
        });
        assert.ok(walkBounds.distance<=walkBounds.radius+1e-7,JSON.stringify(walkBounds));assert.ok(walkBounds.distance>walkBounds.radius-1e-5,JSON.stringify(walkBounds));
        nearArray(viewOffset(walkBoundaryEnd),viewOffset(walkBoundaryStart));
        const boundaryFrames=await frames();await page.waitForTimeout(180);assert.equal(await frames(),boundaryFrames);
        await page.locator('[data-camera="close"]').click();near(await pose(),original);
        assert.equal(await page.evaluate(()=>document.activeElement===window.__navigationTourOpener),true);
        assert.equal(await page.evaluate(()=>StageSelectCore.state._buttonLayerEl.inert||StageSelectCore.state._cardLayerEl.inert||StageSelectCore.state._navLayerEl.inert),false);
        report.checks.push('right-drag and WASD share the home-target XZ radius with camera/target offset preserved; close restores entry, opener focus and inert layers without resident frames');

        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        const rapid=await page.evaluate(()=>{
            const next=document.querySelector('[data-camera="next-poi"]');next.click();next.click();
            const id=StageSelectDiorama.getTourStageIds()[2];
            return {id,expected:StageSelectDiorama.getTourCamera(id),moving:StageSelectDiorama.stats().moving};
        });
        assert.equal(rapid.moving,true);await idle();near(await pose(),rapid.expected);
        assert.ok((await page.locator('.stage-camera-poi-title').textContent()).includes('3 /'));
        const rapidSettled=await pose(),rapidFrames=await frames();await page.waitForTimeout(450);near(await pose(),rapidSettled);assert.equal(await frames(),rapidFrames);
        await page.evaluate(()=>{document.querySelector('[data-camera="next-poi"]').click();document.querySelector('[data-camera="close"]').click();});near(await pose(),original);
        await page.waitForTimeout(450);near(await pose(),original);assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing||StageSelectDiorama.stats().moving),false);
        await page.emulateMedia({reducedMotion:'reduce'});
        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        const reduced=await page.evaluate(()=>{
            const id=StageSelectDiorama.getTourStageIds()[1],expected=StageSelectDiorama.getTourCamera(id);
            document.querySelector('[data-camera="next-poi"]').click();
            return {expected,pose:StageSelectDiorama.snapshotCamera(),moving:StageSelectDiorama.stats().moving};
        });
        assert.equal(reduced.moving,false);near(reduced.pose,reduced.expected);
        const reducedFrames=await frames();await page.evaluate(()=>StageSelectCameraEditor.sync());assert.equal(await frames(),reducedFrames);
        await page.waitForTimeout(180);assert.equal(await frames(),reducedFrames);
        await page.locator('[data-camera="close"]').click();near(await pose(),original);await page.emulateMedia({reducedMotion:'no-preference'});
        report.checks.push('rapid next is latest-wins; exit cancels late transition callbacks; reduced-motion lands synchronously and sync/idle create no extra frames');

        await page.keyboard.press('Control+Shift+C');await movingMode();
        const arrowStart=await pose();await page.keyboard.down('ArrowUp');await page.waitForTimeout(160);await page.keyboard.up('ArrowUp');
        assert.notDeepEqual((await pose()).target,arrowStart.target);
        await page.keyboard.down('w');await page.waitForTimeout(80);await page.evaluate(()=>window.dispatchEvent(new Event('blur')));
        const blurred=await pose();await page.waitForTimeout(130);near(await pose(),blurred);await page.keyboard.up('w');
        await page.locator('[data-camera="export"]').click();const text=await page.locator('textarea').inputValue(),typingStart=await pose();
        assert.equal(await page.evaluate(()=>localStorage.getItem('cf7.stage-camera.base-gate.v1')),stored);
        await page.keyboard.type('wasd');await page.keyboard.press('ArrowLeft');await page.waitForTimeout(120);near(await pose(),typingStart);
        await page.locator('textarea').fill(text);await page.locator('[data-camera="fold-presets"]').click();assert.equal(await page.locator('textarea').isVisible(),false);
        await page.locator('[data-camera="export"]').click();await page.locator('[data-camera="collapse"]').click();
        assert.equal(await page.locator('textarea').isVisible(),false);assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing),true);
        const bounds=await page.locator('.stage-camera-editor').boundingBox();assert.ok(bounds.height<=60,JSON.stringify(bounds));
        await page.screenshot({path:path.join(out,'collapsed-tools.png')});
        const compactStart=await pose();await page.keyboard.down('ArrowRight');await page.waitForTimeout(150);await page.keyboard.up('ArrowRight');near(await pose(),compactStart);
        const tourCanvas=await page.locator('.stage-select-diorama-canvas').boundingBox();await page.mouse.click(tourCanvas.x+tourCanvas.width/2,tourCanvas.y+tourCanvas.height/2);
        await page.keyboard.down('ArrowRight');await page.waitForTimeout(150);await page.keyboard.up('ArrowRight');assert.notDeepEqual((await pose()).target,compactStart.target);
        await page.locator('[data-camera="collapse"]').click();assert.equal(await page.locator('textarea').isVisible(),true);
        JSON.parse(await page.locator('textarea').inputValue());
        await page.screenshot({path:path.join(out,'expanded-tools.png')});
        await page.keyboard.press('Escape');assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing),false);
        report.checks.push('arrows move; window blur stops held keys; typing and caret arrows do not move camera; preset area and whole toolbar collapse independently without leaving navigation');

        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        await page.keyboard.down('w');await page.waitForTimeout(80);
        await page.evaluate(()=>{document.querySelector('[data-camera="next-poi"]').click();document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext();});
        await page.waitForFunction(()=>StageSelectDiorama.stats().state==='error');await page.keyboard.up('w');await page.waitForTimeout(450);
        assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing||StageSelectDiorama.stats().moving),false);
        assert.equal(await page.locator('.stage-camera-editor').isVisible(),false);
        await page.locator('.stage-select-diorama-status button').click();await idle();
        await page.getByRole('button',{name:'游览地图',exact:true}).click();await movingMode();
        await page.keyboard.down('ArrowDown');await page.waitForTimeout(60);
        await page.evaluate(()=>{document.querySelector('[data-camera="next-poi"]').click();StageSelectHarnessHost.close();StageSelectHarnessHost.open({mode:'runtime',frameLabel:'基地门口'});});await page.keyboard.up('ArrowDown');await idle();
        await page.waitForTimeout(450);assert.equal(await page.evaluate(()=>StageSelectDiorama.stats().editing||StageSelectDiorama.stats().moving),false);
        assert.equal(await page.locator('.stage-camera-editor').isVisible(),false);
        await page.locator('.stage-select-stage-button[data-stage-id="stage_0_9"] > .stage-select-stage-name').dblclick();await idle();
        await page.getByRole('button',{name:'游览地点',exact:true}).focus();
        await page.evaluate(()=>{window.__focusedTourOpener=document.activeElement;});
        await page.getByRole('button',{name:'游览地点',exact:true}).click();await movingMode();
        assert.equal(await page.locator('.stage-camera-poi').isVisible(),true);
        assert.match(await page.locator('.stage-camera-poi-title').innerText(),/地铁站/);
        assert.equal(await page.locator('[data-camera="next-poi"]').isVisible(),true);
        await page.locator('[data-camera="next-poi"]').click();await idle();
        assert.doesNotMatch(await page.locator('.stage-camera-poi-title').innerText(),/地铁站/);
        await page.locator('[data-camera="prev-poi"]').click();await idle();
        assert.match(await page.locator('.stage-camera-poi-title').innerText(),/地铁站/);
        await page.keyboard.press('Escape');
        assert.equal(await page.locator('.stage-focus-surface').isVisible(),true);
        assert.equal(await page.evaluate(()=>document.activeElement===window.__focusedTourOpener),true);
        assert.equal(await page.evaluate(()=>StageSelectCore.state._selectedStageId),'stage_0_9');
        assert.equal(await page.evaluate(()=>StageSelectCore.state._buttonLayerEl.inert&&StageSelectCore.state._cardLayerEl.inert&&StageSelectCore.state._navLayerEl.inert),true);
        await page.getByRole('button',{name:'返回总览',exact:true}).click();await idle();
        assert.equal(await page.evaluate(()=>StageSelectCore.state._buttonLayerEl.inert||StageSelectCore.state._cardLayerEl.inert||StageSelectCore.state._navLayerEl.inert),false);
        await page.evaluate(()=>StageSelectRenderer.setFrame('地下2层','qa'));
        assert.equal(await page.locator('.stage-camera-toggle:visible').count(),0);
        assert.equal(await page.evaluate(()=>StageSelectHarnessHost.enterMessages.length),0);
        assert.deepEqual(errors,[]);report.checks.push('graphics loss/close during peek retire movement and late callbacks; reopen remains idle; focused tour preserves selection, opener focus and inert detail; 2D hides unsupported tour; all navigation sends no stage-enter intent');report.pass=true;
    }catch(error){report.pass=false;report.error=error.stack;report.pageErrors=errors;process.exitCode=1;await page.screenshot({path:path.join(out,'failure.png')});}
    finally{await browser.close();server.close();fs.writeFileSync(path.join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
