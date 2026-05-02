/**
 * IntelligenceComponentRenderer — 白名单 H5 情报组件渲染器。
 *
 * 输入为 data/intelligence_h5/*.json 的组件树；渲染只使用 DOM API，不执行
 * 内容侧脚本，也不接收 HTML 字符串。
 */
var IntelligenceComponentRenderer = (function() {
    'use strict';

    var BLOCK_TYPES = {
        paragraph: true,
        heading: true,
        list: true,
        table: true,
        quote: true,
        divider: true,
        stamp: true,
        note: true,
        handwritten: true,
        annotation: true,
        terminalLog: true,
        redaction: true,
        decryptBlock: true,
        blueprint: true,
        timeline: true,
        hardwareExtract: true,
        surfaceMark: true
    };

    var INLINE_TYPES = {
        text: true,
        strong: true,
        underline: true,
        colorToken: true,
        damageText: true,
        redaction: true,
        decryptText: true,
        pcName: true
    };

    var _revealLayer = null;
    var _activeReveal = null;
    var _revealHideTimer = 0;
    var _globalRevealEventsBound = false;

    function render(target, blocks, context) {
        context = context || {};
        if (!target) return;
        closeReveal();
        var list = Array.isArray(blocks) ? blocks : [];
        for (var i = 0; i < list.length; i++) {
            var node = renderBlock(list[i], context);
            if (node) target.appendChild(node);
        }
    }

    function renderBlock(block, context) {
        if (!block || !BLOCK_TYPES[block.type]) return null;
        switch (block.type) {
            case 'paragraph': return blockWithInline('p', 'intel-h5-p', block.content, context);
            case 'heading': return renderHeading(block, context);
            case 'list': return renderList(block, context);
            case 'table': return renderTable(block, context);
            case 'quote': return blockWithInline('blockquote', 'intel-h5-quote', block.content, context);
            case 'divider': return document.createElement('hr');
            case 'stamp': return blockWithInline('div', 'intel-h5-stamp intel-h5-stamp-' + safeClass(block.tone || 'neutral'), block.content, context);
            case 'note': return blockWithInline('div', 'intel-h5-note', block.content, context);
            case 'handwritten': return renderHandwritten(block, context);
            case 'annotation': return renderAnnotation(block, context);
            case 'terminalLog': return renderTerminalLog(block, context);
            case 'redaction': return renderBlockRedaction(block, context);
            case 'decryptBlock': return renderDecryptBlock(block, context);
            case 'blueprint': return renderBlueprint(block, context);
            case 'timeline': return renderTimeline(block, context);
            case 'hardwareExtract': return renderHardwareExtract(block, context);
            case 'surfaceMark': return renderSurfaceMark(block);
        }
        return null;
    }

    function renderHeading(block, context) {
        var level = Number(block.level) || 2;
        if (level < 1 || level > 4) level = 2;
        return blockWithInline('h' + level, 'intel-h5-heading intel-h5-heading-' + level, block.content || block.title, context);
    }

    function blockWithInline(tag, className, inline, context) {
        var el = document.createElement(tag);
        el.className = className;
        appendInline(el, inline || [], context);
        return el;
    }

    function renderList(block, context) {
        var el = document.createElement(block.ordered ? 'ol' : 'ul');
        el.className = 'intel-h5-list';
        var items = Array.isArray(block.items) ? block.items : [];
        for (var i = 0; i < items.length; i++) {
            var li = document.createElement('li');
            var item = items[i];
            if (Array.isArray(item)) appendInline(li, item, context);
            else if (item && Array.isArray(item.content)) appendInline(li, item.content, context);
            else if (item && item.type) {
                var child = renderBlock(item, context);
                if (child) li.appendChild(child);
            } else {
                li.appendChild(document.createTextNode(String(item || '')));
            }
            el.appendChild(li);
        }
        return el;
    }

    function renderTable(block, context) {
        var wrap = document.createElement('div');
        wrap.className = 'intel-h5-table-wrap';
        var table = document.createElement('table');
        table.className = 'intel-h5-table';
        if (Array.isArray(block.columns) && block.columns.length) {
            var thead = document.createElement('thead');
            var tr = document.createElement('tr');
            for (var i = 0; i < block.columns.length; i++) {
                var th = document.createElement('th');
                th.appendChild(document.createTextNode(String(block.columns[i] || '')));
                tr.appendChild(th);
            }
            thead.appendChild(tr);
            table.appendChild(thead);
        }
        var tbody = document.createElement('tbody');
        var rows = Array.isArray(block.rows) ? block.rows : [];
        for (i = 0; i < rows.length; i++) {
            tr = document.createElement('tr');
            var row = Array.isArray(rows[i]) ? rows[i] : [];
            for (var j = 0; j < row.length; j++) {
                var td = document.createElement('td');
                if (Array.isArray(row[j])) appendInline(td, row[j], context);
                else td.appendChild(document.createTextNode(String(row[j] == null ? '' : row[j])));
                tr.appendChild(td);
            }
            tbody.appendChild(tr);
        }
        table.appendChild(tbody);
        wrap.appendChild(table);
        return wrap;
    }

    function renderAnnotation(block, context) {
        var el = document.createElement('aside');
        el.className = 'intel-h5-annotation';
        var main = document.createElement('div');
        main.className = 'intel-h5-annotation-main';
        appendInline(main, block.content || [], context);
        var note = document.createElement('div');
        note.className = 'intel-h5-annotation-note';
        appendInline(note, block.note || block.caption || [], context);
        el.appendChild(main);
        el.appendChild(note);
        return el;
    }

    function renderHandwritten(block, context) {
        var el = document.createElement('aside');
        el.className = 'intel-h5-handwritten intel-h5-handwritten-' + safeClass(block.tone || 'red');
        appendInline(el, block.content || block.note || [], context);
        return el;
    }

    function renderTerminalLog(block, context) {
        var el = document.createElement('section');
        el.className = 'intel-h5-terminal';
        if (block.title) {
            var title = document.createElement('div');
            title.className = 'intel-h5-terminal-title';
            title.appendChild(document.createTextNode(String(block.title)));
            el.appendChild(title);
        }
        var entries = Array.isArray(block.entries) ? block.entries : [];
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i] || {};
            var row = document.createElement('div');
            row.className = 'intel-h5-terminal-row intel-h5-terminal-' + safeClass(entry.kind || 'text');
            appendInline(row, entry.content || [], context);
            if (Array.isArray(entry.blocks)) {
                for (var j = 0; j < entry.blocks.length; j++) {
                    var child = renderBlock(entry.blocks[j], context);
                    if (child) row.appendChild(child);
                }
            }
            el.appendChild(row);
        }
        return el;
    }

    function renderBlockRedaction(block, context) {
        var el = document.createElement('div');
        el.className = 'intel-h5-redaction-block';
        appendRedaction(el, block.content || [], block.reveal || block.plain || [], context);
        return el;
    }

    function renderDecryptBlock(block, context) {
        var level = Number(block.level) || 0;
        var locked = context.encryptedView || level > (Number(context.decryptLevel) || 0) || context.showPlain === false;
        var el = document.createElement('section');
        el.className = 'intel-h5-decrypt' + (locked ? ' locked' : ' unlocked');
        var head = document.createElement('div');
        head.className = 'intel-h5-decrypt-head';
        head.appendChild(document.createTextNode((block.label || '加密块') + (level > 0 ? ' · E' + level : '')));
        el.appendChild(head);
        render(el, locked ? (block.encrypted || encryptedPlaceholder()) : (block.plain || block.blocks || []), extend(context, { encryptedView: locked && !block.encrypted }));
        return el;
    }

    function renderBlueprint(block, context) {
        var el = document.createElement('section');
        el.className = 'intel-h5-blueprint';
        var title = document.createElement('div');
        title.className = 'intel-h5-blueprint-title';
        appendInline(title, block.title || [], context);
        el.appendChild(title);

        var materials = Array.isArray(block.materials) ? block.materials : [];
        if (materials.length) {
            var mat = document.createElement('div');
            mat.className = 'intel-h5-blueprint-materials';
            for (var i = 0; i < materials.length; i++) {
                var row = document.createElement('div');
                row.className = 'intel-h5-blueprint-row';
                appendInline(row, materials[i], context);
                mat.appendChild(row);
            }
            el.appendChild(mat);
        }

        var steps = Array.isArray(block.steps) ? block.steps : [];
        if (steps.length) {
            var list = document.createElement('ol');
            list.className = 'intel-h5-blueprint-steps';
            for (i = 0; i < steps.length; i++) {
                var li = document.createElement('li');
                if (steps[i] && Array.isArray(steps[i].content)) appendInline(li, steps[i].content, context);
                else li.appendChild(document.createTextNode(String(steps[i] || '')));
                list.appendChild(li);
            }
            el.appendChild(list);
        }
        return el;
    }

    function renderTimeline(block, context) {
        var el = document.createElement('section');
        el.className = 'intel-h5-timeline';
        var entries = Array.isArray(block.entries) ? block.entries : [];
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i] || {};
            var row = document.createElement('div');
            row.className = 'intel-h5-timeline-entry';
            var label = document.createElement('div');
            label.className = 'intel-h5-timeline-label';
            label.appendChild(document.createTextNode(String(entry.label || entry.time || '')));
            var body = document.createElement('div');
            body.className = 'intel-h5-timeline-body';
            appendInline(body, entry.content || [], context);
            row.appendChild(label);
            row.appendChild(body);
            el.appendChild(row);
        }
        return el;
    }

    function renderHardwareExtract(block, context) {
        var el = document.createElement('section');
        el.className = 'intel-h5-hardware';
        var head = document.createElement('button');
        head.type = 'button';
        head.className = 'intel-h5-hardware-head';
        head.appendChild(document.createTextNode((block.label || '硬件提取') + (block.status ? ' · ' + block.status : '')));
        var body = document.createElement('div');
        body.className = 'intel-h5-hardware-body';
        var steps = Array.isArray(block.steps) ? block.steps : [];
        for (var i = 0; i < steps.length; i++) {
            var step = document.createElement('div');
            step.className = 'intel-h5-hardware-step';
            if (steps[i] && Array.isArray(steps[i].content)) appendInline(step, steps[i].content, context);
            else step.appendChild(document.createTextNode(String(steps[i] || '')));
            body.appendChild(step);
        }
        render(body, block.reveal || [], context);
        head.addEventListener('click', function() {
            el.classList.toggle('is-open');
        });
        el.appendChild(head);
        el.appendChild(body);
        return el;
    }

    function renderSurfaceMark(block) {
        var el = document.createElement('div');
        el.className = 'intel-h5-surface intel-h5-surface-' + safeClass(block.variant || 'dirt');
        el.setAttribute('aria-hidden', 'true');
        setPercent(el, 'left', block.x, 50);
        setPercent(el, 'top', block.y, 20);
        setPercent(el, 'width', block.w, 18);
        setPercent(el, 'height', block.h, 18);
        var rotate = clampNumber(block.rotate, -45, 45, 0);
        var opacity = clampNumber(block.opacity, 0.08, 0.9, 0.32);
        el.style.transform = 'rotate(' + rotate + 'deg)';
        el.style.opacity = String(opacity);
        return el;
    }

    function appendInline(target, inline, context) {
        var nodes = Array.isArray(inline) ? inline : [];
        for (var i = 0; i < nodes.length; i++) appendInlineNode(target, nodes[i], context);
    }

    function appendInlineNode(target, node, context) {
        if (typeof node === 'string') {
            target.appendChild(document.createTextNode(displayText(node, context)));
            return;
        }
        if (!node || !INLINE_TYPES[node.type]) return;
        if (node.type === 'text') {
            target.appendChild(document.createTextNode(displayText(node.text || '', context)));
        } else if (node.type === 'pcName') {
            target.appendChild(document.createTextNode(displayText(context.pcName || '', context)));
        } else if (node.type === 'strong') {
            var strong = document.createElement('strong');
            appendInline(strong, node.content || [], context);
            target.appendChild(strong);
        } else if (node.type === 'underline') {
            var underline = document.createElement('u');
            appendInline(underline, node.content || [], context);
            target.appendChild(underline);
        } else if (node.type === 'colorToken') {
            var span = document.createElement('span');
            span.className = 'intel-h5-token intel-h5-token-' + safeClass(node.token || 'muted');
            appendInline(span, node.content || [], context);
            target.appendChild(span);
        } else if (node.type === 'damageText') {
            appendDamageText(target, node);
        } else if (node.type === 'redaction') {
            appendInlineRedaction(target, node, context);
        } else if (node.type === 'decryptText') {
            appendInlineDecrypt(target, node, context);
        }
    }

    function appendDamageText(target, node) {
        var span = document.createElement('span');
        var kind = safeClass(node.kind || 'data-loss');
        span.className = 'intel-h5-damage intel-h5-damage-' + kind;
        span.setAttribute('aria-label', node.ariaLabel || '内容损毁');
        span.appendChild(document.createTextNode(node.text || damageLabel(kind)));
        target.appendChild(span);
    }

    function damageLabel(kind) {
        if (kind === 'smear') return '[涂抹]';
        if (kind === 'deleted') return '[已删除]';
        if (kind === 'missing') return '[缺失]';
        if (kind === 'blurred') return '[模糊]';
        if (kind === 'edited') return '[已编辑]';
        return '[数据损毁]';
    }

    function appendInlineRedaction(target, node, context) {
        var span = document.createElement('span');
        span.className = 'intel-h5-redaction';
        appendRedaction(span, [{ type: 'text', text: node.text || '████' }], node.reveal || node.content || [], context);
        target.appendChild(span);
    }

    function appendInlineDecrypt(target, node, context) {
        var level = Number(node.level) || 0;
        var plain = node.content || [{ type: 'text', text: node.text || '' }];
        var canReveal = level <= (Number(context.decryptLevel) || 0);
        var masked = context.encryptedView || context.showPlain === false || !canReveal || node.forceMask === true;
        if (masked) {
            var span = document.createElement('span');
            span.className = 'intel-h5-redaction intel-h5-decrypt-text' + (canReveal ? ' can-reveal' : ' locked');
            span.tabIndex = 0;
            var mask = document.createElement('span');
            mask.className = 'intel-h5-redaction-mask';
            mask.appendChild(document.createTextNode(node.encryptedText || scrambleText(flattenInline(plain)) || '████'));
            span.appendChild(mask);
            var reveal = document.createElement('span');
            reveal.className = 'intel-h5-redaction-reveal';
            if (canReveal) appendInline(reveal, plain, extend(context, { encryptedView: false, showPlain: true }));
            else reveal.appendChild(document.createTextNode('解密等级不足'));
            span.appendChild(reveal);
            span.addEventListener('click', function(e) {
                e.stopPropagation();
                toggleRevealPinned(span, reveal, e);
            });
            wireRevealHover(span, reveal);
            target.appendChild(span);
            return;
        }
        appendInline(target, plain, context);
    }

    function appendRedaction(target, hiddenInline, revealInline, context) {
        var canReveal = hasMeaningfulReveal(revealInline);
        var mask = document.createElement('span');
        mask.className = 'intel-h5-redaction-mask';
        mask.appendChild(document.createTextNode(scrambleText(flattenInline(hiddenInline)) || '████'));
        target.appendChild(mask);
        if (!canReveal) {
            target.className += ' unresolved';
            target.setAttribute('aria-label', '内容未恢复');
            return;
        }
        target.tabIndex = 0;
        var reveal = document.createElement('span');
        reveal.className = 'intel-h5-redaction-reveal';
        appendInline(reveal, revealInline, extend(context, { encryptedView: false, showPlain: true }));
        target.appendChild(reveal);
        target.addEventListener('click', function(e) {
            e.stopPropagation();
            toggleRevealPinned(target, reveal, e);
        });
        wireRevealHover(target, reveal);
    }

    function hasMeaningfulReveal(inline) {
        var raw = flattenInline(inline || []);
        var cleaned = raw
            .replace(/[█▓▒░■□\s]/g, '')
            .replace(/[\[\]【】()（）已编辑数据损毁缺失删除遮盖覆盖水渍焦痕\-_.:：/]/g, '');
        return cleaned.length > 0;
    }

    function wireRevealHover(trigger, reveal) {
        trigger.addEventListener('mouseenter', function() {
            showReveal(trigger, reveal, false);
        });
        trigger.addEventListener('mouseleave', function() {
            scheduleRevealHide();
        });
        trigger.addEventListener('focus', function() {
            showReveal(trigger, reveal, false);
        });
        trigger.addEventListener('blur', function() {
            scheduleRevealHide();
        });
    }

    function toggleRevealPinned(trigger, reveal, event) {
        if (_activeReveal && _activeReveal.trigger === trigger && _activeReveal.pinned) {
            closeReveal();
            return;
        }
        showReveal(trigger, reveal, true);
        if (event && event.preventDefault) event.preventDefault();
    }

    function showReveal(trigger, reveal, pinned) {
        if (!trigger || !reveal) return;
        clearRevealHideTimer();
        var layer = ensureRevealLayer();
        if (!layer) return;
        layer.innerHTML = '';

        var closeBtn = document.createElement('button');
        closeBtn.type = 'button';
        closeBtn.className = 'intel-h5-reveal-close';
        closeBtn.setAttribute('aria-label', '关闭解密内容');
        closeBtn.appendChild(document.createTextNode('×'));
        closeBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            closeReveal();
            trigger.focus();
        });

        var body = document.createElement('div');
        body.className = 'intel-h5-reveal-body';
        for (var i = 0; i < reveal.childNodes.length; i++) {
            body.appendChild(reveal.childNodes[i].cloneNode(true));
        }
        layer.appendChild(closeBtn);
        layer.appendChild(body);
        layer.className = 'intel-h5-floating-reveal is-visible' + (pinned ? ' is-pinned' : '');
        layer.style.left = '0px';
        layer.style.top = '0px';
        layer.setAttribute('aria-hidden', 'false');
        if (_activeReveal && _activeReveal.trigger && _activeReveal.trigger !== trigger) {
            _activeReveal.trigger.classList.remove('is-open');
        }
        trigger.classList.toggle('is-open', !!pinned);
        _activeReveal = { trigger: trigger, reveal: reveal, pinned: !!pinned };
        positionRevealLayer(trigger, layer);
    }

    function positionRevealLayer(trigger, layer) {
        var rect = trigger.getBoundingClientRect();
        var vw = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
        var vh = Math.max(document.documentElement.clientHeight || 0, window.innerHeight || 0);
        var margin = 12;
        var gap = 8;
        var layerRect = layer.getBoundingClientRect();
        var left = rect.left + rect.width / 2 - layerRect.width / 2;
        if (left < margin) left = margin;
        if (left + layerRect.width > vw - margin) left = Math.max(margin, vw - margin - layerRect.width);
        var top = rect.bottom + gap;
        if (top + layerRect.height > vh - margin) top = rect.top - gap - layerRect.height;
        if (top < margin) top = margin;
        layer.style.left = Math.round(left) + 'px';
        layer.style.top = Math.round(top) + 'px';
    }

    function ensureRevealLayer() {
        if (_revealLayer && _revealLayer.parentNode) return _revealLayer;
        _revealLayer = document.createElement('div');
        _revealLayer.className = 'intel-h5-floating-reveal';
        _revealLayer.setAttribute('aria-hidden', 'true');
        _revealLayer.addEventListener('mouseenter', clearRevealHideTimer);
        _revealLayer.addEventListener('mouseleave', scheduleRevealHide);
        document.body.appendChild(_revealLayer);
        bindGlobalRevealEvents();
        return _revealLayer;
    }

    function bindGlobalRevealEvents() {
        if (_globalRevealEventsBound) return;
        _globalRevealEventsBound = true;
        document.addEventListener('mousedown', function(e) {
            if (!_activeReveal || !_activeReveal.pinned) return;
            var layer = _revealLayer;
            if ((layer && layer.contains(e.target)) || (_activeReveal.trigger && _activeReveal.trigger.contains(e.target))) return;
            closeReveal();
        }, true);
        document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') closeReveal();
        }, true);
        window.addEventListener('resize', function() {
            if (_activeReveal && _revealLayer && _revealLayer.classList.contains('is-visible')) {
                positionRevealLayer(_activeReveal.trigger, _revealLayer);
            }
        });
        window.addEventListener('scroll', function() {
            if (_activeReveal && _revealLayer && _revealLayer.classList.contains('is-visible')) {
                if (_activeReveal.pinned) positionRevealLayer(_activeReveal.trigger, _revealLayer);
                else closeReveal();
            }
        }, true);
    }

    function scheduleRevealHide() {
        clearRevealHideTimer();
        _revealHideTimer = window.setTimeout(function() {
            if (_activeReveal && !_activeReveal.pinned) closeReveal();
        }, 90);
    }

    function clearRevealHideTimer() {
        if (_revealHideTimer) {
            window.clearTimeout(_revealHideTimer);
            _revealHideTimer = 0;
        }
    }

    function closeReveal() {
        clearRevealHideTimer();
        if (_activeReveal && _activeReveal.trigger) _activeReveal.trigger.classList.remove('is-open');
        _activeReveal = null;
        if (_revealLayer) {
            _revealLayer.className = 'intel-h5-floating-reveal';
            _revealLayer.setAttribute('aria-hidden', 'true');
            _revealLayer.innerHTML = '';
        }
    }

    function displayText(text, context) {
        return context && context.encryptedView ? scrambleText(text) : String(text == null ? '' : text);
    }

    function scrambleText(text) {
        text = String(text == null ? '' : text);
        var out = '';
        for (var i = 0; i < text.length; i++) {
            var ch = text.charAt(i);
            if (/\s/.test(ch)) out += ch;
            else if (/[，。！？、,.!?;；:：()[\]【】《》"“”'·\-—_#0-9A-Za-z]/.test(ch)) out += ch;
            else out += '█';
        }
        return out;
    }

    function flattenInline(inline) {
        var text = '';
        var list = Array.isArray(inline) ? inline : [];
        for (var i = 0; i < list.length; i++) {
            var node = list[i];
            if (typeof node === 'string') text += node;
            else if (node && node.type === 'text') text += node.text || '';
            else if (node && node.type === 'pcName') text += '玩家';
            else if (node && Array.isArray(node.content)) text += flattenInline(node.content);
        }
        return text;
    }

    function encryptedPlaceholder() {
        return [{ type: 'paragraph', content: [{ type: 'text', text: '████ ████ ███████ ████ ███████' }] }];
    }

    function extend(base, patch) {
        var out = {};
        var key;
        for (key in (base || {})) if (Object.prototype.hasOwnProperty.call(base, key)) out[key] = base[key];
        for (key in (patch || {})) if (Object.prototype.hasOwnProperty.call(patch, key)) out[key] = patch[key];
        return out;
    }

    function safeClass(value) {
        return String(value || '').replace(/[^a-z0-9_-]/gi, '').toLowerCase() || 'neutral';
    }

    function setPercent(el, prop, value, fallback) {
        var n = clampNumber(value, 0, 100, fallback);
        el.style[prop] = n + '%';
    }

    function clampNumber(value, min, max, fallback) {
        var n = Number(value);
        if (isNaN(n)) n = fallback;
        if (n < min) return min;
        if (n > max) return max;
        return n;
    }

    return {
        render: render,
        _debugScrambleText: scrambleText
    };
})();
