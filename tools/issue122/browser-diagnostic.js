'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { startServer } = require('../lib/stage-select-dev-server');

const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(ROOT, 'tmp', 'issue122-linux');
const { chromium } = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
const MODES = ['raw', 'chunked', 'nonindexed'];
const CAMERAS = ['issue-time', 'current'];

function hash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function capture(browser, origin, mode, camera) {
  const page = await browser.newPage({ viewport: { width: 1024, height: 576 } });
  const errors = [];
  const failed = [];
  const httpErrors = [];
  const consoleMessages = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('requestfailed', r => failed.push({ url: r.url(), error: r.failure()?.errorText || '' }));
  page.on('response', r => { if (r.status() >= 400) httpErrors.push({ url: r.url(), status: r.status() }); });
  page.on('console', m => { if (m.type() === 'error' || m.type() === 'warning') consoleMessages.push({ type:m.type(), text:m.text() }); });
  await page.route('https://cfn-fonts.local/**', r => r.fulfill({ status: 204, body: '' }));
  const url = origin + '/modules/stage-select/dev/issue122-index-fixture.html?issue122IndexMode=' + mode + '&issue122Camera=' + camera;
  await page.goto(url);
  await page.waitForFunction(() => window.Issue122Fixture && (Issue122Fixture.ready || Issue122Fixture.error));
  const fixtureError = await page.evaluate(() => Issue122Fixture.error);
  if (fixtureError) throw new Error(fixtureError + '\nHTTP=' + JSON.stringify(httpErrors) + '\nFAILED=' + JSON.stringify(failed) + '\nCONSOLE=' + JSON.stringify(consoleMessages));
  const stats = await page.evaluate(() => Issue122Fixture.stats());
  const gl = await page.evaluate(() => {
    const canvas = document.querySelector('.stage-select-diorama-canvas');
    const ctx = canvas && canvas.getContext('webgl2');
    if (!ctx) return { webgl2: false };
    const debug = ctx.getExtension('WEBGL_debug_renderer_info');
    return {
      webgl2: true,
      vendor: ctx.getParameter(ctx.VENDOR),
      renderer: ctx.getParameter(ctx.RENDERER),
      version: ctx.getParameter(ctx.VERSION),
      shadingLanguageVersion: ctx.getParameter(ctx.SHADING_LANGUAGE_VERSION),
      unmaskedVendor: debug ? ctx.getParameter(debug.UNMASKED_VENDOR_WEBGL) : null,
      unmaskedRenderer: debug ? ctx.getParameter(debug.UNMASKED_RENDERER_WEBGL) : null,
      maxElementsIndices: ctx.getParameter(ctx.MAX_ELEMENTS_INDICES),
      maxElementsVertices: ctx.getParameter(ctx.MAX_ELEMENTS_VERTICES),
      error: ctx.getError(),
    };
  });
  const canvas = page.locator('canvas.stage-select-diorama-canvas');
  const png = await canvas.screenshot({ path: path.join(OUT, camera + '-' + mode + '.png') });
  await page.close();
  assert.deepEqual(errors, [], mode + ' page errors');
  assert.deepEqual(failed, [], mode + ' request failures');
  assert.equal(stats.issue122Mode, mode, mode + ' mode propagated');
  assert.equal(stats.triangles, 361010, mode + ' triangle count');
  assert.equal(gl.webgl2, true, mode + ' WebGL2');
  assert.equal(gl.error, 0, mode + ' gl.getError');
  return { camera, mode, stats, gl, httpErrors, consoleMessages, screenshot: { sha256: hash(png), bytes: png.length } };
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const { server, origin } = await startServer(path.join(ROOT, 'launcher/web'));
  const browser = await chromium.launch({
    headless: true,
    args: process.env.CF7_ISSUE122_CHROMIUM_ARGS ? process.env.CF7_ISSUE122_CHROMIUM_ARGS.split(/\s+/).filter(Boolean) : [],
  });
  const report = {
    schema: 1,
    platform: process.platform,
    arch: process.arch,
    node: process.version,
    chromiumArgs: process.env.CF7_ISSUE122_CHROMIUM_ARGS || '',
    modes: [],
  };
  try {
    for (const camera of CAMERAS) for (const mode of MODES)
      report.modes.push(await capture(browser, origin, mode, camera));
    const byKey = Object.fromEntries(report.modes.map(row => [row.camera + '/' + row.mode, row]));
    for (const camera of CAMERAS) {
      const raw=byKey[camera + '/raw'], chunked=byKey[camera + '/chunked'], nonindexed=byKey[camera + '/nonindexed'];
      assert.equal(raw.stats.indexCompatibility[0].mode, 'raw');
      assert.equal(raw.stats.calls, 51, camera + ' raw draw calls');
      assert.equal(chunked.stats.indexCompatibility[0].mode, 'chunked');
      assert.equal(chunked.stats.indexCompatibility[0].outputChunks, 5);
      assert.equal(chunked.stats.calls, 55, camera + ' chunked draw calls');
      assert.equal(nonindexed.stats.indexCompatibility[0].mode, 'nonindexed');
      assert.equal(nonindexed.stats.indexCompatibility[0].expandedBatches, 1);
      assert.equal(nonindexed.stats.calls, 51, camera + ' non-indexed draw calls');
    }
    const identity = row => JSON.stringify([
      row.gl.vendor, row.gl.renderer, row.gl.version, row.gl.unmaskedVendor, row.gl.unmaskedRenderer,
    ]);
    assert.equal(new Set(report.modes.map(identity)).size, 1, 'same WebGL backend for all modes');
    report.pixelIdentity = Object.fromEntries(CAMERAS.map(camera => {
      const raw=byKey[camera + '/raw'], chunked=byKey[camera + '/chunked'], nonindexed=byKey[camera + '/nonindexed'];
      return [camera, {
        rawVsChunkedPngExact: raw.screenshot.sha256 === chunked.screenshot.sha256,
        rawVsNonindexedPngExact: raw.screenshot.sha256 === nonindexed.screenshot.sha256,
        chunkedVsNonindexedPngExact: chunked.screenshot.sha256 === nonindexed.screenshot.sha256,
      }];
    }));
    report.pass = true;
  } catch (error) {
    report.pass = false;
    report.error = error.stack;
    process.exitCode = 1;
  } finally {
    await browser.close();
    server.close();
    fs.writeFileSync(path.join(OUT, 'browser.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify(report, null, 2));
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
