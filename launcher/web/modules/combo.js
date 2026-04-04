/**
 * Combo - 搓招发现式可视化（刘海体系 v3）
 *
 * 设计理念：
 * - 玩家乱搓 → 看到输入序列 + 可能的分支 → 搓出招后看到完整路径 → 练习
 * - ROOT 状态隐藏，输入中显示"已输入 → 可达分支"，命中时固化为完成态
 *
 * 数据流:
 * 1. combo UiData (每帧): combo|{cmdName}|{typed}|{hints}
 *    - cmdName 空=未命中, 非空=命中
 *    - typed: 已输入的符号序列 "↓↘"
 *    - hints: "波动拳:↓↘A:1;诛杀步:→→:2" (name:fullSeq:remainSteps)
 *
 * 2. N前缀 combo 通知 (AS2确认触发): Notch 拦截后调 onNotchCombo
 *    - 区分 DFA(金)/Sync(青) 做飞出动效
 */
var Combo = (function() {
    'use strict';

    var statusEl = null;
    var flyContainer = null;
    var lastTyped = '';
    var lastHints = '';
    var lastState = 'idle'; // idle | input | hit
    var hitTimer = 0;
    var hitName = '';
    var pendingTyped = ''; // V8 命中时缓存 typed，等 N 前缀确认
    var knownPatterns = {}; // name → fullSequence，从 hints 数据积累

    function init() {
        statusEl = document.getElementById('combo-status');
        if (!statusEl) return;

        flyContainer = document.createElement('div');
        flyContainer.id = 'combo-fly-container';
        document.body.appendChild(flyContainer);

        UiData.onLegacy('combo', function(fields) {
            var cmdName = fields[0] || '';
            var typed = fields[1] || '';
            var hints = fields[2] || '';

            // V8 DFA 命中帧：只缓存 typed，不触发动效（等 AS2 N前缀确认）
            if (cmdName.length > 0) {
                pendingTyped = typed;
                return;
            }

            // hit 态持续显示
            if (lastState === 'hit') {
                hitTimer--;
                if (hitTimer <= 0) {
                    lastState = 'idle';
                    // fall through 到 idle/input 渲染
                } else {
                    return; // 保持 hit 显示
                }
            }

            // 无输入（ROOT）
            if (typed.length === 0 && hints.length === 0) {
                if (lastState !== 'idle') {
                    lastState = 'idle';
                    statusEl.innerHTML = '';
                    statusEl.classList.remove('has-hints');
                    lastTyped = '';
                    lastHints = '';
                }
                return;
            }

            // 输入中
            if (typed !== lastTyped || hints !== lastHints) {
                lastTyped = typed;
                lastHints = hints;
                lastState = 'input';
                renderInput(typed, hints);
            }
        });
    }

    function renderInput(typed, hintsRaw) {
        if (!statusEl) return;

        var html = '<div class="combo-progress">';
        html += '<span class="cp-typed">' + esc(typed) + '</span>';

        if (hintsRaw.length > 0) {
            var entries = hintsRaw.split(';');

            // 积累 pattern 缓存（用于 Sync 路径 fallback）
            for (var k = 0; k < entries.length; k++) {
                var pk = parseHint(entries[k]);
                if (pk && pk.name) knownPatterns[pk.name] = pk.fullSeq;
            }

            for (var i = 0; i < entries.length; i++) {
                var p = parseHint(entries[i]);
                if (!p) continue;
                if (i > 0) html += '<span class="cp-divider">|</span>';
                var remaining = p.fullSeq.substring(typed.length);
                html += '<span class="cp-remain">' + esc(remaining) + '</span>'
                     + '<span class="cp-name">' + esc(p.name) + '</span>';
            }
        }

        html += '</div>';
        statusEl.innerHTML = html;
        statusEl.classList.add('has-hints');
    }

    function showHit(name, typed, isDFA) {
        if (!statusEl) return;
        lastState = 'hit';
        hitTimer = 35; // ~1.2s
        hitName = name;

        var pathClass = isDFA ? 'hit-dfa' : 'hit-sync';

        // 每个字符独立 span，用于收束动画
        var len = typed.length;
        var mid = len / 2;
        var chars = '';
        for (var i = 0; i < len; i++) {
            var ch = typed.charAt(i);
            var offset = Math.round((i - mid) * -3);
            var delay = 50 + i * 25;
            chars += '<span class="ch-converge" style="'
                  + '--ch-offset:' + offset + 'px;'
                  + 'animation-delay:' + delay + 'ms'
                  + '">' + esc(ch) + '</span>';
        }

        var html = '<div class="combo-hit-bar ' + pathClass + '">'
                 + '<div class="chb-sweep"></div>'
                 + '<span class="chb-seq">' + chars + '</span>'
                 + '<span class="chb-tag">' + esc(name) + '</span>'
                 + '</div>';
        statusEl.innerHTML = html;
        statusEl.classList.add('has-hints');
    }

    function parseHint(entry) {
        var segs = entry.split(':');
        if (segs.length < 3) return null;
        return { name: segs[0], fullSeq: segs[1], steps: parseInt(segs[2], 10) };
    }

    // N 前缀 combo 命中通知（AS2 确认触发）→ 触发 showHit
    function onNotchCombo(text, color) {
        var isDFA = text.indexOf('DFA') === 0;
        var name = text.replace(/^(DFA|Sync)\s*/, '');

        // typed 来源优先级：
        // 1. pendingTyped（V8 DFA 命中帧缓存）— DFA 路径
        // 2. knownPatterns[name]（从 hints 积累的完整序列）— Sync 路径 fallback
        // 3. name（最终 fallback，不应该走到这里）
        var typed = pendingTyped || knownPatterns[name] || name;
        pendingTyped = '';

        showHit(name, typed, isDFA);
    }

    function esc(s) {
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }

    return { init: init, onNotchCombo: onNotchCombo };
})();
