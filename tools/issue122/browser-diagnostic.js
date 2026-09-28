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

function hash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function capture(browser, origin, mode) {
  const page = await browser.newPage({ viewport: { width: 1024, height: 576 } });
  const errors = [];
  const failed = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('requestfailed', r => failed.push({ url: r.url(), error: r.failure()?.errorText || '' }));
  await page.route('https://cfn-fonts.local/**', r => r.fulfill({ status: 204, body: '' }));
  const url = origin + '/modules/stage-select/dev/issue122-index-fixture.html?issue122IndexMode=' + mode;
  await page.goto(url);
  await page.waitForFunction(() => window.Issue122Fixture && (Issue122Fixture.ready || Issue122Fixture.error));
  const fixtureError = await page.evaluate(() => Issue122Fixture.error);
  if (fixtureError) throw new Error(fixtureError);
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
  const png = await canvas.screenshot({ path: path.join(OUT, mode + '.png') });
  await page.close();
  assert.deepEqual(errors, [], mode + ' page errors');
  assert.deepEqual(failed, [], mode + ' request failures');
  assert.equal(stats.issue122Mode, mode, mode + ' mode propagated');
  assert.equal(stats.triangles, 361010, mode + ' triangle count');
  assert.equal(gl.webgl2, true, mode + ' WebGL2');
  assert.equal(gl.error, 0, mode + ' gl.getError');
  return { mode, stats, gl, screenshot: { sha256: hash(png), bytes: png.length } };
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
    for (const mode of MODES) report.modes.push(await capture(browser, origin, mode));
    const byMode = Object.fromEntries(report.modes.map(row => [row.mode, row]));
    assert.equal(byMode.raw.stats.indexCompatibility[0].mode, 'raw');
    assert.equal(byMode.raw.stats.calls, 51, 'raw draw calls');
    assert.equal(byMode.chunked.stats.indexCompatibility[0].mode, 'chunked');
    assert.equal(byMode.chunked.stats.indexCompatibility[0].outputChunks, 5);
    assert.equal(byMode.chunked.stats.calls, 55, 'chunked draw calls');
    assert.equal(byMode.nonindexed.stats.indexCompatibility[0].mode, 'nonindexed');
    assert.equal(byMode.nonindexed.stats.indexCompatibility[0].expandedBatches, 1);
    assert.equal(byMode.nonindexed.stats.calls, 51, 'non-indexed draw calls');
    const identity = row => JSON.stringify([
      row.gl.vendor, row.gl.renderer, row.gl.version, row.gl.unmaskedVendor, row.gl.unmaskedRenderer,
    ]);
    assert.equal(new Set(report.modes.map(identity)).size, 1, 'same WebGL backend for all modes');
    report.pixelIdentity = {
      rawVsChunkedPngExact: byMode.raw.screenshot.sha256 === byMode.chunked.screenshot.sha256,
      rawVsNonindexedPngExact: byMode.raw.screenshot.sha256 === byMode.nonindexed.screenshot.sha256,
      chunkedVsNonindexedPngExact: byMode.chunked.screenshot.sha256 === byMode.nonindexed.screenshot.sha256,
    };
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
