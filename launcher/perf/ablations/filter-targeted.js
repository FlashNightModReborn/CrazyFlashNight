// 靶向 ablation：只对实际使用了 filter 的元素清空 inline filter，避开 `*` 选择器副作用。
// 用于验证 Kimi review 指出的 filter-off +58.6% 反向恶化是否为 ablation 假象。
'use strict';
module.exports = {
    name: 'filter-targeted',
    description: '仅对实际带 filter 的元素清空（验证 filter-off 异常）',
    targetedJs: `(() => {
        const targets = [];
        document.querySelectorAll('*').forEach(el => {
            const f = getComputedStyle(el).filter;
            if (f && f !== 'none') {
                el.style.filter = 'none';
                targets.push(el.tagName + (el.id ? '#' + el.id : '') + (el.className ? '.' + String(el.className).split(' ').join('.') : ''));
            }
        });
        window.__cf7AblationTargets = (window.__cf7AblationTargets || []);
        window.__cf7AblationTargets.push({ ablation: 'filter-targeted', count: targets.length, samples: targets.slice(0, 10) });
    })();`,
};
