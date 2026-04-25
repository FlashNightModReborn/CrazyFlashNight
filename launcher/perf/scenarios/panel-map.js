// 场景：map panel 打开态。复现"panel 态 100% iGPU"。
// 由于 headless 无 Bridge / 无 C# 推送地图数据，实际能否完整渲染依 module 行为；
// 失败时回退为合成状态（注入 panel-container 可见 + map-panel data-panel）。

'use strict';

module.exports = {
    name: 'panel-map',
    description: 'map 面板打开：scanline、scene-node、mix-blend-mode、avatar-task-ring 全负载',
    async setup(page) {
        await page.evaluate(() => {
            document.documentElement.classList.remove(
                'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
            );
            // 优先走真 panel 流程
            try {
                if (typeof Panels !== 'undefined' && Panels.open) {
                    Panels.open('map');
                }
            } catch (e) { /* fallback below */ }
            // 兜底：强行让 panel 可见，注入足量 mock DOM 让相关 CSS 进入工作态
            const c = document.getElementById('panel-container');
            if (c) {
                c.style.display = '';
                c.setAttribute('data-panel', 'map');
            }
        });
        await page.waitForTimeout(400);
    },
};
