// 靶向 ablation：只对实际带 will-change 的元素清空。
// 同时统计被 will-change 提升的合成层数量。
'use strict';
module.exports = {
    name: 'will-change-targeted',
    description: '仅对实际带 will-change 的元素清空 + 上报数量',
    targetedJs: `(() => {
        const targets = [];
        document.querySelectorAll('*').forEach(el => {
            const w = getComputedStyle(el).willChange;
            if (w && w !== 'auto') {
                el.style.willChange = 'auto';
                targets.push(el.tagName + (el.id ? '#' + el.id : ''));
            }
        });
        window.__cf7AblationTargets = (window.__cf7AblationTargets || []);
        window.__cf7AblationTargets.push({ ablation: 'will-change-targeted', count: targets.length, samples: targets.slice(0, 20) });
    })();`,
};
