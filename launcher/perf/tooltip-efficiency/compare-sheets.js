'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { DEFAULT_OUT, buildShowcaseSamples } = require('./samples');
const { PRESETS, parseArgs, parseViewports, withFixture, prepareViewport, usePreset, writeJson } = require('./sweep');

const PAD = 12;
const png = url => Buffer.from(url.slice(url.indexOf(',') + 1), 'base64');
const size = n => String(Number(n.toFixed(1)));
const escape = value => String(value).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[c]);

async function capture(fixture, viewport, sample, preset) {
    const { page, cdp } = fixture;
    if (!await usePreset(page, preset)) throw new Error('当前生产代码不支持预设 ' + preset);
    const metrics = await page.evaluate(input => window.efficiency.capture(input), { id: sample.id, document: sample.document });
    const { x, y, tipW, tipH } = metrics;
    const { width, height } = viewport;
    if (x < 0 || y < 0 || x + tipW > width || y + tipH > height) throw new Error(sample.id + ': 截图外框超出实际画布');
    const outer = {
        left: Math.floor(x) - PAD, top: Math.floor(y) - PAD,
        right: Math.ceil(x + tipW) + PAD, bottom: Math.ceil(y + tipH) + PAD
    };
    const left = Math.max(0, outer.left), top = Math.max(0, outer.top);
    const clip = {
        x: left, y: top, width: Math.min(width, outer.right) - left,
        height: Math.min(height, outer.bottom) - top, scale: 1
    };
    const { data } = await cdp.send('Page.captureScreenshot', { format: 'png', clip, captureBeyondViewport: false });
    return {
        preset, metrics, data, clipW: clip.width, clipH: clip.height,
        padLeft: left - outer.left, padTop: top - outer.top,
        padRight: Math.max(0, outer.right - width), padBottom: Math.max(0, outer.bottom - height)
    };
}

async function compose(page, input) {
    return page.evaluate(async ({ title, subtitle, dpr, shots }) => {
        const background = '#181a1c';
        const px = n => Math.round(n * dpr);
        function canvas(width, height, color) {
            const element = document.createElement('canvas');
            element.width = width;
            element.height = height;
            const ctx = element.getContext('2d');
            ctx.fillStyle = color;
            ctx.fillRect(0, 0, width, height);
            return { element, ctx };
        }
        const crops = await Promise.all(shots.map(async shot => {
            const img = new Image();
            img.src = 'data:image/png;base64,' + shot.data;
            await img.decode();
            if (Math.abs(img.width - shot.clipW * dpr) > 1 || Math.abs(img.height - shot.clipH * dpr) > 1) {
                throw new Error('截图像素与 DPR 不符 ' + JSON.stringify([img.width, img.height, shot.clipW, shot.clipH, dpr]));
            }
            const crop = canvas(
                img.width + px(shot.padLeft) + px(shot.padRight),
                img.height + px(shot.padTop) + px(shot.padBottom), background
            );
            crop.ctx.drawImage(img, px(shot.padLeft), px(shot.padTop));
            return crop.element;
        }));

        const gap = px(16), headerH = px(76), labelH = px(80);
        const widths = crops.map(crop => Math.max(crop.width, px(218)));
        const totalW = widths.reduce((sum, w) => sum + w, gap * (widths.length + 1));
        const totalH = headerH + labelH + Math.max(...crops.map(crop => crop.height)) + gap;
        const { element, ctx } = canvas(totalW, totalH, '#101317');
        function text(string, x, y, size, color, maxWidth, weight = '') {
            ctx.font = `${weight} ${px(size)}px "Microsoft YaHei", "Segoe UI", sans-serif`.trim();
            ctx.fillStyle = color;
            ctx.fillText(string, x, y, maxWidth);
        }
        text(title, gap, px(32), 22, '#f8fafc', totalW - 2 * gap, 'bold');
        text(subtitle, gap, px(57), 13, '#b9c5ce', totalW - 2 * gap);
        let x = gap;
        for (let i = 0; i < shots.length; i++) {
            const { preset, dimensions, metrics } = shots[i];
            const width = widths[i];
            const crop = crops[i];
            const left = x + px(12), maxWidth = width - px(24);
            ctx.fillStyle = '#222931';
            ctx.fillRect(x, headerH, width, labelH + crop.height);
            text(preset, left, headerH + px(23), 16, '#f8fafc', maxWidth, 'bold');
            text(dimensions, left, headerH + px(45), 13, '#d1e0eb', maxWidth);
            const overflow = metrics.overflowPx > 0;
            text(overflow ? `溢出 ${metrics.overflowPx} px` : '免滚全览',
                left, headerH + px(66), 13, overflow ? '#ffb879' : '#7de4a6', maxWidth, 'bold');
            ctx.drawImage(crop, x + Math.floor((width - crop.width) / 2), headerH + labelH);
            x += width + gap;
        }
        return { sheet: element.toDataURL(), crops: crops.map(crop => crop.toDataURL()) };
    }, input);
}

function gallery(viewports, presets, unavailable) {
    return `<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tooltip 排版对比</title>
<style>
:root { color-scheme:dark; font:16px "Microsoft YaHei", "Segoe UI", sans-serif; }
body { background:#101317; color:#eaf0f5; margin:24px; }
a { color:#9ad2ff; } nav a { margin-right:16px; }
.grid { display:grid; grid-template-columns:repeat(auto-fill,minmax(min(100%,335px),1fr)); gap:16px; }
figure { background:#181a1c; margin:0; padding:12px; border:1px solid #303942; }
figcaption { margin:0 0 10px; font-weight:bold; } figure img { width:100%; height:250px; object-fit:contain; object-position:top; }
</style>
<h1>Tooltip 排版对比</h1>
<p>${presets.join(' · ')}。点击图片查看原尺寸。标有“排版样例”的来源用于布局压力测试。</p>
${unavailable.length ? `<p>当前生产代码未提供 ${unavailable.join(' · ')}。</p>` : ''}
<nav aria-label="视口">${viewports.map(v => `<a href="#${v.label}">${v.label}</a>`).join('')}</nav>
${viewports.map(v => `<section id="${v.label}"><h2>${v.label}</h2><div class="grid">
${v.items.map(item => `<figure><figcaption>${escape(item.displayName)}</figcaption>
<a href="${item.sheet}"><img src="${item.sheet}" alt="${escape(item.displayName)} 排版截图" loading="lazy"></a></figure>`).join('\n')}
</div></section>`).join('\n')}
</html>\n`;
}

async function main() {
    const args = parseArgs(process.argv.slice(2), {
        presets: PRESETS.join(','), viewports: '1067x600@1.5,1280x720@1.25',
        out: path.join(DEFAULT_OUT, 'sheets'), 'only-presets-available': false
    });
    const requested = args.presets.split(',');
    if (new Set(requested).size !== requested.length || requested.some(p => !PRESETS.includes(p))) {
        throw new Error('预设名称无效或重复 ' + args.presets);
    }
    const viewports = parseViewports(args.viewports);
    const { samples, provenance } = buildShowcaseSamples();
    const out = path.resolve(args.out);
    const results = [];
    await withFixture(viewports[0], async fixture => {
        const { browser, page } = fixture;
        const available = [], unavailable = [];
        for (const preset of requested) {
            (await usePreset(page, preset) ? available : unavailable).push(preset);
        }
        if (unavailable.length && !args['only-presets-available']) {
            throw new Error('当前生产代码不支持 ' + unavailable.join(', ') + '。可指定 --only-presets-available');
        }
        if (!available.length) throw new Error('请求的预设均不可用');
        const compositor = await page.context().newPage();
        await page.emulateMedia({ reducedMotion: 'reduce' });
        for (const viewport of viewports) {
            await prepareViewport(fixture, viewport, samples[0]);
            const viewDir = path.join(out, viewport.label);
            fs.mkdirSync(viewDir, { recursive: true });
            const record = { ...viewport, items: [] };
            for (const sample of samples) {
                const shots = [];
                for (const preset of available) {
                    const shot = await capture(fixture, viewport, sample, preset);
                    const m = shot.metrics;
                    shot.dimensions = `${size(m.tipW)}×${size(m.tipH)} CSS px · ${m.sideColumns} 列`;
                    shots.push(shot);
                }
                const { sheet, crops } = await compose(compositor, {
                    title: sample.displayName,
                    subtitle: `${viewport.label} · ${sample.obtain.length} 条来源 · ${sample.mods.length} 件插件`,
                    dpr: viewport.dpr, shots
                });
                const filename = sample.id + '.png';
                fs.writeFileSync(path.join(viewDir, filename), png(sheet));
                const cropsForSample = shots.map(({ preset, metrics }, i) => {
                    const crop = sample.id + '--' + preset + '.png';
                    fs.writeFileSync(path.join(viewDir, crop), png(crops[i]));
                    return { preset, metrics, crop: viewport.label + '/' + crop };
                });
                record.items.push({
                    id: sample.id, displayName: sample.displayName, sheet: viewport.label + '/' + filename,
                    crops: cropsForSample
                });
            }
            results.push(record);
            console.log(`${viewport.label} · ${record.items.length} 张对比图 · ${available.join(', ')}`);
        }
        fs.writeFileSync(path.join(out, 'index.html'), gallery(results, available, unavailable));
        writeJson(path.join(out, 'sheets.json'), {
            schema: 'cf7.tooltip-efficiency-sheets.v1', provenance, edgeVersion: browser.version(),
            presets: available, unavailablePresets: unavailable, viewports: results
        });
    });
    console.log(path.join(out, 'index.html'));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
