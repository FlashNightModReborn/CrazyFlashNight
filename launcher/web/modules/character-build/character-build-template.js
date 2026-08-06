/* Static Character Build shell markup; behavior and authority live in sibling modules. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.CharacterBuildTemplate = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var ARMOR_SLOTS = [
        {id:'头部装备', label:'头部'}, {id:'上装装备', label:'上装'},
        {id:'下装装备', label:'下装'}, {id:'手部装备', label:'手部'},
        {id:'脚部装备', label:'脚部'}, {id:'颈部装备', label:'颈部'}
    ];
    var WEAPON_SLOTS = [
        {id:'长枪', label:'长枪'}, {id:'手枪', label:'手枪'},
        {id:'手枪2', label:'手枪 2'}, {id:'刀', label:'刀'}, {id:'手雷', label:'手雷'}
    ];
    var DRUG_SLOTS = [
        {id:'drug1', label:'药剂 I'}, {id:'drug2', label:'药剂 II'},
        {id:'drug3', label:'药剂 III'}, {id:'drug4', label:'药剂 IV'}
    ];
    function create() {
        return ''
            + '<main class="character-build-body" data-build-underlay data-pane-layout="55-45">'
            + '  <section class="character-build-pane character-build-composite-pane" data-build-pane="loadout" aria-labelledby="character-build-loadout-title">'
            + '    <header class="character-build-pane-heading"><div class="character-build-loadout-heading-copy"><span>外观与配置</span><h2 id="character-build-loadout-title">当前构筑</h2>'
            + '        <span class="character-build-focus-summary" data-focus-summary title="用方向键浏览槽位；按 Enter 或 Space 选择。">浏览：尚未选择槽位</span></div>'
            + '      <div class="character-build-loadout-tools"><span data-doll-preview-action-host></span></div></header>'
            + '    <div class="character-build-composite">'
            + '      <div class="character-build-visual-column"><div class="character-build-doll-home" data-doll-stage-home>'
            + '        <div class="character-build-doll-stage" data-body-copy>'
            + '          <canvas class="character-build-doll-canvas" width="440" height="650" aria-label="角色当前装备纸娃娃"></canvas>'
            + '          <div class="character-build-candidate-overlay" data-layer="candidate-preview" aria-live="polite" hidden><b data-overlay-copy></b></div>'
            + '        </div></div></div>'
            + '      <div class="character-build-loadout-column">'
            + '        <section class="character-build-slot-section"><h3>护具</h3><div class="character-build-slot-grid item-grid-compact" data-armor-grid role="grid" aria-label="六格护具栏"></div></section>'
            + '        <section class="character-build-slot-section"><h3>武装</h3><div class="character-build-slot-grid item-grid-compact" data-weapon-grid role="grid" aria-label="五格武装栏"></div></section>'
            + '        <section class="character-build-slot-section character-build-drug-section"><h3>药剂</h3><div class="character-build-drug-grid item-grid-compact" data-drug-grid role="grid" aria-label="四格药剂栏"></div></section>'
            + '      </div>'
            + '    </div>'
            + '    <div class="character-build-inline-notice" data-body-copy data-build-notice data-notice-kind="browsing"></div>'
            + '  </section>'
            + '  <aside class="character-build-pane character-build-candidate-pane" data-build-pane="candidates" aria-labelledby="character-build-candidate-title">'
            + '    <header class="character-build-pane-heading"><div><span>背包候选</span><h2 id="character-build-candidate-title">候选对比</h2></div>'
            + '      <div class="character-build-pane-tools"><div class="character-build-candidate-actions" role="toolbar" aria-label="当前槽位与候选操作">'
            + '        <button type="button" data-build-action="commit" aria-label="装备所选候选" disabled>装备</button>'
            + '        <button type="button" data-build-action="tune" aria-label="调制当前装备" hidden disabled>调制</button>'
            + '        <button type="button" data-build-action="unequip" aria-label="卸下当前物品" disabled>卸下</button></div>'
            + '        <div data-build-density-mount></div><b data-candidate-count>0 项</b></div></header>'
            + '    <div class="character-build-candidate-context-row" data-body-copy>'
            + '      <div class="character-build-candidate-scope-row character-build-pane-tools"><span>候选范围</span><div data-build-candidate-scope-mount></div></div>'
            + '      <div class="character-build-candidate-focus-summary" data-candidate-focus-summary>方向键只浏览摘要；Enter 或 Space 固定预览；再次点击或按 Space 取消。</div>'
            + '    </div>'
            + '    <div class="character-build-candidate-scroll" data-scroll-region="candidates"><div class="character-build-candidate-list inventory-owned-grid" data-candidate-list role="listbox" aria-label="装备候选"></div></div>'
            + '  </aside>'
            + '</main>'
            + '<section class="character-build-stats-page" role="dialog" aria-label="个人信息统计">'
            + '  <div class="character-build-stats-scroll" data-scroll-region="stats" tabindex="0" role="region" aria-label="可滚动的个人信息统计"><div class="character-build-stats-grid" data-stats-grid></div></div>'
            + '  <footer data-body-copy><span class="character-build-stats-scroll-hint" data-stats-scroll-hint hidden><i data-stats-scroll-glyph aria-hidden="true">↓</i><span data-stats-scroll-copy>下方还有内容 · 滚轮 / PageDown</span></span>'
            + '    <span class="character-build-stats-return-hint">Esc 返回构筑</span></footer>'
            + '</section>';
    }

    return {
        create:create,
        armorSlots:ARMOR_SLOTS,
        weaponSlots:WEAPON_SLOTS,
        drugSlots:DRUG_SLOTS
    };
});
