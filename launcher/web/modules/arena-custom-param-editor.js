(function(root, factory) {
    if (typeof module === 'object' && module.exports) {
        module.exports = factory();
    } else {
        root.ArenaCustomParamEditor = factory();
    }
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
    'use strict';

    function parametersApi() {
        return typeof ArenaCustomParameters !== 'undefined' ? ArenaCustomParameters : null;
    }

    function escapeFallback(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function createState(side, index, mode, entry) {
        var api = parametersApi();
        var parameters = entry && api && api.has(entry.parameters) ? entry.parameters : null;
        var draftJson = api ? api.formatJson(parameters) : '';
        var draftXml = '';
        try {
            draftXml = api ? api.formatXml(parameters) : '<Parameters>\n</Parameters>';
        } catch (err) {
            draftXml = '<Parameters>\n</Parameters>';
        }
        return {
            side: side,
            index: Number(index) || 0,
            mode: mode === 'xml' ? 'xml' : 'json',
            draftJson: draftJson,
            draftXml: draftXml,
            error: ''
        };
    }

    function dirty(state, entry) {
        if (!state || !entry) return false;
        var api = parametersApi();
        if (!api) return false;
        var mode = state.mode === 'xml' ? 'xml' : 'json';
        try {
            if (mode === 'xml') {
                return String(state.draftXml || '') !== api.formatXml(entry.parameters);
            }
            return String(state.draftJson || '') !== api.formatJson(entry.parameters);
        } catch (err) {
            return true;
        }
    }

    function updateDraft(state, text) {
        if (!state) return;
        if (state.mode === 'xml') state.draftXml = String(text || '');
        else state.draftJson = String(text || '');
        state.error = '';
    }

    function currentMode(state) {
        return state && state.mode === 'xml' ? 'xml' : 'json';
    }

    function currentDraft(state) {
        return currentMode(state) === 'xml' ? state.draftXml : state.draftJson;
    }

    function parseCurrent(state) {
        var api = parametersApi();
        if (!api) return { ok: false, error: 'ArenaCustomParameters 未加载' };
        return api.parseDraft(currentMode(state), currentDraft(state));
    }

    function setMode(state, mode) {
        if (!state) return false;
        var api = parametersApi();
        if (!api) {
            state.error = 'ArenaCustomParameters 未加载';
            return false;
        }
        mode = mode === 'xml' ? 'xml' : 'json';
        if (state.mode === mode) return true;

        var parsed = api.parseDraft(currentMode(state), currentDraft(state));
        if (!parsed.ok) {
            state.error = parsed.error;
            return false;
        }
        try {
            if (mode === 'xml') state.draftXml = api.formatXml(parsed.value);
            else state.draftJson = api.formatJson(parsed.value);
        } catch (err) {
            state.error = err && err.message ? err.message : '参数无法转换';
            return false;
        }
        state.mode = mode;
        state.error = '';
        return true;
    }

    function clearDraft(state) {
        if (!state) return;
        if (state.mode === 'xml') state.draftXml = '<Parameters>\n</Parameters>';
        else state.draftJson = '';
        state.error = '';
    }

    function render(context) {
        context = context || {};
        var rootEl = context.rootEl;
        var bodyEl = context.bodyEl;
        var state = context.state;
        var entry = context.entry;
        var unit = context.unit || {};
        var escapeHtml = typeof context.escapeHtml === 'function' ? context.escapeHtml : escapeFallback;
        if (!bodyEl) return;
        if (!state || !entry) {
            bodyEl.innerHTML = '<div class="arena-custom-roster-empty">参数目标已不存在</div>';
            return;
        }

        var sideLabel = context.sideLabel || '';
        var summary = context.summary || '默认参数';
        if (context.kickerEl) context.kickerEl.textContent = sideLabel + '单位参数';
        if (context.titleEl) context.titleEl.textContent = '编辑 u' + entry.id + ' · ' + (unit.name || ('兵种' + entry.id));
        if (context.metaEl) {
            context.metaEl.textContent = 'Lv.' + entry.level + ' ×' + entry.count + ' · ' +
                (unit.spritename || '--') + ' · ' + summary;
        }

        var mode = currentMode(state);
        var draft = currentDraft(state);
        var isDirty = dirty(state, entry);
        var errorHtml = state.error ? '<div class="arena-custom-param-error">' + escapeHtml(state.error) + '</div>' : '';
        var dirtyHtml = isDirty
            ? '<div class="arena-custom-param-dirty">草稿未应用；点“应用”写入赛程，点“放弃返回”丢弃本页草稿。</div>'
            : '';
        var invalidClass = state.error ? ' arena-custom-param-editor-input-invalid' : '';
        updateBackButton(rootEl, isDirty);
        bodyEl.innerHTML =
            '<div class="arena-custom-param-workbench">' +
                '<div class="arena-custom-param-main">' +
                    '<div class="arena-custom-param-toolbar">' +
                        '<div class="arena-custom-mode-switch" aria-label="参数编辑模式">' +
                            '<button class="arena-custom-btn' + (mode === 'json' ? ' arena-custom-mode-active' : '') + '" type="button" data-custom-param-mode="json" data-audio-cue="select">JSON</button>' +
                            '<button class="arena-custom-btn' + (mode === 'xml' ? ' arena-custom-mode-active' : '') + '" type="button" data-custom-param-mode="xml" data-audio-cue="select">XML</button>' +
                        '</div>' +
                        '<button class="arena-custom-btn" type="button" data-custom-param-action="clear" data-audio-cue="destructive">清空参数</button>' +
                    '</div>' +
                    '<textarea class="arena-custom-param-editor-input' + invalidClass + '" spellcheck="false" data-custom-param-editor-input>' + escapeHtml(draft) + '</textarea>' +
                    dirtyHtml +
                    errorHtml +
                '</div>' +
                '<div class="arena-custom-param-inspector">' +
                    '<div class="arena-custom-param-inspector-title">当前摘要</div>' +
                    '<div class="arena-custom-param-inspector-text">' + escapeHtml(summary) + '</div>' +
                    '<div class="arena-custom-param-inspector-title">预设来源</div>' +
                    '<div class="arena-custom-param-inspector-text">' + escapeHtml(entry.presetLabel || entry.presetId || '手动参数') + '</div>' +
                    '<div class="arena-custom-param-inspector-title">最终覆盖</div>' +
                    '<div class="arena-custom-param-inspector-text">是否为敌人 / 产生源 / 掉落物=[] / 无金钱经验</div>' +
                '</div>' +
            '</div>';
    }

    function updateBackButton(rootEl, isDirty) {
        var backBtn = rootEl ? rootEl.querySelector('[data-custom-param-action="back"]') : null;
        if (!backBtn) return;
        backBtn.textContent = isDirty ? '放弃返回' : '返回阵容';
        backBtn.classList.toggle('arena-custom-btn-warn', !!isDirty);
    }

    function updateInline(rootEl, state, entry) {
        if (!rootEl) return;
        var input = rootEl.querySelector('[data-custom-param-editor-input]');
        if (!input) return;
        input.classList.remove('arena-custom-param-editor-input-invalid');
        var error = rootEl.querySelector('.arena-custom-param-error');
        if (error && error.parentNode) error.parentNode.removeChild(error);

        var isDirty = dirty(state, entry);
        var marker = rootEl.querySelector('.arena-custom-param-dirty');
        if (isDirty && !marker) {
            marker = rootEl.ownerDocument.createElement('div');
            marker.className = 'arena-custom-param-dirty';
            marker.textContent = '草稿未应用；点“应用”写入赛程，点“放弃返回”丢弃本页草稿。';
            if (input.parentNode) input.parentNode.insertBefore(marker, input.nextSibling);
        } else if (!isDirty && marker && marker.parentNode) {
            marker.parentNode.removeChild(marker);
        }

        updateBackButton(rootEl, isDirty);
    }

    return {
        createState: createState,
        dirty: dirty,
        updateDraft: updateDraft,
        updateInline: updateInline,
        setMode: setMode,
        parseCurrent: parseCurrent,
        clearDraft: clearDraft,
        render: render
    };
});
