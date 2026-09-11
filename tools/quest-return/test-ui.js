'use strict';
// 使用生产任务面板和已有隔离 Host harness；只模拟返回选择的权威回包。
const fs = require('fs'), path = require('path'), http = require('http'), assert = require('assert/strict');
const root = path.resolve(__dirname, '../..'), web = path.join(root, 'launcher/web');
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));
const output = path.join(root, 'tmp/quest-return-ui');
const mime = {'.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.json':'application/json', '.svg':'image/svg+xml', '.png':'image/png', '.webp':'image/webp'};
const server = http.createServer((req, res) => {
  const target = path.resolve(web, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
  if (path.relative(web, target).startsWith('..')) { res.writeHead(403).end(); return; }
  fs.readFile(target, (error, bytes) => { res.writeHead(error ? 404 : 200, {'Content-Type': (mime[path.extname(target)] || 'application/octet-stream') + '; charset=utf-8'}); res.end(error ? '' : bytes); });
});
async function main() {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'), headless:true});
  try {
    fs.mkdirSync(output, {recursive:true});
    const page = await browser.newPage({viewport:{width:1200,height:750}}), errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto('http://127.0.0.1:' + server.address().port + '/modules/tasks/dev/harness.html?vp=1024x576');
    await page.waitForSelector('.task-icon');
    await page.evaluate(() => {
      TaskHost.close(); window.returnCalls=[];
      window.returnRows = [
        {taskId:'1',title:'较早完成的基地任务',npcName:'Andy Law',npcId:'a',placementId:'pa',locationId:'base',location:'基地1层',enabled:true},
        {taskId:'40002',title:'大学城周边',npcName:'Bat',npcId:'b',placementId:'pb',locationId:'university',location:'地图-联合大学',enabled:true},
        {taskId:'20072',title:'尚未登记地点的任务',npcName:'阿卡',npcId:'',placementId:'',locationId:'',location:'',enabled:false,reason:'交付人物尚未登记到地图'}
      ];
      const old = TaskHost.handle;
      TaskHost.handle = function(m) {
        returnCalls.push(JSON.parse(JSON.stringify(m)));
        if (m.cmd === 'stageReturnSnapshot' || m.cmd === 'stageReturnConfirm') {
          const response={type:'panel_resp',panel:'tasks',cmd:m.cmd,callId:m.callId,success:true,choices:returnRows,closePanel:m.cmd==='stageReturnConfirm'};
          setTimeout(() => chrome.webview.__dispatch(response), 70); return;
        }
        old.call(this,m);
      };
      TaskHost.open({view:'stage-return',token:'fixture-choice',panelInstanceId:'tasks.fixture'});
    });
    await page.waitForSelector('.task-return-choice:not(:disabled)');
    assert.equal(await page.locator('.task-return-choice').count(),3);
    assert.equal(await page.locator('.task-return-choice:disabled').count(),1);
    assert.equal(await page.locator('.task-tab:visible').count(),0);
    assert.equal(await page.locator('.task-return-choice').nth(1).innerText().then(t=>t.includes('Bat')&&t.includes('地图-联合大学')),true);
    assert.equal(await page.evaluate(()=>returnCalls.filter(m=>m.cmd==='stageReturnConfirm').length),0);
    await page.locator('#shell').screenshot({path:path.join(output,'selection-1024.png')});
    await page.locator('.task-return-choice').nth(1).click();
    await page.waitForFunction(()=>returnCalls.some(m=>m.cmd==='close'));
    const calls=await page.evaluate(()=>returnCalls), confirm=calls.filter(m=>m.cmd==='stageReturnConfirm');
    assert.equal(confirm.length,1);
    assert.equal(confirm[0].taskId,'40002'); assert.equal(confirm[0].placementId,'pb');
    assert.equal(confirm[0].locationId,'university'); assert.equal(confirm[0].token,'fixture-choice');
    assert.equal(confirm[0].panelInstanceId,'tasks.fixture');
    assert.equal(calls.filter(m=>['finishTask','deleteTask','navigateFinishNpc','achievementClaim'].includes(m.cmd)).length,0);
    await page.evaluate(()=>{TaskHost.close(); returnCalls=[]; returnRows=returnRows.slice(1,2); TaskHost.open({view:'stage-return',token:'single'});});
    await page.waitForSelector('.task-return-choice:not(:disabled)');
    assert.equal(await page.evaluate(()=>returnCalls.filter(m=>m.cmd==='stageReturnConfirm').length),0);
    await page.locator('.task-return-footer [data-return-action="cancel"]').click();
    assert.equal(await page.evaluate(()=>returnCalls.filter(m=>m.cmd==='stageReturnConfirm').length),0);
    assert.deepEqual(errors,[]);
    console.log(JSON.stringify({success:true,assertions:15,physicalHost:false,screenshot:path.join(output,'selection-1024.png')}));
  } finally {await browser.close();server.close();}
}
main().catch(e=>{console.error(e);server.close();process.exitCode=1;});
