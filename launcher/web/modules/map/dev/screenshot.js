// 一次性 UI 评估 + 红点回归视觉：枚举几种 page + lock + taskNpc 组合，输出 PNG
// 复用 launcher/perf 下安装的 playwright（perf harness 已声明依赖）
const path = require('path');
const playwrightDir = path.resolve(__dirname, '..', '..', '..', '..', 'perf', 'node_modules', 'playwright');
const { chromium } = require(playwrightDir);

const harnessUrl = 'file:///' + path.resolve(__dirname, 'harness.html').replace(/\\/g, '/');

const scenarios = [
    // 基线（无红点）
    { name: 'base-default',           query: 'page=base' },
    { name: 'faction-all-unlocked',   query: 'page=faction' },
    // 红点演示
    { name: 'base-with-quests',       query: 'page=base&taskNpcs=base_lobby,merc_bar,firing_range' },
    { name: 'faction-with-quests',    query: 'page=faction&taskNpcs=firing_range,fallen_bar' },
    // 剧透防护：所有 faction 子组锁住 + 喂 locked hotspot 任务 → 红点必须不出现
    { name: 'faction-locked-spoiler', query: 'page=base&taskNpcs=firing_range,warlord_base&lockedGroups=warlord,rock,blackiron,fallen' },
];

(async () => {
    const browser = await chromium.launch();
    const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: 1 });
    const page = await ctx.newPage();
    page.on('pageerror', err => console.error('[pageerror]', err.message));
    page.on('console', msg => { if (msg.type() === 'error') console.error('[console.error]', msg.text()); });

    for (const sc of scenarios) {
        const url = harnessUrl + '?' + sc.query;
        await page.goto(url);
        await page.waitForSelector('.map-panel', { state: 'visible', timeout: 5000 });
        await page.waitForTimeout(900);
        const outPath = path.resolve(__dirname, `shot-${sc.name}.png`);
        await page.screenshot({ path: outPath, fullPage: false });
        console.log('saved:', outPath);
    }
    await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
