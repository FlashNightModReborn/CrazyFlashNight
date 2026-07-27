/**
 * Read-only Character Build statistics presenter.
 *
 * The AS2 snapshot remains authoritative. This leaf only formats scalar rows,
 * renders the legacy encumbrance spectrum from its explicit ratio/thresholds,
 * and derives clearly labelled within-group comparison bars.
 */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildStatsView = api;
        root.CharacterBuildStatsView = api;
    }
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function escapeHtml(value) {
        return text(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function finite(value) {
        if (value == null || value === '') return null;
        var numeric = Number(value);
        return isFinite(numeric) ? numeric : null;
    }
    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }
    function trimFixed(value, digits) {
        return Number(value).toFixed(digits).replace(/\.?0+$/, '');
    }
    function groupKey(group) {
        return text(group && (group.key || group.id));
    }
    function groupLabel(group) {
        return text(group && (group.label || group.title), '统计');
    }
    function rowKey(row) {
        return text(row && (row.key || row.id));
    }
    var RESISTANCE_ICON_PATHS = {
        energyResistance:'<path d="M8 1.5 13.5 8 8 14.5 2.5 8 8 1.5Z M8 4.7 10.8 8 8 11.3 5.2 8 8 4.7Z"/>',
        heatResistance:'<path d="M8.2 14.3c-2.8 0-4.8-1.8-4.8-4.4 0-2.1 1.3-3.5 2.8-5.3.1 1.4.6 2.2 1.4 2.9.1-2.5 1.2-4.3 2.4-5.8.3 2.3 2.4 3.9 2.4 6.9 0 2.5-2 4.1-4.8 4.1Z M8.2 13.9c-1.2 0-2.1-.8-2.1-1.9 0-1 .7-1.7 1.6-2.7.1.8.4 1.2.8 1.5.1-1.1.5-1.9 1-2.6.2 1.3.9 2.1.9 3.4 0 1.3-.9 2.3-2.2 2.3Z"/>',
        corrosionResistance:'<path d="M8 1.6C6.3 4 3.8 6.5 3.8 9.4a4.2 4.2 0 0 0 8.4 0C12.2 6.5 9.7 4 8 1.6Z M5.8 8h4.4 M6 10.5c.5.9 1.1 1.3 2.1 1.4"/>',
        poisonResistance:'<path d="M8 6.7v2.6 M6.9 7.3 4.6 5.9 M9.1 7.3l2.3-1.4 M8 9.3 6.2 12 M8 9.3l1.8 2.7"/><circle cx="8" cy="8" r="1.5"/><circle cx="3.7" cy="5.3" r="1.7"/><circle cx="12.3" cy="5.3" r="1.7"/><circle cx="5.7" cy="12.8" r="1.7"/><circle cx="10.3" cy="12.8" r="1.7"/>',
        coldResistance:'<path d="M8 1.3v13.4 M2.2 4.7l11.6 6.6 M2.2 11.3l11.6-6.6 M6.2 2.4 8 4.2l1.8-1.8 M6.2 13.6 8 11.8l1.8 1.8"/>',
        lightningResistance:'<path d="M9.3 1.4 4.3 8.5h3.2l-.8 6.1 5-7.2H8.5l.8-6Z"/>',
        waveResistance:'<path d="M1.5 5.2c1.1 0 1.4 1.4 2.6 1.4S5.7 5.2 6.8 5.2s1.5 1.4 2.6 1.4 1.5-1.4 2.6-1.4 1.5 1.4 2.5 1.4 M1.5 9.4c1.1 0 1.4 1.4 2.6 1.4s1.6-1.4 2.7-1.4 1.5 1.4 2.6 1.4 1.5-1.4 2.6-1.4 1.5 1.4 2.5 1.4"/>',
        impactResistance:'<path d="M8 1.3v3 M8 11.7v3 M1.3 8h3 M11.7 8h3 M3.3 3.3l2.1 2.1 M10.6 10.6l2.1 2.1 M12.7 3.3l-2.1 2.1 M5.4 10.6l-2.1 2.1"/><circle cx="8" cy="8" r="2.2"/>'
    };
    function resistanceIcon(row) {
        var key = rowKey(row);
        var paths = RESISTANCE_ICON_PATHS[key];
        if (!paths) return '';
        return '<span class="character-build-resistance-icon" data-resistance-key="'
            + escapeHtml(key) + '" aria-hidden="true"><svg viewBox="0 0 16 16"'
            + ' aria-hidden="true" focusable="false" fill="none" stroke="currentColor"'
            + ' stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">'
            + paths + '</svg></span>';
    }
    function formatRow(row) {
        if (!row) return '—';
        var value = row.value;
        var numeric = finite(value);
        var hint = text(row.displayHint);
        var rendered;
        if (numeric == null) rendered = text(value, '—');
        else if (hint === 'integer') rendered = String(Math.round(numeric));
        else if (hint === 'signed-integer') {
            rendered = (numeric > 0 ? '+' : '') + String(Math.round(numeric));
        } else if (hint === 'signed-number') {
            rendered = (numeric > 0 ? '+' : '') + trimFixed(numeric, 2);
        } else if (hint === 'percent-1') rendered = Number(numeric).toFixed(1);
        else if (hint === 'percent-0') rendered = String(Math.round(numeric));
        else if (hint === 'decimal-1') rendered = Number(numeric).toFixed(1);
        else if (hint === 'ratio-3') rendered = Number(numeric * 100).toFixed(1) + '%';
        else if (hint === 'compact-number-1') {
            rendered = numeric >= 100000
                ? trimFixed(Math.floor(numeric / 100) / 10, 1) + 'k'
                : String(Math.floor(numeric));
        } else rendered = trimFixed(numeric, 3);
        if (hint === 'enum' && rowKey(row) === 'encumbranceState') {
            rendered = text(value) === 'light' ? '轻装'
                : text(value) === 'normal' ? '标准负载'
                    : text(value) === 'heavy' ? '重装' : text(value, '—');
        }
        return rendered + text(row.unit);
    }
    function indexSnapshot(stats) {
        var groups = Array.isArray(stats && stats.groups) ? stats.groups : [];
        var byGroup = {};
        var byRow = {};
        var rowCount = 0;
        for (var i = 0; i < groups.length; i++) {
            var group = groups[i] || {};
            var key = groupKey(group);
            if (key) byGroup[key] = group;
            var rows = Array.isArray(group.rows) ? group.rows : [];
            for (var j = 0; j < rows.length; j++) {
                var row = rows[j] || {};
                var keyName = rowKey(row);
                if (keyName && !byRow[keyName]) byRow[keyName] = row;
                rowCount++;
            }
        }
        return {groups:groups, byGroup:byGroup, byRow:byRow, rowCount:rowCount};
    }
    function rowValue(index, key) {
        return formatRow(index.byRow[key]);
    }
    function profileMarkup(index) {
        return '<section class="character-build-stats-profile" data-stats-profile>'
            + '<div class="character-build-stats-identity">'
            + '<span>DLS / SUBJECT PROFILE · 当前已应用构筑</span>'
            + '<div><strong data-styled-title>' + escapeHtml(rowValue(index, 'title')) + '</strong>'
            + '<b>LV.' + escapeHtml(rowValue(index, 'level')) + '</b></div>'
            + '<p>经验 ' + escapeHtml(rowValue(index, 'experience'))
            + ' · 杀敌 ' + escapeHtml(rowValue(index, 'killCount'))
            + ' · ' + escapeHtml(rowValue(index, 'height'))
            + ' / ' + escapeHtml(rowValue(index, 'bodyWeight')) + '</p></div>'
            + '<div class="character-build-stats-authority"><b>'
            + index.groups.length + ' 个分类</b><span>' + index.rowCount
            + ' 项已同步读数</span></div></section>';
    }
    function kpi(label, value, kind) {
        return '<div data-kpi="' + kind + '"><span>' + escapeHtml(label)
            + '</span><strong>' + escapeHtml(value) + '</strong></div>';
    }
    function validEncumbrance(index) {
        var ratio = finite(index.byRow.weightRatio && index.byRow.weightRatio.value);
        var light = finite(index.byRow.lightMediumThreshold
            && index.byRow.lightMediumThreshold.value);
        var medium = finite(index.byRow.mediumHeavyThreshold
            && index.byRow.mediumHeavyThreshold.value);
        var heavy = finite(index.byRow.heavyThreshold && index.byRow.heavyThreshold.value);
        return ratio != null && ratio >= 0 && ratio <= 1
            && light != null && medium != null && heavy != null
            && light > 0 && light < medium && medium < heavy
            ? {ratio:ratio, light:light, medium:medium, heavy:heavy} : null;
    }
    function encumbranceMarkup(index) {
        var scale = validEncumbrance(index);
        if (!scale) return '';
        var state = text(index.byRow.encumbranceState
            && index.byRow.encumbranceState.value, 'unknown');
        var stateLabel = state === 'light' ? '轻装'
            : state === 'heavy' ? '重装' : state === 'normal' ? '标准负载' : '状态未知';
        var ratioPercent = trimFixed(scale.ratio * 100, 1);
        /* weightRatio and all three thresholds are already projected by AS2.
           The 25/50/100 visual zones do not recreate UnitUtil speed formulas. */
        return '<section class="character-build-encumbrance" data-stats-encumbrance'
            + ' data-weight-ratio="' + escapeHtml(String(scale.ratio)) + '">'
            + '<header><div><span>ENCUMBRANCE RESPONSE</span><h3>负重与移动响应</h3></div>'
            + '<div class="character-build-encumbrance-readout">'
            + '<span>装备重量 <b>' + escapeHtml(rowValue(index, 'equipmentWeight')) + '</b></span>'
            + '<span>当前速度 <b data-load-state="' + escapeHtml(state) + '">'
            + escapeHtml(rowValue(index, 'movementSpeed')) + '</b></span></div></header>'
            + '<div class="character-build-weight-spectrum" aria-hidden="true">'
            + '<div class="character-build-weight-band"></div>'
            + '<i class="character-build-weight-marker" style="left:'
            + escapeHtml(ratioPercent) + '%"></i>'
            + '<span class="character-build-weight-tick tick-light">轻</span>'
            + '<span class="character-build-weight-tick tick-normal">中</span>'
            + '<span class="character-build-weight-tick tick-heavy">重</span></div>'
            + '<div class="character-build-weight-labels" aria-hidden="true">'
            + '<span>0kg</span><span>' + escapeHtml(trimFixed(scale.light, 3))
            + 'kg</span><span>' + escapeHtml(trimFixed(scale.medium, 3))
            + 'kg</span><span>' + escapeHtml(trimFixed(scale.heavy, 3)) + 'kg</span></div>'
            + '<p><b>' + escapeHtml(stateLabel) + ' · ' + escapeHtml(ratioPercent)
            + '%</b><span>轻/中阈值 ' + escapeHtml(trimFixed(scale.light, 3))
            + 'kg；中/重阈值 ' + escapeHtml(trimFixed(scale.medium, 3))
            + 'kg；最大负重 ' + escapeHtml(trimFixed(scale.heavy, 3))
            + 'kg。色带显示当前已应用构筑。</span></p></section>';
    }
    function relativeMagnitude(value, key) {
        return key === 'power' ? Math.log(value + 1) / Math.LN10 : value;
    }
    function relativeChart(group, eyebrow) {
        if (!group || !Array.isArray(group.rows) || !group.rows.length) return '';
        var key = groupKey(group);
        var showResistanceIcons = key === 'resistance';
        var maximum = 0;
        for (var i = 0; i < group.rows.length; i++) {
            var numeric = finite(group.rows[i] && group.rows[i].value);
            if (numeric == null || numeric < 0) return '';
            maximum = Math.max(maximum, relativeMagnitude(numeric, key));
        }
        if (maximum <= 0) return '';
        var html = '<section class="character-build-relative-chart" data-chart="'
            + escapeHtml(key) + '" data-scale="' + (key === 'power' ? 'log10' : 'linear')
            + '"><header><div><span>'
            + escapeHtml(eyebrow) + '</span><h3>' + escapeHtml(groupLabel(group))
            + '</h3></div><small>' + (key === 'power' ? '对数相对量级' : '当前组相对量级')
            + ' · 数值见右侧</small></header><dl>';
        for (var j = 0; j < group.rows.length; j++) {
            var row = group.rows[j] || {};
            var value = finite(row.value);
            var width = value == null ? 0
                : clamp(relativeMagnitude(value, key) / maximum * 100, 0, 100);
            html += '<div>' + (showResistanceIcons ? resistanceIcon(row) : '')
                + '<dt>' + escapeHtml(row.label) + '</dt><dd><i aria-hidden="true"><b style="width:'
                + escapeHtml(trimFixed(width, 1)) + '%"></b></i><strong>'
                + escapeHtml(formatRow(row)) + '</strong></dd></div>';
        }
        return html + '</dl></section>';
    }
    function detailMarkup(index) {
        var html = '<section class="character-build-stats-detail"><header><div>'
            + '<span>CURRENT BUILD DATA</span><h3>完整属性</h3></div><b>'
            + index.groups.length + ' 组 · ' + index.rowCount + ' 项</b></header>'
            + '<div class="character-build-stats-detail-grid" data-stats-detail-grid>';
        for (var i = 0; i < index.groups.length; i++) {
            var group = index.groups[i] || {};
            var key = groupKey(group);
            var showResistanceIcons = key === 'resistance';
            html += '<section data-stats-group="' + escapeHtml(key)
                + '"><h4>' + escapeHtml(groupLabel(group)) + '</h4><dl>';
            var rows = Array.isArray(group.rows) ? group.rows : [];
            for (var j = 0; j < rows.length; j++) {
                var row = rows[j] || {};
                html += '<div data-body-copy data-stat-key="' + escapeHtml(rowKey(row))
                    + '">' + (showResistanceIcons ? resistanceIcon(row) : '')
                    + '<dt>' + escapeHtml(row.label) + '</dt><dd>'
                    + escapeHtml(formatRow(row)) + '</dd></div>';
            }
            html += '</dl></section>';
        }
        return html + '</div></section>';
    }
    function StatsView(options) {
        options = options || {};
        this._host = options.host;
        this._scroll = options.scroll;
        this._hint = options.hint;
        this._copy = options.copy;
        this._glyph = options.glyph;
        if (!this._host || !this._scroll || !this._hint || !this._copy || !this._glyph) {
            throw new Error('CharacterBuildStatsView requires stats DOM');
        }
    }
    StatsView.prototype._applyStyledTitle = function(row) {
        var target = this._host.querySelector('[data-styled-title]');
        var spans = row && Array.isArray(row.spans) ? row.spans : [];
        if (!target || !spans.length) return false;
        var joined = '';
        for (var i = 0; i < spans.length; i++) joined += text(spans[i] && spans[i].text);
        if (joined !== text(row.value)) return false;
        target.textContent = '';
        var documentRef = this._host.ownerDocument;
        for (var j = 0; j < spans.length; j++) {
            var source = spans[j] || {};
            var node = documentRef.createElement('span');
            node.textContent = text(source.text);
            if (/^#[0-9a-f]{6}$/i.test(text(source.color))) {
                node.style.color = text(source.color);
            }
            var size = finite(source.size);
            if (size != null && Math.floor(size) === size && size >= 1 && size <= 72) {
                node.style.fontSize = clamp(size, 11, 22) + 'px';
                node.setAttribute('data-projected-size', String(size));
            }
            target.appendChild(node);
        }
        return true;
    };
    StatsView.prototype.render = function(stats) {
        var index = indexSnapshot(stats || {});
        if (!index.groups.length) {
            this._host.innerHTML = '<p class="character-build-stats-unavailable" role="status">'
                + '个人信息暂不可用，请返回后重试。</p>';
            this.syncScrollAffordance();
            return false;
        }
        this._host.innerHTML = profileMarkup(index)
            + '<div class="character-build-stats-diagnostic-row">'
            + encumbranceMarkup(index)
            + '<section class="character-build-vital-card"><header><span>COMBAT SUMMARY</span>'
            + '<h3>生存与战斗摘要</h3></header><div>'
            + kpi('最大 HP', rowValue(index, 'maxHp'), 'hp')
            + kpi('最大 MP', rowValue(index, 'maxMp'), 'mp')
            + kpi('综合防御', rowValue(index, 'totalDefense'), 'defense')
            + kpi('减伤率', rowValue(index, 'damageReduction'), 'reduction')
            + kpi('命中力', rowValue(index, 'accuracy'), 'accuracy')
            + kpi('内力', rowValue(index, 'innerPower'), 'inner')
            + '</div></section></div>'
            + '<div class="character-build-stats-charts">'
            + relativeChart(index.byGroup.power, 'OUTPUT PROFILE')
            + relativeChart(index.byGroup.resistance, 'RESISTANCE MATRIX')
            + '</div>' + detailMarkup(index);
        this._applyStyledTitle(index.byRow.title);
        this.syncScrollAffordance();
        return true;
    };
    StatsView.prototype.syncScrollAffordance = function() {
        var maxScroll = Math.max(0, this._scroll.scrollHeight - this._scroll.clientHeight);
        var position = maxScroll <= 1 ? 'none'
            : this._scroll.scrollTop >= maxScroll - 1 ? 'end'
                : this._scroll.scrollTop <= 1 ? 'start' : 'middle';
        this._scroll.setAttribute('data-scroll-position', position);
        this._hint.hidden = position === 'none';
        if (position !== 'none') {
            this._glyph.textContent = position === 'end' ? '↑' : '↓';
            this._copy.textContent = position === 'start'
                ? '下方还有完整属性 · 滚轮 / PageDown'
                : position === 'end' ? '已到属性末尾 · PageUp 返回'
                    : '继续浏览 · PageUp / PageDown';
        }
        return position;
    };

    return {StatsView:StatsView, formatRow:formatRow, indexSnapshot:indexSnapshot};
});
