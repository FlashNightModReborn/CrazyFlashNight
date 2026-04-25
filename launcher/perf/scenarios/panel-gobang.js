// 场景：五子棋面板。覆盖 gobang.css 的呼吸/扫掠/准星动画。

'use strict';

module.exports = {
    name: 'panel-gobang',
    description: 'gobang 面板：board breathe + sweep beam + last-cell reticle',
    async setup(page) {
        await page.evaluate(() => {
            document.documentElement.classList.remove(
                'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
            );
            try {
                if (typeof Panels !== 'undefined' && Panels.open) {
                    Panels.open('gobang');
                }
            } catch (e) { /* fallback */ }
            const c = document.getElementById('panel-container');
            if (c) {
                c.style.display = '';
                c.setAttribute('data-panel', 'gobang');
            }
        });
        await page.waitForTimeout(400);
    },
};
