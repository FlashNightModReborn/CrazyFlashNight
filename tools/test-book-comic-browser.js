'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const assert = require('assert/strict');
const repo = path.resolve(__dirname, '..');
const web = path.join(repo, 'launcher/web');
const { chromium } = require(path.join(repo, 'launcher/perf/node_modules/playwright'));
const output = path.join(repo, 'tmp/book-comic-ui');
const viewports = [[1024, 576], [1440, 900], [640, 360], [480, 800]];
const mime = { '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png' };

// Only the Host transport is simulated. CSS, player, content and PanelScale are production files.
const fixture = `<!doctype html>
<meta charset="utf-8">
<link rel="stylesheet" href="/css/panels.css">
<style>
html,body{margin:0;width:100%;height:100%}
.panel-scale-shell{position:absolute;transform:scale(var(--panel-scale));transform-origin:top left;width:var(--pss-w);height:var(--pss-h)}
</style>
<div id="panel-container" data-panel="book-comic"><div id="panel-content"></div></div>
<script>
window.Panels = {register: (id, spec) => window.spec = spec};
window.messages = [];
window.Bridge = {
  on: (name, handler) => window.reply = handler,
  off: () => {},
  send: message => {
    messages.push(message);
    setTimeout(() => reply({...message, ...message.payload, success:true}), 0);
    return true;
  }
};
</script>
<script src="/modules/panel-scale.js"></script>
<script src="/modules/book-comic-content.js"></script>
<script src="/modules/book-comic-panel.js"></script>
<script>
window.comicRoot = spec.create();
document.querySelector('#panel-content').append(comicRoot);
window.openComic = function(pageId) {
  spec.onClose();
  messages.length = 0;
  spec.onOpen(comicRoot, {
    v:1, presentationId:'bookcomic:1', slot:'fixture', sceneId:'scene:1',
    pageId, panelInstanceId:'fixture:1'
  });
};
openComic('prologue');
</script>`;

const server = http.createServer((request, response) => {
  if (request.url === '/fixture') {
    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.end(fixture);
    return;
  }
  const file = path.resolve(web, '.' + decodeURIComponent(request.url));
  if (path.relative(web, file).startsWith('..')) {
    response.writeHead(403).end();
    return;
  }
  fs.readFile(file, (error, bytes) => {
    response.writeHead(error ? 404 : 200, {
      'Content-Type': mime[path.extname(file)] || 'application/octet-stream'
    });
    response.end(error ? '' : bytes);
  });
});

async function pauseAfterPrepare(page) {
  await page.waitForFunction(() => messages.some(message => message.cmd === 'prepared'));
  await page.waitForFunction(() => document.querySelector('[data-comic=play]').textContent === '暂停');
  await page.locator('[data-comic=play]').click();
}

async function checkEveryLine(page, pageId, viewport) {
  const lines = await page.evaluate(id => BOOK_COMIC_CONTENT.pages.find(p => p.id === id)
    .panels.flatMap(panel => panel.lines), pageId);
  for (let index = 0; index < lines.length; index++) {
    const current = await page.evaluate(() => {
      const subtitle = document.querySelector('[data-comic=subtitle]');
      return {
        text: document.querySelector('[data-comic=speech]').textContent,
        hidden: subtitle.hidden,
        height: subtitle.clientHeight,
        scrollHeight: subtitle.scrollHeight,
        width: subtitle.clientWidth,
        scrollWidth: subtitle.scrollWidth
      };
    });
    const label = `${pageId} line ${index + 1} at ${viewport}`;
    assert.equal(current.text, lines[index].text, label + ' actual playback line');
    assert.equal(current.hidden, false, label + ' visible');
    assert(current.scrollHeight <= current.height, label + ' vertical overflow');
    assert(current.scrollWidth <= current.width, label + ' horizontal overflow');
    if (index + 1 < lines.length) await page.locator('[data-comic=next]').click();
  }
  return lines.length;
}

async function checkLayout(page) {
  const metrics = await page.evaluate(() => {
    const select = selector => document.querySelector(selector);
    const bounds = selector => {
      const rect = select(selector).getBoundingClientRect();
      return {x:rect.x, y:rect.y, w:rect.width, h:rect.height};
    };
    return {
      shell:bounds('.book-comic-shell'), art:bounds('canvas'),
      subtitle:bounds('.book-comic-subtitle'), footer:bounds('footer'),
      font:getComputedStyle(select('.book-comic-subtitle p')).fontSize,
      toolbarOverflow:select('footer').scrollWidth > select('footer').clientWidth
    };
  });
  assert.equal(metrics.font, '21px');
  assert(Math.abs(metrics.shell.w / metrics.shell.h - 1024 / 576) < .002);
  assert(metrics.subtitle.y >= metrics.art.y + metrics.art.h - .1);
  assert(metrics.footer.y >= metrics.subtitle.y + metrics.subtitle.h - .1);
  assert(!metrics.toolbarOverflow);
  assert(metrics.shell.x >= -.1 && metrics.shell.y >= -.1);
}

async function checkReadingScrollbars(page, pageId, viewport) {
  for (const id of ['paper', 'transcript']) {
    const style = await page.locator(`[data-comic=${id}]`).evaluate(element => ({
      colors: getComputedStyle(element).scrollbarColor,
      width: getComputedStyle(element).scrollbarWidth,
      tabIndex: element.tabIndex,
      corner: getComputedStyle(element, '::-webkit-scrollbar-corner').backgroundColor
    }));
    assert.equal(style.colors, 'rgb(125, 137, 98) rgb(20, 27, 21)');
    assert.equal(style.width, 'thin');
    assert.equal(style.corner, 'rgb(20, 27, 21)');
    assert.equal(style.tabIndex, 0);
  }
  const transcript = page.locator('[data-comic=transcript]');
  await transcript.hover();
  await page.mouse.wheel(0, 240);
  await page.waitForFunction(() => document.querySelector('[data-comic=transcript]').scrollTop > 0);
  await transcript.focus();
  await page.keyboard.press('End');
  await page.waitForFunction(() => {
    const element = document.querySelector('[data-comic=transcript]');
    return element.scrollTop > 240;
  });
  const paper = page.locator('[data-comic=paper]');
  await paper.hover();
  await page.keyboard.down('Control');
  await page.mouse.wheel(0, -1000);
  await page.keyboard.up('Control');
  await page.waitForFunction(() => {
    const element = document.querySelector('[data-comic=paper]');
    return element.scrollHeight > element.clientHeight && element.scrollWidth > element.clientWidth;
  });
  await page.mouse.wheel(120, 240);
  await page.waitForFunction(() => {
    const element = document.querySelector('[data-comic=paper]');
    return element.scrollTop > 0 && element.scrollLeft > 0;
  });
  await page.screenshot({path:path.join(output, `${pageId}-scrollbars-${viewport}.png`)});
}

async function checkReadingAndKeyboard(page, pageId, viewport) {
  // Unfocus buttons so the document keyboard contract applies.
  await page.evaluate(() => document.activeElement.blur());
  await page.keyboard.press('r');
  assert.equal(await page.locator('[data-comic=reading]').isVisible(), true);
  const image = await page.locator('[data-comic=whole]').boundingBox();
  const paper = await page.locator('[data-comic=paper]').boundingBox();
  assert(image.height < paper.height && image.width < paper.width, 'whole image fits');
  assert.equal(await page.locator('.book-comic-transcript article').count(),
    await page.evaluate(id => BOOK_COMIC_CONTENT.pages.find(p => p.id === id).panels.length, pageId));
  await page.screenshot({path:path.join(output, `${pageId}-whole-${viewport}.png`)});
  await checkReadingScrollbars(page, pageId, viewport);
  await page.locator('[data-comic=play]').click();
  assert.equal(await page.locator('[data-comic=reading]').isVisible(), false);
  assert.equal(await page.locator('[data-comic=play]').innerText(), '暂停');
  await page.evaluate(() => document.activeElement.blur());
  await page.keyboard.press('Space');
  assert.equal(await page.locator('[data-comic=play]').innerText(), '播放');
  await page.keyboard.press('Space');
  assert.equal(await page.locator('[data-comic=play]').innerText(), '暂停');
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.locator('[data-comic=play]').innerText(), '播放');
  await page.screenshot({path:path.join(output, `${pageId}-focus-${viewport}.png`)});
}

async function main() {
  assert(!fs.readFileSync(path.join(web, 'modules/panels-lazy-registry.js'), 'utf8')
    .includes("'css/book-comic.css'"));
  assert(fs.readFileSync(path.join(web, 'css/panels.css'), 'utf8').includes('./book-comic.css'));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const browser = await chromium.launch({
    executablePath:path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'),
    headless:true,
    // Scrollbars are part of the game UI under test, including in screenshots.
    ignoreDefaultArgs:['--hide-scrollbars']
  });
  try {
    fs.mkdirSync(output, {recursive:true});
    const page = await browser.newPage();
    const errors = [];
    let checkedLines = 0;
    page.on('pageerror', error => errors.push(error.message));
    for (const [width, height] of viewports) {
      const viewport = `${width}x${height}`;
      await page.setViewportSize({width, height});
      await page.goto(`http://127.0.0.1:${server.address().port}/fixture`);
      for (const pageId of ['prologue', 'boss']) {
        if (pageId === 'boss') await page.evaluate(id => openComic(id), pageId);
        await pauseAfterPrepare(page);
        await checkLayout(page);
        checkedLines += await checkEveryLine(page, pageId, viewport);
        await checkReadingAndKeyboard(page, pageId, viewport);
      }
    }
    assert.deepEqual(errors, []);
    console.log(`PASS: ${checkedLines} real playback subtitle checks; both pages, 4 fixed-ratio viewports, CSS, themed scrollbars, wheel/keyboard scrolling, zoom, reading and keyboard. Screenshots: ${output}`);
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch(error => {
  console.error(error);
  server.close();
  process.exitCode = 1;
});
