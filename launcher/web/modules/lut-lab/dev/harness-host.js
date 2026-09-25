/**
 * LUT 实验室 dev harness 宿主桩：Panels / Bridge 最小替身 + 可切换 mock Host。
 *
 * bridge 模式：
 *  - 'off'（默认）：不定义 window.chrome.webview，面板按「无 WebView2 宿主」降级；
 *  - 'mock'：定义 chrome.webview 并以测试替身应答 lutlab.grabFrame / lutlab.bakeXml
 *    （mock 烘焙曲线仅用于联调面板 wiring，非权威光照数据）。
 * vhost 由 window.CF7_LUTLAB_VHOST_BASE 覆盖（harness.html 按 ?vhost= 设置）。
 */
(function() {
    'use strict';

    var specs = {};
    var active = null;
    var activeElement = null;
    var bridgeMode = 'off';

    window.Panels = {
        register: function(id, spec) { specs[id] = spec; },
        open: function(id, initData) {
            var spec = specs[id];
            if (!spec) throw new Error('unknown harness panel: ' + id);
            if (active && active !== id) window.Panels.close();
            if (active === id) return true;
            if (!spec._el) {
                spec._el = spec.create(document.getElementById('harness-stage'));
                document.getElementById('harness-stage').appendChild(spec._el);
            }
            spec._el.style.display = '';
            active = id;
            activeElement = spec._el;
            return spec.onOpen ? spec.onOpen(spec._el, initData || {}) !== false : true;
        },
        close: function() {
            if (!active) return;
            var spec = specs[active];
            if (spec && spec.onClose) try { spec.onClose(); } catch (e) { console.error(e); }
            if (activeElement) activeElement.style.display = 'none';
            // 与生产 Panels 语义一致（panels.js close/_doOpen）：DOM 与 spec._el 跨 close
            // 保留，下次 open 不再 create，仅 display 复位 + onOpen(el, initData)。
            // （旧桩在此 removeChild + _el=null，掩盖了 2026-09-24 真机重开黑死。）
            active = null;
            activeElement = null;
        }
    };

    // ── mock Host（测试替身）：确定性假烘焙/假抓帧，只证明面板 wiring ──
    // 信封对齐真实实现（LutLabTask.cs）：两条独立 task 名 'lutlab.grabFrame' /
    // 'lutlab.bakeXml'，回包 {type:'taskResult', ok:true, success:true, task, ...}。
    function mockBakeRgba(level, mode) {
        var size = 32;
        var rgba = new Uint8Array(size * size * size * 4);
        var shift = (level - 5) * 10;
        var greenBias = mode === '夜视' ? 0.25 : 0;
        var i = 0;
        for (var b = 0; b < size; b++) for (var g = 0; g < size; g++) for (var r = 0; r < size; r++) {
            var rv = r / 31 * 255, gv = g / 31 * 255, bv = b / 31 * 255;
            rgba[i++] = Math.max(0, Math.min(255, Math.round(rv * (1 - greenBias) + shift)));
            rgba[i++] = Math.max(0, Math.min(255, Math.round(gv + shift)));
            rgba[i++] = Math.max(0, Math.min(255, Math.round(bv * (1 - greenBias) + shift)));
            rgba[i++] = 255;
        }
        return rgba;
    }

    function mockGrabFrameUrl() {
        var canvas = document.createElement('canvas');
        canvas.width = 160; canvas.height = 90;
        var ctx = canvas.getContext('2d');
        var grad = ctx.createLinearGradient(0, 0, 160, 90);
        grad.addColorStop(0, '#0a0d12');
        grad.addColorStop(0.6, '#2a3138');
        grad.addColorStop(1, '#5a4a33');
        ctx.fillStyle = grad;
        ctx.fillRect(0, 0, 160, 90);
        ctx.fillStyle = '#c8b28a';
        ctx.fillRect(20, 20, 30, 30);
        ctx.fillStyle = '#5e8cff';
        ctx.fillRect(90, 40, 40, 24);
        return { url: canvas.toDataURL('image/png'), width: 160, height: 90 };
    }

    function toBase64(bytes) {
        var bin = '';
        for (var i = 0; i < bytes.length; i += 8192) {
            bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
        }
        return btoa(bin);
    }

    function respond(cb, fields) {
        setTimeout(function() {
            cb(Object.assign({ type: 'taskResult', ok: true, success: true }, fields));
        }, 0);
    }

    function installMockBridge() {
        window.chrome = window.chrome || {};
        window.chrome.webview = window.chrome.webview || {
            postMessage: function() {},
            addEventListener: function() {}
        };
        window.Bridge = {
            task: function(name, payload, cb) {
                if (name === 'lutlab.grabFrame') {
                    respond(cb, Object.assign({ task: name }, mockGrabFrameUrl()));
                    return 'mock-grab';
                }
                if (name === 'lutlab.bakeXml') {
                    var level = Math.max(0, Math.min(10, Number(payload && payload.level) || 0));
                    var mode = payload && payload.mode === '夜视' ? '夜视' : '光照';
                    respond(cb, { task: name, mode: mode, level: level, size: 32, rgbaBase64: toBase64(mockBakeRgba(level, mode)) });
                    return 'mock-bake';
                }
                if (name === 'lutlab.bakeXmlSet') {
                    var setMode = payload && payload.mode === '夜视' ? '夜视' : '光照';
                    var levels = [];
                    for (var lv = 0; lv <= 9; lv++) {
                        levels.push({ level: lv, rgbaBase64: toBase64(mockBakeRgba(lv, setMode)) });
                    }
                    respond(cb, { task: name, mode: setMode === '夜视' ? '夜视仪' : '光照', size: 32, levels: levels });
                    return 'mock-bake-set';
                }
                if (name === 'lutlab.savePreset') {
                    // mock 保存：回显自检内容（真实 Host 写盘+重读+manifest 由 LutLabTask 单测覆盖）
                    var saveName = payload && payload.name;
                    var saveMode = payload && payload.mode;
                    var saveLevels = payload && Array.isArray(payload.levels) ? payload.levels : [];
                    if (!saveName || saveLevels.length !== 10) {
                        respond(cb, { ok: false, success: false, error: 'mock savePreset 缺 name/levels[10]' });
                        return 'mock-save-bad';
                    }
                    var saveFiles = [];
                    for (var sf = 0; sf < 10; sf++) saveFiles.push(saveMode + '-' + sf + '.cube');
                    var manifestEntry = {
                        name: saveName, title: '预设 · ' + saveName, mode: saveMode,
                        dir: 'presets/' + saveName, files: saveFiles,
                        source: 'lut-lab 预设工作流', license: '项目内部生成，随仓库', notes: ''
                    };
                    window.__lutLabSavedPreset = {
                        payload: payload,
                        manifestEntry: manifestEntry
                    };
                    respond(cb, {
                        task: name, name: saveName, dir: 'presets/' + saveName,
                        files: saveFiles, manifestEntry: manifestEntry, levels: saveLevels
                    });
                    return 'mock-save';
                }
                respond(cb, { ok: false, success: false, error: 'mock host 未实现 ' + name });
                return 'mock-unknown';
            },
            send: function(msg) {
                // 记录面板→Host 消息（QA 用：验证关闭按钮仍发 panel close）
                (window.__lutLabSent = window.__lutLabSent || []).push(msg);
                return true;
            },
            on: function() {},
            off: function() {}
        };
    }

    function uninstallBridge() {
        if (window.chrome && window.chrome.webview) {
            try { delete window.chrome.webview; } catch (e) { window.chrome.webview = undefined; }
        }
        delete window.Bridge;
    }

    function applyBridgeMode(mode) {
        if (mode === 'mock') installMockBridge();
        else uninstallBridge();
        bridgeMode = mode === 'mock' ? 'mock' : 'off';
    }

    var params = new URLSearchParams(location.search);
    if (params.get('vhost') === 'local') {
        window.CF7_LUTLAB_VHOST_BASE = '/vhost';
    } else if (params.get('vhost') === 'off') {
        window.CF7_LUTLAB_VHOST_BASE = '/vhost-missing';
    }
    applyBridgeMode(params.get('bridge') === 'mock' ? 'mock' : 'off');

    window.__lutLabHarness = {
        open: function() { return window.Panels.open('lut-lab', { source: 'dev-harness' }); },
        close: function() { return window.Panels.close(); },
        reopen: function() { window.Panels.close(); return window.Panels.open('lut-lab', { source: 'dev-harness' }); },
        setBridgeMode: function(mode) { applyBridgeMode(mode); return bridgeMode; },
        setVhostBase: function(base) { window.CF7_LUTLAB_VHOST_BASE = base; },
        spec: function() { return specs['lut-lab']; },
        activeElement: function() { return activeElement; }
    };
})();
