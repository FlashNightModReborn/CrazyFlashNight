// 场景：panel 反复开关。压测 panel 切换过渡期 layer 创建/销毁风暴。
// 切换间隔 600ms（覆盖典型 transition 时长 200-300ms + 视觉静止）。

'use strict';

module.exports = {
    name: 'panel-toggle',
    description: 'map / lockbox 反复切换，压测 panel 过渡期 layer 风暴',
    async setup(page) {
        await page.evaluate(() => {
            document.documentElement.classList.remove(
                'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
            );
            window.__cf7ToggleStop && clearInterval(window.__cf7ToggleStop);
            const sequence = ['map', 'lockbox', null];
            let i = 0;
            window.__cf7ToggleStop = setInterval(() => {
                const target = sequence[i % sequence.length];
                i++;
                try {
                    if (target === null && typeof Panels !== 'undefined' && Panels.close) {
                        Panels.close();
                    } else if (target && typeof Panels !== 'undefined' && Panels.open) {
                        Panels.open(target);
                    }
                } catch (e) { /* ignore */ }
                // 容错兜底
                const c = document.getElementById('panel-container');
                if (c) {
                    if (target === null) c.style.display = 'none';
                    else { c.style.display = ''; c.setAttribute('data-panel', target); }
                }
            }, 600);
        });
        await page.waitForTimeout(600);
    },
};
