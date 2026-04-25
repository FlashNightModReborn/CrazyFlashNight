// 场景：idle 态。overlay 加载后无 panel 打开，仅 HUD 常驻动画。
// 对应"非 panel 态 35% iGPU"基线。

'use strict';

module.exports = {
    name: 'idle',
    description: 'overlay HUD 常驻态：notch、jukebox、context-panel、工具条',
    async setup(page) {
        // 不点开任何 panel；让常驻 HUD 自然运行
        await page.evaluate(() => {
            // 清掉可能残留的状态类
            document.documentElement.classList.remove(
                'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
            );
        });
        // 模拟一些 mouse 移动以触发 hover 反馈采样路径
        await page.mouse.move(200, 200);
        await page.waitForTimeout(200);
        await page.mouse.move(800, 400);
        await page.waitForTimeout(200);
        await page.mouse.move(400, 600);
    },
};
