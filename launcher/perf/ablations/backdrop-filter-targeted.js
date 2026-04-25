// 靶向 ablation：只对实际使用了 backdrop-filter 的元素清空。
'use strict';
module.exports = {
    name: 'backdrop-filter-targeted',
    description: '仅对实际带 backdrop-filter 的元素清空（避开 * 副作用）',
    targetedJs: `(() => {
        const targets = [];
        document.querySelectorAll('*').forEach(el => {
            const cs = getComputedStyle(el);
            const f = cs.backdropFilter || cs.webkitBackdropFilter || '';
            if (f && f !== 'none') {
                el.style.backdropFilter = 'none';
                el.style.webkitBackdropFilter = 'none';
                targets.push(el.tagName + (el.id ? '#' + el.id : ''));
            }
        });
        window.__cf7AblationTargets = (window.__cf7AblationTargets || []);
        window.__cf7AblationTargets.push({ ablation: 'backdrop-filter-targeted', count: targets.length });
    })();`,
};
