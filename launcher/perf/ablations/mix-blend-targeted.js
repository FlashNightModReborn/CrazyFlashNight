// 靶向 ablation：只对实际使用了 mix-blend-mode 的元素清空。
// 验证 mix-blend-off -26% 是否真来自这两处扫描线（panels.css:1065 + panels.css:3693）。
'use strict';
module.exports = {
    name: 'mix-blend-targeted',
    description: '仅对实际带 mix-blend-mode 的元素清空（归因 mix-blend-off 收益）',
    targetedJs: `(() => {
        const targets = [];
        document.querySelectorAll('*').forEach(el => {
            const m = getComputedStyle(el).mixBlendMode;
            if (m && m !== 'normal') {
                el.style.mixBlendMode = 'normal';
                targets.push(el.tagName + (el.id ? '#' + el.id : '') + (el.className ? '.' + String(el.className).split(' ').slice(0,2).join('.') : ''));
            }
        });
        // 伪元素无法通过 getComputedStyle 直接遍历，但可以通过添加全局规则覆盖
        // 这部分留给伪元素专项 ablation。
        window.__cf7AblationTargets = (window.__cf7AblationTargets || []);
        window.__cf7AblationTargets.push({ ablation: 'mix-blend-targeted', count: targets.length, samples: targets.slice(0, 10) });
    })();`,
    // 伪元素（如 .lockbox-panel::before）无法用 inline style 覆盖，仍需 stylesheet 注入
    css: `*::before, *::after { mix-blend-mode: normal !important; }`,
};
