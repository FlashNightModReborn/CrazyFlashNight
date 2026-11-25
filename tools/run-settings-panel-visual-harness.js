#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');

const root = path.resolve(__dirname, '..');
const playwrightPath = process.env.CF7_PLAYWRIGHT_PATH
  || path.join(root, 'launcher', 'perf', 'node_modules', 'playwright');

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

async function runPerformanceControls(page, viewport, screenshotDir) {
  let checked = 0;
  const selector = key => '[data-performance-key="' + key + '"]';
  const performanceWrites = () => page.evaluate(() => window.__settingsHarness.sent.filter(message =>
    message.cmd === 'host_set' && /^performance/.test(message.payload.key)));
  const savedState = () => page.evaluate(() => window.__settingsHarness.model.hostPrefs.performance);
  const waitSaved = () => page.waitForFunction(() => {
    const message = document.querySelector('.settings-performance-message');
    return message && message.textContent.includes('关闭设置后按方案运行');
  });

  await page.click('.settings-tab[data-tab="visual"]');
  await page.locator('.settings-performance').scrollIntoViewIfNeeded();
  const layout = await page.evaluate(() => {
    const group = document.querySelector('.settings-performance');
    const content = document.querySelector('.settings-content');
    const box = group.getBoundingClientRect();
    return {
      clientWidth:content.clientWidth, scrollWidth:content.scrollWidth,
      controls:Array.from(group.querySelectorAll('select,button')).map(node => {
        const rect = node.getBoundingClientRect();
        return {left:rect.left,right:rect.right,width:rect.width,height:rect.height};
      }),
      left:box.left, right:box.right
    };
  });
  assert(layout.scrollWidth <= layout.clientWidth + 1, 'performance fields must not add horizontal overflow');
  assert(layout.controls.every(control => control.left >= layout.left - 1 && control.right <= layout.right + 1
    && control.height >= 20 && control.width >= 20));
  assert.strictEqual(await page.locator('.settings-performance-undo').isDisabled(), true);
  assert.strictEqual(await page.locator('.settings-performance-apply').isDisabled(), true);
  checked++;

  const beforeDraft = await page.evaluate(() => window.__settingsHarness.sent.length);
  await page.selectOption(selector('preset'), 'performance');
  await page.selectOption(selector('maxRenderHeight'), '540');
  await page.selectOption(selector('mode'), 'fixed');
  await page.locator('.settings-performance-reset').click();
  assert.strictEqual(await page.inputValue(selector('preset')), 'performance');
  assert.strictEqual(await page.inputValue(selector('maxRenderHeight')), '540');
  assert.strictEqual(await page.inputValue(selector('mode')), 'auto');
  assert.strictEqual(await page.evaluate(() => window.__settingsHarness.sent.length), beforeDraft,
    'editing and restoring performance recommendations must remain a local draft');
  assert.strictEqual(await page.locator('.settings-footer .primary').isDisabled(), true,
    'performance drafts must not make the AS2 save action dirty');
  checked++;

  await page.locator(selector('preset')).focus();
  await page.keyboard.press('Tab');
  assert.strictEqual(await page.evaluate(() => document.activeElement.getAttribute('data-performance-key')), 'mode');
  await page.keyboard.press('Tab');
  assert.strictEqual(await page.evaluate(() => document.activeElement.getAttribute('data-performance-key')), 'maxRenderHeight');
  checked++;

  await page.selectOption(selector('preset'), 'quality');
  await page.selectOption(selector('mode'), 'fixed');
  const untouched = await page.evaluate(() => ({settings:window.__settingsHarness.model.settings,
    tutorial:window.__settingsHarness.model.hostPrefs.tutorialsAutoOpen}));
  await page.evaluate(() => window.__settingsHarness.failNextPerformanceSave());
  await page.locator('.settings-performance-apply').click();
  await page.waitForSelector('.settings-performance-message[data-state="error"]');
  assert.deepStrictEqual((await savedState()).current, {preset:'balanced',mode:'auto',maxRenderHeight:0});
  assert.strictEqual(await page.inputValue(selector('preset')), 'quality');
  assert.strictEqual(await page.inputValue(selector('mode')), 'fixed');
  assert.strictEqual(await page.inputValue(selector('maxRenderHeight')), '540');
  assert.strictEqual(await page.locator('.settings-performance-apply').isEnabled(), true);
  checked++;

  await page.locator('.settings-performance-apply').click();
  await waitSaved();
  const write = (await performanceWrites()).pop();
  assert.deepStrictEqual(write.payload, {v:1,key:'performance',value:{preset:'quality',mode:'fixed',maxRenderHeight:540}});
  assert.deepStrictEqual(await savedState(), {v:1,current:write.payload.value,
    previous:{preset:'balanced',mode:'auto',maxRenderHeight:0}});
  assert.deepStrictEqual(await page.evaluate(() => ({settings:window.__settingsHarness.model.settings,
    tutorial:window.__settingsHarness.model.hostPrefs.tutorialsAutoOpen})), untouched);
  assert.strictEqual(await page.locator('.settings-performance-apply').isDisabled(), true);
  if (screenshotDir) await page.screenshot({path:path.join(screenshotDir,
    viewport.width + 'x' + viewport.height + '-visual-performance.png')});
  checked++;

  await page.selectOption(selector('maxRenderHeight'), '720');
  await page.evaluate(() => window.__settingsHarness.failNextPerformanceSave());
  await page.locator('.settings-performance-apply').click();
  await page.waitForSelector('.settings-performance-message[data-state="error"]');
  assert.deepStrictEqual(await savedState(), {v:1,current:{preset:'quality',mode:'fixed',maxRenderHeight:540},
    previous:{preset:'balanced',mode:'auto',maxRenderHeight:0}});
  assert.strictEqual(await page.locator('.settings-performance-undo').isEnabled(), true,
    'save rollback must retain the last successful undo point');
  checked++;

  await page.selectOption(selector('mode'), 'auto');
  await page.selectOption(selector('maxRenderHeight'), '720');
  await page.locator('.settings-performance-undo').click();
  await waitSaved();
  assert.deepStrictEqual((await performanceWrites()).pop().payload, {v:1,key:'performanceUndo',value:true});
  assert.deepStrictEqual(await savedState(), {v:1,current:{preset:'balanced',mode:'auto',maxRenderHeight:0},previous:null});
  assert.strictEqual(await page.locator('.settings-performance-undo').isDisabled(), true);
  assert.deepStrictEqual(await page.evaluate(() => window.__settingsHarness.model.settings), untouched.settings);
  checked++;

  await page.selectOption(selector('preset'), 'quality');
  await page.selectOption(selector('maxRenderHeight'), '540');
  await page.selectOption(selector('mode'), 'fixed');
  await page.locator('.settings-performance-apply').click();
  await waitSaved();
  await page.evaluate(() => window.__settingsHarness.reopen());
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await page.inputValue(selector('preset')), 'quality');
  assert.strictEqual(await page.inputValue(selector('mode')), 'fixed');
  assert.strictEqual(await page.inputValue(selector('maxRenderHeight')), '540');
  assert.strictEqual(await page.locator('.settings-performance-undo').isEnabled(), true);
  checked++;

  // Malformed success reconciles once while preserving unrelated game drafts.
  await page.click('.settings-tab[data-tab="common"]');
  await page.locator('.settings-audio-grid input[type="range"]').first().evaluate(input => {
    input.value = '42'; input.dispatchEvent(new Event('input', {bubbles:true}));
  });
  await page.click('.settings-tab[data-tab="visual"]');
  await page.selectOption(selector('mode'), 'auto');
  const beforeMalformed = (await performanceWrites()).length;
  await page.evaluate(() => window.__settingsHarness.malformNextPerformanceResponse());
  await page.locator('.settings-performance-apply').click();
  await page.waitForFunction(() => {
    const control = document.querySelector('[data-performance-key="mode"]');
    return control && control.value === 'auto' && !control.disabled
      && document.querySelector('.settings-status').textContent.includes('已与游戏状态同步');
  });
  assert.strictEqual((await performanceWrites()).length, beforeMalformed + 1);
  assert.strictEqual((await savedState()).current.mode, 'auto');
  await page.click('.settings-tab[data-tab="common"]');
  assert.strictEqual(await page.locator('.settings-audio-grid input[type="range"]').first().inputValue(), '42');
  assert.strictEqual(await page.locator('.settings-footer .primary').isEnabled(), true);
  assert.strictEqual(await page.evaluate(() => window.__settingsHarness.model.settings.setGlobalVolume), 80);
  checked++;

  // Timeout plus failed snapshot keeps the latch and draft until a fresh successful read.
  await page.click('.settings-tab[data-tab="visual"]');
  await page.selectOption(selector('mode'), 'fixed');
  const beforeTimeout = (await performanceWrites()).length;
  await page.evaluate(() => {
    window.__settingsHarness.dropNextResponse('host_set');
    window.__settingsHarness.failNextSnapshot();
  });
  await page.locator('.settings-performance-apply').click();
  await page.waitForFunction(() => document.querySelector('.settings-status').textContent.includes('写入仍保持锁定'));
  assert.strictEqual(await page.locator('.settings-performance').count(), 0);
  assert.strictEqual((await performanceWrites()).length, beforeTimeout + 1);
  await page.locator('.settings-empty button').click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  assert.strictEqual(await page.inputValue(selector('mode')), 'fixed');
  await page.click('.settings-tab[data-tab="common"]');
  assert.strictEqual(await page.locator('.settings-audio-grid input[type="range"]').first().inputValue(), '42');
  assert.strictEqual((await performanceWrites()).length, beforeTimeout + 1);
  checked++;

  // Replaced document rejects stale response.
  await page.click('.settings-tab[data-tab="visual"]');
  await page.selectOption(selector('mode'), 'auto');
  await page.evaluate(() => window.__settingsHarness.holdNextHostResponse());
  await page.locator('.settings-performance-apply').click();
  await page.evaluate(() => window.__settingsHarness.reopen());
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.click('.settings-tab[data-tab="visual"]');
  await page.selectOption(selector('preset'), 'performance');
  await page.evaluate(() => window.__settingsHarness.releaseHostResponse());
  assert.strictEqual(await page.inputValue(selector('preset')), 'performance');
  assert.strictEqual(await page.locator('.settings-performance-apply').isEnabled(), true);
  checked++;

  // Malformed performance state degrades cleanly without locking other Host controls.
  const validState = await savedState();
  await page.evaluate(() => {
    window.__settingsHarness.model.hostPrefs.performance.current.maxRenderHeight = '540';
    window.__settingsHarness.reopen();
  });
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await page.locator('[data-performance-key]').count(), 0);
  assert((await page.locator('.settings-performance-message').textContent()).includes('暂不可用'));
  await page.click('.settings-tab[data-tab="prefs"]');
  assert.strictEqual(await page.locator('[data-host-key="tutorialsAutoOpen"]').isEnabled(), true);
  await page.evaluate(state => {
    window.__settingsHarness.model.hostPrefs.performance = state;
    window.__settingsHarness.reopen();
  }, validState);
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.click('.settings-tab[data-tab="visual"]');
  checked++;

  // Other Host preferences finishing across tab switches retain performance draft.
  await page.selectOption(selector('preset'), 'performance');
  await page.selectOption(selector('maxRenderHeight'), '720');
  const beforeOtherHost = (await performanceWrites()).length;
  await page.evaluate(() => window.__settingsHarness.holdNextHostResponse());
  await page.click('.settings-tab[data-tab="prefs"]');
  await page.locator('[data-host-key="introEnabled"]').click();
  await page.click('.settings-tab[data-tab="keys"]');
  await page.click('.settings-tab[data-tab="prefs"]');
  await page.evaluate(() => window.__settingsHarness.releaseHostResponse());
  assert.strictEqual(await page.locator('[data-host-key="introEnabled"]').isChecked(), false);
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await page.inputValue(selector('preset')), 'performance');
  assert.strictEqual(await page.inputValue(selector('maxRenderHeight')), '720');
  assert.strictEqual((await performanceWrites()).length, beforeOtherHost);
  checked++;

  await page.click('.settings-tab[data-tab="prefs"]');
  await page.evaluate(() => window.__settingsHarness.dropNextResponse('host_set'));
  await page.locator('[data-host-key="introEnabled"]').click();
  await page.waitForFunction(() => {
    const checkbox = document.querySelector('[data-host-key="introEnabled"]');
    return checkbox && checkbox.checked
      && document.querySelector('.settings-status').textContent.includes('已与游戏状态同步');
  });
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await page.inputValue(selector('preset')), 'performance');
  assert.strictEqual(await page.inputValue(selector('maxRenderHeight')), '720');
  assert.strictEqual(await page.locator('.settings-performance-apply').isEnabled(), true);
  assert.strictEqual((await performanceWrites()).length, beforeOtherHost);
  checked++;
  await page.evaluate(() => window.__settingsHarness.reopen());
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  return checked;
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
  await page.evaluate(async () => {
    const panel = document.querySelector('.settings-panel');
    const finite = panel.getAnimations().filter(animation =>
      Number.isFinite(animation.effect.getTiming().iterations));
    await Promise.all(finite.map(animation => animation.finished.catch(() => {})));
  });

  // ── 1. Page 1 ("常用" 驾驶舱) zero-scroll & 6 core controls ──
  const layout = await page.evaluate(() => {
    function rect(selector) {
      const value = document.querySelector(selector).getBoundingClientRect();
      return {x:value.x,y:value.y,width:value.width,height:value.height,bottom:value.bottom};
    }
    const mainEl = document.querySelector('.settings-content');
    return {
      content:rect('#panel-content'),
      header:rect('.settings-terminal-header'),
      tabs:rect('.settings-tabs'),
      main:rect('.settings-content'),
      panel:rect('.settings-panel'),
      common:rect('.settings-game-common'),
      rescue:rect('.settings-rescue-strip'),
      homeCheat:rect('.settings-home-cheat-bar'),
      cameraEntry:rect('.settings-camera-entry'),
      footer:rect('.settings-footer'),
      terminal:document.querySelector('.settings-panel').classList.contains('settings-terminal-shell'),
      workbench:document.querySelector('.settings-panel').classList.contains('workbench-shell'),
      brand:document.querySelector('.settings-brand-seal').textContent.trim(),
      tabLabels:Array.from(document.querySelectorAll('.settings-tab')).map(tab => tab.textContent.trim()),
      scrollTop:mainEl.scrollTop,
      scrollHeight:mainEl.scrollHeight,
      clientHeight:mainEl.clientHeight,
      scrollWidth:mainEl.scrollWidth,
      clientWidth:mainEl.clientWidth
    };
  });
  near(layout.content.x, 0, 'panel-content x');
  near(layout.content.y, 0, 'panel-content y');
  near(layout.content.width, viewport.width, 'panel-content width');
  near(layout.content.height, viewport.height, 'panel-content height');
  near(layout.panel.width, layout.content.width, 'settings panel width', 2);
  near(layout.panel.height, layout.content.height, 'settings panel height', 2);
  assert(layout.terminal, 'settings must use the launcher terminal shell');
  assert(!layout.workbench, 'settings must not inherit the workbench shell');
  assert.strictEqual(layout.brand, 'CF7:ME');
  assert.deepStrictEqual(layout.tabLabels, ['常用','画面与战斗','键位','界面与音频']);
  assert(layout.tabs.y >= layout.header.y && layout.tabs.bottom <= layout.header.bottom + 1,
    'all four tabs must share the launcher header row');
  near(layout.main.y, layout.header.bottom, 'content begins directly below the launcher header');
  assert.strictEqual(layout.scrollTop, 0);
  assert(layout.scrollHeight <= layout.clientHeight + 2,
    'common cockpit must fit in one screen without vertical scroll: ' + layout.scrollHeight + ' vs ' + layout.clientHeight);
  assert(layout.scrollWidth <= layout.clientWidth + 1, 'common cockpit must not overflow horizontally');
  assert(layout.rescue.bottom <= layout.main.bottom && layout.rescue.y >= layout.main.y);
  assert(layout.homeCheat.bottom <= layout.main.bottom + 1 && layout.homeCheat.y >= layout.main.y);
  assert(layout.cameraEntry.bottom <= layout.main.bottom + 1 && layout.cameraEntry.y >= layout.main.y);
  assert.strictEqual(await page.getByRole('button', {name:'试听界面音效'}).count(), 1);
  assert.strictEqual(await page.locator('#settings-home-cheat-input').count(), 1);
  assert.strictEqual(await page.locator('.settings-home-cheat .settings-cheat-help-open').count(), 1);
  assert.strictEqual(await page.locator('.settings-panel [title]').count(), 0);
  assert.strictEqual(await page.locator('.settings-camera-inline-viewport img').count(), 1);

  // Verify PanelTooltip appears on hover AND clears immediately on tab switch (no ghost tooltip).
  const rescueButton = page.getByRole('button', {name:'立即返回基地'});
  await rescueButton.hover();
  await page.waitForFunction(() => window.PanelTooltip && PanelTooltip.isVisible());
  assert((await page.locator('#panel-tooltip').textContent()).includes('立即跳过当前流程并返回基地'));
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await page.evaluate(() => window.PanelTooltip && PanelTooltip.isVisible()), false,
    'switching tabs must immediately hide active tooltip');
  await page.click('.settings-tab[data-tab="common"]');

  if (screenshotDir) {
    fs.mkdirSync(screenshotDir, {recursive:true});
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-common.png')});
  }

  // Test inline camera zoom live scaling and strict 16:9 aspect ratio on Page 1.
  const inlineCameraRect = await page.locator('.settings-camera-inline-viewport').boundingBox();
  assert(inlineCameraRect && Math.abs((inlineCameraRect.width / inlineCameraRect.height) - (16 / 9)) < 0.02,
    'inline camera viewport must keep exact 16:9 ratio: ' + JSON.stringify(inlineCameraRect));
  await page.locator('.settings-camera-zoom-row input[type="range"]').evaluate(input => {
    input.value = '1.8'; input.dispatchEvent(new Event('input', {bubbles:true}));
  });
  assert.strictEqual(await page.locator('.settings-camera-inline-hud').textContent(), '1.8×');
  const inlineCamMode = await page.locator('.settings-camera-inline-viewport img').getAttribute('data-preview-mode');
  assert.strictEqual(inlineCamMode, 'as2_exact');
  assert.strictEqual(await page.locator('.settings-dirty-badge').isVisible(), true);

  // Test custom in-panel close confirm modal (no native window.confirm).
  await page.locator('.settings-terminal-close').click();
  await page.waitForSelector('.settings-confirm-modal');
  await page.evaluate(async () => {
    const layer = document.querySelector('.settings-confirm-layer');
    if (layer && layer.getAnimations) {
      await Promise.all(layer.getAnimations().map(a => a.finished.catch(() => {})));
    }
  });
  assert.strictEqual(await page.evaluate(() => window.PanelTooltip && PanelTooltip.isVisible()), false,
    'opening close-confirm modal must dismiss hover tooltip');
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-close-confirm.png')});
  }
  await page.keyboard.press('Escape');
  assert.strictEqual(await page.locator('.settings-confirm-modal').count(), 0);
  await page.locator('.settings-camera-reset-inline').click();
  assert.strictEqual(await page.locator('.settings-camera-inline-hud').textContent(), '1.0×');

  // ── 2. Page 2 ("画面与战斗") Live HitNumber Sandbox + Andy Law Portrait Compare ──
  await page.click('.settings-tab[data-tab="visual"]');
  await page.waitForSelector('.settings-hit-preview-canvas');
  await page.waitForFunction(() => {
    const telemetry = document.querySelector('.settings-hit-telemetry');
    return telemetry && telemetry.textContent.includes('可见行');
  });
  const hitCanvasPixels = await page.evaluate(() => {
    const canvas = document.querySelector('.settings-hit-preview-canvas');
    const data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
    let nonZero = 0;
    for (let i = 3; i < data.length; i += 4) if (data[i] > 0) nonZero++;
    return nonZero;
  });
  assert(hitCanvasPixels > 500, 'live hit-number preview canvas must draw visible pixels: ' + hitCanvasPixels);
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-visual-top.png')});
  }

  // Switch damage mode and worldRowLimit live via quick chip.
  await page.locator('.settings-hit-sandbox [data-host-segment="hitNumberMode"] [data-value="total"]').click();
  await page.waitForFunction(() => window.__settingsHarness.model.hostPrefs.hitNumberMode === 'total');
  await page.locator('.settings-limit-chips [data-limit="12"]').click();
  await page.waitForFunction(() => window.__settingsHarness.model.hostPrefs.hitNumberWorldRowLimit === 12);

  // Scroll to Andy Law portrait comparison & verify both portrait cards render real images.
  await page.locator('.settings-portrait-picker').scrollIntoViewIfNeeded();
  await page.waitForFunction(() => {
    const canvases = document.querySelectorAll('.settings-portrait-canvas');
    if (canvases.length !== 2) return false;
    return Array.from(canvases).every(c => {
      const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
      let nonZero = 0;
      for (let i = 3; i < d.length; i += 4) if (d[i] > 0) nonZero++;
      return nonZero > 200;
    });
  }, {timeout:5000});
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-visual-portrait.png')});
  }
  await page.locator('.settings-portrait-card[data-portrait-type="2"]').click();
  assert.strictEqual(await page.locator('.settings-portrait-card[data-portrait-type="2"]').getAttribute('aria-pressed'), 'true');
  // Discard portrait draft before testing remaining flows cleanly.
  await page.getByRole('button', {name:'放弃游戏改动'}).click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));

  // ── 3. Page 3 ("键位") 36 keys zero-scroll + search filter ──
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
  assert.strictEqual(keyState.count, 36);
  assert(!keyState.labels.some(label => !label || /^(undefined|null)$/i.test(label)));
  assert(keyState.labels.includes('药剂组切换键')
    && keyState.labels.includes('奔跑键') && keyState.labels.includes('组合键'));
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
    'key density must come from removing label/control whitespace, maxGap=' + keyState.maximumTextControlGap);
  await page.fill('.settings-key-search', '药剂');
  assert.strictEqual(await page.locator('.settings-key-row.is-match').count(), 1);
  assert.strictEqual(await page.locator('.settings-key-row.is-dimmed').count(), 35);
  await page.fill('.settings-key-search', '');

  // ── 4. Page 4 ("界面与音频") unified jukebox + batch item-grid density ──
  await page.click('.settings-tab[data-tab="prefs"]');
  assert.strictEqual(await page.locator('.settings-jukebox-unified').count(), 1);
  assert.strictEqual(await page.locator('.settings-theme-card').count(), 2);
  await page.locator('.settings-theme-card[data-theme-value="amber"]').click();
  assert.strictEqual(await page.evaluate(() => localStorage.getItem('cf7-jukebox-theme')), 'amber');
  await page.getByRole('button', {name:'全部设为完整'}).click();
  assert.strictEqual(await page.evaluate(() => localStorage.getItem('cf7.itemgrid.mode.workbench')), 'full');
  assert.strictEqual(await page.evaluate(() => localStorage.getItem('cf7.itemgrid.mode.kshop')), 'full');
  await page.getByRole('button', {name:'全部设为紧凑'}).click();
  assert.strictEqual(await page.evaluate(() => localStorage.getItem('cf7.itemgrid.mode.workbench')), 'compact');
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-prefs.png')});
    await page.locator('.settings-itemgrid-section').scrollIntoViewIfNeeded();
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-prefs-density.png')});
  }

  // ── 5. Full Camera Simulator Modal ──
  await page.click('.settings-tab[data-tab="common"]');
  assert.strictEqual(await page.locator('.settings-jukebox-unified').count(), 0);
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
    && modalGeometry.modalHeight >= modalGeometry.panelHeight * 0.96);
  assert(Math.abs((modalGeometry.previewWidth / modalGeometry.previewHeight) - (16 / 9)) < 0.02,
    'modal camera viewport must keep exact 16:9 ratio');
  near(modalGeometry.imageWidth, modalGeometry.previewWidth, 'entry frame fills preview width at 1.0x');
  near(modalGeometry.imageHeight, modalGeometry.previewHeight, 'entry frame fills preview height at 1.0x');
  assert(modalGeometry.previewWidth >= modalGeometry.stageContentWidth * 0.95);
  near(modalGeometry.scale, 1, 'entry frame begins at the captured baseline');
  assert.strictEqual(modalGeometry.objectFit, 'cover');
  assert.deepStrictEqual([modalGeometry.naturalWidth, modalGeometry.naturalHeight], [1024, 576]);
  assert.strictEqual(await page.locator('.settings-camera-control-field input[type="checkbox"]').isChecked(), false);
  const zoom = page.locator('.settings-camera-control-field input[type="range"]');
  await zoom.evaluate(input => { input.value = '0.6'; input.dispatchEvent(new Event('input', {bubbles:true})); });
  await page.waitForFunction(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    const viewport = document.querySelector('.settings-camera-simulator-viewport');
    if (!image || !viewport) return false;
    const matrix = new DOMMatrix(getComputedStyle(image).transform);
    return Math.abs(matrix.a - 0.6) < 0.01
      && Math.abs(matrix.e) < 1 && Math.abs(matrix.f) < 1
      && image.getBoundingClientRect().width < viewport.getBoundingClientRect().width * 0.7;
  });
  await zoom.evaluate(input => { input.value = '2.2'; input.dispatchEvent(new Event('input', {bubbles:true})); });
  await page.waitForFunction(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    const viewport = document.querySelector('.settings-camera-simulator-viewport');
    if (!image || !viewport) return false;
    const matrix = new DOMMatrix(getComputedStyle(image).transform);
    const vr = viewport.getBoundingClientRect();
    const localW = viewport.clientWidth;
    const localH = viewport.clientHeight;
    // AS2 HorizontalScroller at 2.2x: targetWorldX = -703 (-68.65% of W), targetWorldY = -305 (-52.95% of H)
    return Math.abs(matrix.a - 2.2) < 0.01
      && localW > 0 && localH > 0
      && Math.abs((matrix.e / localW) - (-703 / 1024)) < 0.015
      && Math.abs((matrix.f / localH) - (-305 / 576)) < 0.015
      && image.getBoundingClientRect().width > vr.width * 2;
  });
  await page.locator('.settings-camera-control-field input[type="checkbox"]').click();
  assert((await page.locator('.settings-camera-mode-hud').textContent()).trim().startsWith('动态镜头：开启'));
  await page.locator('.settings-camera-dynamic-samples .settings-seg-btn[data-value="1.5"]').click();
  await page.waitForFunction(() => {
    const image = document.querySelector('.settings-camera-simulator-viewport img');
    if (!image) return false;
    const matrix = new DOMMatrix(getComputedStyle(image).transform);
    return Math.abs(matrix.a - 3.3) < 0.02;
  });
  if (screenshotDir) {
    await page.screenshot({path:path.join(screenshotDir, viewport.width + 'x' + viewport.height + '-camera-modal.png')});
  }
  await page.keyboard.press('Escape');
  assert.strictEqual(await page.locator('.settings-camera-modal').count(), 0);
  assert.strictEqual(await page.evaluate(() => document.activeElement.classList.contains('settings-camera-open')), true);

  // ── 6. Cheat Help Modal & Challenge Mode Boundary ──
  await page.getByRole('button', {name:'作弊码帮助'}).click();
  await page.waitForSelector('.settings-cheat-doc code');
  const normalHelp = await page.locator('.settings-cheat-doc').textContent();
  assert(normalHelp.includes('#level:15'));
  assert((await page.locator('.settings-copy-command').count()) >= 30);
  await page.locator('.settings-cheat-modal-close').click();

  await page.evaluate(() => window.__settingsHarness.setChallengeMode(true));
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.getByRole('button', {name:'作弊码帮助'}).click();
  await page.waitForSelector('.settings-cheat-doc code');
  const challengeHelp = await page.locator('.settings-cheat-doc').textContent();
  assert(challengeHelp.includes('hardmode') && challengeHelp.includes('easymode') && challengeHelp.includes('challengemode'));
  assert(!challengeHelp.includes('#level:15') && !challengeHelp.includes('status'));
  await page.locator('.settings-cheat-modal-close').click();

  // ── 7. Rescue Return Base & Performance + Host Prefs Recovery ──
  await page.evaluate(() => window.__settingsHarness.setChallengeMode(false));
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  const before = await page.evaluate(() => window.__settingsHarness.sent.length);
  await page.getByRole('button', {name:'立即返回基地'}).click();
  await page.waitForFunction(count => window.__settingsHarness.sent.length > count, before);
  const rescuePayload = await page.evaluate(() => {
    const messages = window.__settingsHarness.sent.filter(message => message.cmd === 'return_base');
    return messages[messages.length - 1].payload;
  });
  assert.deepStrictEqual(rescuePayload, {v:1});

  const performanceChecked = await runPerformanceControls(page, viewport, screenshotDir);

  // Verify CAS / MotionFeedback on visual tab + tutorialsAutoOpen & reconcile recovery on prefs tab
  await page.click('.settings-tab[data-tab="visual"]');
  const casToggle = page.locator('[data-host-key="casEnabled"]');
  const feedbackToggle = page.locator('[data-host-key="motionFeedbackEnabled"]');
  assert.strictEqual(await casToggle.isChecked(), true);
  assert.strictEqual(await feedbackToggle.isChecked(), false);
  await casToggle.click();
  await page.waitForFunction(() => window.__settingsHarness.model.hostPrefs.casEnabled === false);
  await feedbackToggle.click();
  await page.waitForFunction(() => window.__settingsHarness.model.hostPrefs.motionFeedbackEnabled === true);
  await page.click('.settings-tab[data-tab="common"]');
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await casToggle.isChecked(), false);
  assert.strictEqual(await feedbackToggle.isChecked(), true);

  await page.click('.settings-tab[data-tab="prefs"]');
  const tutorialToggle = page.locator('[data-host-key="tutorialsAutoOpen"]');
  assert.strictEqual(await tutorialToggle.isChecked(), true);
  await tutorialToggle.click();
  await page.waitForFunction(() => window.__settingsHarness.model.hostPrefs.tutorialsAutoOpen === false);
  await page.evaluate(() => {
    window.__settingsHarness.dropNextResponse('host_set');
    window.__settingsHarness.failNextSnapshot();
  });
  await page.locator('[data-host-key="introEnabled"]').click();
  await page.waitForFunction(() => {
    const status = document.querySelector('.settings-status');
    return status && status.textContent.includes('写入仍保持锁定');
  }, {timeout:4000});
  assert.strictEqual(await page.locator('.settings-empty h2').textContent(), '写入状态等待权威核对');
  await page.locator('.settings-empty button').click();
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));

  // Verify graceful degradation when hitNumberPreview capability is absent
  await page.evaluate(() => {
    window.__settingsHarness.setHitPreviewEnabled(false);
    window.__settingsHarness.reopen();
  });
  await page.waitForFunction(() => document.querySelector('.settings-status[data-state="ready"]'));
  await page.click('.settings-tab[data-tab="visual"]');
  assert.strictEqual(await page.locator('.settings-hit-fallback').count(), 1);
  assert.strictEqual(await page.locator('.settings-hit-preview-canvas').count(), 0);
  await page.evaluate(() => window.__settingsHarness.setHitPreviewEnabled(true));

  assert.deepStrictEqual(pageErrors, []);
  assert.deepStrictEqual(failedRequests, []);
  await page.close();
  return 74 + performanceChecked;
}

async function runAuthorityViewport(browser,url,viewport,screenshotDir) {
  const page=await browser.newPage({viewport});
  try {
    await page.goto(url+'&authority=2');
    const persist=page.locator('.settings-persistence-status');
    await page.waitForFunction(()=>document.querySelector('.settings-status[data-state="ready"]'));
    assert(!(await persist.textContent()).includes('已保存'));
    const changeVolume=async value=>page.locator('.settings-audio-grid input[type="range"]').first().evaluate((input,n)=> {
      input.value=String(n);input.dispatchEvent(new Event('input',{bubbles:true}));input.dispatchEvent(new Event('change',{bubbles:true}));
    },value);
    await page.evaluate(()=>window.__settingsHarness.setDurable(false));
    await changeVolume(42);await page.getByRole('button',{name:'应用并保存',exact:true}).click();
    await page.getByRole('button',{name:'只重试保存',exact:true}).waitFor({state:'visible'});
    assert((await persist.textContent()).includes('保存尚未确认'));
    assert(await page.getByRole('button',{name:'应用并保存',exact:true}).isDisabled());
    await page.evaluate(()=>window.__settingsHarness.reopen());
    await page.getByRole('button',{name:'只重试保存',exact:true}).waitFor({state:'visible'});
    await changeVolume(72);await page.evaluate(()=>window.__settingsHarness.setDurable(true));
    await page.getByRole('button',{name:'只重试保存',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.settings-persistence-status').textContent==='当前设置已保存。');
    assert.equal(await page.locator('.settings-audio-grid input[type="range"]').first().inputValue(),'72');
    assert.equal(await page.evaluate(()=>window.__settingsHarness.model.settings.setGlobalVolume),42);
    assert.equal(await page.evaluate(()=>window.__settingsHarness.sent.filter(x=>x.cmd==='apply').length),1);
    await page.evaluate(()=> {window.__settingsHarness.setMetadataBlocked(true);window.__settingsHarness.reopen();});
    await page.waitForFunction(()=>document.querySelector('.settings-persistence-status').textContent.includes('状态通知尚未完成'));
    assert(await page.getByRole('button',{name:'应用并保存',exact:true}).isDisabled());
    await page.evaluate(()=>window.__settingsHarness.setMetadataBlocked(false));
    await page.getByRole('button',{name:'核对状态',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.settings-persistence-status').textContent==='当前设置已保存。');
    await page.waitForFunction(()=>document.querySelector('.settings-status[data-state="ready"]'));
    await page.evaluate(()=> {window.__settingsHarness.setDurable(false);window.__settingsHarness.dropNextResponse('apply');});
    await changeVolume(30);await page.getByRole('button',{name:'应用并保存',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.settings-empty h2')?.textContent==='写入状态等待权威核对');
    assert((await persist.textContent()).includes('尚未核对'));
    await page.getByRole('button',{name:'核对状态',exact:true}).click();
    await page.getByRole('button',{name:'只重试保存',exact:true}).waitFor({state:'visible'});
    assert.equal(await page.evaluate(()=>window.__settingsHarness.sent.filter(x=>x.cmd==='apply').length),2);
    if(screenshotDir)await page.screenshot({path:path.join(screenshotDir,viewport.width+'x'+viewport.height+'-authority-unconfirmed.png')});
    return 15;
  } finally { await page.close(); }
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
  const url = 'http://127.0.0.1:' + address.port + '/launcher/web/modules/settings/dev/harness.html?clean=1';
  const browser = await chromium.launch({executablePath, headless:true});
  let passed = 0;
  try {
    for (const viewport of [{width:1024,height:576},{width:1600,height:900}]) {
      const count = await runViewport(browser, url, viewport, screenshotDir);
      passed += count;
      process.stdout.write('[PASS] settings Edge ' + viewport.width + 'x' + viewport.height + ' (' + count + '/' + count + ')\n');
      const authorityCount=await runAuthorityViewport(browser,url,viewport,screenshotDir);
      passed+=authorityCount;
      process.stdout.write('[PASS] settings v2 Edge '+viewport.width+'x'+viewport.height+' ('+authorityCount+'/'+authorityCount+')\n');
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
