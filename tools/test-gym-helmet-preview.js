'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const root = process.env.CF7_REPO_ROOT || path.resolve(__dirname, '..');
const out = process.env.CF7_UI_REVIEW_OUT || path.join(root, 'tmp/gym-helmet-preview');
const {chromium} = require(path.join(root, 'launcher/perf/node_modules/playwright'));
const {startServer} = require(path.join(root, 'tools/lib/stage-select-dev-server'));
async function main() {
    fs.mkdirSync(out, {recursive:true});
    const {server, origin} = await startServer(path.join(root, 'launcher/web'));
    let browser;
    const report = {scope:'Real production motion and dressup assets in Edge; no Host, training writes or player save.', checks:[]};
    try {
        browser = await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'), headless:true});
        const page = await browser.newPage({viewport:{width:1024,height:700}});
        const errors=[];page.on('pageerror',error=>errors.push(error.message));
        await page.addInitScript(()=>Object.defineProperty(Document.prototype,'hasFocus',{configurable:true,value:()=>false}));
        await page.route('https://cfn-fonts.local/**',route=>route.fulfill({status:204,body:''}));
        if (process.env.CF7_UI_BASELINE_ROOT) await page.route('**/modules/gym/gym-motion-renderer.js',route=>route.fulfill({path:path.join(process.env.CF7_UI_BASELINE_ROOT,'launcher/web/modules/gym/gym-motion-renderer.js')}));
        await page.goto(origin+'/modules/gym/dev/motion-review.html');
        await page.waitForFunction(()=>window.__gymMotionReviewResult, null, {timeout:60000});
        for (const helmet of ['钢铁小熊头', '黑色摩托头盔', '警用防爆服头盔']) {
            const results=await page.evaluate(async helmet=>{
                const api=GymMotionRenderer, data=await api.ready();
                let gallery=document.getElementById('helmet-matrix');if(gallery)gallery.remove();
                gallery=document.createElement('div');gallery.id='helmet-matrix';
                gallery.style.cssText='position:fixed;inset:0;z-index:1000;background:#10151a;color:#eee;display:grid;grid-template-columns:repeat(3,1fr);grid-template-rows:repeat(2,1fr);padding:12px;gap:12px;';
                document.body.appendChild(gallery);
                const handles=[], results=[];
                try {
                    for (const gender of ['male','female']) for (const stationId of ['dummy','dumbbell','squat']) {
                        const hairs=Object.keys(data.dressup.skinKeys).filter(key=>key.startsWith(gender==='male'?'发型-男式-':'发型-女式-'));
                        const portrait={gender,face:gender==='male'?'男变装-基本脸型':'女变装-基本脸型',hair:hairs[0],equipment:{'头部装备':helmet}};
                        if(helmet==='钢铁小熊头')Object.assign(portrait.equipment,{'上装装备':'钢铁小熊上装','下装装备':'钢铁小熊下装','脚部装备':'钢铁小熊鞋','手部装备':'钢铁小熊手套'});
                        const original=JSON.stringify(portrait);
                        if(!await api.preparePortrait(portrait,stationId))throw new Error('helmet prepare failed: '+gender+'/'+helmet+'/'+stationId);
                        const cell=document.createElement('section'), title=document.createElement('div'), stage=document.createElement('div');
                        title.textContent=(gender==='male'?'男':'女')+' · '+helmet+' · '+stationId;
                        stage.style.cssText='width:300px;height:280px';cell.append(title,stage);gallery.appendChild(cell);
                        const handle=api.create(stage,{portrait,stationId});handles.push(handle);
                        const canvas=stage.querySelector('canvas'), pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
                        let visible=0;for(let i=3;i<pixels.length;i+=4)if(pixels[i])visible++;
                        const picture=canvas.toDataURL();
                        const other=JSON.parse(original);other.hair=hairs[1];
                        if(!await api.preparePortrait(other,stationId))throw new Error('second hairstyle failed');
                        const probe=document.createElement('div');probe.style.cssText='width:300px;height:280px;position:absolute;left:-10000px';gallery.appendChild(probe);
                        const alternate=api.create(probe,{portrait:other,stationId});
                        const same=picture===probe.querySelector('canvas').toDataURL();alternate.destroy();probe.remove();
                        results.push({gender,helmet,stationId,visible,hiddenHairStable:same,portraitUnchanged:JSON.stringify(portrait)===original,failed:handle.debugState().failed});
                    }
                } catch(error) {handles.forEach(handle=>handle.destroy());throw error;}
                window.__helmetHandles=handles;return results;
            },helmet);
            for(const result of results){assert.ok(result.visible>1000,JSON.stringify(result));assert.ok(result.hiddenHairStable,JSON.stringify(result));assert.ok(result.portraitUnchanged);assert.equal(result.failed,false);}
            await page.screenshot({path:path.join(out,helmet==='钢铁小熊头'?'gym-steel-bear.png':helmet==='黑色摩托头盔'?'gym-motorcycle.png':'gym-riot-helmet.png')});
            await page.evaluate(()=>{window.__helmetHandles.forEach(handle=>handle.destroy());document.getElementById('helmet-matrix').remove();});
            report.checks.push(...results);
        }
        const negatives=await page.evaluate(async()=>{
            const data=await GymMotionRenderer.ready();
            const portrait={gender:'male',face:'男变装-基本脸型',hair:'missing-skin',equipment:{}};
            const noHair=await GymMotionRenderer.preparePortrait(portrait,'dummy');
            portrait.equipment['头部装备']='钢铁小熊头';portrait.face='missing-face';
            const noFace=await GymMotionRenderer.preparePortrait(portrait,'dummy');
            return {noHair,noFace,stats:GymMotionRenderer.getDebugStats()};
        });
        assert.equal(negatives.noHair,false);assert.equal(negatives.noFace,false);assert.deepEqual(errors,[]);
        // motion-review owns two pre-existing samples; our matrix must release all its instances.
        assert.equal(negatives.stats.activeInstances,2);
        report.negativeCases=negatives;report.pass=true;
    } catch(error) {report.pass=false;report.error=error.stack;process.exitCode=1;}
    finally {if(browser)await browser.close();server.close();fs.writeFileSync(path.join(out,'gym-helmet-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
