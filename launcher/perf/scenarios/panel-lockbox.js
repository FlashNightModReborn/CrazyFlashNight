// 场景：lockbox panel 打开态。覆盖 mix-blend-mode 扫描线 + 大量 cell drop-shadow。

'use strict';

module.exports = {
    name: 'panel-lockbox',
    description: 'lockbox 面板：扫描线 mix-blend-mode、cell drop-shadow、infinite breathe',
    async setup(page) {
        await page.evaluate(() => {
            document.documentElement.classList.remove(
                'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
            );
            try {
                if (typeof Panels !== 'undefined' && Panels.open) {
                    Panels.open('lockbox');
                }
            } catch (e) { /* fallback */ }
            const c = document.getElementById('panel-container');
            if (c) {
                c.style.display = '';
                c.setAttribute('data-panel', 'lockbox');
            }
        });
        await page.waitForTimeout(400);
    },
};
