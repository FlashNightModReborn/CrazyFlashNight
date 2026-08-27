#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');

const root = path.resolve(__dirname, '..');
const playwrightPath = path.join(root, 'launcher', 'perf', 'node_modules', 'playwright');

function edgeExecutable() {
  const candidates = [
    path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
    process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
  ].filter(Boolean);
  return candidates.find(candidate => fs.existsSync(candidate));
}

function contentType(file) {
  const ext = path.extname(file).toLowerCase();
  return ({'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8',
    '.css':'text/css; charset=utf-8','.md':'text/markdown; charset=utf-8',
    '.json':'application/json; charset=utf-8','.png':'image/png','.jpg':'image/jpeg',
    '.jpeg':'image/jpeg','.webp':'image/webp','.svg':'image/svg+xml','.woff2':'font/woff2'})[ext]
    || 'application/octet-stream';
}

function startServer() {
  return new Promise((resolve, reject) => {
    const server = http.createServer((request, response) => {
      const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname)
        .replace(/^\/+/, '');
      const file = path.resolve(root, pathname);
      const relative = path.relative(root, file);
      if (!relative || relative.startsWith('..') || path.isAbsolute(relative)) {
        response.writeHead(403); response.end(); return;
      }
      fs.readFile(file, (error, data) => {
        if (error) { response.writeHead(404); response.end(); return; }
        response.writeHead(200, {'Content-Type':contentType(file),'Cache-Control':'no-store'});
        response.end(data);
      });
    });
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

function near(actual, expected, label, tolerance) {
  tolerance = tolerance == null ? 1 : tolerance;
  assert(Math.abs(actual - expected) <= tolerance,
    label + ': expected ' + expected + ', got ' + actual);
}

async function runViewport(browser, baseUrl, viewport, screenshotDir) {
  const page = await browser.newPage({viewport});
  const pageErrors = [];
  const failedRequests = [];
  page.on('pageerror', error => pageErrors.push(error.message || String(error)));
  page.on('requestfailed', request => failedRequests.push(request.url()));
  await page.route('https://cfn-fonts.local/**', route => route.fulfill({status:204, body:''}));
  await page.goto(baseUrl, {waitUntil:'load'});
  await page.waitForSelector('.settings-panel .settings-rescue-strip');
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));

  const layout = await page.evaluate(() => {
    function rect(selector) {
      const value = document.querySelector(selector).getBoundingClientRect();
      return {x:value.x,y:value.y,width:value.width,height:value.height,bottom:value.bottom};
    }
    return {
      content:rect('#panel-content'),
      header:rect('.settings-terminal-header'),
      tabs:rect('.settings-tabs'),
      main:rect('.settings-content'),
      panel:rect('.settings-panel'),
      common:rect('.settings-game-common'),
      rescue:rect('.settings-rescue-strip'),
      homeCheat:rect('.settings-home-cheat'),
      cameraEntry:rect('.settings-camera-entry'),
      footer:rect('.settings-footer'),
      terminal:document.querySelector('.settings-panel').classList.contains('settings-terminal-shell'),
      workbench:document.querySelector('.settings-panel').classList.contains('workbench-shell'),
      brand:document.querySelector('.settings-brand-seal').textContent.trim(),
      tabLabels:Array.from(document.querySelectorAll('.settings-tab')).map(tab => tab.textContent.trim()),
      scrollTop:document.querySelector('.settings-content').scrollTop
    };
  });
  near(layout.content.x, 0, 'panel-content x');
  near(layout.content.y, 0, 'panel-content y');
  near(layout.content.width, viewport.width, 'panel-content width');
  near(layout.content.height, viewport.height, 'panel-content height');
  // PanelScale preserves 16:9 against the measured anchor. Fractional Windows DPI can
  // make Edge expose a parent rect just under the requested viewport and leave <2 CSS px
  // letterbox after the four-decimal scale write; compare to that real anchor.
  near(layout.panel.width, layout.content.width, 'settings panel width', 2);
  near(layout.panel.height, layout.content.height, 'settings panel height', 2);
  assert(layout.terminal, 'settings must use the launcher terminal shell');
  assert(!layout.workbench, 'settings must not inherit the workbench shell');
  assert.strictEqual(layout.brand, 'CF7:ME');
  assert.deepStrictEqual(layout.tabLabels, ['游戏','键位','本机与 Web']);
  assert(layout.tabs.y >= layout.header.y && layout.tabs.bottom <= layout.header.bottom + 1,
    'the three page switches must share the launcher header row');
  near(layout.main.y, layout.header.bottom, 'content begins directly below the launcher header');
  assert.strictEqual(await page.locator('.settings-tab[data-tab="tools"]').count(), 0);
  assert.strictEqual(layout.scrollTop, 0);
  assert(layout.common.bottom <= layout.main.bottom + 1,
    'all common game controls must fit in the first viewport: commonBottom=' + layout.common.bottom
      + ' mainBottom=' + layout.main.bottom);
  assert(layout.rescue.bottom <= layout.main.bottom && layout.rescue.y >= layout.main.y,
    'rescue strip must be immediately reachable in the default viewport');
  assert(layout.homeCheat.bottom <= layout.main.bottom && layout.homeCheat.y >= layout.main.y,
    'frequent cheat entry must be immediately reachable in the default viewport');
  assert(layout.cameraEntry.y >= layout.common.bottom,
    'camera simulator entry must follow the common-control surface');
  // 打击数字已经迁为 Launcher 本机偏好，不再占用 AS2 游戏常用设置行：
  // 2 个音量字段 + 7 个画面字段 = 9。
  assert.strictEqual(await page.locator('.settings-game-common .settings-field').count(), 9);
  assert.strictEqual(await page.getByRole('button', {name:'试听界面音效'}).count(), 1);
  assert.strictEqual(await page.locator('#settings-home-cheat-input').count(), 1);
  assert.strictEqual(await page.locator('.settings-home-cheat .settings-cheat-help-open').count(), 1);
  assert.strictEqual(await page.locator('.settings-panel [title]').count(), 0);

  const rescueButton = page.getByRole('button', {name:'立即返回基地'});
  await rescueButton.hover();
  await page.waitForFunction(() => window.PanelTooltip && PanelTooltip.isVisible());
  assert((await page.locator('#panel-tooltip').textContent()).includes('立即跳过当前流程并返回基地'));
  await page.mouse.move(0, 0);

  if (screenshotDir) {
    fs.mkdirSync(screenshotDir, {recursive:true});
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-game.png')});
  }

  await page.click('.settings-tab[data-tab="keys"]');
  const keyState = await page.evaluate(() => {
    const rows = Array.from(document.querySelectorAll('.settings-key-row'));
    const gaps = rows.map(row => {
      const label = row.querySelector('.settings-key-label');
      const button = row.querySelector('.settings-key-button');
      const range = document.createRange();
      range.selectNodeContents(label);
      return button.getBoundingClientRect().left - range.getBoundingClientRect().right;
    });
    return {
      count:rows.length,
      labels:rows.map(row => row.querySelector('.settings-key-label').textContent.trim()),
      boardBottom:document.querySelector('.settings-key-board').getBoundingClientRect().bottom,
      mainBottom:document.querySelector('.settings-content').getBoundingClientRect().bottom,
      scrollHeight:document.querySelector('.settings-content').scrollHeight,
      clientHeight:document.querySelector('.settings-content').clientHeight,
      labelFont:parseFloat(getComputedStyle(rows[0].querySelector('.settings-key-label')).fontSize),
      buttonFont:parseFloat(getComputedStyle(rows[0].querySelector('.settings-key-button')).fontSize),
      maximumTextControlGap:Math.max.apply(Math, gaps)
    };
  });
  assert.strictEqual(keyState.count, 35);
  assert(!keyState.labels.some(label => !label || /^(undefined|null)$/i.test(label)));
  assert(keyState.labels.includes('奔跑键') && keyState.labels.includes('组合键'));
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-keys.png')});
  }
  assert(keyState.boardBottom <= keyState.mainBottom + 1,
    'all grouped key bindings must fit inside the default viewport: boardBottom=' + keyState.boardBottom
      + ' mainBottom=' + keyState.mainBottom);
  assert(keyState.scrollHeight <= keyState.clientHeight + 1,
    'the dense key layout must not require page scrolling: scrollHeight=' + keyState.scrollHeight
      + ' clientHeight=' + keyState.clientHeight);
  assert(keyState.labelFont >= 12 && keyState.buttonFont >= 12,
    'key labels and controls must remain readable at the 1024 design scale');
  assert(keyState.maximumTextControlGap <= 9,
    'key density must come from removing label/control whitespace, not shrinking text: maxGap='
      + keyState.maximumTextControlGap);

  await page.click('.settings-tab[data-tab="local"]');
  assert.strictEqual(await page.locator('.settings-section', {hasText:'点歌器运行规则'}).count(), 1);

  await page.click('.settings-tab[data-tab="game"]');
  assert.strictEqual(await page.locator('.settings-section', {hasText:'点歌器运行规则'}).count(), 0);
  await page.getByRole('button', {name:'打开镜头预览'}).click();
  await page.waitForSelector('.settings-camera-modal');
  await page.waitForFunction(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    return image && image.complete && image.naturalWidth > 0;
  });
  const modalGeometry = await page.evaluate(() => {
    const modal = document.querySelector('.settings-camera-modal').getBoundingClientRect();
    const panel = document.querySelector('.settings-panel').getBoundingClientRect();
    const imageNode = document.querySelector('.settings-camera-simulator-viewport img');
    const image = imageNode.getBoundingClientRect();
    const preview = document.querySelector('.settings-camera-simulator-viewport').getBoundingClientRect();
    const stageNode = document.querySelector('.settings-camera-simulator-stage');
    const stage = stageNode.getBoundingClientRect();
    const stageStyle = getComputedStyle(stageNode);
    const stageContentWidth = stage.width - parseFloat(stageStyle.paddingLeft) - parseFloat(stageStyle.paddingRight);
    const transform = new DOMMatrix(getComputedStyle(imageNode).transform);
    return {modalWidth:modal.width,modalHeight:modal.height,panelWidth:panel.width,panelHeight:panel.height,
      imageWidth:image.width,imageHeight:image.height,previewWidth:preview.width,previewHeight:preview.height,
      stageContentWidth:stageContentWidth,
      naturalWidth:imageNode.naturalWidth,naturalHeight:imageNode.naturalHeight,
      objectFit:getComputedStyle(imageNode).objectFit,scale:transform.a};
  });
  assert(modalGeometry.modalWidth >= modalGeometry.panelWidth * 0.96
    && modalGeometry.modalHeight >= modalGeometry.panelHeight * 0.96,
  'camera simulator must use the full panel surface: ' + JSON.stringify(modalGeometry));
  near(modalGeometry.imageWidth, modalGeometry.previewWidth, 'entry frame fills preview width at 1.0x');
  near(modalGeometry.imageHeight, modalGeometry.previewHeight, 'entry frame fills preview height at 1.0x');
  assert(modalGeometry.previewWidth >= modalGeometry.stageContentWidth * 0.95,
    'camera viewport must use the available simulator width instead of a fixed-size cap: '
      + JSON.stringify(modalGeometry));
  near(modalGeometry.scale, 1, 'entry frame begins at the captured baseline');
  assert.strictEqual(modalGeometry.objectFit, 'cover');
  assert.deepStrictEqual([modalGeometry.naturalWidth, modalGeometry.naturalHeight], [1024, 576],
    'the preview must retain the original fixture resolution instead of a 512x288 proxy');
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-camera-baseline.png')});
  }
  assert.strictEqual(await page.locator('.settings-camera-control-field input[type="checkbox"]').isChecked(), false);
  const zoom = page.locator('.settings-camera-control-field input[type="range"]');
  await zoom.evaluate(input => {
    input.value = '0.6';
    input.dispatchEvent(new Event('input', {bubbles:true}));
  });
  await page.waitForFunction(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    const viewport = document.querySelector('.settings-camera-simulator-viewport');
    if (!image || !viewport) return false;
    const matrix = new DOMMatrix(getComputedStyle(image).transform);
    return Math.abs(matrix.a - 0.6) < 0.01
      && image.getBoundingClientRect().width < viewport.getBoundingClientRect().width * 0.7;
  });
  const wideGeometry = await page.evaluate(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img').getBoundingClientRect();
    const viewport = document.querySelector('.settings-camera-simulator-viewport').getBoundingClientRect();
    return {imageWidth:image.width,viewportWidth:viewport.width};
  });
  assert(wideGeometry.imageWidth < wideGeometry.viewportWidth,
    'a scale below the entry baseline must visibly shrink the captured frame');
  await zoom.evaluate(input => {
    input.value = '2.2';
    input.dispatchEvent(new Event('input', {bubbles:true}));
  });
  await page.waitForFunction(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    const viewport = document.querySelector('.settings-camera-simulator-viewport');
    if (!image || !viewport) return false;
    const matrix = new DOMMatrix(getComputedStyle(image).transform);
    return Math.abs(matrix.a - 2.2) < 0.01
      && image.getBoundingClientRect().width > viewport.getBoundingClientRect().width * 2;
  });
  const closeGeometry = await page.evaluate(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    const viewport = document.querySelector('.settings-camera-simulator-viewport');
    return {
      imageWidth:image.getBoundingClientRect().width,
      viewportWidth:viewport.getBoundingClientRect().width,
      target:image.getAttribute('data-preview-scale'),
      relative:image.getAttribute('data-preview-relative-scale'),
      mode:document.querySelector('.settings-camera-mode-hud').textContent
    };
  });
  assert.strictEqual(closeGeometry.target, '2.2');
  assert.strictEqual(closeGeometry.relative, '2.200');
  assert(closeGeometry.imageWidth > closeGeometry.viewportWidth * 2,
    'a scale above the entry baseline must visibly enlarge and crop the frame');
  assert.strictEqual(closeGeometry.mode.trim(), '固定基础倍率');
  assert((await page.locator('.settings-camera-preview figcaption').textContent()).includes('入口静态帧'));
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-camera-lab.png')});
  }
  await page.locator('.settings-camera-control-field input[type="checkbox"]').click();
  const dynamicGeometry = await page.evaluate(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    return {width:image.getBoundingClientRect().width,
      mode:document.querySelector('.settings-camera-mode-hud').textContent};
  });
  near(dynamicGeometry.width, closeGeometry.imageWidth, 'dynamic toggle preserves the selected basic scale');
  assert.strictEqual(dynamicGeometry.mode.trim(), '动态镜头：开启');
  await page.keyboard.press('Escape');
  assert.strictEqual(await page.locator('.settings-camera-modal').count(), 0);
  assert.strictEqual(await page.evaluate(() => document.activeElement.classList.contains('settings-camera-open')), true);

  await page.click('.settings-tab[data-tab="game"]');
  await page.getByRole('button', {name:'作弊码帮助'}).click();
  await page.waitForSelector('.settings-cheat-doc code');
  const normalHelp = await page.locator('.settings-cheat-doc').textContent();
  assert(normalHelp.includes('#level:15'));
  assert((await page.locator('.settings-copy-command').count()) >= 30);
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-cheat-help.png')});
  }
  await page.locator('.settings-cheat-modal-close').click();

  await page.locator('#toggle-mode').click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.click('.settings-tab[data-tab="game"]');
  await page.getByRole('button', {name:'作弊码帮助'}).click();
  await page.waitForSelector('.settings-cheat-doc code');
  const challengeHelp = await page.locator('.settings-cheat-doc').textContent();
  assert(challengeHelp.includes('hardmode') && challengeHelp.includes('easymode')
    && challengeHelp.includes('challengemode'));
  assert(!challengeHelp.includes('#level:15') && !challengeHelp.includes('status'));
  await page.locator('.settings-cheat-modal-close').click();

  await page.locator('#toggle-mode').click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  const before = await page.evaluate(() => window.__settingsHarness.sent.length);
  await page.getByRole('button', {name:'立即返回基地'}).click();
  await page.waitForFunction(count => window.__settingsHarness.sent.length > count, before);
  const rescuePayload = await page.evaluate(() => {
    const messages = window.__settingsHarness.sent.filter(message => message.cmd === 'return_base');
    return messages[messages.length - 1].payload;
  });
  assert.deepStrictEqual(rescuePayload, {v:1});

  await page.click('.settings-tab[data-tab="local"]');
  await page.evaluate(() => {
    window.__settingsHarness.dropNextResponse('host_set');
    window.__settingsHarness.failNextSnapshot();
  });
  await page.locator('[data-host-key="introEnabled"]').click();
  await page.waitForFunction(() => {
    const status = document.querySelector('.settings-status');
    return status && status.textContent.includes('写入仍保持锁定');
  }, {timeout:4000});
  assert((await page.locator('.settings-status').textContent()).includes('权威状态读取失败'));
  assert.strictEqual(await page.locator('.settings-empty h2').textContent(), '写入状态等待权威核对');
  assert.strictEqual(await page.locator('.settings-empty button').isEnabled(), true);
  await page.locator('.settings-empty button').click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  assert.strictEqual(await page.locator('.settings-empty').count(), 0);

  await page.click('.settings-tab[data-tab="local"]');
  await page.evaluate(() => {
    window.__settingsHarness.dropNextResponse('host_set');
    window.__settingsHarness.holdNextSnapshotForReconcile();
  });
  await page.locator('[data-host-key="introEnabled"]').click();
  await page.waitForFunction(() => {
    const status = document.querySelector('.settings-status');
    return status && status.textContent.includes('该权威快照早于未决写入终态');
  }, {timeout:4000});
  assert.strictEqual(await page.locator('.settings-empty h2').textContent(), '写入状态等待权威核对');
  assert.strictEqual(await page.locator('.settings-empty button').isEnabled(), true);
  await page.locator('.settings-empty button').click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  assert.strictEqual(await page.locator('.settings-empty').count(), 0);

  assert.deepStrictEqual(pageErrors, []);
  assert.deepStrictEqual(failedRequests, []);
  await page.close();
  return 58;
}

async function main() {
  if (!fs.existsSync(playwrightPath)) throw new Error('Missing launcher/perf Playwright dependency');
  const executablePath = edgeExecutable();
  if (!executablePath) throw new Error('Microsoft Edge not found');
  const screenshotArg = process.argv.indexOf('--screenshot-dir');
  const screenshotDir = screenshotArg >= 0
    ? path.resolve(root, process.argv[screenshotArg + 1] || 'tmp/settings-panel-review') : null;
  const {chromium} = require(playwrightPath);
  const server = await startServer();
  const address = server.address();
  const url = 'http://127.0.0.1:' + address.port + '/launcher/web/modules/settings/dev/harness.html';
  const browser = await chromium.launch({executablePath, headless:true});
  let passed = 0;
  try {
    for (const viewport of [{width:1024,height:576},{width:1600,height:900}]) {
      passed += await runViewport(browser, url, viewport, screenshotDir);
      process.stdout.write('[PASS] settings Edge ' + viewport.width + 'x' + viewport.height + ' (58/58)\n');
    }
  } finally {
    await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
  process.stdout.write('Settings visual harness: ' + passed + '/' + passed + ' passed\n');
}

main().catch(error => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
