'use strict';
// Exercise the review page and the production panel in an isolated mock host.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const assert = require('assert/strict');
const { chromium } = require('../../launcher/perf/node_modules/playwright');
const { startServer } = require('../lib/stage-select-dev-server');
const { startReviewServer } = require('./review-server');
const root = path.resolve(__dirname, '../..');
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

async function verify(candidate, integrated = false) {
  const directory = path.resolve(candidate);
  const manifestFile = path.join(directory, 'manifest.json');
  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  const entries = new Map(manifest.stages.map(s => [s.id, s]));
  const refined = manifest.stages.filter(s => s.decision === 'refined');
  const runtimeFile = path.join(root, 'launcher/web/assets/stage-select/previews/hd/manifest.json');
  const runtime = integrated ? JSON.parse(fs.readFileSync(runtimeFile, 'utf8')) : null;
  const urls = Object.fromEntries(manifest.stages.map(stage => [stage.id, integrated
    ? runtime.stages.find(s => s.id === stage.id)?.url : 'assets/__stage-preview-review/' + stage.id + '.png']));
  assert(Object.values(urls).every(Boolean), 'Runtime delivery does not cover the candidate');
  const output = path.join(directory, integrated ? 'integrated-consumer' : 'consumer');
  fs.mkdirSync(output, { recursive: true });
  const reportName = integrated ? 'integrated-browser-report' : 'browser-report';
  const reportFile = path.join(directory, reportName + '.json');
  if (fs.existsSync(reportFile)) fs.renameSync(reportFile, path.join(directory, reportName + '-attempt-' + Date.now() + '.json'));
  const report = {
    scope: integrated ? 'Isolated Edge, production stage-select registry, DOM/CSS and installed assets with no URL override; mock Host, no game entry or player save.'
      : 'Isolated Edge, production stage-select DOM/CSS, mock Host, in-memory candidate URLs. No game entry or player save was used. Human visual acceptance remains open.',
    manifestSha256: sha(manifestFile), views: [], noPreviewEntries: [], gallery: {}, errors: [], pass: false
  };
  if (integrated) { report.runtimeManifestSha256 = sha(runtimeFile); report.registrySha256 = sha(path.join(root, 'launcher/web/modules/stage-select-data.js')); }
  const { server, origin } = await startServer(path.join(root, 'launcher/web'));
  let browser, reviewServer;
  try {
    const executablePath = process.env.CFN_EDGE_PATH || path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe');
    browser = await chromium.launch({ executablePath, headless: true });
    const page = await browser.newPage({ viewport: { width: 1024, height: 576 } });
    page.setDefaultTimeout(20000);
    page.on('pageerror', e => report.errors.push(e.message));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
    if (!integrated) await page.route('**/assets/__stage-preview-review/*.png', route => {
      const id = path.basename(new URL(route.request().url()).pathname, '.png');
      const entry = entries.get(id);
      if (!entry) return route.fulfill({ status: 404, body: '' });
      return route.fulfill({ status: 200, contentType: 'image/png', body: fs.readFileSync(path.join(directory, entry.file)) });
    });
    await page.goto(origin + '/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked&review=1');
    await page.waitForFunction(() => window.StageSelectViewModel && window.StageSelectHarnessHost);
    await page.evaluate(({ stages, urls, integrated }) => {
      document.body.classList.add('stage-select-qa');
      document.querySelector('#debug-log')?.remove();
      document.querySelector('#qa-panel')?.remove();
      const buttons = StageSelectData.getManifest().frames.flatMap(f => f.stageButtons || []);
      for (const stage of stages) {
        const button = buttons.find(b => b.id === stage.id);
        if (!button) throw Error('Missing production stage button ' + stage.id);
        if (integrated) {
          if (button.bannerUrl !== urls[stage.id]) throw Error('Production banner mapping differs: ' + stage.id);
        } else button.bannerUrl = urls[stage.id];
      }
    }, { stages: manifest.stages, urls, integrated });
    report.decoded = await page.evaluate(async ({ stages, urls }) => {
      return Promise.all(stages.map(stage => new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => image.naturalWidth === 644 && image.naturalHeight === 276
          ? resolve(stage.id) : reject(Error('Wrong browser image dimensions: ' + stage.id));
        image.onerror = () => reject(Error('Image decode failed: ' + stage.id));
        image.src = '/' + urls[stage.id];
      })));
    }, { stages: manifest.stages, urls });
    for (const stage of refined) {
      await page.evaluate(frame => {
        StageSelectHarnessHost.close();
        StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: frame });
      }, stage.region);
      await page.waitForFunction(() => !window.StageSelectDiorama || !StageSelectDiorama.stats().moving);
      // Use the panel's real keyboard path so a neighboring hover card cannot
      // cover the next node while the 3D camera moves between stages.
      await page.mouse.move(5, 5);
      const node = page.locator('.stage-select-stage-button[data-stage-id="' + stage.id + '"]');
      if (await node.getAttribute('data-entry-kind') === 'task') {
        report.noPreviewEntries.push({ id: stage.id, reason: 'Current task-direct entry activates immediately and has no preview surface. Asset decoding is verified separately.' });
        continue;
      }
      await node.focus();
      await node.press('Enter');
      await page.waitForFunction(() => !window.StageSelectDiorama || !StageSelectDiorama.stats().moving);
      await page.waitForFunction(url => Array.from(document.images).some(image =>
        image.src.endsWith('/' + url) && image.complete && image.naturalWidth === 644 && image.getBoundingClientRect().width > 200), urls[stage.id]);
      const metrics = await page.evaluate(url => Array.from(document.images)
        .filter(image => image.src.endsWith('/' + url))
        .map(image => {
          const rect = image.getBoundingClientRect(), css = getComputedStyle(image);
          return { className: image.className, width: rect.width, height: rect.height,
            naturalWidth: image.naturalWidth, naturalHeight: image.naturalHeight,
            objectFit: css.objectFit, tier: image.closest('[data-preview-tier]')?.dataset.previewTier };
        }), urls[stage.id]);
      const preview = metrics.find(m => m.width > 200 && m.height > 100);
      assert(preview, 'Missing visible focused preview for ' + stage.id);
      assert.equal(preview.tier, 'hd', 'Candidate lost HD preview tier: ' + stage.id);
      assert(Math.abs(preview.width / preview.height - 644 / 276) < .02, 'Consumer unexpectedly crops candidate: ' + stage.id);
      const file = path.join(output, stage.id + '.png');
      await page.screenshot({ path: file, animations: 'disabled' });
      report.views.push({ id: stage.id, interaction: 'production keyboard focus and Enter', file: path.relative(directory, file).split(path.sep).join('/'), sha256: sha(file), metrics });
      console.log('Consumer verified: ' + stage.id);
    }
    assert.equal(report.errors.length, 0, 'Production panel JavaScript errors');
    // Enable only validated consumer captures on the review server.
    report.consumerPass = true;
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n');
    if (!integrated) {
    const review = await startReviewServer(directory);
    reviewServer = review.server;
    const gallery = await browser.newPage({ viewport: { width: 1366, height: 900 } });
    gallery.on('pageerror', e => report.errors.push(e.message));
    await gallery.goto(review.url);
    await gallery.waitForFunction(() => document.querySelectorAll('article').length > 0);
    assert.equal(await gallery.locator('article').count(), refined.length);
    assert.equal(await gallery.locator('.consumer-button').count(), report.views.length);
    await gallery.locator('.consumer-button').first().click();
    await gallery.locator('#large').evaluate(image => image.decode());
    assert.equal(await gallery.locator('#large').evaluate(image => image.naturalWidth), 1024);
    await gallery.locator('#close').click();
    await gallery.locator('#changed').uncheck();
    assert.equal(await gallery.locator('article').count(), manifest.stages.length);
    report.gallery.decoded = await gallery.evaluate(async () => {
      const images = Array.from(document.querySelectorAll('article img'));
      await Promise.all(images.map(image => { image.loading = 'eager'; return image.decode(); }));
      return images.length;
    });
    await gallery.locator('#search').fill('stage_0_12');
    assert.equal(await gallery.locator('article').count(), 1);
    await gallery.locator('.main-image').last().click();
    assert(await gallery.locator('#zoom').isVisible());
    await gallery.locator('#close').click();
    assert(!(await gallery.locator('#zoom').isVisible()));
    await gallery.locator('#search').fill('');
    await gallery.locator('#region').selectOption('黑铁会总部');
    assert.equal(await gallery.locator('article').count(), manifest.stages.filter(s => s.region === '黑铁会总部').length);
    await gallery.locator('#region').selectOption('');
    await gallery.locator('#changed').check();
    await gallery.screenshot({ path: path.join(directory, 'review-gallery.png'), animations: 'disabled' });
    report.gallery.filters = true;
    report.gallery.zoom = true;
    assert.equal(report.errors.length, 0, 'Review page JavaScript errors');
    }
    report.pass = true;
  } catch (error) {
    report.pass = false;
    report.failure = String(error.stack || error);
  } finally {
    if (browser) await browser.close();
    if (reviewServer) await new Promise(resolve => reviewServer.close(resolve));
    await new Promise(resolve => server.close(resolve));
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({ pass: report.pass, decoded: report.decoded?.length, consumerViews: report.views.length, noPreviewEntries: report.noPreviewEntries, gallery: report.gallery, errors: report.errors, failure: report.failure }, null, 2));
  }
  return report.pass ? 0 : 1;
}

if (require.main === module) {
  if (!process.argv[2]) throw Error('Usage: node tools/stage-preview/verify-browser.js <candidate-directory> [--integrated]');
  verify(process.argv[2], process.argv.includes('--integrated')).then(code => { process.exitCode = code; }).catch(error => { console.error(error); process.exitCode = 1; });
}
module.exports = { verify };
