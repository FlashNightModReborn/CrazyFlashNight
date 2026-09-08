#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const assert = require('assert');
const ROOT = path.resolve(__dirname, '..');
const Controls = require('../launcher/web/modules/character-identity-controls.js');
const Runtime = require('../launcher/web/modules/plastic-surgery-runtime.js');
const out = path.join(ROOT, 'tmp', 'surgery-web');
fs.mkdirSync(out, {recursive:true});
let passed = 0;
function check(value, message) { assert(value, message); passed++; }
function staticChecks() {
    check(Controls.characterNameError('正常姓名') === '', 'Chinese name accepted');
    check(Controls.characterNameError(' '.repeat(4)) !== '', 'blank name rejected');
    check(Controls.characterNameError('a'.repeat(16)) !== '', 'long name rejected');
    check(Controls.characterNameError('a' + String.fromCharCode(133)) !== '', 'control character rejected');
    [149, 201, 175.5, '175', NaN].forEach(height => check(Controls.validateProfile({characterName:'甲',gender:'male',height}).height, 'invalid height rejected'));
    check(Runtime.normalizeState({success:true,phase:'applied'}) === null, 'incomplete success rejected');
    const creation = fs.readFileSync(path.join(ROOT,'launcher/web/modules/bootstrap-character-create.js'),'utf8');
    check(creation.includes("Controls.nameMarkup('cc'") && creation.includes('Controls.bindGender') && creation.includes('Controls.bindHeight'), 'creation consumes shared controls');
    check(creation.includes('CharacterAppearancePreview.create') && creation.includes('renderer.renderProfile'), 'creation consumes shared preview adapter');
    const manifest = JSON.parse(fs.readFileSync(path.join(ROOT,'launcher/web/assets/dressup/manifest.json'),'utf8'));
    ['黑色功夫装','咖啡色多包裤','棕色皮鞋'].forEach(name => check(manifest.items[name], 'preview fixture uses real equipment: '+name));
    const uiRoot = path.join(ROOT, 'flashswf/UI/基地特殊UI合集');
    const read = name => fs.readFileSync(path.join(ROOT, name), 'utf8');
    check(!fs.existsSync(path.join(uiRoot, 'LIBRARY/整容整形界面.xml')), 'retired Flash surgery symbol is deleted');
    const medical = read('flashswf/levels/基地场景合集/LIBRARY/地图/医务室.xml');
    const uiManager = read('scripts/展现/UI交互/UI交互_lsy_UI管理.as');
    const service = read('scripts/类定义/org/flashNight/arki/ui/PlasticSurgeryPanelService.as');
    check(medical.includes('_root.打开整形手术();') && uiManager.includes('_root.打开整形手术 = function()'),
        'medical room calls the production surgery opener directly');
    check([medical, uiManager, service, read('flashswf/UI/基地特殊UI合集/DOMDocument.xml'),
        read('flashswf/UI/基地特殊UI合集/LIBRARY/素材库-基地特殊UI.xml')]
        .every(source => !source.includes('整容整形界面') && !source.includes('openPlasticSurgery')),
        'no old linkage, generic-loader special case, or compatibility command remains in production sources');
}
function serve(req, res) {
    let pathname;
    try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); } catch (_) { res.writeHead(400); res.end(); return; }
    const target = path.resolve(ROOT, '.' + pathname);
    if (!target.startsWith(ROOT + path.sep)) { res.writeHead(403); res.end(); return; }
    fs.readFile(target, (error, bytes) => {
        if (error) { res.writeHead(404); res.end(); return; }
        const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.woff2':'font/woff2'};
        res.setHeader('Content-Type', types[path.extname(target)] || 'application/octet-stream'); res.end(bytes);
    });
}
async function runViewport(browser, address, viewport) {
    const page = await browser.newPage({viewport});
    const faults = [];
    page.on('pageerror', error => faults.push(String(error)));
    await page.goto(address + '/launcher/web/modules/plastic-surgery/dev/harness.html');
    const state = () => page.evaluate(() => PlasticSurgeryPanel.debugState());
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'editing', null, {timeout:10000}).catch(async error => {
        console.error(JSON.stringify({faults, state:await state(), text:await page.locator('body').innerText(), sent:await page.evaluate(() => __sent)}));
        await page.screenshot({path:path.join(out,'failure.png')});
        throw error;
    });
    await page.waitForFunction(() => {
        const canvas=document.getElementById('surgery-canvas');
        if(!canvas||!canvas.width||!canvas.height)return false;
        const bytes=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
        let n=0;for(let i=3;i<bytes.length;i+=4)if(bytes[i]>0&&++n>500)return true;return false;
    });
    check(await page.locator('#surgery-confirm').isDisabled(), 'unchanged draft cannot charge');
    check(await page.evaluate(() => __charges === 0), 'opening has no charge');
    const geometry = await page.evaluate(() => {
        const root=document.querySelector('.surgery-panel').getBoundingClientRect();
        const button=document.getElementById('surgery-confirm').getBoundingClientRect();
        const hit=document.elementFromPoint(button.x+button.width/2,button.y+button.height/2);
        return {fits:root.left>=-1&&root.top>=-1&&root.right<=innerWidth+1&&root.bottom<=innerHeight+1,
            hit:hit===document.getElementById('surgery-confirm'), noScroll:document.documentElement.scrollWidth<=innerWidth};
    });
    check(geometry.fits && geometry.hit && geometry.noScroll, 'scaled layout and footer remain reachable');
    await page.locator('#surgery-character-name').fill('整形验收');
    await page.locator('input[name="surgery-gender"][value="female"]').check();
    await page.locator('#surgery-height').fill('180');
    check((await state()).draft.height === 180 && (await state()).draft.gender === 'female', 'local gender and height draft');
    check(await page.evaluate(() => __profile.characterName === '远行者' && __balance === 20 && __charges === 0), 'draft does not mutate authority');
    await page.screenshot({path:path.join(out, viewport.width + 'x' + viewport.height + '.png')});
    await page.locator('#surgery-cancel').click();
    check(await page.evaluate(() => __charges === 0 && PlasticSurgeryPanel.debugState().phase === 'closed'), 'cancel discards without charge');
    await page.evaluate(() => __open());
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'editing');
    check((await state()).draft.characterName === '远行者', 'reopen receives authoritative profile');
    await page.locator('#surgery-character-name').fill('输入中');
    await page.evaluate(() => {
        const input=document.getElementById('surgery-character-name');
        input.dispatchEvent(new CompositionEvent('compositionstart',{bubbles:true,data:'中'}));
        input.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,cancelable:true,key:'Enter',isComposing:true,keyCode:229}));
    });
    check(await page.evaluate(() => __charges === 0), 'IME confirmation is not payment confirmation');
    await page.evaluate(() => document.getElementById('surgery-character-name').dispatchEvent(new CompositionEvent('compositionend',{bubbles:true})));
    await page.evaluate(() => {__fault='save_failure'});
    await page.locator('#surgery-confirm').click();
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'save_pending');
    check(await page.locator('#surgery-character-name').isDisabled(), 'accepted draft stays frozen while save pending');
    check(await page.evaluate(() => __charges === 1 && __balance === 15), 'failed save has one economic mutation');
    await page.locator('#surgery-confirm').click();
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'closed');
    check(await page.evaluate(() => __charges === 1 && __balance === 15), 'save retry does not charge twice');

    await page.evaluate(() => {__reset();__open()});
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'editing');
    await page.locator('#surgery-character-name').fill('回包丢失');
    await page.evaluate(() => {__fault='unknown_applied'});
    await page.locator('#surgery-confirm').click();
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'unknown');
    check(await page.locator('#surgery-confirm').textContent() === '核对上次结果', 'unknown write offers exact query');
    await page.locator('#surgery-confirm').click();
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'closed');
    check(await page.evaluate(() => __queries === 1 && __charges === 1), 'reconciliation does not resubmit');

    await page.evaluate(() => {__reset();__open()});
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'editing');
    await page.evaluate(() => {__closeFails=true});
    await page.locator('#surgery-close').click();
    check((await state()).phase === 'editing' && await page.locator('.surgery-panel').isVisible(), 'failed close preserves usable panel');
    await page.evaluate(() => {__closeFails=false});
    await page.locator('#surgery-close').click();
    check(await page.evaluate(() => PanelRuntime.sharedResponseRouter.debugState().handlerCount === 0), 'close releases response subscription');
    await page.evaluate(() => {__reset();__open()});
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'editing');
    await page.locator('#surgery-character-name').fill('关闭重试');
    await page.evaluate(() => {__closeFails=true});
    await page.locator('#surgery-confirm').click();
    await page.waitForFunction(() => PlasticSurgeryPanel.debugState().phase === 'applied');
    check(await page.locator('#surgery-confirm').textContent() === '关闭', 'saved result offers close rather than another payment');
    const commits = await page.evaluate(() => __sent.filter(x => x.domain==='surgery'&&x.cmd==='commit').length);
    await page.evaluate(() => {__closeFails=false});
    await page.locator('#surgery-confirm').click();
    check(await page.evaluate(() => __sent.filter(x => x.domain==='surgery'&&x.cmd==='commit').length) === commits, 'retrying close never resubmits');
    check(faults.length === 0, 'no browser exceptions: ' + faults.join(';'));
    await page.close();
}
async function main() {
    staticChecks();
    if (process.argv.includes('--static-only')) {
        console.log(JSON.stringify({ok:true, passed, browser:false}));
        return;
    }
    const { chromium } = require('../launcher/perf/node_modules/playwright');
    const server = http.createServer(serve);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const candidates = [process.env.CF7_BROWSER_EXE,'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe','C:/Program Files/Microsoft/Edge/Application/msedge.exe'];
    const executablePath = candidates.find(value => value && fs.existsSync(value));
    const browser = await chromium.launch({executablePath,headless:true});
    try {
        for (const viewport of [{width:1024,height:576},{width:1366,height:768},{width:1920,height:1080}])
            await runViewport(browser, 'http://127.0.0.1:' + server.address().port, viewport);
        const result={ok:true,passed,viewports:3};
        fs.writeFileSync(path.join(out,'result.json'),JSON.stringify(result,null,2)); console.log(JSON.stringify(result));
    } finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
}
main().catch(error => { console.error(error.stack); process.exitCode=1; });
