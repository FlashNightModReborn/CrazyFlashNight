// 场景：高频 mouse hover/move。压测 cursor-feedback.js + 样式重算热路径。
// 不开 panel，让 HUD 的 hover 反馈成为主要工作源。

'use strict';

module.exports = {
    name: 'mouse-burst',
    description: '高频鼠标移动+悬停切换，压测 hover 反馈与样式重算',
    async setup(page) {
        await page.evaluate(() => {
            document.documentElement.classList.remove(
                'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
            );
        });
        // 启动一个持续移动鼠标的循环（在测量窗口期间持续触发 hover）
        await page.evaluate(() => {
            // 在页面里启一个独立 ticker 持续触发合成鼠标事件
            window.__cf7MouseBurstId && cancelAnimationFrame(window.__cf7MouseBurstId);
            const W = innerWidth, H = innerHeight;
            let t = 0;
            function tick() {
                t += 1 / 60;
                const x = Math.round((Math.sin(t * 1.3) * 0.4 + 0.5) * W);
                const y = Math.round((Math.cos(t * 1.7) * 0.4 + 0.5) * H);
                const ev = new MouseEvent('mousemove', { clientX: x, clientY: y, bubbles: true, cancelable: true });
                (document.elementFromPoint(x, y) || document.body).dispatchEvent(ev);
                window.__cf7MouseBurstId = requestAnimationFrame(tick);
            }
            window.__cf7MouseBurstId = requestAnimationFrame(tick);
        });
    },
};
